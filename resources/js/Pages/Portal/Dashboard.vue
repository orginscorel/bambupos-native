<script setup lang="ts">
/**
 * Portal "Panelim" — personelin ANA EKRANI (özet dashboard).
 *
 * Tek bakışta: mesai durumu + hızlı başlat/bitir/mola, açık görev özeti,
 * bu haftaki performans mini-özeti ve hızlı erişim. Özel görsel kimlik
 * (p-card / p-tile-* / p-chip — app.css .portal-root). Selamlama + tarih
 * PortalLayout hero'sunda (heading/subtitle) gösterilir.
 */
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { formatNumber } from '@/lib/format';
import { authFromPage } from '@/types/auth';
import { useToast } from '@/composables/useToast';
import PortalLayout from '@/Layouts/PortalLayout.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import type { PortalState } from '@/types/portal';
import { formatMinutes } from '@/types/portal';

interface TaskDTO {
    id: number;
    title: string;
    priority: string;
    status: string;
    due_at: string | null;
}
interface TasksResp {
    tasks: TaskDTO[];
    counts: { open: number; in_progress: number; done: number };
}
interface ReportResp {
    worked: { total_min: number; active_days: number };
    ops: { prepared_count: number; taken_count: number; served_count: number; avg_delivery_min: number | null };
    role_label: string | null;
}

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));
const firstName = computed(() => {
    const n = auth.value?.user?.name?.trim() ?? '';
    return n.split(' ')[0] || '';
});

const { success, danger } = useToast();

const state = ref<PortalState | null>(null);
const tasks = ref<TasksResp | null>(null);
const report = ref<ReportResp | null>(null);
const loading = ref(true);
const busy = ref(false);

/* Teslimat modülü (kurye): erişim/aktif teslimat varsa hızlı-erişim kartı gösterilir.
 * Erişim yoksa (403) veya hata olursa sessizce gizli kalır. */
interface DeliveryLite {
    status: 'pending' | 'assigned' | 'on_the_way' | 'delivered' | 'failed';
}
const activeDeliveries = ref(0);

const working = computed(() => state.value?.status === 'working');
const onBreak = computed(() => state.value?.on_break === true);

const greeting = computed(() => {
    const h = new Date().getHours();
    if (h < 6) return 'İyi geceler';
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi çalışmalar';
    return 'İyi akşamlar';
});
const heading = computed(() => (firstName.value ? `${greeting.value}, ${firstName.value} 👋` : `${greeting.value} 👋`));

/** Canlı saat: her saniye güncellenen zaman kaynağı (ms). */
const now = ref(Date.now());
let clockTimer: ReturnType<typeof setInterval> | null = null;

const todayLabel = computed(() =>
    new Intl.DateTimeFormat('tr-TR', { weekday: 'long', day: 'numeric', month: 'long' }).format(new Date()),
);

