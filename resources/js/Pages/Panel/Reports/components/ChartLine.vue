<script setup lang="ts">
import { computed, ref } from 'vue';
import { formatCurrencyMinor, formatNumber } from '@/lib/format';

/**
 * Tek serili çizgi/alan grafiği (satır-içi SVG). Dataviz kuralları:
 * 2px çizgi, %10 alan yıkaması, ≥8px uç noktası + 2px yüzey halkası,
 * crosshair'li tooltip (okuyucu tarihe nişan alır, çizgiye değil).
 */
export interface LinePoint {
    label: string;
    title?: string;
    value: number;
}

const props = withDefaults(
    defineProps<{
        points: LinePoint[];
        money?: boolean;
        height?: number;
        label: string;
    }>(),
    { money: false, height: 180 },
);

const W = 640;
const PAD = { top: 14, right: 14, bottom: 22, left: 44 };

const H = computed(() => props.height);
const plotW = computed(() => W - PAD.left - PAD.right);
const plotH = computed(() => H.value - PAD.top - PAD.bottom);

const max = computed(() => Math.max(...props.points.map((p) => p.value), 0));
const niceMax = computed(() => {
    if (max.value === 0) return 1;
    const pow = Math.pow(10, Math.floor(Math.log10(max.value)));
    for (const m of [1, 2, 5, 10]) {
        if (m * pow >= max.value) return m * pow;
    }
    return 10 * pow;
});
const ticks = computed(() => [0, niceMax.value / 2, niceMax.value]);

function x(i: number): number {
    const n = Math.max(props.points.length - 1, 1);
    return PAD.left + (i / n) * plotW.value;
}

function y(v: number): number {
    return PAD.top + plotH.value - (v / niceMax.value) * plotH.value;
}

const linePath = computed(() =>
    props.points.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(p.value).toFixed(1)}`).join(' '),
);

const areaPath = computed(() => {
    if (props.points.length === 0) return '';
    const base = PAD.top + plotH.value;
    return `${linePath.value} L${x(props.points.length - 1).toFixed(1)},${base} L${x(0).toFixed(1)},${base} Z`;
});

const fmt = (v: number) => (props.money ? formatCurrencyMinor(v) : formatNumber(v));
const fmtAxis = (v: number) =>
    new Intl.NumberFormat('tr-TR', { notation: 'compact', maximumFractionDigits: 1 }).format(props.money ? v / 100 : v);

const labelStep = computed(() => Math.max(1, Math.ceil(props.points.length / 7)));

const hover = ref<number | null>(null);

function onMove(event: PointerEvent): void {
    const svg = event.currentTarget as SVGSVGElement;
    const rect = svg.getBoundingClientRect();
    const px = ((event.clientX - rect.left) / rect.width) * W;
    const n = Math.max(props.points.length - 1, 1);
    const idx = Math.round(((px - PAD.left) / plotW.value) * n);
    hover.value = Math.min(Math.max(idx, 0), props.points.length - 1);
}

const last = computed(() => props.points.length - 1);

const tooltipStyle = computed(() => {
    if (hover.value === null) return {};
    return { left: `${Math.min(Math.max((x(hover.value) / W) * 100, 12), 88)}%` };
});
</script>

<template>
    <div class="relative" role="img" :aria-label="label">
        <svg :viewBox="`0 0 ${W} ${H}`" class="block w-full" @pointermove="onMove" @pointerleave="hover = null">
            <g>
                <line
                    v-for="t in ticks"
                    :key="`g${t}`"
                    :x1="PAD.left"
                    :x2="W - PAD.right"
                    :y1="y(t)"
                    :y2="y(t)"
                    :stroke="t === 0 ? 'var(--viz-axis)' : 'var(--viz-grid)'"
                    stroke-width="1"
                />
                <text
                    v-for="t in ticks"
                    :key="`gt${t}`"
                    :x="PAD.left - 6"
                    :y="y(t) + 3"
                    text-anchor="end"
                    class="fill-subtle"
                    font-size="10"
                >
                    {{ fmtAxis(t) }}
                </text>
            </g>

            <!-- alan yıkaması + 2px çizgi -->
            <path :d="areaPath" fill="var(--viz-1)" :opacity="0.1" />
            <path :d="linePath" fill="none" stroke="var(--viz-1)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />

            <!-- crosshair -->
            <line
                v-if="hover !== null"
                :x1="x(hover)"
                :x2="x(hover)"
                :y1="PAD.top"
                :y2="PAD.top + plotH"
                stroke="var(--viz-axis)"
                stroke-width="1"
            />

            <!-- uç nokta: ≥8px işaret + 2px yüzey halkası -->
            <circle
                v-if="points.length > 0"
                :cx="x(last)"
                :cy="y(points[last].value)"
                r="4"
                fill="var(--viz-1)"
                stroke="var(--color-raised)"
                stroke-width="2"
            />

            <!-- hover noktası -->
            <circle
                v-if="hover !== null"
                :cx="x(hover)"
                :cy="y(points[hover].value)"
                r="4"
                fill="var(--viz-1)"
                stroke="var(--color-raised)"
                stroke-width="2"
            />

            <!-- x etiketleri -->
            <g>
                <template v-for="(p, i) in points" :key="`l${i}`">
                    <text
                        v-if="i % labelStep === 0 || i === last"
                        :x="x(i)"
                        :y="H - 6"
                        :text-anchor="i === 0 ? 'start' : i === last ? 'end' : 'middle'"
                        class="fill-subtle"
                        font-size="10"
                    >
                        {{ p.label }}
                    </text>
                </template>
            </g>
        </svg>

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
