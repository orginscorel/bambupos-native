<script setup lang="ts">
withDefaults(
    defineProps<{
        title?: string;
        /** Gövde iç boşluğunu kaldırır (tablo gömmek için) */
        flush?: boolean;
    }>(),
    { title: '', flush: false },
);
</script>

<template>
    <section class="rounded-lg border border-default bg-raised shadow-card">
        <header
            v-if="title || $slots.header || $slots.actions"
            class="flex min-h-12 items-center justify-between gap-3 border-b border-default px-4 py-3"
        >
            <slot name="header">
                <h2 class="text-sm font-semibold text-body">{{ title }}</h2>
            </slot>
            <slot name="actions" />
        </header>
        <div :class="flush ? '' : 'p-4'">
            <slot />
        </div>
        <footer v-if="$slots.footer" class="border-t border-default px-4 py-3">
            <slot name="footer" />
        </footer>
    </section>
</template>
