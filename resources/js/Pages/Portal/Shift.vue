<script setup lang="ts">
/**
 * Portal "Mesaim": kişinin KENDİ mesai/mola/tuvalet başlat-bitir (PIN'SİZ) +
 * bugünün vardiyası, çalışılan/mola süresi (canlı). Mola/tuvalet olayı §8
 * bildirimini tetikler (yönetici + mesaidekiler). Özel görsel kimlik
 * (p-card / p-tile-* / p-chip — app.css .portal-root). Başlık/tarih
 * PortalLayout hero'sunda (heading/subtitle) gösterilir.
 */
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PortalLayout from '@/Layouts/PortalLayout.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import type { PortalBreak, PortalState } from '@/types/portal';
import { formatMinutes } from '@/types/portal';

/** GET /api/v1/portal/history — son 14 mesai kaydı (en yeni önce). */
interface HistoryEntry {
    id: number;
    date: string;
    clock_in_at: string;
    clock_out_at: string | null;
    worked_min: number;
    break_min: number;
    toilet_min: number;
    status: string;
}
interface HistoryResp {
    entries: HistoryEntry[];
}

const { success, danger } = useToast();

const state = ref<PortalState | null>(null);
const history = ref<HistoryEntry[]>([]);
const loading = ref(true);
const busy = ref(false);
let timer: ReturnType<typeof setInterval> | null = null;
/** Canlı saat/kalan süre kaynağı (ms); her saniye güncellenir. */
const now = ref(Date.now());
let clockTimer: ReturnType<typeof setInterval> | null = null;

const working = computed(() => state.value?.status === 'working');
const onBreak = computed(() => state.value?.on_break === true);
const onToilet = computed(() => onBreak.value && state.value?.break_kind === 'toilet');
const onRegularBreak = computed(() => onBreak.value && state.value?.break_kind !== 'toilet');

const timeFmt = new Intl.DateTimeFormat('tr-TR', { hour: '2-digit', minute: '2-digit' });
const clockTime = (iso: string | null | undefined): string => (iso ? timeFmt.format(new Date(iso)) : '—');

/** Mesai geçmişi tarihleri (Y-m-d → gün adı / gün.ay). */
const dayNameFmt = new Intl.DateTimeFormat('tr-TR', { weekday: 'long' });
const dayMonthFmt = new Intl.DateTimeFormat('tr-TR', { day: '2-digit', month: '2-digit' });
const dayName = (d: string): string => dayNameFmt.format(new Date(`${d}T00:00:00`));
const dayMonth = (d: string): string => dayMonthFmt.format(new Date(`${d}T00:00:00`));

/** Bir mola tuvalet mi? */
const isToilet = (b: PortalBreak): boolean => b.kind === 'toilet';
/** Bitmiş molanın süresi (dakika); sürüyorsa null. */
function breakDuration(b: PortalBreak): number | null {
    if (!b.ended_at) return null;
    return Math.max(0, Math.round((new Date(b.ended_at).getTime() - new Date(b.started_at).getTime()) / 60000));
}

const shiftLabel = computed(() => {
    const s = state.value?.today_shift;
    if (!s) return null;
    return `${clockTime(s.starts_at)} – ${clockTime(s.ends_at)}`;
});

/** Vardiya bitişine kalan süre (dk); çalışmıyorsa/vardiya yoksa null, bittiyse ≤0. */
const remainingMin = computed<number | null>(() => {
    const s = state.value?.today_shift;
    if (!working.value || !s) return null;
    return Math.round((new Date(s.ends_at).getTime() - now.value) / 60000);
});
/** Bugünkü planlı vardiya süresi (dk); vardiya yoksa null. */
const plannedMin = computed<number | null>(() => {
    const s = state.value?.today_shift;
    if (!s) return null;
    return Math.max(0, Math.round((new Date(s.ends_at).getTime() - new Date(s.starts_at).getTime()) / 60000));
});

