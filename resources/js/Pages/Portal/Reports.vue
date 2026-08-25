<script setup lang="ts">
/**
 * Portal "Raporlarım" — özel görsel kimlikli performans panosu.
 *
 * Dönem seçici (Bugün/Bu Hafta/Bu Ay) → GET /api/v1/portal/reports?period=…
 * Çalışma özeti fiili (mola düşülmüş net) vs planlı vardiya karşılaştırması +
 * plan karşılama çubuğu + mesai giriş/çıkış sayısı. Operasyon kartları (kaç ürün
 * hazırlandı/teslim alındı/servis edildi) HER ZAMAN görünür (0 olsa da). Aynı gün
 * birden çok mesai açılmışsa anomali uyarısı + grafikte işaret. Renkli p-tile
 * kutuları, SVG donut grafikleri (çalışma + operasyon dağılımı) ve SVG bar
 * grafikler (günlük çalışma + günlük operasyon). Dış grafik kütüphanesi YOK — tümü
 * satır-içi SVG. Renkler portal paleti (--p-*) token'larına bağlı (koyu/açık
 * tema uyumlu); sabit hex gömülmez. Başlık/tarih aralığı PortalLayout hero'sunda.
 */
import { computed, onMounted, ref } from 'vue';
import { api } from '@/lib/http';
import { formatNumber, formatCurrencyMinor } from '@/lib/format';
import PortalLayout from '@/Layouts/PortalLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import { formatMinutes } from '@/types/portal';

/* ---------- Yanıt tipleri (§2 sözleşmesi) ---------- */
type Period = 'day' | 'week' | 'month';

interface WorkedDay {
    date: string;
    worked_min: number;
    break_min: number;
    sessions: number;
}
interface OpsDay {
    date: string;
    prepared: number;
    taken: number;
    served: number;
}
interface WorkedBlock {
    total_min: number;
    planned_min: number;
    active_days: number;
    avg_daily_min: number;
    break_min: number;
    toilet_min: number;
    total_sessions: number;
    multi_session_days: number;
    by_day: WorkedDay[];
}
interface OpsBlock {
    prepared_count: number;
    taken_count: number;
    served_count: number;
    delivered_count: number;
    avg_pickup_min: number | null;
    avg_delivery_min: number | null;
    avg_delay_min: number | null;
    delay_count: number;
    delay_threshold_min: number;
    by_day: OpsDay[];
}
interface OrdersBlock {
    order_count: number;
    avg_service_min: number | null;
}
interface ReportData {
    period: Period;
    from: string;
    to: string;
    position: string | null;
    role_label: string | null;
    worked: WorkedBlock;
    ops: OpsBlock;
    orders?: OrdersBlock;
}

/* ---------- Durum ---------- */
const data = ref<ReportData | null>(null);
const loading = ref(true);
const period = ref<Period>('day');
const barTab = ref<'worked' | 'ops'>('worked');

const periods: { key: Period; label: string }[] = [
    { key: 'day', label: 'Bugün' },
    { key: 'week', label: 'Bu Hafta' },
    { key: 'month', label: 'Bu Ay' },
];

async function load(): Promise<void> {
    loading.value = true;
    try {
        data.value = await api<ReportData>(`/api/v1/portal/reports?period=${period.value}`);
    } catch {
        data.value = null;
    } finally {
        loading.value = false;
    }
}

/* ---------- Kazancım (prim/komisyon) ----------
 * Aynı dönem seçiciye bağlı bağımsız kart. Kişiye atanmış aktif bir prim
 * şeması yoksa (scheme_name boş) ya da uç 404 dönerse bölüm gizlenir. */
interface EarningsData {
    sales_minor: number;
    order_count: number;
    commission_minor: number;
    target_minor: number;
    target_met: boolean;
    worked_min: number;
    scheme_name: string | null;
}
const earnings = ref<EarningsData | null>(null);

async function loadEarnings(): Promise<void> {
    try {
        earnings.value = await api<EarningsData>(`/api/v1/portal/earnings?period=${period.value}`);
    } catch {
        // 404 (modül/şema yok) veya hata → bölümü sessizce gizle
        earnings.value = null;
    }
}

/** Kişiye atanmış aktif prim şeması var mı? (yoksa/boşsa bölüm gizli). */
const hasEarnings = computed<boolean>(() => !!earnings.value && !!earnings.value.scheme_name);

/** Hedef karşılanma yüzdesi (çubuk); hedef yoksa null. */
const earningsTarget = computed(() => {
    const e = earnings.value;
    if (!e || e.target_minor <= 0) return null;
    const pct = Math.round((e.sales_minor / e.target_minor) * 100);
    return { pct, barPct: Math.min(100, Math.max(0, pct)), met: e.target_met };
});

function selectPeriod(p: Period): void {
    if (period.value === p) return;
    period.value = p;
    void load();
    void loadEarnings();
}

onMounted(() => {
    void load();
    void loadEarnings();
});

/* ---------- Yardımcılar ---------- */
const wkFmt = new Intl.DateTimeFormat('tr-TR', { weekday: 'short' });
const dayMonthFmt = new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'long' });
const dayOnlyFmt = new Intl.DateTimeFormat('tr-TR', { day: 'numeric' });

