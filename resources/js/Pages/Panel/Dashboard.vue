<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { Head, Link, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { authFromPage } from '@/types/auth';
import { formatCurrencyMinor, formatLongDate, formatNumber } from '@/lib/format';
import PanelShell from '@/Components/panel/PanelShell.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import MetricTile from '@/Components/ui/MetricTile.vue';
import SectionLabel from '@/Components/ui/SectionLabel.vue';
import StatusPill from '@/Components/ui/StatusPill.vue';
import ChartLine from './Reports/components/ChartLine.vue';
import ChartStackedBar from './Reports/components/ChartStackedBar.vue';
import { pctChange, shortDay, type DayPoint, type PeriodTotals } from './Reports/reports';

/**
 * Panel açılışı — ROL BAZLI (prompt §20): sunucu, kullanıcının izinlerine
 * göre bölüm döndürür (DashboardService). Sahip ciro+kıyas+ödeme kırılımı;
 * şube müdürü operasyon+kasa; garson yalnız operasyon görür. İzinsiz bölüm
 * yanıtta yoktur, ekran da onu hiç çizmez.
 *
 * Veri yoksa DÜRÜST boş durum: uydurma sayı/grafik yasak.
 * Bu ekran YALNIZ sunumu düzenler; veri sözleşmesi (DashboardSections)
 * ve /api/v1/reports/dashboard ucu değişmez.
 */

interface DashboardSections {
    today?: {
        date: string;
        current: PeriodTotals;
        yesterday: PeriodTotals;
        last_week: PeriodTotals;
        cancelled: { orders: number; total_minor: number };
        collected_minor: number;
        open_table_minor: number;
        open_table_orders: number;
    };
    trend?: { days: DayPoint[] };
    payment_mix?: {
        total_minor: number;
        tips_minor: number;
        rows: { method: string; label: string; count: number; amount_minor: number }[];
    };
    open_orders?: {
        open_total: number;
        pending_approval: number;
        in_kitchen: number;
        awaiting_payment: number;
        delayed: number;
        delayed_threshold_minutes: number;
    };
    service_requests?: { open: number; rows: { id: number; label: string; table: string | null; age_minutes: number }[] };
    occupancy?: { tables: number; occupied: number; rate: number | null };
    cash?: {
        open_sessions: {
            id: number;
            z_number: number;
            register: string;
            opened_by: string | null;
            opened_at: string;
            expected_cash_minor: number;
        }[];
    };
    adjustments?: {
        cancelled_orders: number;
        cancelled_minor: number;
        discount_minor: number;
        comp_minor: number;
    };
}

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));
const today = formatLongDate(new Date());

const loading = ref(true);
const loadError = ref('');
const sections = ref<DashboardSections | null>(null);

let timer: ReturnType<typeof setTimeout> | null = null;

async function load(initial = false): Promise<void> {
    if (initial) loading.value = true;
    try {
        const res = await api<{ sections: DashboardSections }>('/api/v1/reports/dashboard');
        sections.value = res.sections;
        loadError.value = '';
    } catch (e) {
        if (initial) loadError.value = e instanceof ApiError ? e.displayMessage : 'Panel verisi yüklenemedi.';
    } finally {
        loading.value = false;
    }
    // Operasyonel sayılar (açık sipariş, çağrılar, doluluk) 60 sn'de bir tazelenir.
    timer = setTimeout(() => void load(false), 60000);
}

onMounted(() => void load(true));
onUnmounted(() => {
    if (timer !== null) clearTimeout(timer);
});

/* ---- sunum türetimleri (yalnız payload alanlarından) ---- */
const s = computed(() => sections.value);

type Accent = 'brand' | 'success' | 'warning' | 'danger' | 'info';
type PillKind =
    | 'order-new'
    | 'order-preparing'
    | 'order-ready'
    | 'order-served'
    | 'table-empty'
    | 'table-occupied'
    | 'table-delayed'
    | 'stock-critical'
    | 'success'
    | 'warning'
    | 'danger'
    | 'info';

interface TileDelta {
    value: number;
    direction: 'up' | 'down' | 'flat';
}

