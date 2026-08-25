<script setup lang="ts">
/**
 * /panel/boss — YÖNETİM KOKPİTİ (patron/yönetici özeti).
 *
 * Tek ekranda: büyük ciro kartı + önceki döneme kıyas oku, KPI kartları,
 * saatlik/günlük satış grafiği (inline SVG), ödeme & servis tipi dağılımı
 * (donut), en çok satanlar, personel performans mini-tablosu, düşük stok ve
 * teslimat özet kartları. Veriler /api/v1/boss/overview'dan gelir (mevcut
 * modüllerden derlenir). Sayfa `boss.view` iznine bağlıdır (asıl koruma backend).
 */
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { usePermissions } from '@/composables/usePermissions';
import { useToast } from '@/composables/useToast';
import { formatCurrencyMinor, formatNumber } from '@/lib/format';
import BossLayout from '@/Layouts/BossLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import ChartColumn from '@/Pages/Panel/Reports/components/ChartColumn.vue';
import ChartLine from '@/Pages/Panel/Reports/components/ChartLine.vue';
import '@/Pages/Panel/Reports/viz.css';

type Period = 'day' | 'week' | 'month';

interface StaffLite {
    id: number;
    name: string;
    position: string | null;
}

interface Overview {
    range: { from: string; to: string; branch_id: number | null; timezone: string };
    sales: {
        revenue_minor: number;
        orders: number;
        avg_basket_minor: number;
        cancelled_orders: number;
        prev: { revenue_minor: number; orders: number; avg_basket_minor: number };
        delta_pct: { revenue: number | null; orders: number | null; avg_basket: number | null };
    };
    by_day: { date: string; revenue_minor: number; orders: number }[];
    by_hour: { hour: number; revenue_minor: number; orders: number }[];
    by_weekday: { weekday: number; revenue_minor: number; orders: number }[];
    payment_mix: {
        total_minor: number;
        rows: { method: string; label: string; count: number; amount_minor: number; share: number }[];
    };
    service_types: {
        total_minor: number;
        rows: { type: string; label: string; orders: number; revenue_minor: number; share: number }[];
    };
    channel_mix: {
        total_minor: number;
        rows: { channel: string; label: string; orders: number; revenue_minor: number; share: number }[];
    };
    top_products: { name: string; qty: number; revenue_minor: number }[];
    top_categories: { name: string; qty: number; revenue_minor: number }[];
    top_tables: { name: string; orders: number; revenue_minor: number }[];
    discounts: { discount_minor: number; comp_minor: number; discount_orders: number; comp_orders: number };
    open: {
        open_orders: number;
        open_amount_minor: number;
        open_tables: number;
        receivables: { count: number; total_minor: number; enabled: boolean };
    };
    staff: {
        rows: { user: StaffLite; sales_minor: number; order_count: number; commission_minor: number }[];
        commission_total_minor: number;
        sales_total_minor: number;
    };
    on_shift: { name: string; position: string | null; since: string; worked_minutes: number }[];
    upcoming_today: { name: string; position: string | null; start: string }[];
    inventory: { critical: number; low: number; rows: InventoryRow[] } | null;
    delivery: {
        pending: number;
        assigned: number;
        on_the_way: number;
        delivered: number;
        failed: number;
        total: number;
    } | null;
    operations: {
        covers: number;
        revenue_per_guest_minor: number | null;
        avg_service_min: number | null;
        table_turnover: number | null;
        qr_share: number | null;
        qr_orders: number;
        cancellation_rate: number | null;
        cancelled_orders: number;
        peak_hour: { hour: number; orders: number } | null;
        best_day: { date: string; revenue_minor: number } | null;
    };
}

interface InventoryRow {
    item_id: number;
    name: string;
    severity: 'critical' | 'low';
    on_hand: string;
    threshold: string;
    unit: string;
}

const { can } = usePermissions();
const { danger } = useToast();

const canView = computed(() => can('boss.view'));

const loading = ref(true);
const period = ref<Period>('day');
const data = ref<Overview | null>(null);

const periods: { value: Period; label: string }[] = [
    { value: 'day', label: 'Bugün' },
    { value: 'week', label: 'Bu Hafta' },
    { value: 'month', label: 'Bu Ay' },
];

const dateFmt = new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'long' });

const rangeLabel = computed(() => {
    const r = data.value?.range;
    if (!r) return '';
    if (r.from === r.to) return dateFmt.format(new Date(r.from));
    return `${dateFmt.format(new Date(r.from))} – ${dateFmt.format(new Date(r.to))}`;
});

