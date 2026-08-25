<script setup lang="ts">
/**
 * Bölüm başlığı: solda küçük semibold başlık (+ opsiyonel sayı), sağda aksiyon
 * (slot — "Tümü", "Düzenle" vb. text-buton). Native gruplar arası ritmi verir.
 */
withDefaults(
    defineProps<{
        title: string;
        /** Başlığın yanında yumuşak sayaç rozeti. */
        count?: number | string;
    }>(),
    {},
);
</script>

<template>
    <div class="flex items-center justify-between gap-3 px-1">
        <h2 class="flex items-center gap-2 text-[17px] font-semibold text-body">
            {{ title }}
            <span
                v-if="count !== undefined && count !== ''"
                class="inline-flex min-w-5 items-center justify-center rounded-full bg-inset px-1.5 text-[12px] font-semibold text-muted tabular-nums"
            >
                {{ count }}
            </span>
        </h2>
        <div v-if="$slots.action" class="shrink-0">
            <slot name="action" />
        </div>
    </div>
</template>