interface Metric {
    key: string;
    label: string;
    value: string;
    icon: string;
    accent: Accent;
    /** Kıyas ALANI yalnız payload'da önceki dönem varsa (pctChange !== null). */
    delta?: TileDelta;
    hint: string;
    /** Tıklanınca gidilecek içerik sayfası (KPI → drill-down). */
    href?: string | null;
}

/** pctChange (number|null) → MetricTile delta. Önceki dönem yoksa undefined (uydurma kıyas yok). */
function toDelta(pct: number | null): TileDelta | undefined {
    if (pct === null) return undefined;
    if (pct === 0) return { value: 0, direction: 'flat' };
    return { value: Math.abs(pct), direction: pct > 0 ? 'up' : 'down' };
}

/**
 * ÖNE ÇIKAN metrik: bugünkü ciro. Sayfanın birincil sayısı — büyük değer +
 * kıyas + son 14 gün mini eğilim (sparkline). Yalnız payload alanlarından.
 */
const featuredRevenue = computed(() => {
    const t = s.value?.today;
    if (!t) return null;
    const revDelta = toDelta(pctChange(t.current.revenue_minor, t.yesterday.revenue_minor));
    return {
        value: formatCurrencyMinor(t.current.revenue_minor),
        delta: revDelta,
        hint: revDelta
            ? 'düne göre'
            : t.last_week.revenue_minor > 0
              ? `geçen hafta: ${formatCurrencyMinor(t.last_week.revenue_minor)}`
              : 'kapanan adisyonlar',
    };
});

/** Destekleyici para metrikleri (tahsilat + açık masa) — ciro ile aynı satırda. */
const moneyMetrics = computed<Metric[]>(() => {
    const t = s.value?.today;
    if (!t) return [];
    return [
        {
            key: 'collected',
            label: 'Bugünkü tahsilat',
            value: formatCurrencyMinor(t.collected_minor),
            icon: 'cart',
            accent: 'success',
            hint: 'kasaya giren para',
            href: '/panel/raporlar',
        },
        {
            key: 'open_table',
            label: 'Açık masa tutarı',
            value: formatCurrencyMinor(t.open_table_minor),
            icon: 'utensils',
            accent: 'info',
            hint: t.open_table_orders > 0 ? `${formatNumber(t.open_table_orders)} açık adisyon` : 'açık adisyon yok',
            href: '/panel/siparisler',
        },
    ];
});

/** İkincil operasyon metrikleri — kompakt (küçük) tile satırı. */
const opsMetrics = computed<Metric[]>(() => {
    const t = s.value?.today;
    if (!t) return [];
    const orderDelta = toDelta(pctChange(t.current.orders, t.yesterday.orders));
    const basketDelta = t.current.orders > 0 ? toDelta(pctChange(t.current.avg_basket_minor, t.yesterday.avg_basket_minor)) : undefined;
    const list: Metric[] = [
        {
            key: 'orders',
            label: 'Bugünkü sipariş',
            value: formatNumber(t.current.orders),
            icon: 'orders',
            accent: 'brand',
            delta: orderDelta,
            hint: orderDelta ? 'düne göre' : 'kapanan adisyon',
            href: '/panel/raporlar',
        },
        {
            key: 'basket',
            label: 'Ortalama sepet',
            value: t.current.orders > 0 ? formatCurrencyMinor(t.current.avg_basket_minor) : '—',
            icon: 'chart',
            accent: 'info',
            delta: basketDelta,
            hint: basketDelta ? 'düne göre' : t.current.orders === 0 ? 'kapanan satış yok' : '',
            href: '/panel/raporlar',
        },
    ];
    const occ = s.value?.occupancy;
    if (occ) {
        list.push({
            key: 'occupancy',
            label: 'Masa doluluğu',
            value: occ.rate !== null ? `%${occ.rate.toFixed(0)}` : '—',
            icon: 'users',
            accent: 'info',
            hint: `${formatNumber(occ.occupied)} / ${formatNumber(occ.tables)} masa`,
        });
    }
    return list;
});

const hasSummary = computed(() => featuredRevenue.value !== null);

