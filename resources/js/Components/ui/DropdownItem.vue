<script setup lang="ts">
import { Link } from '@inertiajs/vue3';
import AppIcon from './AppIcon.vue';

const props = withDefaults(
    defineProps<{
        icon?: string;
        href?: string;
        danger?: boolean;
        disabled?: boolean;
    }>(),
    { icon: '', danger: false, disabled: false },
);

const emit = defineEmits<{ select: [] }>();
</script>

<template>
    <component
        :is="href && !disabled ? Link : 'button'"
        :href="href"
        :type="href ? undefined : 'button'"
        role="menuitem"
        :tabindex="-1"
        :aria-disabled="disabled || undefined"
        :disabled="href ? undefined : disabled"
        class="flex w-full items-center gap-2.5 px-3 py-2 text-left text-sm transition-colors duration-(--dur-fast)
               focus:outline-none focus-visible:bg-inset
               disabled:cursor-not-allowed disabled:opacity-55"
        :class="danger ? 'text-danger hover:bg-danger-soft' : 'text-body hover:bg-inset'"
        @click="!disabled && emit('select')"
    >
        <AppIcon v-if="icon" :name="icon" :size="16" />
        <slot />
    </component>
</template>
