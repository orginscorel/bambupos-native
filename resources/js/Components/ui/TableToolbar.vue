<script setup lang="ts">
/**
 * Liste filtre/araç çubuğu deseni.
 *
 * Sol tarafta arama + filtreler (default slot), sağda birincil aksiyon
 * (#action slot). Dar ekranda dikey sarmalanır; asla yatay TAŞMAZ.
 * Kontroller `flex-wrap` ile alt satıra iner, dokunma hedefleri ≥44px kalır.
 *
 * <TableToolbar>
 *   <SearchInput ... />
 *   <BaseSelect ... />
 *   <template #action><BaseButton>Yeni</BaseButton></template>
 * </TableToolbar>
 */
const slots = defineSlots<{
    default(): unknown;
    action?: () => unknown;
}>();
</script>

<template>
    <div class="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center">
        <div class="flex min-w-0 flex-1 flex-wrap items-center gap-2">
            <slot />
        </div>
        <div v-if="slots.action" class="flex shrink-0 items-center gap-2">
            <slot name="action" />
        </div>
    </div>
</template>