function dayLabel(dateStr: string): string {
    const d = new Date(dateStr);
    if (Number.isNaN(d.getTime())) return '';
    if (period.value === 'month') return String(d.getDate());
    return wkFmt.format(d);
}

/** 0/null → zarif "—" (yalnız süre metrikleri için; sayımlar 0 gösterir). */
const dashMin = (v: number | null | undefined): string => (v ? formatMinutes(v) : '—');

/** Dönemde toplam mesai giriş/çıkış sayısı. */
const totalSessions = computed<number>(() => data.value?.worked.total_sessions ?? 0);

/** Aynı gün birden çok kez mesai açılan gün sayısı (olası hata). */
const multiSessionDays = computed<number>(() => data.value?.worked.multi_session_days ?? 0);

/** Hero alt satırı: seçili dönemin kompakt tarih aralığı (örn "20–26 Temmuz"). */
const subtitle = computed<string | undefined>(() => {
    const d = data.value;
    if (!d) return undefined;
    const from = new Date(d.from);
    const to = new Date(d.to);
    if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) return undefined;
    if (d.from === d.to) return dayMonthFmt.format(from);
    const sameMonth = from.getMonth() === to.getMonth() && from.getFullYear() === to.getFullYear();
    return sameMonth
        ? `${dayOnlyFmt.format(from)}–${dayMonthFmt.format(to)}`
        : `${dayMonthFmt.format(from)} – ${dayMonthFmt.format(to)}`;
});

/* ---------- Özet stat kutuları (renkli p-tile) ---------- */
interface StatTile {
    label: string;
    value: string;
    icon: string;
    tile: string;
}

/** Fiili (mola düşülmüş) vs planlı vardiya karşılaştırması. */
const workedCompare = computed(() => {
    const w = data.value?.worked;
    if (!w) return null;
    const planned = w.planned_min;
    const pct = planned > 0 ? Math.round((w.total_min / planned) * 100) : null;
    return {
        actualMin: w.total_min,
        plannedMin: planned,
        actualLabel: dashMin(w.total_min),
        plannedLabel: dashMin(planned),
        pct,
        barPct: pct === null ? 0 : Math.min(100, Math.max(0, pct)),
    };
});

/** İkincil çalışma kutuları (aktif gün + ort. günlük). */
const workedCards = computed<StatTile[]>(() => {
    const w = data.value?.worked;
    if (!w) return [];
    return [
        { label: 'Aktif gün', value: w.active_days ? `${formatNumber(w.active_days)} gün` : '—', icon: 'calendar', tile: 'p-tile-sky' },
        { label: 'Ort. günlük', value: dashMin(w.avg_daily_min), icon: 'chart', tile: 'p-tile-violet' },
    ];
});

/**
 * Operasyon sayım kutuları — HER ZAMAN gösterilir (kişi kaç ürün
 * hazırlamış/teslim almış/servis etmiş net görünsün). Sayımlar 0 olsa da "0".
 * Süre/gecikme metrikleri aşağıdaki "Performans" bölümünde.
 */
const opsCards = computed<StatTile[]>(() => {
    const o = data.value?.ops;
    if (!o) return [];
    return [
        { label: 'Hazırlanan', value: formatNumber(o.prepared_count), icon: 'chef-hat', tile: 'p-tile-amber' },
        { label: 'Teslim aldığı', value: formatNumber(o.taken_count), icon: 'package', tile: 'p-tile-sky' },
        { label: 'Servis ettiği', value: formatNumber(o.served_count), icon: 'utensils', tile: 'p-tile-emerald' },
    ];
});

/** Performans süre metrikleri (veri yoksa "—"). */
const perfCards = computed<StatTile[]>(() => {
    const o = data.value?.ops;
    if (!o) return [];
    return [
        { label: 'Ort. alma süresi', value: dashMin(o.avg_pickup_min), icon: 'package', tile: 'p-tile-sky' },
        { label: 'Ort. teslim süresi', value: dashMin(o.avg_delivery_min), icon: 'cart', tile: 'p-tile-indigo' },
        { label: 'Ort. gecikme', value: dashMin(o.avg_delay_min), icon: 'clock', tile: 'p-tile-amber' },
    ];
});

/** Gecikme sayısı + eşik (delay_count>0 ise vurgulu uyarı tonu). */
const delayStat = computed(() => {
    const o = data.value?.ops;
    if (!o) return null;
    return {
        count: o.delay_count,
        countLabel: formatNumber(o.delay_count),
        threshold: o.delay_threshold_min,
        alert: o.delay_count > 0,
    };
});

/* ---------- Donut grafikleri ---------- */
const R = 58;
const STROKE = 15; // ince, kurumsal halka (eski 24 "oval" hissi yerine)
const CIRC = 2 * Math.PI * R;

interface DonutSeg {
    label: string;
    value: number;
    color: string;
    dash: string;
    offset: number;
    pct: number;
}
interface Donut {
    segs: DonutSeg[];
    total: number;
    centerMain: string;
    centerSub: string;
}

