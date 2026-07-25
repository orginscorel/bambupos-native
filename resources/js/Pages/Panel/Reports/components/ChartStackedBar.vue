<script setup lang="ts">
import { computed, ref } from 'vue';
import { formatCurrencyMinor, formatNumber } from '@/lib/format';
import { seriesColor } from '../reports';

/**
 * Yatay parça-bütün çubuğu (satır-içi SVG): ödeme yöntemi / kanal payı gibi
 * ≤4 segment + "Diğer". Dataviz kuralları: segmentler arası 2px yüzey
 * boşluğu, ≥2 seri için legend HER ZAMAN var, renk varlığı izler (sabit
 * sıra caller'da kurulur), tooltip segment üstünde.
 */
export interface StackSegment {
    label: string;
    value: number;
    /** Palet slotu (0-3) ya da 4+ = "Diğer" grisi. Varlığa sabitlenir. */
    colorIndex: number;
    hint?: string;
}

const props = withDefaults(
    defineProps<{
        segments: StackSegment[];
        money?: boolean;
        label: string;
    }>(),
    { money: false },
);

const total = computed(() => props.segments.reduce((sum, s) => sum + s.value, 0));
const fmt = (v: number) => (props.money ? formatCurrencyMinor(v) : formatNumber(v));

const W = 640;
const BAR_H = 28;
const GAP = 2;

const boxes = computed(() => {
    if (total.value === 0) return [];
    let cursor = 0;
    return props.segments.map((s, i) => {
        const w = (s.value / total.value) * (W - GAP * (props.segments.length - 1));
        const box = { x: cursor, w, seg: s, i };
        cursor += w + GAP;
        return box;
    });
});

const hover = ref<number | null>(null);

const tooltipStyle = computed(() => {
    if (hover.value === null) return {};
    const b = boxes.value[hover.value];
    return { left: `${Math.min(Math.max(((b.x + b.w / 2) / W) * 100, 12), 88)}%` };
});
</script>

<template>
    <div>
        <div class="relative" role="img" :aria-label="label">
            <svg :viewBox="`0 0 ${W} ${BAR_H}`" class="block w-full" :style="{ height: `${BAR_H}px` }" @pointerleave="hover = null">
                <rect
                    v-for="b in boxes"
                    :key="b.i"
                    :x="b.x"
                    y="4"
                    :width="Math.max(b.w, 1)"
                    :height="BAR_H - 8"
                    rx="3"
                    :fill="seriesColor(b.seg.colorIndex)"
                    :opacity="hover === null || hover === b.i ? 1 : 0.45"
                    @pointerenter="hover = b.i"
                />
            </svg>

            <div
                v-if="hover !== null"
                class="pointer-events-none absolute bottom-full z-10 mb-1 -translate-x-1/2 rounded-md border border-default bg-raised px-2.5 py-1.5 text-xs whitespace-nowrap shadow-dropdown"
                :style="tooltipStyle"
            >
                <div class="font-semibold text-body">{{ fmt(segments[hover].value) }}</div>
                <div class="text-subtle">
                    {{ segments[hover].label }}
                    <template v-if="segments[hover].hint"> · {{ segments[hover].hint }}</template>
                </div>
            </div>
        </div>

        <!-- legend: kimlik asla yalnız renkle anlatılmaz -->
        <ul class="mt-2 flex flex-wrap gap-x-4 gap-y-1">
            <li v-for="(s, i) in segments" :key="i" class="flex items-center gap-1.5 text-xs">
                <span
                    class="inline-block size-2.5 shrink-0 rounded-[3px]"
                    :style="{ backgroundColor: seriesColor(s.colorIndex) }"
                    aria-hidden="true"
                />
                <span class="text-muted">{{ s.label }}</span>
                <span class="font-semibold text-body">{{ fmt(s.value) }}</span>
                <span v-if="total > 0" class="text-subtle">(%{{ ((s.value * 100) / total).toFixed(1).replace('.', ',') }})</span>
            </li>
        </ul>
    </div>
</template>
