<script setup lang="ts">
import { computed, ref } from 'vue';
import { formatCurrencyMinor, formatNumber } from '@/lib/format';

/**
 * Dikey sütun grafiği (tek seri, satır-içi SVG — dış kütüphane yok).
 * Dataviz kuralları: ≤24px sütun, 4px yuvarlak VERİ UCU (taban köşeli),
 * kılcal düz gridline, metin token rengi, işaretleyici hover tooltip
 * (vurgu marka değil; tek seri = palet 1. slot).
 */
export interface ColumnPoint {
    label: string;      // eksen etiketi (kısa)
    title?: string;     // tooltip başlığı (uzun; yoksa label)
    value: number;
}

const props = withDefaults(
    defineProps<{
        points: ColumnPoint[];
        /** value alanı kuruş mu (₺ biçimi) yoksa adet mi */
        money?: boolean;
        height?: number;
        /** Uzun eksenlerde her n. etiket yazılır (0 = otomatik) */
        labelEvery?: number;
        label: string;
    }>(),
    { money: false, height: 200, labelEvery: 0 },
);

const W = 640;
const PAD = { top: 14, right: 8, bottom: 22, left: 44 };

const H = computed(() => props.height);
const plotW = computed(() => W - PAD.left - PAD.right);
const plotH = computed(() => H.value - PAD.top - PAD.bottom);

const max = computed(() => Math.max(...props.points.map((p) => p.value), 0));

/** Temiz üst sınır: 1/2/5 × 10^n. */
const niceMax = computed(() => {
    if (max.value === 0) return 1;
    const pow = Math.pow(10, Math.floor(Math.log10(max.value)));
    for (const m of [1, 2, 5, 10]) {
        if (m * pow >= max.value) return m * pow;
    }
    return 10 * pow;
});

const ticks = computed(() => [0, niceMax.value / 2, niceMax.value]);

const band = computed(() => plotW.value / Math.max(props.points.length, 1));
const barW = computed(() => Math.min(24, Math.max(3, band.value - 4)));

const fmt = (v: number) => (props.money ? formatCurrencyMinor(v) : formatNumber(v));
const fmtAxis = (v: number) =>
    props.money
        ? new Intl.NumberFormat('tr-TR', { notation: 'compact', maximumFractionDigits: 1 }).format(v / 100)
        : new Intl.NumberFormat('tr-TR', { notation: 'compact', maximumFractionDigits: 1 }).format(v);

function x(i: number): number {
    return PAD.left + i * band.value + (band.value - barW.value) / 2;
}

function barH(v: number): number {
    return niceMax.value > 0 ? (v / niceMax.value) * plotH.value : 0;
}

/** 4px yuvarlak uç YALNIZ üstte; taban köşeli (dataviz mark spec). */
function barPath(i: number, v: number): string {
    const h = barH(v);
    if (h <= 0) return '';
    const bx = x(i);
    const by = PAD.top + plotH.value - h;
    const r = Math.min(4, barW.value / 2, h);
    const w = barW.value;
    return `M${bx},${by + h} V${by + r} Q${bx},${by} ${bx + r},${by} H${bx + w - r} Q${bx + w},${by} ${bx + w},${by + r} V${by + h} Z`;
}

const labelStep = computed(() => {
    if (props.labelEvery > 0) return props.labelEvery;
    return Math.max(1, Math.ceil(props.points.length / 8));
});

/* En yüksek nokta seçici direct-label alır (her noktaya sayı yazılmaz). */
const maxIndex = computed(() => {
    let idx = -1;
    let best = 0;
    props.points.forEach((p, i) => {
        if (p.value > best) {
            best = p.value;
            idx = i;
        }
    });
    return idx;
});

const hover = ref<number | null>(null);
const hasData = computed(() => props.points.some((p) => p.value > 0));

const tooltipStyle = computed(() => {
    if (hover.value === null) return {};
    const center = ((x(hover.value) + barW.value / 2) / W) * 100;
    return { left: `${Math.min(Math.max(center, 12), 88)}%` };
});
</script>

<template>
    <div class="relative" role="img" :aria-label="label">
        <svg :viewBox="`0 0 ${W} ${H}`" class="block w-full" @pointerleave="hover = null">
            <!-- gridlines: kılcal, düz, çekinik -->
            <g>
                <line
                    v-for="t in ticks"
                    :key="`g${t}`"
                    :x1="PAD.left"
                    :x2="W - PAD.right"
                    :y1="PAD.top + plotH - (t / niceMax) * plotH"
                    :y2="PAD.top + plotH - (t / niceMax) * plotH"
                    :stroke="t === 0 ? 'var(--viz-axis)' : 'var(--viz-grid)'"
                    stroke-width="1"
                />
                <text
                    v-for="t in ticks"
                    :key="`gt${t}`"
                    :x="PAD.left - 6"
                    :y="PAD.top + plotH - (t / niceMax) * plotH + 3"
                    text-anchor="end"
                    class="fill-subtle"
                    font-size="10"
                >
                    {{ fmtAxis(t) }}
                </text>
            </g>

            <!-- sütunlar -->
            <g>
                <path
                    v-for="(p, i) in points"
                    :key="`b${i}`"
                    :d="barPath(i, p.value)"
                    fill="var(--viz-1)"
                    :opacity="hover === null || hover === i ? 1 : 0.45"
                />
            </g>

            <!-- seçici direct label: yalnız zirve -->
            <text
                v-if="maxIndex >= 0 && hasData"
                :x="x(maxIndex) + barW / 2"
                :y="PAD.top + plotH - barH(points[maxIndex].value) - 5"
                text-anchor="middle"
                class="fill-muted"
                font-size="10"
                font-weight="600"
            >
                {{ fmt(points[maxIndex].value) }}
            </text>

            <!-- x ekseni etiketleri -->
            <g>
                <template v-for="(p, i) in points" :key="`l${i}`">
                    <text
                        v-if="i % labelStep === 0"
                        :x="x(i) + barW / 2"
                        :y="H - 6"
                        text-anchor="middle"
                        class="fill-subtle"
                        font-size="10"
                    >
                        {{ p.label }}
                    </text>
                </template>
            </g>

            <!-- hover hit alanları: işaretten büyük hedef -->
            <g>
                <rect
                    v-for="(p, i) in points"
                    :key="`h${i}`"
                    :x="PAD.left + i * band"
                    :y="PAD.top"
                    :width="band"
                    :height="plotH"
                    fill="transparent"
                    @pointerenter="hover = i"
                    @focus="hover = i"
                />
            </g>
        </svg>

        <!-- tooltip: değer önde, etiket ikincil -->
        <div
            v-if="hover !== null"
            class="pointer-events-none absolute top-1 z-10 -translate-x-1/2 rounded-md border border-default bg-raised px-2.5 py-1.5 text-xs shadow-dropdown"
            :style="tooltipStyle"
        >
            <div class="font-semibold text-body">{{ fmt(points[hover].value) }}</div>
            <div class="text-subtle">{{ points[hover].title ?? points[hover].label }}</div>
        </div>
    </div>
</template>
