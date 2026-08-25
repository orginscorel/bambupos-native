<script setup lang="ts">
import BaseSkeleton from './BaseSkeleton.vue';

/**
 * Liste satırı iskeleti (native yükleme). `ListRow` anatomisini taklit eder:
 * sol yuvarlak + iki metin çizgisi + sağda kısa değer. `count` kadar tekrar.
 * `MobileListGroup` içine konur (hairline ayraçlar otomatik gelir).
 */
withDefaults(
    defineProps<{
        count?: number;
        /** Sol ikon dairesini göster. */
        icon?: boolean;
        /** İkinci (alt) metin çizgisini göster. */
        subtitle?: boolean;
    }>(),
    { count: 4, icon: true, subtitle: true },
);
</script>

<template>
    <div
        v-for="i in count"
        :key="i"
        class="flex items-center gap-3 px-4"
        :style="{ minHeight: subtitle ? 'var(--h-list-row-lg)' : 'var(--h-list-row)' }"
    >
        <BaseSkeleton v-if="icon" variant="circle" size-class="size-9 rounded-[10px]" />
        <div class="flex min-w-0 grow flex-col gap-1.5">
            <BaseSkeleton size-class="h-3.5 w-2/5" />
            <BaseSkeleton v-if="subtitle" size-class="h-3 w-3/5" />
        </div>
        <BaseSkeleton size-class="h-3.5 w-10" />
    </div>
</template>