/** Öne çıkan ciro kıyas rozeti — yön renk + ok ile (a11y renk-dışı kodlama). */
const featuredDeltaMeta = computed(() => {
    const d = featuredRevenue.value?.delta;
    if (!d) return null;
    const map = {
        up: { cls: 'text-success bg-success-soft', icon: 'arrow-up' },
        down: { cls: 'text-danger bg-danger-soft', icon: 'arrow-down' },
        flat: { cls: 'text-muted bg-inset', icon: 'minus' },
    } as const;
    return { ...map[d.direction], value: d.value };
});

/**
 * Açık adisyon AKIŞI: siparişin yaşam döngüsündeki aşamalar (onay → mutfak →
 * ödeme). Her aşama bir oran çubuğuyla toplam açığa göre yükü gösterir.
 * "Geciken" ayrı bir uyarı olarak vurgulanır (akışa dik bir bayrak).
 */
interface OpenStage {
    key: string;
    label: string;
    value: number;
    kind: PillKind;
    icon: string;
}
const openStages = computed<OpenStage[]>(() => {
    const o = s.value?.open_orders;
    if (!o) return [];
    return [
        { key: 'approval', label: 'Onay bekleyen', value: o.pending_approval, kind: 'order-new', icon: 'bell' },
        { key: 'kitchen', label: 'Mutfakta', value: o.in_kitchen, kind: 'order-preparing', icon: 'clock' },
        { key: 'payment', label: 'Ödeme bekleyen', value: o.awaiting_payment, kind: 'warning', icon: 'wallet' },
    ];
});

/** Aşama çubuğu genişliği — toplam açığa oran (0 iken boş). */
function stageBarWidth(value: number): string {
    const total = s.value?.open_orders?.open_total ?? 0;
    if (total <= 0) return '0%';
    return `${Math.min(100, Math.round((value / total) * 100))}%`;
}

/** Durum türü → ikon metin rengi (statik sınıflar; Tailwind tarayıcısı için). */
const kindTextClass: Record<PillKind, string> = {
    'order-new': 'text-order-new',
    'order-preparing': 'text-order-preparing',
    'order-ready': 'text-order-ready',
    'order-served': 'text-order-served',
    'table-empty': 'text-table-empty',
    'table-occupied': 'text-table-occupied',
    'table-delayed': 'text-table-delayed',
    'stock-critical': 'text-stock-critical',
    success: 'text-success',
    warning: 'text-warning',
    danger: 'text-danger',
    info: 'text-info',
};

/** Durum türü → çubuk dolgu rengi (statik sınıflar). */
const kindBarClass: Record<PillKind, string> = {
    'order-new': 'bg-order-new',
    'order-preparing': 'bg-order-preparing',
    'order-ready': 'bg-order-ready',
    'order-served': 'bg-order-served',
    'table-empty': 'bg-table-empty',
    'table-occupied': 'bg-table-occupied',
    'table-delayed': 'bg-table-delayed',
    'stock-critical': 'bg-stock-critical',
    success: 'bg-success',
    warning: 'bg-warning',
    danger: 'bg-danger',
    info: 'bg-info',
};

/**
 * "Yapılması gereken aksiyonlar" — YALNIZ payload'dan türetilebilen sinyaller.
 * Kritik stok payload'da olmadığı için EKLENMEZ.
 */
interface ActionItem {
    key: string;
    kind: PillKind;
    icon: string;
    label: string;
    text: string;
    href: string | null;
}
const actions = computed<ActionItem[]>(() => {
    const list: ActionItem[] = [];
    const o = s.value?.open_orders;
    if (o) {
        if (o.delayed > 0) {
            list.push({
                key: 'delayed',
                kind: 'table-delayed',
                icon: 'alert-triangle',
                label: 'Geciken',
                text: `${formatNumber(o.delayed)} adisyon ${o.delayed_threshold_minutes} dk'yı aştı`,
                href: '/panel/siparisler',
            });
        }
        if (o.pending_approval > 0) {
            list.push({
                key: 'approval',
                kind: 'order-new',
                icon: 'bell',
                label: 'Onay',
                text: `${formatNumber(o.pending_approval)} adisyon onay bekliyor`,
                href: '/panel/siparisler',
            });
        }
        if (o.awaiting_payment > 0) {
            list.push({
                key: 'payment',
                kind: 'warning',
                icon: 'wallet',
                label: 'Ödeme',
                text: `${formatNumber(o.awaiting_payment)} adisyon ödeme bekliyor`,
                href: '/panel/siparisler',
            });
        }
    }
    const sr = s.value?.service_requests;
    if (sr && sr.open > 0) {
        list.push({
            key: 'service',
            kind: 'warning',
            icon: 'bell',
            label: 'Çağrı',
            text: `${formatNumber(sr.open)} açık servis çağrısı`,
            href: null,
        });
    }
    return list;
});