function buildDonut(input: { label: string; value: number; color: string }[], centerMain: (t: number) => string, centerSub: string): Donut {
    const total = input.reduce((s, i) => s + Math.max(0, i.value), 0);
    let acc = 0;
    const segs: DonutSeg[] = input.map((i) => {
        const value = Math.max(0, i.value);
        const frac = total > 0 ? value / total : 0;
        const seg: DonutSeg = {
            label: i.label,
            value,
            color: i.color,
            dash: `${(frac * CIRC).toFixed(2)} ${((1 - frac) * CIRC).toFixed(2)}`,
            offset: -acc * CIRC,
            pct: Math.round(frac * 100),
        };
        acc += frac;
        return seg;
    });
    return { segs, total, centerMain: centerMain(total), centerSub };
}

/** Çalışma / Mola / Tuvalet dağılımı. */
const workDonut = computed<Donut | null>(() => {
    const w = data.value?.worked;
    if (!w) return null;
    const total = w.total_min + w.break_min + w.toilet_min;
    if (total <= 0) return null;
    return buildDonut(
        [
            { label: 'Çalışma', value: w.total_min, color: 'var(--p-teal)' },
            { label: 'Mola', value: w.break_min, color: 'var(--p-amber)' },
            { label: 'Tuvalet', value: w.toilet_min, color: 'var(--p-sky)' },
        ],
        (t) => formatMinutes(t),
        'toplam süre',
    );
});

/** Hazırlanan / Teslim / Servis dağılımı. */
const opsDonut = computed<Donut | null>(() => {
    const o = data.value?.ops;
    if (!o) return null;
    const total = o.prepared_count + o.taken_count + o.served_count;
    if (total <= 0) return null;
    return buildDonut(
        [
            { label: 'Hazırlanan', value: o.prepared_count, color: 'var(--p-indigo)' },
            { label: 'Teslim aldığı', value: o.taken_count, color: 'var(--p-sky)' },
            { label: 'Servis ettiği', value: o.served_count, color: 'var(--p-teal)' },
        ],
        (t) => formatNumber(t),
        'işlem',
    );
});

/* ---------- Bar grafik geometrisi ---------- */
const PLOT_H = 184;
const SVG_H = PLOT_H + 28;
const gridLines = [0, 0.25, 0.5, 0.75, 1].map((f) => ({ y: +(PLOT_H * (1 - f)).toFixed(1), f }));

interface WorkedBar {
    label: string;
    x: number;
    cx: number;
    workY: number;
    workH: number;
    breakY: number;
    breakH: number;
    markerY: number;
    multi: boolean;
    title: string;
}
const workedChart = computed(() => {
    const days = data.value?.worked.by_day ?? [];
    const SLOT = 46;
    const BARW = 24;
    const max = Math.max(1, ...days.map((d) => d.worked_min + d.break_min));
    const bars: WorkedBar[] = days.map((d, i) => {
        const workH = (d.worked_min / max) * PLOT_H;
        const breakH = (d.break_min / max) * PLOT_H;
        const x = i * SLOT + (SLOT - BARW) / 2;
        const topY = PLOT_H - workH - breakH;
        const multi = (d.sessions ?? 0) > 1;
        return {
            label: dayLabel(d.date),
            x,
            cx: x + BARW / 2,
            workY: PLOT_H - workH,
            workH,
            breakY: topY,
            breakH,
            markerY: Math.max(6, topY - 7),
            multi,
            title: `${dayLabel(d.date)}: çalışma ${formatMinutes(d.worked_min)}${d.break_min ? `, mola ${formatMinutes(d.break_min)}` : ''}${multi ? ` · ${d.sessions} mesai (kontrol edin)` : ''}`,
        };
    });
    return {
        bars,
        barW: BARW,
        slot: SLOT,
        width: Math.max(days.length * SLOT, 1),
        labelXOffset: BARW / 2,
        maxLabel: formatMinutes(Math.round(max)),
    };
});

interface OpsBarCol {
    label: string;
    slotX: number;
    rects: { x: number; y: number; h: number; color: string; title: string }[];
}
const opsChart = computed(() => {
    const days = data.value?.ops.by_day ?? [];
    const SLOT = 54;
    const BARW = 11;
    const GAP = 4;
    const groupW = BARW * 3 + GAP * 2;
    const pad = (SLOT - groupW) / 2;
    const max = Math.max(1, ...days.map((d) => Math.max(d.prepared, d.taken, d.served)));
    const series: { key: 'prepared' | 'taken' | 'served'; color: string; name: string }[] = [
        { key: 'prepared', color: 'var(--p-indigo)', name: 'Hazırlanan' },
        { key: 'taken', color: 'var(--p-sky)', name: 'Teslim' },
        { key: 'served', color: 'var(--p-teal)', name: 'Servis' },
    ];
    const cols: OpsBarCol[] = days.map((d, i) => {
        const slotX = i * SLOT;
        return {
            label: dayLabel(d.date),
            slotX,
            rects: series.map((s, si) => {
                const v = d[s.key];
                const h = (v / max) * PLOT_H;
                return {
                    x: slotX + pad + si * (BARW + GAP),
                    y: PLOT_H - h,
                    h,
                    color: s.color,
                    title: `${dayLabel(d.date)} · ${s.name}: ${formatNumber(v)}`,
                };
            }),
        };
    });
    return { cols, slot: SLOT, barW: BARW, width: Math.max(days.length * SLOT, 1), maxLabel: formatNumber(Math.round(max)) };
});