async function load(): Promise<void> {
    if (!canView.value) {
        loading.value = false;
        return;
    }
    loading.value = true;
    try {
        const res = await api<{ data: Overview }>(`/api/v1/boss/overview?period=${period.value}`);
        data.value = res.data;
    } catch (e) {
        danger('Kokpit yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
}

function setPeriod(p: Period): void {
    if (period.value === p) return;
    period.value = p;
    void load();
}

onMounted(load);

/* ---- Trend / kıyas oku ---- */
interface Trend {
    glyph: string;
    cls: string;
    text: string;
}
function trend(pct: number | null): Trend {
    if (pct === null) return { glyph: '—', cls: 'text-subtle', text: 'kıyas yok' };
    if (pct > 0) return { glyph: '▲', cls: 'text-success', text: `%${formatNumber(pct)}` };
    if (pct < 0) return { glyph: '▼', cls: 'text-danger', text: `%${formatNumber(Math.abs(pct))}` };
    return { glyph: '▬', cls: 'text-subtle', text: 'değişim yok' };
}

/* ---- Grafik noktaları ---- */
const hourPoints = computed(() =>
    (data.value?.by_hour ?? []).map((h) => ({
        label: String(h.hour).padStart(2, '0'),
        title: `${String(h.hour).padStart(2, '0')}:00`,
        value: h.revenue_minor,
    })),
);
const dayPoints = computed(() =>
    (data.value?.by_day ?? []).map((d) => ({
        label: dateFmt.format(new Date(d.date)),
        title: dateFmt.format(new Date(d.date)),
        value: d.revenue_minor,
    })),
);
const showDailyTrend = computed(() => (data.value?.by_day?.length ?? 0) > 1);

/* Haftanın günleri (0=Pzt … 6=Paz) */
const DAY_SHORT = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const DAY_FULL = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
const weekdayPoints = computed(() =>
    (data.value?.by_weekday ?? []).map((w) => ({
        label: DAY_SHORT[w.weekday],
        title: DAY_FULL[w.weekday],
        value: w.revenue_minor,
    })),
);
const showWeekday = computed(() => (data.value?.by_day?.length ?? 0) > 1);

/* Kategori satışları: en yüksek ciroya göre normalize edilmiş bar payı */
const categoryBars = computed(() => {
    const rows = data.value?.top_categories ?? [];
    const max = rows.reduce((m, r) => Math.max(m, r.revenue_minor), 0);
    return rows.map((r) => ({
        name: r.name,
        qty: r.qty,
        revenue_minor: r.revenue_minor,
        pct: max > 0 ? Math.round((r.revenue_minor / max) * 100) : 0,
    }));
});

/* ---- Donut ---- */
const VIZ = ['var(--viz-1)', 'var(--viz-2)', 'var(--viz-3)', 'var(--viz-4)', 'var(--viz-other)'];
interface DonutSeg {
    label: string;
    share: number;
    color: string;
    dash: string;
    offset: number;
}
function donut(rows: { label: string; share: number }[]): DonutSeg[] {
    let acc = 0;
    return rows
        .filter((r) => r.share > 0)
        .map((r, i) => {
            const seg: DonutSeg = {
                label: r.label,
                share: r.share,
                color: VIZ[i] ?? VIZ[VIZ.length - 1],
                dash: `${r.share} ${100 - r.share}`,
                offset: 25 - acc,
            };
            acc += r.share;
            return seg;
        });
}
const paymentDonut = computed(() => donut(data.value?.payment_mix.rows ?? []));
const serviceDonut = computed(() => donut(data.value?.service_types.rows.map((r) => ({ label: r.label, share: r.share })) ?? []));
const channelDonut = computed(() => donut(data.value?.channel_mix.rows.map((r) => ({ label: r.label, share: r.share })) ?? []));

/* Masa bazlı ciro: en yüksek ciroya göre normalize bar */
const tableBars = computed(() => {
    const rows = data.value?.top_tables ?? [];
    const max = rows.reduce((m, r) => Math.max(m, r.revenue_minor), 0);
    return rows.map((r) => ({
        name: r.name,
        orders: r.orders,
        revenue_minor: r.revenue_minor,
        pct: max > 0 ? Math.round((r.revenue_minor / max) * 100) : 0,
    }));
});

const money = (m: number): string => formatCurrencyMinor(m);
const hasData = computed(() => (data.value?.sales.orders ?? 0) > 0);

/* ---- Operasyon metrik yardımcıları ---- */
const hourLabel = (h: number): string => `${String(h).padStart(2, '0')}:00`;
function shortDate(iso: string): string {
    const d = new Date(iso + 'T00:00:00');
    return d.toLocaleDateString('tr-TR', { weekday: 'short', day: '2-digit', month: 'short' });
}

/* ---- Canlı mesai / bugünkü plan ---- */
const timeFmt = new Intl.DateTimeFormat('tr-TR', { hour: '2-digit', minute: '2-digit' });
const clock = (iso: string): string => timeFmt.format(new Date(iso));

/** Çalışılan dakikayı "X saat Y dk" (veya sadece "Y dk") biçimine getirir. */
function workedLabel(minutes: number): string {
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    if (h > 0) return `${formatNumber(h)} saat ${formatNumber(m)} dk`;
    return `${formatNumber(m)} dk`;
}
</script>

<template>
    <Head title="Patron Paneli" />
    <BossLayout title="Patron Paneli" :subtitle="rangeLabel">
        <!-- Dönem seçici: executive üst barın aksiyon alanında -->
        <template v-if="canView" #actions>
            <div class="mr-1 inline-flex rounded-lg bg-white/15 p-0.5 ring-1 ring-white/25">
                <button
                    v-for="p in periods"
                    :key="p.value"
                    type="button"
                    class="rounded-md px-3 py-1.5 text-sm font-semibold transition-colors duration-(--dur-fast)"
                    :class="period === p.value ? 'bg-white text-primary shadow' : 'text-white/80 hover:text-white'"
                    @click="setPeriod(p.value)"
                >
                    {{ p.label }}
                </button>
            </div>
        </template>

        <!-- Yetki yok -->
        <EmptyState
            v-if="!canView"
            icon="alert-circle"
            title="Erişim yok"
            description="Patron panelini görüntülemek için yetkiniz bulunmuyor."
        />

        <div v-else class="flex flex-col gap-4">

            <!-- Yükleniyor iskeleti -->
            <template v-if="loading">
                <BaseSkeleton class="h-32 w-full rounded-xl" />
                <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
                    <BaseSkeleton v-for="i in 4" :key="i" class="h-24 w-full rounded-xl" />
                </div>
                <BaseSkeleton class="h-64 w-full rounded-xl" />
            </template>

            <template v-else-if="data">
                <!-- Büyük ciro kartı — premium hero (marka gradyanı) -->
                <section class="boss-hero relative overflow-hidden rounded-2xl p-5 text-white shadow-lg sm:p-6">
                    <!-- Dekoratif arka plan ikonu (soluk, taşan) — düz renk hissini kırar. -->
                    <AppIcon name="chart" :size="190" class="boss-hero__decor" aria-hidden="true" />
                    <div class="relative flex flex-wrap items-end justify-between gap-5">
                        <div class="min-w-0">
                            <p class="flex items-center gap-1.5 text-sm font-medium text-white/80">
                                <AppIcon name="wallet" :size="16" />
                                Ciro · kapanan adisyon
                            </p>
                            <p class="mt-1 text-4xl font-bold tracking-tight break-words sm:text-5xl">{{ money(data.sales.revenue_minor) }}</p>
                            <p class="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
                                <span
                                    class="inline-flex items-center gap-1 rounded-full bg-white/15 px-2 py-0.5 font-semibold ring-1 ring-white/25"
                                    :class="data.sales.delta_pct.revenue !== null && data.sales.delta_pct.revenue < 0 ? 'text-rose-100' : 'text-emerald-100'"
                                >
                                    {{ trend(data.sales.delta_pct.revenue).glyph }} {{ trend(data.sales.delta_pct.revenue).text }}
                                </span>
                                <span class="text-white/70">önceki döneme göre ({{ money(data.sales.prev.revenue_minor) }})</span>
                            </p>
                            <a
                                href="#boss-sales"
                                class="group mt-2.5 inline-flex items-center gap-1 text-xs font-medium text-white/75 transition hover:text-white"
                            >
                                Günlük/saatlik ciro detayı
                                <AppIcon name="chevron-right" :size="12" class="transition-transform group-hover:translate-x-0.5" />
                            </a>
                        </div>
                        <div class="flex gap-3">
                            <div class="rounded-xl bg-white/12 px-4 py-2.5 ring-1 ring-white/20 backdrop-blur">
                                <p class="text-[11px] text-white/70">Sipariş</p>
                                <p class="text-xl font-bold">{{ formatNumber(data.sales.orders) }}</p>
                                <p class="text-[11px] font-medium text-white/80">
                                    {{ trend(data.sales.delta_pct.orders).glyph }} {{ trend(data.sales.delta_pct.orders).text }}
                                </p>
                            </div>
                            <div class="rounded-xl bg-white/12 px-4 py-2.5 ring-1 ring-white/20 backdrop-blur">
                                <p class="text-[11px] text-white/70">Ort. adisyon</p>
                                <p class="text-xl font-bold">{{ money(data.sales.avg_basket_minor) }}</p>
                                <p class="text-[11px] font-medium text-white/80">
                                    {{ trend(data.sales.delta_pct.avg_basket).glyph }} {{ trend(data.sales.delta_pct.avg_basket).text }}
                                </p>
                            </div>
                        </div>
                    </div>
                </section>

                <!-- KPI kartları -->
                <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
                    <article class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <p class="flex items-center gap-1.5 text-xs text-muted"><AppIcon name="utensils" :size="14" /> Açık masa</p>
                        <p class="mt-1 text-2xl font-semibold text-body">{{ formatNumber(data.open.open_tables) }}</p>
                        <p class="text-xs text-subtle">{{ formatNumber(data.open.open_orders) }} açık adisyon</p>
                    </article>
                    <article class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <p class="flex items-center gap-1.5 text-xs text-muted"><AppIcon name="orders" :size="14" /> Açık masa tutarı</p>
                        <p class="mt-1 text-2xl font-semibold text-body">{{ money(data.open.open_amount_minor) }}</p>
                        <p class="text-xs text-subtle">henüz tahsil edilmedi</p>
                    </article>
                    <article class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <p class="flex items-center gap-1.5 text-xs text-muted"><AppIcon name="tag" :size="14" /> Açık borç</p>
                        <p class="mt-1 text-2xl font-semibold text-body">
                            {{ data.open.receivables.enabled ? money(data.open.receivables.total_minor) : '—' }}
                        </p>
                        <p class="text-xs text-subtle">
                            {{ data.open.receivables.enabled ? `${formatNumber(data.open.receivables.count)} cari` : 'kapalı' }}
                        </p>
                    </article>
                    <a href="#boss-staff" class="group rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card) transition-colors hover:border-strong hover:bg-inset">
                        <p class="flex items-center gap-1.5 text-xs text-muted">
                            <AppIcon name="wallet" :size="14" /> Prim toplamı
                            <AppIcon name="chevron-right" :size="13" class="text-subtle transition-transform group-hover:translate-x-0.5" />
                        </p>
                        <p class="mt-1 text-2xl font-semibold text-body">{{ money(data.staff.commission_total_minor) }}</p>
                        <p class="text-xs text-subtle">dönem primi · personele göre gör</p>
                    </a>
                </div>

                <!-- Operasyon metrikleri (executive) -->
                <section>
                    <h2 class="mb-3 flex items-center gap-1.5 text-sm font-semibold text-body">
                        <AppIcon name="gauge" :size="15" class="text-muted" /> Operasyon metrikleri
                    </h2>
                    <div class="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-4">
                        <article class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                            <p class="flex items-center gap-1.5 text-xs text-muted"><AppIcon name="users" :size="14" /> Misafir</p>
                            <p class="mt-1 text-2xl font-semibold text-body">{{ formatNumber(data.operations.covers) }}</p>
                            <p class="text-xs text-subtle">
                                {{ data.operations.revenue_per_guest_minor !== null ? `${money(data.operations.revenue_per_guest_minor)} / kişi` : 'kişi başı —' }}
                            </p>
                        </article>
                        <article class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                            <p class="flex items-center gap-1.5 text-xs text-muted"><AppIcon name="clock" :size="14" /> Ort. servis süresi</p>
                            <p class="mt-1 text-2xl font-semibold text-body">
                                {{ data.operations.avg_service_min !== null ? `${formatNumber(data.operations.avg_service_min)} dk` : '—' }}
                            </p>
                            <p class="text-xs text-subtle">masa açılış → kapanış</p>
                        </article>
                        <a
                            href="#boss-tables"
                            class="group rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card) transition-colors hover:border-strong hover:bg-inset"
                        >
                            <p class="flex items-center gap-1.5 text-xs text-muted">
                                <AppIcon name="refresh-cw" :size="14" /> Masa devir hızı
                                <AppIcon name="chevron-right" :size="13" class="text-subtle transition-transform group-hover:translate-x-0.5" />
                            </p>
                            <p class="mt-1 text-2xl font-semibold text-body">
                                {{ data.operations.table_turnover !== null ? `${data.operations.table_turnover.toFixed(1)}×` : '—' }}
                            </p>
                            <p class="text-xs text-subtle">masa başına adisyon · masa bazlı ciro gör</p>
                        </a>
                        <article class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                            <p class="flex items-center gap-1.5 text-xs text-muted"><AppIcon name="qr-code" :size="14" /> QR self-servis</p>
                            <p class="mt-1 text-2xl font-semibold text-body">
                                {{ data.operations.qr_share !== null ? `%${data.operations.qr_share}` : '—' }}
                            </p>
                            <p class="text-xs text-subtle">{{ formatNumber(data.operations.qr_orders) }} QR sipariş</p>
                        </article>
                        <article class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                            <p class="flex items-center gap-1.5 text-xs text-muted"><AppIcon name="x-circle" :size="14" /> İptal oranı</p>
                            <p class="mt-1 text-2xl font-semibold" :class="(data.operations.cancellation_rate ?? 0) >= 10 ? 'text-danger' : 'text-body'">
                                {{ data.operations.cancellation_rate !== null ? `%${data.operations.cancellation_rate}` : '—' }}
                            </p>
                            <p class="text-xs text-subtle">{{ formatNumber(data.operations.cancelled_orders) }} iptal</p>
                        </article>
                        <a
                            href="#boss-sales"
                            class="group rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card) transition-colors hover:border-strong hover:bg-inset"
                        >
                            <p class="flex items-center gap-1.5 text-xs text-muted">
                                <AppIcon name="chart" :size="14" /> Yoğun saat
                                <AppIcon name="chevron-right" :size="13" class="text-subtle transition-transform group-hover:translate-x-0.5" />
                            </p>
                            <p class="mt-1 text-2xl font-semibold text-body">
                                {{ data.operations.peak_hour ? hourLabel(data.operations.peak_hour.hour) : '—' }}
                            </p>
                            <p class="text-xs text-subtle">
                                {{ data.operations.peak_hour ? `${formatNumber(data.operations.peak_hour.orders)} sipariş · saatlik dağılımı gör` : 'veri yok' }}
                            </p>
                        </a>
                        <a
                            href="#boss-sales"
                            class="group rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card) transition-colors hover:border-strong hover:bg-inset"
                        >
                            <p class="flex items-center gap-1.5 text-xs text-muted">
                                <AppIcon name="calendar" :size="14" /> En iyi gün
                                <AppIcon name="chevron-right" :size="13" class="text-subtle transition-transform group-hover:translate-x-0.5" />
                            </p>
                            <p class="mt-1 text-lg font-semibold text-body">
                                {{ data.operations.best_day ? shortDate(data.operations.best_day.date) : '—' }}
                            </p>
                            <p class="text-xs text-subtle">
                                {{ data.operations.best_day ? `${money(data.operations.best_day.revenue_minor)} · günlük seyri gör` : 'veri yok' }}
                            </p>
                        </a>
                        <article class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                            <p class="flex items-center gap-1.5 text-xs text-muted"><AppIcon name="tag" :size="14" /> İndirim</p>
                            <p class="mt-1 text-2xl font-semibold text-body">{{ money(data.discounts.discount_minor) }}</p>
                            <p class="text-xs text-subtle">{{ formatNumber(data.discounts.discount_orders) }} adisyonda</p>
                        </article>
                        <article class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                            <p class="flex items-center gap-1.5 text-xs text-muted"><AppIcon name="coffee" :size="14" /> İkram</p>
                            <p class="mt-1 text-2xl font-semibold text-body">{{ money(data.discounts.comp_minor) }}</p>
                            <p class="text-xs text-subtle">{{ formatNumber(data.discounts.comp_orders) }} adisyonda</p>
                        </article>
                    </div>
                </section>

                <!-- Canlı mesai: şu an mesaide + bugün gelecekler -->
                <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    <!-- Şu an mesaide -->
                    <section class="rounded-2xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <div class="mb-3 flex items-center justify-between">
                            <h2 class="flex items-center gap-1.5 text-sm font-semibold text-body">
                                <AppIcon name="users" :size="15" class="text-muted" /> Şu an mesaide
                            </h2>
                            <BaseBadge v-if="data.on_shift.length" variant="success" no-icon>
                                {{ formatNumber(data.on_shift.length) }} kişi
                            </BaseBadge>
                        </div>
                        <ul v-if="data.on_shift.length" class="space-y-2.5">
                            <li v-for="(p, i) in data.on_shift" :key="i" class="flex items-center gap-2 text-sm">
                                <span class="relative flex h-2.5 w-2.5 shrink-0">
                                    <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-success opacity-60" />
                                    <span class="relative inline-flex h-2.5 w-2.5 rounded-full bg-success" />
                                </span>
                                <span class="min-w-0 flex-1 truncate">
                                    <span class="font-medium text-body">{{ p.name }}</span>
                                    <span v-if="p.position" class="ml-1 text-xs text-subtle">· {{ p.position }}</span>
                                </span>
                                <span class="shrink-0 text-xs font-medium text-body">{{ workedLabel(p.worked_minutes) }}</span>
                                <span class="shrink-0 text-xs text-subtle">{{ clock(p.since) }}'den beri</span>
                            </li>
                        </ul>
                        <p v-else class="py-6 text-center text-xs text-subtle">Şu an mesaide personel yok.</p>
                    </section>

                    <!-- Bugün gelecekler -->
                    <section class="rounded-2xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <div class="mb-3 flex items-center justify-between">
                            <h2 class="flex items-center gap-1.5 text-sm font-semibold text-body">
                                <AppIcon name="clock" :size="15" class="text-muted" /> Bugün gelecekler
                            </h2>
                            <BaseBadge v-if="data.upcoming_today.length" variant="info" no-icon>
                                {{ formatNumber(data.upcoming_today.length) }} vardiya
                            </BaseBadge>
                        </div>
                        <ul v-if="data.upcoming_today.length" class="space-y-2.5">
                            <li v-for="(p, i) in data.upcoming_today" :key="i" class="flex items-center gap-2 text-sm">
                                <AppIcon name="clock" :size="14" class="shrink-0 text-subtle" />
                                <span class="min-w-0 flex-1 truncate">
                                    <span class="font-medium text-body">{{ p.name }}</span>
                                    <span v-if="p.position" class="ml-1 text-xs text-subtle">· {{ p.position }}</span>
                                </span>
                                <span class="shrink-0 text-xs font-medium text-body">{{ clock(p.start) }}</span>
                            </li>
                        </ul>
                        <p v-else class="py-6 text-center text-xs text-subtle">Bugün için planlı yeni vardiya yok.</p>
                    </section>
                </div>

                <!-- Boş dönem bilgisi -->
                <div
                    v-if="!hasData"
                    class="flex items-center gap-2 rounded-lg border border-dashed border-strong bg-surface-alt px-4 py-3 text-sm text-muted"
                >
                    <AppIcon name="info" :size="16" />
                    Bu dönemde kapanmış satış yok. Aşağıdaki grafikler dönem verisi geldikçe dolacak.
                </div>

                <!-- Satış grafikleri: günlük seyir + saatlik dağılım (yan yana) -->
                <div id="boss-sales" class="scroll-mt-24 grid grid-cols-1 gap-4" :class="showDailyTrend ? 'lg:grid-cols-2' : ''">
                    <section v-if="showDailyTrend" class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <div class="mb-3 flex items-center gap-1.5">
                            <AppIcon name="chart" :size="16" class="text-muted" />
                            <h2 class="text-sm font-semibold text-body">Günlük ciro seyri</h2>
                        </div>
                        <ChartLine :points="dayPoints" money label="Günlük ciro seyri" :height="200" />
                    </section>
                    <section class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <div class="mb-3 flex items-center gap-1.5">
                            <AppIcon name="clock" :size="16" class="text-muted" />
                            <h2 class="text-sm font-semibold text-body">Saatlik ciro dağılımı</h2>
                        </div>
                        <ChartColumn :points="hourPoints" money label="Saatlik ciro dağılımı" :height="200" />
                    </section>
                </div>

                <!-- Haftanın günleri + Kategori satışları -->
                <div class="grid grid-cols-1 gap-4" :class="showWeekday ? 'lg:grid-cols-2' : ''">
                    <section v-if="showWeekday" class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <div class="mb-3 flex items-center gap-1.5">
                            <AppIcon name="calendar" :size="16" class="text-muted" />
                            <h2 class="text-sm font-semibold text-body">Haftanın günleri</h2>
                        </div>
                        <ChartColumn :points="weekdayPoints" money label="Haftanın günleri" :height="180" />
                    </section>

                    <section class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <h2 class="mb-3 flex items-center gap-1.5 text-sm font-semibold text-body">
                            <AppIcon name="utensils" :size="15" class="text-muted" /> Kategori satışları
                        </h2>
                        <ul v-if="categoryBars.length" class="space-y-2.5">
                            <li v-for="(c, i) in categoryBars" :key="i">
                                <div class="mb-1 flex items-center justify-between gap-2 text-sm">
                                    <span class="truncate font-medium text-body">{{ c.name }}</span>
                                    <span class="shrink-0 text-xs text-muted">
                                        {{ formatNumber(c.qty) }} adet · <span class="font-medium text-body">{{ money(c.revenue_minor) }}</span>
                                    </span>
                                </div>
                                <div class="h-2 overflow-hidden rounded-full bg-inset">
                                    <div class="h-full rounded-full bg-primary transition-[width] duration-500" :style="{ width: c.pct + '%' }" />
                                </div>
                            </li>
                        </ul>
                        <p v-else class="py-6 text-center text-xs text-subtle">Bu dönemde satış yok.</p>
                    </section>
                </div>

                <!-- Kanal dağılımı + Masa bazlı ciro -->
                <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    <!-- Kanal dağılımı (QR / Kiosk / Masa / Paket) -->
                    <section class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <h2 class="mb-3 flex items-center gap-1.5 text-sm font-semibold text-body">
                            <AppIcon name="qr-code" :size="15" class="text-muted" /> Sipariş kanalı
                        </h2>
                        <div v-if="channelDonut.length" class="flex items-center gap-4">
                            <svg viewBox="0 0 36 36" class="h-24 w-24 shrink-0 -rotate-90">
                                <circle cx="18" cy="18" r="15.9155" fill="none" stroke="var(--viz-grid)" stroke-width="3.5" />
                                <circle
                                    v-for="(s, i) in channelDonut"
                                    :key="i"
                                    cx="18" cy="18" r="15.9155" fill="none"
                                    :stroke="s.color" stroke-width="3.5"
                                    :stroke-dasharray="s.dash" :stroke-dashoffset="s.offset"
                                />
                            </svg>
                            <ul class="flex-1 space-y-1.5 text-xs">
                                <li v-for="(s, i) in channelDonut" :key="i" class="flex items-center gap-2">
                                    <span class="h-2.5 w-2.5 shrink-0 rounded-full" :style="{ background: s.color }" />
                                    <span class="flex-1 truncate text-body">{{ s.label }}</span>
                                    <span class="font-medium text-muted">%{{ formatNumber(s.share) }}</span>
                                </li>
                            </ul>
                        </div>
                        <p v-else class="py-6 text-center text-xs text-subtle">Bu dönemde satış yok.</p>
                    </section>

                    <!-- Masa bazlı ciro -->
                    <section id="boss-tables" class="scroll-mt-24 rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <h2 class="mb-3 flex items-center gap-1.5 text-sm font-semibold text-body">
                            <AppIcon name="utensils" :size="15" class="text-muted" /> Masa bazlı ciro
                        </h2>
                        <ul v-if="tableBars.length" class="space-y-2.5">
                            <li v-for="(t, i) in tableBars" :key="i">
                                <div class="mb-1 flex items-center justify-between gap-2 text-sm">
                                    <span class="truncate font-medium text-body">{{ t.name }}</span>
                                    <span class="shrink-0 text-xs text-muted">
                                        {{ formatNumber(t.orders) }} adisyon · <span class="font-medium text-body">{{ money(t.revenue_minor) }}</span>
                                    </span>
                                </div>
                                <div class="h-2 overflow-hidden rounded-full bg-inset">
                                    <div class="h-full rounded-full bg-primary transition-[width] duration-500" :style="{ width: t.pct + '%' }" />
                                </div>
                            </li>
                        </ul>
                        <p v-else class="py-6 text-center text-xs text-subtle">Masa siparişi yok.</p>
                    </section>
                </div>

                <!-- Dağılımlar + En çok satanlar -->
                <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
                    <!-- Ödeme dağılımı -->
                    <section class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <h2 class="mb-3 flex items-center gap-1.5 text-sm font-semibold text-body">
                            <AppIcon name="wallet" :size="15" class="text-muted" /> Ödeme yöntemi
                        </h2>
                        <div v-if="paymentDonut.length" class="flex items-center gap-4">
                            <svg viewBox="0 0 36 36" class="h-24 w-24 shrink-0 -rotate-90">
                                <circle cx="18" cy="18" r="15.9155" fill="none" stroke="var(--viz-grid)" stroke-width="3.5" />
                                <circle
                                    v-for="(s, i) in paymentDonut"
                                    :key="i"
                                    cx="18"
                                    cy="18"
                                    r="15.9155"
                                    fill="none"
                                    :stroke="s.color"
                                    stroke-width="3.5"
                                    :stroke-dasharray="s.dash"
                                    :stroke-dashoffset="s.offset"
                                />
                            </svg>
                            <ul class="flex-1 space-y-1.5 text-xs">
                                <li v-for="(s, i) in paymentDonut" :key="i" class="flex items-center gap-2">
                                    <span class="h-2.5 w-2.5 shrink-0 rounded-full" :style="{ background: s.color }" />
                                    <span class="flex-1 truncate text-body">{{ s.label }}</span>
                                    <span class="font-medium text-muted">%{{ formatNumber(s.share) }}</span>
                                </li>
                            </ul>
                        </div>
                        <p v-else class="py-6 text-center text-xs text-subtle">Bu dönemde tahsilat yok.</p>
                    </section>

                    <!-- Servis tipi dağılımı -->
                    <section class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <h2 class="mb-3 flex items-center gap-1.5 text-sm font-semibold text-body">
                            <AppIcon name="store" :size="15" class="text-muted" /> Servis tipi
                        </h2>
                        <div v-if="serviceDonut.length" class="flex items-center gap-4">
                            <svg viewBox="0 0 36 36" class="h-24 w-24 shrink-0 -rotate-90">
                                <circle cx="18" cy="18" r="15.9155" fill="none" stroke="var(--viz-grid)" stroke-width="3.5" />
                                <circle
                                    v-for="(s, i) in serviceDonut"
                                    :key="i"
                                    cx="18"
                                    cy="18"
                                    r="15.9155"
                                    fill="none"
                                    :stroke="s.color"
                                    stroke-width="3.5"
                                    :stroke-dasharray="s.dash"
                                    :stroke-dashoffset="s.offset"
                                />
                            </svg>
                            <ul class="flex-1 space-y-1.5 text-xs">
                                <li v-for="(s, i) in serviceDonut" :key="i" class="flex items-center gap-2">
                                    <span class="h-2.5 w-2.5 shrink-0 rounded-full" :style="{ background: s.color }" />
                                    <span class="flex-1 truncate text-body">{{ s.label }}</span>
                                    <span class="font-medium text-muted">%{{ formatNumber(s.share) }}</span>
                                </li>
                            </ul>
                        </div>
                        <p v-else class="py-6 text-center text-xs text-subtle">Bu dönemde satış yok.</p>
                    </section>

                    <!-- En çok satanlar -->
                    <section class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <h2 class="mb-3 flex items-center gap-1.5 text-sm font-semibold text-body">
                            <AppIcon name="cart" :size="15" class="text-muted" /> En çok satanlar
                        </h2>
                        <ol v-if="data.top_products.length" class="space-y-2">
                            <li v-for="(p, i) in data.top_products" :key="i" class="flex items-center gap-2 text-sm">
                                <span class="w-5 text-right text-xs font-semibold text-subtle">{{ i + 1 }}.</span>
                                <span class="flex-1 truncate text-body">{{ p.name }}</span>
                                <span class="shrink-0 text-xs text-muted">{{ formatNumber(p.qty) }} adet</span>
                                <span class="shrink-0 text-xs font-medium text-body">{{ money(p.revenue_minor) }}</span>
                            </li>
                        </ol>
                        <p v-else class="py-6 text-center text-xs text-subtle">Satılan ürün yok.</p>
                    </section>
                </div>

                <!-- Personel performansı -->
                <section id="boss-staff" class="scroll-mt-24 rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                    <h2 class="mb-3 flex items-center gap-1.5 text-sm font-semibold text-body">
                        <AppIcon name="users" :size="15" class="text-muted" /> Personel performansı
                    </h2>
                    <div v-if="data.staff.rows.length" class="overflow-x-auto">
                        <table class="w-full min-w-[28rem] text-sm">
                            <thead>
                                <tr class="border-b border-default text-left text-xs text-subtle">
                                    <th class="pb-2 font-medium">Personel</th>
                                    <th class="pb-2 text-right font-medium">Ciro</th>
                                    <th class="pb-2 text-right font-medium">Sipariş</th>
                                    <th class="pb-2 text-right font-medium">Prim</th>
                                </tr>
                            </thead>
                            <tbody>
                                <tr v-for="row in data.staff.rows" :key="row.user.id" class="border-b border-default last:border-0">
                                    <td class="py-2">
                                        <span class="font-medium text-body">{{ row.user.name }}</span>
                                        <span v-if="row.user.position" class="ml-1 text-xs text-subtle">· {{ row.user.position }}</span>
                                    </td>
                                    <td class="py-2 text-right font-medium text-body">{{ money(row.sales_minor) }}</td>
                                    <td class="py-2 text-right text-muted">{{ formatNumber(row.order_count) }}</td>
                                    <td class="py-2 text-right text-muted">{{ money(row.commission_minor) }}</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                    <p v-else class="py-6 text-center text-xs text-subtle">Bu dönemde personel satışı yok.</p>
                </section>

                <!-- Düşük stok + Teslimat -->
                <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    <!-- Düşük stok -->
                    <section v-if="data.inventory" class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <div class="mb-3 flex items-center justify-between">
                            <h2 class="flex items-center gap-1.5 text-sm font-semibold text-body">
                                <AppIcon name="alert-triangle" :size="15" class="text-muted" /> Düşük stok
                            </h2>
                            <div class="flex gap-1.5">
                                <BaseBadge variant="danger" no-icon>{{ data.inventory.critical }} kritik</BaseBadge>
                                <BaseBadge variant="warning" no-icon>{{ data.inventory.low }} düşük</BaseBadge>
                            </div>
                        </div>
                        <ul v-if="data.inventory.rows.length" class="space-y-2">
                            <li v-for="row in data.inventory.rows" :key="row.item_id" class="flex items-center gap-2 text-sm">
                                <span
                                    class="h-2 w-2 shrink-0 rounded-full"
                                    :class="row.severity === 'critical' ? 'bg-danger' : 'bg-warning'"
                                />
                                <span class="flex-1 truncate text-body">{{ row.name }}</span>
                                <span class="shrink-0 text-xs text-muted">{{ row.on_hand }} {{ row.unit }}</span>
                            </li>
                        </ul>
                        <p v-else class="py-4 text-center text-xs text-subtle">Eşik altı stok yok.</p>
                    </section>

                    <!-- Teslimat -->
                    <section v-if="data.delivery" class="rounded-xl border border-default bg-raised p-4 shadow-(--shadow-card)">
                        <h2 class="mb-3 flex items-center gap-1.5 text-sm font-semibold text-body">
                            <AppIcon name="truck" :size="15" class="text-muted" /> Teslimat
                        </h2>
                        <div class="grid grid-cols-3 gap-3 text-center">
                            <div class="rounded-lg bg-surface-alt p-3">
                                <p class="text-xl font-semibold text-body">{{ formatNumber(data.delivery.pending + data.delivery.assigned) }}</p>
                                <p class="text-xs text-subtle">Bekleyen</p>
                            </div>
                            <div class="rounded-lg bg-surface-alt p-3">
                                <p class="text-xl font-semibold text-body">{{ formatNumber(data.delivery.on_the_way) }}</p>
                                <p class="text-xs text-subtle">Yolda</p>
                            </div>
                            <div class="rounded-lg bg-surface-alt p-3">
                                <p class="text-xl font-semibold text-body">{{ formatNumber(data.delivery.delivered) }}</p>
                                <p class="text-xs text-subtle">Teslim</p>
                            </div>
                        </div>
                        <p v-if="data.delivery.failed > 0" class="mt-2 text-center text-xs text-danger">
                            {{ formatNumber(data.delivery.failed) }} başarısız teslimat
                        </p>
                    </section>
                </div>
            </template>
        </div>
    </BossLayout>
</template>

<style scoped>
/* Zengin hero: katmanlı marka gradyanı + köşe parlaması + gölge derinliği. */
.boss-hero {
    background-color: var(--brand-700);
    background-image:
        radial-gradient(130% 150% at 100% 0%, rgb(255 255 255 / 0.20) 0%, transparent 46%),
        radial-gradient(90% 130% at 0% 100%, rgb(0 0 0 / 0.24) 0%, transparent 52%),
        linear-gradient(120deg, var(--brand-800) 0%, var(--brand-600) 55%, var(--brand-500) 100%);
}
/* İnce nokta deseni dokusu (düz renk hissini kırar) — köşeye doğru silinir. */
.boss-hero::before {
    content: '';
    position: absolute;
    inset: 0;
    background-image: radial-gradient(rgb(255 255 255 / 0.14) 1px, transparent 1.6px);
    background-size: 18px 18px;
    opacity: 0.55;
    pointer-events: none;
    -webkit-mask-image: linear-gradient(105deg, #000 0%, transparent 72%);
    mask-image: linear-gradient(105deg, #000 0%, transparent 72%);
}
:root[data-theme='dark'] .boss-hero {
    background-color: #0b1f4d;
    background-image:
        radial-gradient(130% 150% at 100% 0%, rgb(255 255 255 / 0.10) 0%, transparent 46%),
        radial-gradient(90% 130% at 0% 100%, rgb(0 0 0 / 0.35) 0%, transparent 52%),
        linear-gradient(120deg, #0b1f4d 0%, var(--brand-800) 60%, var(--brand-700) 100%);
}
/* Dekoratif arka plan ikonu: büyük, soluk, taşan — "boş renk" hissini giderir. */
.boss-hero__decor {
    position: absolute;
    right: -1.5rem;
    top: 50%;
    translate: 0 -50%;
    color: rgb(255 255 255 / 0.08);
    pointer-events: none;
}
</style>