const trendPoints = computed(() =>
    (s.value?.trend?.days ?? []).map((d) => ({ label: shortDay(d.date), title: d.date, value: d.revenue_minor })),
);
const trendHasData = computed(() => trendPoints.value.some((p) => p.value > 0));

/**
 * Öne çıkan ciro tile'ındaki mini eğilim (eksensiz sparkline). 200×48 viewBox,
 * son 14 günün değerlerini 0..max aralığına ölçekler; çizgi + %12 alan.
 */
const SPARK_W = 200;
const SPARK_H = 48;
const sparkline = computed(() => {
    const pts = trendPoints.value;
    if (pts.length < 2) return null;
    const max = Math.max(...pts.map((p) => p.value), 1);
    const n = pts.length - 1;
    const coords = pts.map((p, i) => {
        const x = (i / n) * SPARK_W;
        const y = SPARK_H - 3 - (p.value / max) * (SPARK_H - 6);
        return `${x.toFixed(1)},${y.toFixed(1)}`;
    });
    const line = `M${coords.join(' L')}`;
    const area = `${line} L${SPARK_W},${SPARK_H} L0,${SPARK_H} Z`;
    return { line, area };
});

const paymentSegments = computed(() => {
    const rows = s.value?.payment_mix?.rows ?? [];
    const head = rows.slice(0, 4).map((r, i) => ({
        label: r.label,
        value: r.amount_minor,
        colorIndex: i,
        hint: `${formatNumber(r.count)} işlem`,
    }));
    const tail = rows.slice(4);
    if (tail.length > 0) {
        head.push({
            label: 'Diğer',
            value: tail.reduce((sum, r) => sum + r.amount_minor, 0),
            colorIndex: 4,
            hint: `${tail.length} yöntem`,
        });
    }
    return head;
});

/** Hiç bölüm dönmedi mi? (ör. yalnız KDS izinli personel) */
const noSections = computed(
    () => sections.value !== null && Object.keys(sections.value).length === 0,
);

/** Kiracı taze mi? (rapor izni var ama hiç hareket yok) */
const isFresh = computed(() => {
    const t = s.value?.today;
    if (!t) return false;
    return (
        t.current.orders === 0 &&
        t.yesterday.orders === 0 &&
        !trendHasData.value &&
        (s.value?.open_orders?.open_total ?? 0) === 0
    );
});
</script>

