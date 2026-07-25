<script setup lang="ts">
import { computed } from 'vue';

/**
 * Stat kartı (dataviz "stat tile" sözleşmesi): etiket + değer + isteğe
 * bağlı delta (adlandırılmış döneme karşı, işaretli). Delta yoksa ya da
 * önceki dönem 0 ise kıyas GÖSTERİLMEZ — uydurma oran yok.
 */
const props = withDefaults(
    defineProps<{
        label: string;
        value: string;
        /** Yüzde değişim (null = kıyas verisi yok) */
        delta?: number | null;
        /** Kıyasın adı: "düne göre" gibi */
        deltaLabel?: string;
        /** Artış iyi mi? (iptallerde artış kötüdür) */
        upIsGood?: boolean;
        hint?: string;
    }>(),
    { delta: null, deltaLabel: '', upIsGood: true, hint: '' },
);

const deltaText = computed(() => {
    if (props.delta === null) return '';
    const sign = props.delta > 0 ? '+' : '';
    return `${sign}${props.delta.toLocaleString('tr-TR')}%`;
});

const deltaClass = computed(() => {
    if (props.delta === null || props.delta === 0) return 'text-muted';
    const good = props.delta > 0 === props.upIsGood;
    return good ? 'text-success' : 'text-danger';
});
</script>

<template>
    <div class="flex flex-col gap-1.5 rounded-lg border border-default bg-raised p-4 shadow-card">
        <span class="text-xs font-medium text-muted">{{ label }}</span>
        <span class="text-2xl font-semibold text-body">{{ value }}</span>
        <span v-if="delta !== null && deltaLabel" class="text-xs" :class="deltaClass">
            {{ deltaText }} <span class="text-subtle">{{ deltaLabel }}</span>
        </span>
        <span v-else-if="hint" class="text-xs text-subtle">{{ hint }}</span>
    </div>
</template>