/* ---------- Boş durum ---------- */
/** Bar sekmesi/donut bağlamı için gerçek operasyon hareketi var mı? */
const hasOpsActivity = computed(() => {
    const o = data.value?.ops;
    return !!o && o.prepared_count + o.taken_count + o.served_count > 0;
});
</script>

<template>
    <PortalLayout title="Raporlarım" active="reports" :heading="'Raporlarım'" :subtitle="subtitle">
        <!-- Pozisyon/rol rozeti (backend zaten hesaplıyor: PortalPerformanceService::roleLabel) -->
        <div v-if="data?.role_label" class="flex justify-center">
            <span class="inline-flex items-center rounded-full bg-(--p-indigo-soft) px-2.5 py-1 text-xs font-semibold text-(--p-indigo)">
                {{ data.role_label }}
            </span>
        </div>

        <!-- Dönem seçici (segmented control) -->
        <div class="flex justify-center">
            <div class="p-seg w-full">
                <button
                    v-for="p in periods"
                    :key="p.key"
                    type="button"
                    class="flex-1"
                    :aria-selected="period === p.key"
                    @click="selectPeriod(p.key)"
                >
                    {{ p.label }}
                </button>
            </div>
        </div>

        <!-- Kazancım (prim) — kişiye atanmış aktif şema varsa görünür -->
        <div v-if="hasEarnings && earnings" class="mt-4 p-card p-4">
            <p class="mb-1 flex items-center gap-2.5 font-semibold text-body">
                <span class="p-chip" style="--chip-bg: var(--p-emerald-soft); --chip-fg: var(--p-emerald)"><AppIcon name="chart" :size="18" /></span>
                Kazancım
            </p>
            <p class="mb-3.5 text-xs text-muted">
                Bu dönemdeki satışın ve hak ettiğin prim
                <span class="font-medium text-body">· {{ earnings.scheme_name }}</span>
            </p>

            <div class="grid grid-cols-2 gap-3">
                <!-- Satışım -->
                <div class="p-tile flex min-h-[4.75rem] flex-col p-tile-sky">
                    <div class="flex items-center gap-1.5 opacity-80">
                        <AppIcon name="cart" :size="15" />
                        <span class="truncate text-xs font-medium">Satışım</span>
                    </div>
                    <p class="mt-auto pt-1.5 text-2xl font-extrabold leading-none tracking-tight tabular-nums">{{ formatCurrencyMinor(earnings.sales_minor) }}</p>
                    <p class="pt-0.5 text-[11px] opacity-70">{{ formatNumber(earnings.order_count) }} sipariş</p>
                </div>

                <!-- Primim (vurgulu) -->
                <div class="p-tile flex min-h-[4.75rem] flex-col p-tile-emerald ring-2 ring-(--p-emerald)">
                    <div class="flex items-center gap-1.5 opacity-80">
                        <AppIcon name="chart" :size="15" />
                        <span class="truncate text-xs font-medium">Primim</span>
                    </div>
                    <p class="mt-auto pt-1.5 text-3xl font-extrabold leading-none tracking-tight tabular-nums">{{ formatCurrencyMinor(earnings.commission_minor) }}</p>
                    <p class="pt-0.5 text-[11px] opacity-70">bu dönem hak edilen</p>
                </div>
            </div>

            <!-- Hedef + karşılanma çubuğu -->
            <div v-if="earningsTarget" class="mt-3">
                <div class="mb-1 flex items-center justify-between text-[11px] font-medium text-muted">
                    <span>Hedef: <strong class="text-body tabular-nums">{{ formatCurrencyMinor(earnings.target_minor) }}</strong></span>
                    <span
                        class="inline-flex items-center gap-1 font-bold tabular-nums"
                        :class="earningsTarget.met ? 'text-(--p-emerald)' : 'text-(--p-amber)'"
                    >
                        <AppIcon :name="earningsTarget.met ? 'check-circle' : 'clock'" :size="13" />
                        %{{ earningsTarget.pct }}
                    </span>
                </div>
                <div class="h-2.5 overflow-hidden rounded-full bg-(--color-inset)">
                    <div
                        class="h-full rounded-full transition-[width] duration-500"
                        :class="earningsTarget.met ? 'bg-(--p-emerald)' : 'bg-(--p-amber)'"
                        :style="{ width: earningsTarget.barPct + '%' }"
                    />
                </div>
                <p class="mt-1.5 text-[11px] text-muted">
                    {{ earningsTarget.met ? 'Hedefe ulaştın — prim kazandın.' : 'Hedefe ulaşınca prim hak edeceksin.' }}
                </p>
            </div>
        </div>

        <!-- Yükleniyor iskeleti -->
        <div v-if="loading" class="mt-4 space-y-4">
            <div class="p-card animate-pulse p-4">
                <div class="mb-3 h-4 w-28 rounded-full bg-(--color-inset)" />
                <div class="grid grid-cols-3 gap-3">
                    <div v-for="n in 3" :key="n" class="h-[4.75rem] rounded-2xl bg-(--color-inset)" />
                </div>
            </div>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div v-for="n in 2" :key="n" class="p-card animate-pulse p-4">
                    <div class="mb-4 h-4 w-32 rounded-full bg-(--color-inset)" />
                    <div class="flex items-center gap-4">
                        <div class="size-[7.5rem] shrink-0 rounded-full bg-(--color-inset)" />
                        <div class="flex-1 space-y-2">
                            <div class="h-3 rounded-full bg-(--color-inset)" />
                            <div class="h-3 w-4/5 rounded-full bg-(--color-inset)" />
                            <div class="h-3 w-3/5 rounded-full bg-(--color-inset)" />
                        </div>
                    </div>
                </div>
            </div>
            <div class="p-card animate-pulse p-4">
                <div class="mb-4 h-4 w-28 rounded-full bg-(--color-inset)" />
                <div class="h-52 rounded-2xl bg-(--color-inset)" />
            </div>
        </div>

        <!-- Veri alınamadı -->
        <div v-else-if="!data" class="mt-4 p-card flex flex-col items-center gap-4 px-6 py-12 text-center">
            <span class="flex size-16 items-center justify-center rounded-2xl bg-(--p-indigo-soft) text-(--p-indigo)">
                <AppIcon name="inbox" :size="30" />
            </span>
            <div>
                <p class="text-base font-bold text-body">Rapor yüklenemedi</p>
                <p class="mt-1 text-sm text-muted">Farklı bir dönem seçmeyi ya da sayfayı yenilemeyi deneyebilirsin.</p>
            </div>
        </div>

        <!-- İçerik -->
        <template v-else-if="data">
            <!-- Anomali uyarısı: aynı gün birden çok mesai -->
            <div
                v-if="multiSessionDays > 0"
                class="mt-4 flex items-start gap-3 rounded-2xl border border-(--p-amber) bg-(--p-amber-soft) p-3.5"
            >
                <span class="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-xl bg-(--p-amber) text-white">
                    <AppIcon name="alert-triangle" :size="18" />
                </span>
                <div class="min-w-0">
                    <p class="text-sm font-bold text-(--p-amber)">Mesai kaydı kontrol edin</p>
                    <p class="mt-0.5 text-xs leading-relaxed text-body">
                        Bu dönemde <strong>{{ formatNumber(multiSessionDays) }}</strong> günde aynı gün birden çok kez mesai başlatılıp
                        bitirilmiş. Sehven açılıp kapatılmış mesai olabilir — aşağıdaki grafikte
                        <span class="inline-flex size-2 rounded-full bg-(--p-amber) align-middle"></span> işaretli günlere bakın.
                    </p>
                </div>
            </div>

            <!-- Çalışma özeti -->
            <div class="mt-4 p-card p-4">
                <p class="mb-3.5 flex items-center gap-2.5 font-semibold text-body">
                    <span class="p-chip" style="--chip-bg: var(--p-teal-soft); --chip-fg: var(--p-teal)"><AppIcon name="clock" :size="18" /></span>
                    Çalışma özeti
                </p>

                <!-- Fiili vs planlı (vurgulu karşılaştırma) -->
                <div v-if="workedCompare" class="grid grid-cols-2 gap-3">
                    <div class="p-tile flex min-h-[4.75rem] flex-col p-tile-teal">
                        <div class="flex items-center gap-1.5 opacity-80">
                            <AppIcon name="clock" :size="15" />
                            <span class="truncate text-xs font-medium">Fiili çalışma</span>
                        </div>
                        <p class="mt-auto pt-1.5 text-3xl font-extrabold leading-none tracking-tight">{{ workedCompare.actualLabel }}</p>
                        <p class="pt-0.5 text-[11px] opacity-70">mola düşülmüş net</p>
                    </div>
                    <div class="p-tile flex min-h-[4.75rem] flex-col p-tile-indigo">
                        <div class="flex items-center gap-1.5 opacity-80">
                            <AppIcon name="calendar" :size="15" />
                            <span class="truncate text-xs font-medium">Planlı</span>
                        </div>
                        <p class="mt-auto pt-1.5 text-3xl font-extrabold leading-none tracking-tight">{{ workedCompare.plannedLabel }}</p>
                        <p class="pt-0.5 text-[11px] opacity-70">planlanan vardiya</p>
                    </div>
                </div>

                <!-- Fiili/planlı oran çubuğu -->
                <div v-if="workedCompare && workedCompare.pct !== null" class="mt-3">
                    <div class="mb-1 flex items-center justify-between text-[11px] font-medium text-muted">
                        <span>Planın karşılanması</span>
                        <span class="font-bold text-(--p-teal) tabular-nums">%{{ workedCompare.pct }}</span>
                    </div>
                    <div class="h-2.5 overflow-hidden rounded-full bg-(--color-inset)">
                        <div
                            class="h-full rounded-full bg-(--p-teal) transition-[width] duration-500"
                            :style="{ width: workedCompare.barPct + '%' }"
                        />
                    </div>
                </div>

                <!-- İkincil kutular + mesai giriş/çıkış -->
                <div class="mt-3 grid grid-cols-2 gap-3">
                    <div v-for="c in workedCards" :key="c.label" class="p-tile flex min-h-[4.75rem] flex-col" :class="c.tile">
                        <div class="flex items-center gap-1.5 opacity-80">
                            <AppIcon :name="c.icon" :size="15" />
                            <span class="truncate text-xs font-medium">{{ c.label }}</span>
                        </div>
                        <p class="mt-auto pt-1.5 text-2xl font-extrabold leading-none tracking-tight">{{ c.value }}</p>
                    </div>
                </div>

                <p class="mt-3 flex items-center gap-2 rounded-xl bg-(--color-inset) px-3 py-2 text-xs text-muted">
                    <AppIcon name="logout" :size="14" class="shrink-0 text-(--p-indigo)" />
                    <span>Mesai giriş/çıkış: <strong class="text-body tabular-nums">{{ formatNumber(totalSessions) }}</strong> kez</span>
                </p>
            </div>

            <!-- Operasyon kutuları — HER ZAMAN görünür -->
            <div class="mt-4 p-card p-4">
                <p class="mb-1 flex items-center gap-2.5 font-semibold text-body">
                    <span class="p-chip" style="--chip-bg: var(--p-amber-soft); --chip-fg: var(--p-amber)"><AppIcon name="utensils" :size="18" /></span>
                    Operasyon
                </p>
                <p class="mb-3.5 text-xs text-muted">Bu dönemde kaç ürün hazırladın, teslim aldın ve servis ettin.</p>
                <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
                    <div v-for="c in opsCards" :key="c.label" class="p-tile flex min-h-[4.75rem] flex-col" :class="c.tile">
                        <div class="flex items-center gap-1.5 opacity-80">
                            <AppIcon :name="c.icon" :size="15" />
                            <span class="truncate text-xs font-medium">{{ c.label }}</span>
                        </div>
                        <p class="mt-auto pt-1.5 text-2xl font-extrabold leading-none tracking-tight">{{ c.value }}</p>
                    </div>
                </div>
            </div>

            <!-- Performans (süre + gecikme metrikleri) -->
            <div class="mt-4 p-card p-4">
                <p class="mb-1 flex items-center gap-2.5 font-semibold text-body">
                    <span class="p-chip" style="--chip-bg: var(--p-indigo-soft); --chip-fg: var(--p-indigo)"><AppIcon name="chart" :size="18" /></span>
                    Performans
                </p>
                <p class="mb-3.5 text-xs text-muted">Sipariş akışında ortalama süreler ve eşiği aşan servisler.</p>
                <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
                    <div v-for="c in perfCards" :key="c.label" class="p-tile flex min-h-[4.75rem] flex-col" :class="c.tile">
                        <div class="flex items-center gap-1.5 opacity-80">
                            <AppIcon :name="c.icon" :size="15" />
                            <span class="truncate text-xs font-medium">{{ c.label }}</span>
                        </div>
                        <p class="mt-auto pt-1.5 text-2xl font-extrabold leading-none tracking-tight">{{ c.value }}</p>
                    </div>

                    <!-- Gecikme sayısı (delay_count>0 ise vurgulu uyarı tonu) -->
                    <div
                        v-if="delayStat"
                        class="p-tile flex min-h-[4.75rem] flex-col p-tile-rose"
                        :class="delayStat.alert ? 'ring-2 ring-(--p-rose)' : 'opacity-90'"
                    >
                        <div class="flex items-center gap-1.5 opacity-80">
                            <AppIcon :name="delayStat.alert ? 'alert-triangle' : 'clock'" :size="15" />
                            <span class="truncate text-xs font-medium">Gecikme sayısı</span>
                        </div>
                        <p class="mt-auto pt-1.5 text-2xl font-extrabold leading-none tracking-tight">{{ delayStat.countLabel }}</p>
                        <p class="pt-0.5 text-[11px] opacity-70">{{ formatNumber(delayStat.threshold) }} dk üzeri servis</p>
                    </div>
                </div>
            </div>

            <!-- Donut grafikleri -->
            <div v-if="workDonut || opsDonut" class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
                <!-- Çalışma dağılımı -->
                <div v-if="workDonut" class="p-card p-4">
                    <p class="mb-3.5 flex items-center gap-2.5 font-semibold text-body">
                        <span class="p-chip" style="--chip-bg: var(--p-teal-soft); --chip-fg: var(--p-teal)"><AppIcon name="clock" :size="18" /></span>
                        Çalışma dağılımı
                    </p>
                    <div class="flex items-center gap-5">
                        <div class="relative size-32 shrink-0">
                            <svg viewBox="0 0 160 160" preserveAspectRatio="xMidYMid meet" class="size-full">
                                <circle cx="80" cy="80" :r="R" fill="none" stroke="var(--color-inset)" :stroke-width="STROKE" />
                                <circle
                                    v-for="(s, i) in workDonut.segs"
                                    :key="i"
                                    cx="80"
                                    cy="80"
                                    :r="R"
                                    fill="none"
                                    :stroke="s.color"
                                    :stroke-width="STROKE"
                                    stroke-linecap="round"
                                    :stroke-dasharray="s.dash"
                                    :stroke-dashoffset="s.offset"
                                    transform="rotate(-90 80 80)"
                                />
                            </svg>
                            <div class="absolute inset-0 flex flex-col items-center justify-center text-center">
                                <span class="text-2xl font-extrabold leading-none tracking-tight text-body tabular-nums">{{ workDonut.centerMain }}</span>
                                <span class="mt-1.5 text-[10px] font-medium uppercase tracking-wide text-subtle">{{ workDonut.centerSub }}</span>
                            </div>
                        </div>
                        <ul class="min-w-0 flex-1 space-y-3">
                            <li v-for="(s, i) in workDonut.segs" :key="i" class="flex items-center gap-2.5 text-sm">
                                <span class="size-2.5 shrink-0 rounded-full" :style="{ backgroundColor: s.color }" />
                                <span class="flex-1 truncate text-muted">{{ s.label }}</span>
                                <span class="font-semibold text-body tabular-nums">{{ formatMinutes(s.value) }}</span>
                                <span class="w-11 shrink-0 rounded-full bg-(--color-inset) py-0.5 text-center text-[11px] font-semibold text-subtle tabular-nums">%{{ s.pct }}</span>
                            </li>
                        </ul>
                    </div>
                </div>

                <!-- Operasyon dağılımı -->
                <div v-if="opsDonut" class="p-card p-4">
                    <p class="mb-3.5 flex items-center gap-2.5 font-semibold text-body">
                        <span class="p-chip" style="--chip-bg: var(--p-emerald-soft); --chip-fg: var(--p-emerald)"><AppIcon name="utensils" :size="18" /></span>
                        Operasyon dağılımı
                    </p>
                    <div class="flex items-center gap-5">
                        <div class="relative size-32 shrink-0">
                            <svg viewBox="0 0 160 160" preserveAspectRatio="xMidYMid meet" class="size-full">
                                <circle cx="80" cy="80" :r="R" fill="none" stroke="var(--color-inset)" :stroke-width="STROKE" />
                                <circle
                                    v-for="(s, i) in opsDonut.segs"
                                    :key="i"
                                    cx="80"
                                    cy="80"
                                    :r="R"
                                    fill="none"
                                    :stroke="s.color"
                                    :stroke-width="STROKE"
                                    stroke-linecap="round"
                                    :stroke-dasharray="s.dash"
                                    :stroke-dashoffset="s.offset"
                                    transform="rotate(-90 80 80)"
                                />
                            </svg>
                            <div class="absolute inset-0 flex flex-col items-center justify-center text-center">
                                <span class="text-2xl font-extrabold leading-none tracking-tight text-body tabular-nums">{{ formatNumber(opsDonut.total) }}</span>
                                <span class="mt-1.5 text-[10px] font-medium uppercase tracking-wide text-subtle">{{ opsDonut.centerSub }}</span>
                            </div>
                        </div>
                        <ul class="min-w-0 flex-1 space-y-3">
                            <li v-for="(s, i) in opsDonut.segs" :key="i" class="flex items-center gap-2.5 text-sm">
                                <span class="size-2.5 shrink-0 rounded-full" :style="{ backgroundColor: s.color }" />
                                <span class="flex-1 truncate text-muted">{{ s.label }}</span>
                                <span class="font-semibold text-body tabular-nums">{{ formatNumber(s.value) }}</span>
                                <span class="w-11 shrink-0 rounded-full bg-(--color-inset) py-0.5 text-center text-[11px] font-semibold text-subtle tabular-nums">%{{ s.pct }}</span>
                            </li>
                        </ul>
                    </div>
                </div>
            </div>

            <!-- Günlük bar grafik -->
            <div class="mt-4 p-card p-4">
                <div class="flex items-center justify-between gap-2">
                    <p class="flex items-center gap-2.5 font-semibold text-body">
                        <span class="p-chip" style="--chip-bg: var(--p-indigo-soft); --chip-fg: var(--p-indigo)"><AppIcon name="chart" :size="18" /></span>
                        Günlük dağılım
                    </p>
                    <div v-if="hasOpsActivity" class="flex gap-1 rounded-full border border-(--p-card-border) bg-(--color-inset) p-0.5 text-xs font-medium">
                        <button
                            type="button"
                            class="min-h-8 rounded-full px-2.5 transition-colors"
                            :class="barTab === 'worked' ? 'bg-(--p-card) text-body shadow-(--p-card-shadow)' : 'text-muted'"
                            @click="barTab = 'worked'"
                        >
                            Çalışma
                        </button>
                        <button
                            type="button"
                            class="min-h-8 rounded-full px-2.5 transition-colors"
                            :class="barTab === 'ops' ? 'bg-(--p-card) text-body shadow-(--p-card-shadow)' : 'text-muted'"
                            @click="barTab = 'ops'"
                        >
                            Operasyon
                        </button>
                    </div>
                </div>

                <!-- Çalışma bar grafik (yığılmış: çalışma + mola) -->
                <div v-show="barTab === 'worked' || !hasOpsActivity" class="mt-4">
                    <div class="mb-2.5 flex flex-wrap items-center gap-3 text-[11px] font-medium text-muted">
                        <span class="flex items-center gap-1.5"><span class="size-2.5 rounded-full bg-(--p-teal)" /> Çalışma</span>
                        <span class="flex items-center gap-1.5"><span class="size-2.5 rounded-full bg-(--p-amber)" /> Mola</span>
                        <span v-if="multiSessionDays > 0" class="flex items-center gap-1.5"><span class="size-2.5 rounded-full bg-(--p-amber) ring-2 ring-(--p-amber-soft)" /> Çok mesai</span>
                        <span class="ml-auto text-subtle">en yüksek {{ workedChart.maxLabel }}</span>
                    </div>
                    <div class="overflow-x-auto">
                        <svg :width="workedChart.width" :height="SVG_H" class="mx-auto block">
                            <defs>
                                <linearGradient id="barWork" x1="0" y1="0" x2="0" y2="1">
                                    <stop offset="0%" stop-color="var(--p-teal)" stop-opacity="0.85" />
                                    <stop offset="100%" stop-color="var(--p-teal)" stop-opacity="1" />
                                </linearGradient>
                            </defs>
                            <!-- ızgara -->
                            <line
                                v-for="g in gridLines"
                                :key="g.f"
                                x1="0"
                                :y1="g.y"
                                :x2="workedChart.width"
                                :y2="g.y"
                                stroke="var(--p-card-border)"
                                stroke-width="1"
                                :stroke-dasharray="g.f === 0 ? '0' : '2 3'"
                            />
                            <template v-for="(b, i) in workedChart.bars" :key="i">
                                <rect :x="b.x" :y="b.breakY" :width="workedChart.barW" :height="b.breakH" rx="6" fill="var(--p-amber)">
                                    <title>{{ b.title }}</title>
                                </rect>
                                <rect :x="b.x" :y="b.workY" :width="workedChart.barW" :height="b.workH" rx="6" fill="url(#barWork)">
                                    <title>{{ b.title }}</title>
                                </rect>
                                <!-- Aynı gün birden çok mesai işareti -->
                                <circle
                                    v-if="b.multi"
                                    :cx="b.cx"
                                    :cy="b.markerY"
                                    r="4"
                                    fill="var(--p-amber)"
                                    stroke="var(--p-card)"
                                    stroke-width="1.5"
                                >
                                    <title>{{ b.title }}</title>
                                </circle>
                                <text
                                    :x="b.x + workedChart.labelXOffset"
                                    :y="PLOT_H + 16"
                                    text-anchor="middle"
                                    class="fill-(--color-subtle)"
                                    style="font-size: 10px"
                                >
                                    {{ b.label }}
                                </text>
                            </template>
                        </svg>
                    </div>
                </div>

                <!-- Operasyon bar grafik (gruplu) -->
                <div v-if="hasOpsActivity" v-show="barTab === 'ops'" class="mt-4">
                    <div class="mb-2.5 flex flex-wrap items-center gap-3 text-[11px] font-medium text-muted">
                        <span class="flex items-center gap-1.5"><span class="size-2.5 rounded-full bg-(--p-indigo)" /> Hazırlanan</span>
                        <span class="flex items-center gap-1.5"><span class="size-2.5 rounded-full bg-(--p-sky)" /> Teslim</span>
                        <span class="flex items-center gap-1.5"><span class="size-2.5 rounded-full bg-(--p-teal)" /> Servis</span>
                        <span class="ml-auto text-subtle">en yüksek {{ opsChart.maxLabel }}</span>
                    </div>
                    <div class="overflow-x-auto">
                        <svg :width="opsChart.width" :height="SVG_H" class="mx-auto block">
                            <line
                                v-for="g in gridLines"
                                :key="g.f"
                                x1="0"
                                :y1="g.y"
                                :x2="opsChart.width"
                                :y2="g.y"
                                stroke="var(--p-card-border)"
                                stroke-width="1"
                                :stroke-dasharray="g.f === 0 ? '0' : '2 3'"
                            />
                            <template v-for="(col, i) in opsChart.cols" :key="i">
                                <rect
                                    v-for="(r, ri) in col.rects"
                                    :key="ri"
                                    :x="r.x"
                                    :y="r.y"
                                    :width="opsChart.barW"
                                    :height="r.h"
                                    rx="4"
                                    :fill="r.color"
                                >
                                    <title>{{ r.title }}</title>
                                </rect>
                                <text
                                    :x="col.slotX + opsChart.slot / 2"
                                    :y="PLOT_H + 16"
                                    text-anchor="middle"
                                    class="fill-(--color-subtle)"
                                    style="font-size: 10px"
                                >
                                    {{ col.label }}
                                </text>
                            </template>
                        </svg>
                    </div>
                </div>
            </div>

            <!-- Sipariş özeti (opsiyonel) -->
            <div v-if="data.orders && data.orders.order_count" class="mt-4 p-card flex items-center gap-3 p-4">
                <span class="p-tile flex size-11 items-center justify-center !p-0 p-tile-violet">
                    <AppIcon name="orders" :size="20" />
                </span>
                <div class="flex-1">
                    <p class="text-sm font-semibold text-body">{{ formatNumber(data.orders.order_count) }} sipariş</p>
                    <p class="text-xs text-muted">Ort. servis süresi {{ dashMin(data.orders.avg_service_min) }}</p>
                </div>
            </div>
        </template>
    </PortalLayout>
</template>