const timeFmt = new Intl.DateTimeFormat('tr-TR', { hour: '2-digit', minute: '2-digit' });
const clockTime = (iso: string | null | undefined): string => (iso ? timeFmt.format(new Date(iso)) : '—');
/** Canlı HH:MM (now ref'ine bağlı, dakika döndükçe güncellenir). */
const liveClock = computed(() => timeFmt.format(new Date(now.value)));
/** Hero alt satırı: "Pazar, 26 Temmuz · 20:47" (canlı saat). */
const subtitle = computed(() => `${todayLabel.value} · ${liveClock.value}`);
const shiftLabel = computed(() => {
    const s = state.value?.today_shift;
    return s ? `${clockTime(s.starts_at)} – ${clockTime(s.ends_at)}` : null;
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

const openTasks = computed(() => (tasks.value?.tasks ?? []).filter((t) => t.status !== 'done').slice(0, 3));
const openCount = computed(() => (tasks.value?.counts?.open ?? 0) + (tasks.value?.counts?.in_progress ?? 0));

/** "Bugün" mini performans kutuları (renkli p-tile, ikon + büyük sayı). */
interface TodayTile {
    label: string;
    value: string;
    icon: string;
    tile: string;
}
const todayTiles = computed<TodayTile[]>(() => {
    const r = report.value;
    return [
        { label: 'Çalışma', value: r ? formatMinutes(r.worked.total_min) : '—', icon: 'clock', tile: 'p-tile-teal' },
        { label: 'Servis', value: r ? formatNumber(r.ops.served_count) : '—', icon: 'utensils', tile: 'p-tile-emerald' },
        {
            label: 'Ort. teslim',
            value: r?.ops.avg_delivery_min ? formatMinutes(r.ops.avg_delivery_min) : '—',
            icon: 'cart',
            tile: 'p-tile-sky',
        },
    ];
});

async function loadAll(): Promise<void> {
    const [s, t, r, d] = await Promise.allSettled([
        api<PortalState>('/api/v1/portal/state'),
        api<TasksResp>('/api/v1/portal/tasks'),
        api<ReportResp>('/api/v1/portal/reports?period=day'),
        api<{ deliveries: DeliveryLite[] }>('/api/v1/portal/deliveries'),
    ]);
    if (s.status === 'fulfilled') state.value = s.value;
    if (t.status === 'fulfilled') tasks.value = t.value;
    if (r.status === 'fulfilled') report.value = r.value;
    if (d.status === 'fulfilled') {
        activeDeliveries.value = (d.value.deliveries ?? []).filter(
            (x) => x.status !== 'delivered' && x.status !== 'failed',
        ).length;
    }
    loading.value = false;
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
const breakEnd = () => act('/api/v1/portal/break/end', 'Moladan dönüldü');

const priorityMeta = (p: string): { label: string; cls: string } =>
    p === 'high'
        ? { label: 'Yüksek', cls: 'bg-(--p-rose-soft) text-(--p-rose)' }
        : p === 'low'
          ? { label: 'Düşük', cls: 'bg-(--color-inset) text-muted' }
          : { label: 'Normal', cls: 'bg-(--p-indigo-soft) text-(--p-indigo)' };

const quick = [
    { label: 'Mesaim', icon: 'clock', href: '/mesaim', tile: 'p-tile-teal' },
    { label: 'Görevlerim', icon: 'clipboard', href: '/gorevlerim', tile: 'p-tile-indigo' },
    { label: 'Takvim', icon: 'calendar', href: '/takvim', tile: 'p-tile-violet' },
    { label: 'Raporlarım', icon: 'chart', href: '/raporlarim', tile: 'p-tile-amber' },
];

onMounted(() => {
    void loadAll();
    clockTimer = setInterval(() => {
        now.value = Date.now();
    }, 1000);
});

onBeforeUnmount(() => {
    if (clockTimer) clearInterval(clockTimer);
});
</script>

<template>
    <PortalLayout title="Panelim" active="home" :heading="heading" :subtitle="subtitle">
        <!-- Pozisyon/rol rozeti (backend zaten hesaplıyor: PortalPerformanceService::roleLabel) -->
        <span
            v-if="report?.role_label"
            class="mb-3.5 inline-flex w-fit items-center rounded-full bg-(--p-indigo-soft) px-2.5 py-1 text-xs font-semibold text-(--p-indigo)"
        >
            {{ report.role_label }}
        </span>

        <!-- Mesai durumu + hızlı aksiyon -->
        <div class="p-card p-4">
            <div class="flex items-center gap-3.5">
                <span
                    class="flex size-14 shrink-0 items-center justify-center rounded-2xl"
                    :class="working ? (onBreak ? 'bg-(--p-amber-soft) text-(--p-amber)' : 'bg-(--p-emerald-soft) text-(--p-emerald)') : 'bg-(--color-inset) text-muted'"
                >
                    <AppIcon :name="working ? (onBreak ? 'coffee' : 'check') : 'clock'" :size="26" />
                </span>
                <div class="min-w-0 flex-1">
                    <p class="text-base font-bold text-body">
                        <template v-if="!working">Mesaide değilsiniz</template>
                        <template v-else-if="onBreak">Moladasınız</template>
                        <template v-else>Mesaidesiniz</template>
                    </p>
                    <p class="mt-0.5 text-sm text-muted">
                        <template v-if="working && state?.entry">Bugün {{ formatMinutes(state.entry.worked_min) }} fiili çalışma</template>
                        <template v-else-if="shiftLabel">Bugünkü vardiya: {{ shiftLabel }}</template>
                        <template v-else>Başlamak için mesai başlatın.</template>
                    </p>
                </div>
                <BaseButton v-if="!working" size="sm" :loading="busy" @click="clockIn">Başlat</BaseButton>
                <BaseButton v-else-if="onBreak" size="sm" variant="secondary" :loading="busy" @click="breakEnd">Dön</BaseButton>
                <Link v-else href="/mesaim" class="shrink-0 text-sm font-semibold text-(--p-indigo)">Mesaim →</Link>
            </div>

            <!-- Vardiya bitişine kalan süre (canlı) + planlı süre -->
            <div v-if="remainingMin !== null || plannedMin !== null" class="mt-3.5 flex flex-wrap items-center gap-2">
                <span
                    v-if="remainingMin !== null"
                    class="inline-flex min-h-11 items-center gap-2 rounded-xl px-3 py-2 text-sm font-semibold"
                    :class="remainingMin > 0 ? 'bg-(--p-teal-soft) text-(--p-teal)' : 'bg-(--p-rose-soft) text-(--p-rose)'"
                >
                    <AppIcon name="clock" :size="16" />
                    <template v-if="remainingMin > 0">Bitişe {{ formatMinutes(remainingMin) }} kaldı</template>
                    <template v-else>Vardiya süresi doldu</template>
                </span>
                <span
                    v-if="plannedMin !== null"
                    class="inline-flex min-h-11 items-center gap-2 rounded-xl bg-(--color-inset) px-3 py-2 text-sm font-medium text-muted"
                >
                    <AppIcon name="calendar" :size="16" />
                    Planlı: <span class="font-semibold text-body">{{ formatMinutes(plannedMin) }}</span>
                </span>
            </div>
        </div>

        <!-- Teslimatlarım (yalnız kurye erişimi + aktif teslimat varsa) -->
        <Link
            v-if="activeDeliveries > 0"
            href="/teslimatlarim"
            class="mt-4 p-card flex items-center gap-3.5 p-4 transition active:scale-[0.98]"
        >
            <span class="p-tile flex size-12 shrink-0 items-center justify-center !p-0 p-tile-indigo">
                <AppIcon name="package" :size="22" />
            </span>
            <div class="min-w-0 flex-1">
                <p class="text-base font-bold text-body">Teslimatlarım</p>
                <p class="mt-0.5 text-sm text-muted">{{ activeDeliveries }} aktif teslimat seni bekliyor</p>
            </div>
            <span class="shrink-0 rounded-full bg-(--p-indigo-soft) px-2.5 py-1 text-sm font-bold text-(--p-indigo)">{{ activeDeliveries }}</span>
            <AppIcon name="chevron-right" :size="16" class="shrink-0 text-subtle" />
        </Link>

        <!-- Bugün performans mini (renkli tile'lar) -->
        <div class="mt-4 p-card p-4">
            <div class="mb-3.5 flex items-center justify-between gap-2">
                <p class="flex items-center gap-2.5 font-semibold text-body">
                    <span class="p-chip" style="--chip-bg: var(--p-amber-soft); --chip-fg: var(--p-amber)"><AppIcon name="chart" :size="18" /></span>
                    Bugün
                </p>
                <Link href="/raporlarim" class="shrink-0 text-sm font-semibold text-(--p-indigo)">Detay →</Link>
            </div>
            <div class="grid grid-cols-3 gap-3">
                <div v-for="t in todayTiles" :key="t.label" class="p-tile flex flex-col" :class="t.tile">
                    <div class="flex items-center gap-1.5 opacity-80">
                        <AppIcon :name="t.icon" :size="15" />
                        <span class="truncate text-xs font-medium">{{ t.label }}</span>
                    </div>
                    <p class="mt-1.5 text-2xl font-extrabold leading-none tracking-tight">{{ t.value }}</p>
                </div>
            </div>
        </div>

        <!-- Görev özeti -->
        <div class="mt-4 p-card p-4">
            <div class="mb-3.5 flex items-center justify-between gap-2">
                <p class="flex items-center gap-2.5 font-semibold text-body">
                    <span class="p-chip"><AppIcon name="clipboard" :size="18" /></span>
                    Görevlerim
                    <span v-if="openCount" class="rounded-full bg-(--p-indigo-soft) px-2 py-0.5 text-xs font-bold text-(--p-indigo)">{{ openCount }}</span>
                </p>
                <Link href="/gorevlerim" class="shrink-0 text-sm font-semibold text-(--p-indigo)">Tümü →</Link>
            </div>
            <ul v-if="openTasks.length" class="flex flex-col gap-2">
                <li v-for="t in openTasks" :key="t.id" class="flex items-center gap-2.5 rounded-xl bg-(--color-inset) px-3 py-2.5">
                    <span class="shrink-0 rounded-full px-2 py-0.5 text-[0.7rem] font-bold" :class="priorityMeta(t.priority).cls">{{ priorityMeta(t.priority).label }}</span>
                    <span class="min-w-0 flex-1 truncate text-sm text-body">{{ t.title }}</span>
                </li>
            </ul>
            <div v-else class="flex flex-col items-center gap-2 py-6 text-center">
                <span class="flex size-12 items-center justify-center rounded-full bg-(--p-emerald-soft) text-(--p-emerald)">
                    <AppIcon name="check" :size="22" />
                </span>
                <p class="text-sm font-medium text-muted">Açık görev yok. Harikasın! 🎉</p>
            </div>
        </div>

        <!-- Hızlı erişim (renkli çipli kartlar) -->
        <div class="mt-4">
            <p class="mb-3 flex items-center gap-2.5 px-1 font-semibold text-body">
                <span class="p-chip" style="--chip-bg: var(--p-violet-soft); --chip-fg: var(--p-violet)"><AppIcon name="dashboard" :size="18" /></span>
                Hızlı erişim
            </p>
            <div class="grid grid-cols-2 gap-3">
                <Link
                    v-for="q in quick"
                    :key="q.href"
                    :href="q.href"
                    class="p-card flex min-h-16 items-center gap-3 px-4 py-3.5 transition active:scale-[0.98]"
                >
                    <span class="p-tile flex size-11 shrink-0 items-center justify-center !p-0" :class="q.tile">
                        <AppIcon :name="q.icon" :size="20" />
                    </span>
                    <span class="min-w-0 flex-1 truncate text-sm font-semibold text-body">{{ q.label }}</span>
                    <AppIcon name="chevron-right" :size="16" class="shrink-0 text-subtle" />
                </Link>
            </div>
        </div>

        <div v-if="loading" class="mt-4 flex items-center justify-center gap-2 text-xs font-medium text-subtle">
            <span class="size-1.5 animate-pulse rounded-full bg-(--p-indigo)" />
            Güncelleniyor…
        </div>
    </PortalLayout>
</template>