/** Hero başlığı — mesai durumuna göre. */
const heading = computed(() => {
    if (!working.value) return 'Mesaim';
    if (onToilet.value) return 'Tuvalet molası';
    if (onRegularBreak.value) return 'Moladasınız';
    return 'Mesaidesiniz';
});
const todayLabel = computed(() =>
    new Intl.DateTimeFormat('tr-TR', { weekday: 'long', day: 'numeric', month: 'long' }).format(new Date()),
);
/** Hero alt satırı — vardiya saati varsa onu, yoksa bugünkü tarihi göster. */
const subtitle = computed(() => (shiftLabel.value ? `Bugünkü vardiya: ${shiftLabel.value}` : todayLabel.value));

/** Durum ikonu çipinin rengi (soft zemin + aksan metin). */
const statusChip = computed(() =>
    working.value
        ? onBreak.value
            ? 'bg-(--p-amber-soft) text-(--p-amber)'
            : 'bg-(--p-emerald-soft) text-(--p-emerald)'
        : 'bg-(--color-inset) text-muted',
);

async function refresh(): Promise<void> {
    try {
        state.value = await api<PortalState>('/api/v1/portal/state');
    } catch {
        /* durum süsleyici — sessiz */
    } finally {
        loading.value = false;
    }
}

async function loadHistory(): Promise<void> {
    try {
        const resp = await api<HistoryResp>('/api/v1/portal/history');
        history.value = (resp.entries ?? []).slice(0, 14);
    } catch {
        /* geçmiş süsleyici — sessiz */
    }
}

async function act(path: string, okMessage: string, body?: unknown): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    try {
        state.value = await api<PortalState>(path, { method: 'POST', body });
        success(okMessage);
    } catch (e) {
        danger(e instanceof ApiError ? e.displayMessage : 'İşlem tamamlanamadı.');
    } finally {
        busy.value = false;
    }
}

const clockIn = () => act('/api/v1/portal/clock/in', 'Mesai başlatıldı');
const clockOut = async () => {
    await act('/api/v1/portal/clock/out', 'Mesai bitirildi');
    await loadHistory();
};
const breakStart = () => act('/api/v1/portal/break/start', 'Molaya çıkıldı', { kind: 'break' });
const toiletStart = () => act('/api/v1/portal/break/start', 'Tuvalet molası başladı', { kind: 'toilet' });
const breakEnd = () => act('/api/v1/portal/break/end', 'Moladan dönüldü');

onMounted(() => {
    void refresh();
    void loadHistory();
    timer = setInterval(() => {
        if (document.visibilityState === 'visible') void refresh();
    }, 30000);
    clockTimer = setInterval(() => {
        now.value = Date.now();
    }, 1000);
});

onBeforeUnmount(() => {
    if (timer) clearInterval(timer);
    if (clockTimer) clearInterval(clockTimer);
});
</script>

