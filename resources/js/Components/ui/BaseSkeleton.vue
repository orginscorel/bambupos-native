<script setup lang="ts">
withDefaults(
    defineProps<{
        variant?: 'line' | 'circle' | 'rect';
        /** Tailwind boyut sınıfları (ör. "h-4 w-40") */
        sizeClass?: string;
    }>(),
    { variant: 'line', sizeClass: '' },
);
</script>

<template>
    <span
        class="skeleton-shimmer block bg-inset"
        :class="[
            variant === 'circle' ? 'rounded-full' : variant === 'rect' ? 'rounded-lg' : 'rounded-xs',
            sizeClass || (variant === 'circle' ? 'size-10' : variant === 'rect' ? 'h-24 w-full' : 'h-4 w-full'),
        ]"
        aria-hidden="true"
    />
</template>
