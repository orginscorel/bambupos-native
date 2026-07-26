<script setup lang="ts">
/**
 * Portal "Mesaim": kişinin KENDİ mesai/mola/tuvalet başlat-bitir (PIN'SİZ) +
 * bugünün vardiyası, çalışılan/mola süresi (canlı). Mola/tuvalet olayı §8
 * bildirimini tetikler (yönetici + mesaidekiler).
 */
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PortalLayout from '@/Layouts/PortalLayout.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import type { PortalState } from '@/types/portal';
import { formatMinutes } from '@/types/portal';

const { success, danger } = useToast();

const state = ref<PortalState | null>(null);
const loading = ref(true);
const busy = ref(false);
let timer: ReturnType<typeof setInterval> | null = null;

const working = computed(() => state.value?.status === 'working');
const onBreak = computed(() => state.value?.on_break === true);
const onToilet = computed(() => onBreak.value && state.value?.break_kind === 'toilet');
const onRegularBreak = computed(() => onBreak.value && state.value?.break_kind !== 'toilet');

const timeFmt = new Intl.DateTimeFormat('tr-TR', { hour: '2-digit', minute: '2-digit' });
const clockTime = (iso: string | null | undefined): string => (iso ? timeFmt.format(new Date(iso)) : '—');

const shiftLabel = computed(() => {
    const s = state.value?.today_shift;
    if (!s) return null;
    return `${clockTime(s.starts_at)} – ${clockTime(s.ends_at)}`;
});

async function refresh(): Promise<void> {
    try {
        state.value = await api<PortalState>('/api/v1/portal/state');
    } catch {
        /* durum süsleyici — sessiz */
    } finally {
        loading.value = false;
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
const clockOut = () => act('/api/v1/portal/clock/out', 'Mesai bitirildi');
const breakStart = () => act('/api/v1/portal/break/start', 'Molaya çıkıldı', { kind: 'break' });
const toiletStart = () => act('/api/v1/portal/break/start', 'Tuvalet molası başladı', { kind: 'toilet' });
const breakEnd = () => act('/api/v1/portal/break/end', 'Moladan dönüldü');

onMounted(() => {
    void refresh();
    timer = setInterval(() => {
        if (document.visibilityState === 'visible') void refresh();
    }, 30000);
});

onBeforeUnmount(() => {
    if (timer) clearInterval(timer);
});
</script>

<template>
    <PortalLayout title="Mesaim" active="shift">
        <!-- Durum kartı -->
        <div class="rounded-xl border border-(--ui-border) bg-raised p-5 shadow-(--shadow-card)">
            <div class="flex items-center gap-3">
                <span
                    class="flex size-12 items-center justify-center rounded-full"
                    :class="working ? (onBreak ? 'bg-(--color-warning-soft) text-(--color-warning)' : 'bg-(--color-success-soft) text-(--color-success)') : 'bg-(--color-inset) text-muted'"
                >
                    <AppIcon :name="working ? (onBreak ? 'coffee' : 'check') : 'clock'" :size="24" />
                </span>
                <div class="min-w-0">
                    <p class="text-lg font-semibold text-body">
                        <template v-if="!working">Mesaide değilsiniz</template>
                        <template v-else-if="onToilet">Tuvalet molasındasınız</template>
                        <template v-else-if="onRegularBreak">Moladasınız</template>
                        <template v-else>Mesaidesiniz</template>
                    </p>
                    <p v-if="working && state?.entry" class="text-sm text-muted">
                        Giriş {{ clockTime(state.entry.clock_in_at) }} · Çalışma {{ formatMinutes(state.entry.worked_min) }}
                    </p>
                    <p v-else-if="!working" class="text-sm text-muted">Başlamak için mesai başlatın.</p>
                </div>
            </div>

            <!-- Bugünün vardiyası -->
            <div v-if="shiftLabel" class="mt-4 flex items-center gap-2 rounded-lg bg-(--color-inset) px-3 py-2 text-sm">
                <AppIcon name="calendar" :size="16" class="text-muted" />
                <span class="text-muted">Bugünkü vardiya:</span>
                <span class="font-medium text-body">{{ shiftLabel }}</span>
            </div>

            <!-- Süre özeti -->
            <div v-if="working && state?.entry" class="mt-4 grid grid-cols-3 gap-2 text-center">
                <div class="rounded-lg bg-(--color-inset) py-2">
                    <p class="text-xs text-subtle">Çalışma</p>
                    <p class="mt-0.5 text-sm font-semibold text-body">{{ formatMinutes(state.entry.worked_min) }}</p>
                </div>
                <div class="rounded-lg bg-(--color-inset) py-2">
                    <p class="text-xs text-subtle">Mola</p>
                    <p class="mt-0.5 text-sm font-semibold text-body">{{ formatMinutes(state.entry.break_total_min) }}</p>
                </div>
                <div class="rounded-lg bg-(--color-inset) py-2">
                    <p class="text-xs text-subtle">Tuvalet</p>
                    <p class="mt-0.5 text-sm font-semibold text-body">{{ formatMinutes(state.entry.toilet_total_min) }}</p>
                </div>
            </div>
        </div>

        <!-- Eylemler -->
        <div class="mt-5 flex flex-col gap-3">
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

        <!-- Bugünkü molalar -->
        <div v-if="state?.entry?.breaks?.length" class="mt-6">
            <p class="mb-2 text-sm font-semibold text-body">Bugünkü molalar</p>
            <ul class="flex flex-col divide-y divide-(--ui-border) overflow-hidden rounded-xl border border-(--ui-border) bg-raised">
                <li v-for="(b, i) in state.entry.breaks" :key="i" class="flex items-center justify-between px-4 py-2.5 text-sm">
                    <span class="flex items-center gap-2">
                        <AppIcon name="coffee" :size="15" class="text-muted" />
                        <span class="text-body">{{ b.kind_label }}</span>
                    </span>
                    <span class="text-muted">
                        {{ clockTime(b.started_at) }}<template v-if="b.ended_at"> – {{ clockTime(b.ended_at) }}</template>
                        <template v-else> · sürüyor</template>
                    </span>
                </li>
            </ul>
        </div>
    </PortalLayout>
</template>