<template>
    <PortalLayout title="Mesaim" active="shift" :heading="heading" :subtitle="subtitle">
        <!-- Durum kartı -->
        <div class="p-card p-4">
            <div class="flex items-center gap-3">
                <span class="flex size-12 shrink-0 items-center justify-center rounded-2xl" :class="statusChip">
                    <AppIcon :name="working ? (onBreak ? 'coffee' : 'check') : 'clock'" :size="24" />
                </span>
                <div class="min-w-0 flex-1">
                    <p class="font-semibold text-body">
                        <template v-if="!working">Mesaide değilsiniz</template>
                        <template v-else-if="onToilet">Tuvalet molasındasınız</template>
                        <template v-else-if="onRegularBreak">Moladasınız</template>
                        <template v-else>Mesaidesiniz</template>
                    </p>
                    <p v-if="working && state?.entry" class="text-sm text-muted">
                        Giriş {{ clockTime(state.entry.clock_in_at) }} · Fiili çalışma {{ formatMinutes(state.entry.worked_min) }}
                    </p>
                    <p v-else-if="!working" class="text-sm text-muted">Başlamak için mesai başlatın.</p>
                </div>
            </div>

            <!-- Vardiya bitişine kalan süre (canlı) -->
            <div
                v-if="remainingMin !== null"
                class="mt-4 flex min-h-11 items-center gap-2 rounded-xl px-3 py-2.5 text-sm font-semibold"
                :class="remainingMin > 0 ? 'bg-(--p-teal-soft) text-(--p-teal)' : 'bg-(--p-rose-soft) text-(--p-rose)'"
            >
                <span
                    class="p-chip"
                    :style="remainingMin > 0
                        ? '--chip-bg: var(--p-teal-soft); --chip-fg: var(--p-teal)'
                        : '--chip-bg: var(--p-rose-soft); --chip-fg: var(--p-rose)'"
                ><AppIcon name="clock" :size="16" /></span>
                <template v-if="remainingMin > 0">Bitişe {{ formatMinutes(remainingMin) }} kaldı</template>
                <template v-else>Vardiya süresi doldu</template>
            </div>

            <!-- Bugünün vardiyası (saat aralığı + planlı süre) -->
            <div v-if="shiftLabel" class="mt-4 flex flex-wrap items-center gap-2 rounded-xl bg-(--color-inset) px-3 py-2.5 text-sm">
                <span class="p-chip" style="--chip-bg: var(--p-violet-soft); --chip-fg: var(--p-violet)"><AppIcon name="calendar" :size="16" /></span>
                <span class="text-muted">Bugünkü vardiya:</span>
                <span class="font-semibold text-body">{{ shiftLabel }}</span>
                <span v-if="plannedMin !== null" class="text-muted">· Planlı <span class="font-semibold text-body">{{ formatMinutes(plannedMin) }}</span></span>
            </div>

            <!-- Süre özeti (renkli tile'lar) -->
            <div v-if="working && state?.entry" class="mt-4 grid grid-cols-3 gap-2.5 text-center">
                <div class="p-tile p-tile-teal">
                    <p class="text-xl font-extrabold">{{ formatMinutes(state.entry.worked_min) }}</p>
                    <p class="mt-0.5 text-xs opacity-80">Fiili çalışma</p>
                </div>
                <div class="p-tile p-tile-amber">
                    <p class="text-xl font-extrabold">{{ formatMinutes(state.entry.break_total_min) }}</p>
                    <p class="mt-0.5 text-xs opacity-80">Mola</p>
                </div>
                <div class="p-tile p-tile-violet">
                    <p class="text-xl font-extrabold">{{ formatMinutes(state.entry.toilet_total_min) }}</p>
                    <p class="mt-0.5 text-xs opacity-80">Tuvalet</p>
                </div>
            </div>
        </div>

        <!-- Eylemler -->
        <div class="mt-4 flex flex-col gap-3">
            <template v-if="!working">
                <BaseButton size="lg" block :loading="busy" @click="clockIn">Mesai Başlat</BaseButton>
            </template>

            <template v-else-if="onBreak">
                <BaseButton size="lg" block variant="secondary" :loading="busy" @click="breakEnd">
                    {{ onToilet ? 'Tuvaletten Dön' : 'Moladan Dön' }}
                </BaseButton>
            </template>

            <template v-else>
                <div class="grid grid-cols-2 gap-3">
                    <BaseButton size="lg" variant="secondary" :loading="busy" @click="breakStart">Mola Başlat</BaseButton>
                    <BaseButton size="lg" variant="secondary" :loading="busy" @click="toiletStart">Tuvalet Molası</BaseButton>
                </div>
                <BaseButton size="lg" block variant="danger" :loading="busy" @click="clockOut">Mesai Bitir</BaseButton>
            </template>
        </div>

        <!-- Molalarım (bugün) -->
        <div v-if="state?.entry?.breaks?.length" class="mt-4 p-card p-4">
            <p class="mb-3 flex items-center gap-2 font-semibold text-body">
                <span class="p-chip" style="--chip-bg: var(--p-amber-soft); --chip-fg: var(--p-amber)"><AppIcon name="coffee" :size="17" /></span>
                Molalarım
            </p>
            <ul class="flex flex-col gap-2">
                <li
                    v-for="(b, i) in state.entry.breaks"
                    :key="i"
                    class="flex items-center gap-3 rounded-2xl bg-(--color-inset) p-2.5"
                >
                    <span
                        class="flex size-9 shrink-0 items-center justify-center rounded-xl"
                        :class="isToilet(b) ? 'bg-(--p-violet-soft) text-(--p-violet)' : 'bg-(--p-amber-soft) text-(--p-amber)'"
                    >
                        <!-- tuvalet: damla glyph · mola: coffee -->
                        <svg v-if="isToilet(b)" xmlns="http://www.w3.org/2000/svg" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                            <path d="M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5S5 13 5 15a7 7 0 0 0 7 7z" />
                        </svg>
                        <AppIcon v-else name="coffee" :size="17" />
                    </span>
                    <div class="min-w-0 flex-1">
                        <p class="truncate text-sm font-semibold text-body">{{ b.kind_label }}</p>
                        <p class="mt-0.5 text-xs text-muted">
                            {{ clockTime(b.started_at) }}<template v-if="b.ended_at"> – {{ clockTime(b.ended_at) }}</template>
                        </p>
                    </div>
                    <span
                        v-if="b.ended_at"
                        class="shrink-0 rounded-full px-2.5 py-1 text-xs font-bold"
                        :class="isToilet(b) ? 'bg-(--p-violet-soft) text-(--p-violet)' : 'bg-(--p-amber-soft) text-(--p-amber)'"
                    >
                        {{ formatMinutes(breakDuration(b) ?? 0) }}
                    </span>
                    <span
                        v-else
                        class="inline-flex shrink-0 items-center gap-1.5 rounded-full bg-(--p-emerald-soft) px-2.5 py-1 text-xs font-bold text-(--p-emerald)"
                    >
                        <span class="size-1.5 animate-pulse rounded-full bg-current" />
                        sürüyor
                    </span>
                </li>
            </ul>
        </div>

        <!-- Mesai geçmişi -->
        <div class="mt-4 p-card p-4">
            <p class="mb-3 flex items-center gap-2 font-semibold text-body">
                <span class="p-chip" style="--chip-bg: var(--p-indigo-soft); --chip-fg: var(--p-indigo)"><AppIcon name="calendar" :size="17" /></span>
                Mesai geçmişi
            </p>
            <ul v-if="history.length" class="flex flex-col gap-2.5">
                <li v-for="h in history" :key="h.id" class="rounded-2xl bg-(--color-inset) p-3">
                    <div class="flex items-start justify-between gap-3">
                        <div class="min-w-0">
                            <p class="text-sm font-semibold capitalize text-body">{{ dayName(h.date) }}</p>
                            <p class="mt-0.5 text-xs text-muted">
                                {{ dayMonth(h.date) }} · {{ clockTime(h.clock_in_at) }}<template v-if="h.clock_out_at"> – {{ clockTime(h.clock_out_at) }}</template>
                            </p>
                        </div>
                        <div class="shrink-0 text-right">
                            <p class="text-lg font-extrabold leading-none text-body">{{ formatMinutes(h.worked_min) }}</p>
                            <span
                                v-if="!h.clock_out_at"
                                class="mt-1.5 inline-flex items-center gap-1.5 rounded-full bg-(--p-emerald-soft) px-2 py-0.5 text-[0.7rem] font-bold text-(--p-emerald)"
                            >
                                <span class="size-1.5 animate-pulse rounded-full bg-current" />
                                sürüyor
                            </span>
                            <p v-else class="mt-0.5 text-xs text-muted">çalışma</p>
                        </div>
                    </div>
                    <div v-if="h.break_min || h.toilet_min" class="mt-2 flex flex-wrap gap-1.5">
                        <span
                            v-if="h.break_min"
                            class="inline-flex items-center gap-1 rounded-full bg-(--p-amber-soft) px-2 py-0.5 text-[0.7rem] font-semibold text-(--p-amber)"
                        >
                            <AppIcon name="coffee" :size="12" />
                            {{ formatMinutes(h.break_min) }}
                        </span>
                        <span
                            v-if="h.toilet_min"
                            class="inline-flex items-center gap-1 rounded-full bg-(--p-violet-soft) px-2 py-0.5 text-[0.7rem] font-semibold text-(--p-violet)"
                        >
                            <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                <path d="M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5S5 13 5 15a7 7 0 0 0 7 7z" />
                            </svg>
                            {{ formatMinutes(h.toilet_min) }}
                        </span>
                    </div>
                </li>
            </ul>
            <p v-else class="py-1 text-sm text-muted">Henüz mesai kaydı yok.</p>
        </div>

        <div v-if="loading" class="mt-4 h-1 animate-pulse rounded bg-(--color-inset)" />
    </PortalLayout>
</template>