<template>
    <Head title="Panel" />

    <!-- ================= PANO (yeniden tasarım) =================
         Eski düzen tek sütunda üst üste dizilmiş bölümlerden oluşuyordu ve
         renk yalnız küçük ikon çiplerindeydi: ekran gri bir kutu yığını gibi
         duruyor, "şu an neye bakmalıyım" sorusu okumadan yanıtlanmıyordu.

         Yeni düzen üç katman:
         1) KOYU MARKA BANDI — karşılama + CANLI durum çipleri (açık masa,
            mutfakta, geciken). İşletmenin nabzı ekranın en üstünde, renkli.
         2) İKİ KOLON — solda para (ciro kahramanı + KPI ızgarası + ödeme
            dağılımı), sağda operasyon (aksiyonlar, doluluk, açık adisyon
            aşamaları, kasa).
         3) Alt şerit — düzeltmeler (iptal/indirim/ikram).
         Kolonlar bağımsız; dar ekranda alt alta düşer. -->
    <PanelShell title="Panel" flush canvas>
        <!-- ===== 1) Başlık şeridi: karşılama + canlı durum =====
             Koyu marka bandı denendi ve BOĞUCU oldu: sayfanın tepesinde geniş
             bir renk bloğu, altındaki renkli kartlarla birleşince ekran
             yoruyordu. Şerit artık sade; renk yalnız durum çiplerinin ikon ve
             sayısında — yani anlam taşıdığı yerde. -->
        <div class="shrink-0 border-b border-default bg-raised px-4 py-3 sm:px-6">
            <div class="mx-auto flex w-full max-w-[1440px] flex-wrap items-center justify-between gap-3">
                <div class="min-w-0">
                    <h2 class="truncate text-lg font-bold text-body sm:text-xl">
                        Merhaba{{ auth?.user.first_name ? `, ${auth.user.first_name}` : '' }}
                    </h2>
                    <p class="flex items-center gap-1.5 text-xs text-muted">
                        <AppIcon name="calendar" :size="13" class="text-subtle" />
                        {{ today }}
                    </p>
                </div>

                <!-- Canlı durum: çerçeveli çipler; yalnız GERÇEKTEN acil olan
                     (geciken / servis çağrısı) dolgu alır. -->
                <div class="flex flex-wrap items-center gap-1.5">
                    <span
                        v-if="s?.occupancy"
                        class="inline-flex items-center gap-1.5 rounded-full border border-default px-2.5 py-1 text-xs font-semibold text-muted tabular-nums"
                        title="Dolu masa / toplam masa"
                    >
                        <AppIcon name="utensils" :size="13" class="text-info" />
                        {{ s.occupancy.occupied }}/{{ s.occupancy.tables }}
                    </span>
                    <span
                        v-if="s?.open_orders"
                        class="inline-flex items-center gap-1.5 rounded-full border border-default px-2.5 py-1 text-xs font-semibold text-muted tabular-nums"
                        title="Mutfakta hazırlanan adisyon"
                    >
                        <AppIcon name="chef-hat" :size="13" class="text-primary" />
                        {{ s.open_orders.in_kitchen }} mutfakta
                    </span>
                    <span
                        v-if="(s?.open_orders?.delayed ?? 0) > 0"
                        class="inline-flex items-center gap-1.5 rounded-full border border-danger-border bg-danger-soft px-2.5 py-1 text-xs font-bold text-danger tabular-nums"
                        :title="`${s?.open_orders?.delayed_threshold_minutes} dakikayı aşan adisyon`"
                    >
                        <AppIcon name="alert-triangle" :size="13" />
                        {{ s?.open_orders?.delayed }} geciken
                    </span>
                    <span
                        v-if="(s?.service_requests?.open ?? 0) > 0"
                        class="inline-flex items-center gap-1.5 rounded-full border border-warning-border bg-warning-soft px-2.5 py-1 text-xs font-bold text-warning tabular-nums"
                        title="Bekleyen servis çağrısı"
                    >
                        <AppIcon name="bell" :size="13" />
                        {{ s?.service_requests?.open }} çağrı
                    </span>

                    <BaseButton v-if="s?.today" variant="secondary" size="sm" href="/panel/raporlar">
                        <AppIcon name="chart" :size="15" />
                        <span class="hidden sm:inline">Raporlar</span>
                    </BaseButton>
                </div>
            </div>
        </div>

        <!-- ===== İçerik ===== -->
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-4">

            <!-- Yükleniyor -->
            <div v-if="loading" class="grid gap-3 xl:grid-cols-3">
                <div class="flex flex-col gap-2.5 xl:col-span-2">
                    <BaseSkeleton variant="rect" size-class="h-40 w-full" />
                    <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
                        <BaseSkeleton v-for="n in 4" :key="n" variant="rect" size-class="h-24 w-full" />
                    </div>
                </div>
                <BaseSkeleton variant="rect" size-class="h-80 w-full" />
            </div>

            <div
                v-else-if="loadError"
                class="flex items-start gap-2.5 rounded-lg border border-danger-border bg-danger-soft px-3 py-2.5 text-sm text-danger"
                role="alert"
            >
                <AppIcon name="alert-circle" :size="17" class="mt-0.5 shrink-0" />
                <p>{{ loadError }}</p>
            </div>

            <template v-else-if="sections">
                <!-- Rolünde panel bölümü olmayanlar (ör. mutfak) -->
                <BaseCard v-if="noSections" flush>
                    <EmptyState
                        icon="dashboard"
                        title="Bu ekranda size özel bölüm yok"
                        description="Rolünüz operasyon ekranlarını kullanıyor. Menüden çalışma ekranınıza (Mutfak, Komi, Siparişler…) geçebilirsiniz."
                    />
                </BaseCard>

                <!-- ===== 2) İki kolon: PARA (sol) · OPERASYON (sağ) ===== -->
                <SectionLabel label="Bugün" icon="wallet" :hint="s?.today?.date ?? null" />

                <div class="grid gap-3 xl:grid-cols-3">

                    <!-- ---------- SOL: para ---------- -->
                    <div class="flex flex-col gap-3 xl:col-span-2">

                        <!-- Ciro kahramanı: büyük tutar + eğilim + kıyas -->
                        <section
                            v-if="featuredRevenue"
                            class="rounded-xl border border-default bg-raised p-4"
                        >
                            <div class="flex flex-wrap items-start justify-between gap-3">
                                <div class="min-w-0">
                                    <p class="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-subtle">
                                        <AppIcon name="wallet" :size="13" class="text-primary" />
                                        Bugünkü ciro
                                    </p>
                                    <div class="mt-1 flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
                                        <span class="text-3xl font-extrabold tabular-nums text-primary sm:text-4xl">{{ featuredRevenue.value }}</span>
                                        <span
                                            v-if="featuredDeltaMeta"
                                            class="inline-flex items-center gap-0.5 rounded-full px-2 py-0.5 text-xs font-bold tabular-nums"
                                            :class="featuredDeltaMeta.cls"
                                        >
                                            <AppIcon :name="featuredDeltaMeta.icon" :size="13" />
                                            {{ featuredDeltaMeta.value }}%
                                        </span>
                                    </div>
                                    <p class="mt-0.5 text-xs text-muted">{{ featuredRevenue.hint }}</p>
                                </div>

                                <!-- 14 günlük eğilim: sayının yanında, bağlam olarak -->
                                <svg
                                    v-if="sparkline && trendHasData"
                                    :viewBox="`0 0 ${SPARK_W} ${SPARK_H}`"
                                    preserveAspectRatio="none"
                                    class="h-14 w-full max-w-64 shrink-0"
                                    role="img"
                                    aria-label="Son 14 günün ciro eğilimi"
                                >
                                    <path :d="sparkline.area" fill="var(--viz-1)" :opacity="0.18" />
                                    <path
                                        :d="sparkline.line"
                                        fill="none"
                                        stroke="var(--viz-1)"
                                        stroke-width="2"
                                        stroke-linejoin="round"
                                        stroke-linecap="round"
                                        vector-effect="non-scaling-stroke"
                                    />
                                </svg>
                            </div>
                        </section>

                        <!-- KPI ızgarası: para + operasyon tek ızgarada, renkli -->
                        <div v-if="moneyMetrics.length || opsMetrics.length" class="grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-4">
                            <MetricTile
                                v-for="m in moneyMetrics"
                                :key="m.key"
                                size="sm"
                                :label="m.label"
                                :value="m.value"
                                :icon="m.icon"
                                :accent="m.accent"
                                :delta="m.delta"
                                :hint="m.hint"
                                :href="m.href"
                            />
                            <MetricTile
                                v-for="m in opsMetrics"
                                :key="m.key"
                                size="sm"
                                :label="m.label"
                                :value="m.value"
                                :icon="m.icon"
                                :accent="m.accent"
                                :delta="m.delta"
                                :hint="m.hint"
                                :href="m.href"
                            />
                        </div>

                        <SectionLabel label="Tahsilat ve eğilim" icon="chart" class="pt-0.5" />

                        <!-- Ödeme dağılımı -->
                        <BaseCard v-if="paymentSegments.length > 0" title="Ödeme dağılımı">
                            <template #actions>
                                <span class="text-xs font-semibold tabular-nums text-muted">
                                    {{ formatCurrencyMinor(s?.payment_mix?.total_minor ?? 0) }}
                                </span>
                            </template>
                            <ChartStackedBar :segments="paymentSegments" money label="Bugünkü tahsilatın ödeme yöntemine göre payı" />
                        </BaseCard>

                        <!-- Ciro eğilimi (tam grafik) -->
                        <BaseCard v-if="trendHasData" title="Son 14 gün">
                            <ChartLine :points="trendPoints" money label="Son 14 günün günlük ciro eğilimi" />
                        </BaseCard>
                    </div>

                    <!-- ---------- SAĞ: operasyon ---------- -->
                    <div class="flex flex-col gap-2.5">

                        <SectionLabel label="Operasyon" icon="gauge" />

                        <!-- Aksiyonlar: ekranın en dikkat çeken listesi -->
                        <section class="overflow-hidden rounded-xl border border-default bg-raised">
                            <header class="flex items-center gap-2 border-b border-default px-3.5 py-2.5">
                                <AppIcon name="bell" :size="16" class="text-warning" />
                                <h3 class="text-sm font-semibold text-body">Şimdi ilgilen</h3>
                                <span
                                    v-if="actions.length > 0"
                                    class="ms-auto rounded-full border border-warning-border bg-warning-soft px-2 py-0.5 text-xs font-bold text-warning tabular-nums"
                                >{{ actions.length }}</span>
                            </header>

                            <p v-if="actions.length === 0" class="flex items-center gap-2 px-3.5 py-4 text-sm text-success">
                                <AppIcon name="check-circle" :size="17" />
                                Bekleyen bir şey yok — akış temiz.
                            </p>
                            <ul v-else class="divide-y divide-default">
                                <li v-for="a in actions" :key="a.key">
                                    <component
                                        :is="a.href ? Link : 'div'"
                                        :href="a.href || undefined"
                                        class="flex items-center gap-2.5 px-3.5 py-2.5 transition"
                                        :class="a.href ? 'hover:bg-inset' : ''"
                                    >
                                        <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-inset" :class="kindTextClass[a.kind]">
                                            <AppIcon :name="a.icon" :size="16" />
                                        </span>
                                        <span class="min-w-0 grow">
                                            <span class="block text-xs font-bold uppercase tracking-wide" :class="kindTextClass[a.kind]">{{ a.label }}</span>
                                            <span class="block truncate text-sm text-body">{{ a.text }}</span>
                                        </span>
                                        <AppIcon v-if="a.href" name="chevron-right" :size="15" class="shrink-0 text-subtle" />
                                    </component>
                                </li>
                            </ul>
                        </section>

                        <!-- Doluluk: tek bakışta oran -->
                        <section v-if="s?.occupancy && s.occupancy.tables > 0" class="rounded-xl border border-default bg-raised p-3.5">
                            <div class="flex items-center justify-between gap-2">
                                <h3 class="flex items-center gap-1.5 text-sm font-semibold text-body">
                                    <AppIcon name="gauge" :size="15" class="text-info" />
                                    Doluluk
                                </h3>
                                <span class="text-lg font-extrabold tabular-nums text-info">%{{ s.occupancy.rate ?? 0 }}</span>
                            </div>
                            <div class="mt-2 h-2 overflow-hidden rounded-full bg-inset">
                                <div class="h-full rounded-full bg-info transition-[width] duration-(--dur-normal)" :style="{ width: `${s.occupancy.rate ?? 0}%` }" />
                            </div>
                            <p class="mt-1.5 text-xs text-muted tabular-nums">
                                <span class="font-semibold text-body">{{ s.occupancy.occupied }}</span> dolu ·
                                {{ s.occupancy.tables - s.occupancy.occupied }} boş
                            </p>
                        </section>

                        <!-- Açık adisyon aşamaları: TEK yığılmış çubuk + lejant -->
                        <section v-if="openStages.length > 0" class="rounded-xl border border-default bg-raised p-3.5">
                            <div class="flex items-center justify-between gap-2">
                                <h3 class="flex items-center gap-1.5 text-sm font-semibold text-body">
                                    <AppIcon name="orders" :size="15" class="text-primary" />
                                    Açık adisyonlar
                                </h3>
                                <span class="text-lg font-extrabold tabular-nums text-body">{{ s?.open_orders?.open_total ?? 0 }}</span>
                            </div>

                            <div class="mt-2 flex h-2 overflow-hidden rounded-full bg-inset">
                                <div
                                    v-for="st in openStages"
                                    :key="st.key"
                                    class="h-full transition-[width] duration-(--dur-normal)"
                                    :class="kindBarClass[st.kind]"
                                    :style="{ width: stageBarWidth(st.value) }"
                                />
                            </div>

                            <ul class="mt-2 flex flex-col gap-1">
                                <li v-for="st in openStages" :key="st.key" class="flex items-center gap-2 text-xs">
                                    <span class="size-2 shrink-0 rounded-full" :class="kindBarClass[st.kind]" aria-hidden="true"></span>
                                    <span class="grow text-muted">{{ st.label }}</span>
                                    <span class="font-bold tabular-nums" :class="kindTextClass[st.kind]">{{ st.value }}</span>
                                </li>
                            </ul>
                        </section>

                        <!-- Açık kasa oturumları -->
                        <section v-if="(s?.cash?.open_sessions?.length ?? 0) > 0" class="overflow-hidden rounded-xl border border-default bg-raised">
                            <header class="flex items-center gap-2 border-b border-default px-3.5 py-2.5">
                                <AppIcon name="cart" :size="16" class="text-success" />
                                <h3 class="text-sm font-semibold text-body">Açık kasa</h3>
                            </header>
                            <ul class="divide-y divide-default">
                                <li v-for="cs in s?.cash?.open_sessions ?? []" :key="cs.id" class="flex items-center justify-between gap-2 px-3.5 py-2">
                                    <span class="min-w-0">
                                        <span class="block truncate text-sm font-medium text-body">{{ cs.register }} · Z#{{ cs.z_number }}</span>
                                        <span class="block truncate text-xs text-muted">{{ cs.opened_by ?? '—' }}</span>
                                    </span>
                                    <span class="shrink-0 text-sm font-bold tabular-nums text-success">
                                        {{ formatCurrencyMinor(cs.expected_cash_minor) }}
                                    </span>
                                </li>
                            </ul>
                        </section>
                    </div>
                </div>

                <!-- ===== 3) Alt şerit: düzeltmeler ===== -->
                <template v-if="s?.adjustments">
                <SectionLabel label="Düzeltmeler" icon="pencil" hint="bugün" />
                <div class="grid grid-cols-2 gap-2.5 sm:grid-cols-4">
                    <MetricTile
                        size="sm"
                        label="İptal edilen"
                        :value="formatNumber(s.adjustments.cancelled_orders)"
                        unit="adisyon"
                        icon="x-circle"
                        accent="danger"
                        :hint="formatCurrencyMinor(s.adjustments.cancelled_minor)"
                    />
                    <MetricTile
                        size="sm"
                        label="İndirim"
                        :value="formatCurrencyMinor(s.adjustments.discount_minor)"
                        icon="tag"
                        accent="warning"
                        hint="bugün"
                    />
                    <MetricTile
                        size="sm"
                        label="İkram"
                        :value="formatCurrencyMinor(s.adjustments.comp_minor)"
                        icon="check-circle"
                        accent="info"
                        hint="bugün"
                    />
                    <MetricTile
                        v-if="s?.payment_mix"
                        size="sm"
                        label="Bahşiş"
                        :value="formatCurrencyMinor(s.payment_mix.tips_minor)"
                        icon="wallet"
                        accent="success"
                        hint="bugün"
                    />
                </div>
                </template>

                <!-- Taze kiracı: dürüst boş durum (uydurma sayı yok) -->
                <BaseCard v-if="isFresh" flush>
                    <EmptyState
                        icon="chart"
                        title="Henüz hareket yok"
                        description="İlk adisyon açıldığında ciro, doluluk ve ödeme dağılımı burada canlanır."
                    />
                </BaseCard>
            </template>
        </div>
        </div>
    </PanelShell>
</template>
