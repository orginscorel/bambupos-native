<script setup lang="ts">
import AppIcon from './AppIcon.vue';

withDefaults(
    defineProps<{
        title: string;
        description?: string;
        icon?: string;
    }>(),
    { description: '', icon: 'inbox' },
);
</script>

<template>
    <div class="flex flex-col items-center justify-center gap-2 px-6 py-12 text-center">
        <span class="mb-1 flex size-12 items-center justify-center rounded-full bg-inset text-subtle">
            <AppIcon :name="icon" :size="24" />
        </span>
        <h3 class="text-sm font-semibold text-body">{{ title }}</h3>
        <p v-if="description" class="max-w-sm text-sm text-muted">{{ description }}</p>
        <div v-if="$slots.action" class="mt-3">
            <slot name="action" />
        </div>
    </div>
</template>
