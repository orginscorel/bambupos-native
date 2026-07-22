<script setup lang="ts">
import { computed } from 'vue';
import { Link } from '@inertiajs/vue3';

const props = withDefaults(
    defineProps<{
        variant?: 'primary' | 'secondary' | 'danger' | 'ghost';
        size?: 'sm' | 'md' | 'lg';
        type?: 'button' | 'submit' | 'reset';
        /** Verilirse Inertia <Link> olarak render edilir */
        href?: string;
        loading?: boolean;
        disabled?: boolean;
        block?: boolean;
        /** Yalnız-ikon buton: kare olur; erişilebilirlik için label zorunlu */
        iconOnly?: boolean;
        label?: string;
    }>(),
    { variant: 'primary', size: 'md', type: 'button', loading: false, disabled: false, block: false, iconOnly: false },
);

const isDisabled = computed(() => props.disabled || props.loading);

const classes = computed(() => {
    const base =
        'inline-flex items-center justify-center gap-2 font-medium select-none whitespace-nowrap ' +
        'transition-colors duration-(--dur-fast) rounded-md ' +
        'disabled:opacity-55 disabled:cursor-not-allowed';
    const sizes = {
        sm: props.iconOnly ? 'h-8 w-8 text-sm' : 'h-8 px-3 text-sm',
        md: props.iconOnly ? 'h-10 w-10 text-sm' : 'h-10 px-4 text-sm',
        lg: props.iconOnly ? 'h-11 w-11 text-base' : 'h-11 px-5 text-base',
    };
    const variants = {
        primary: 'bg-primary text-on-primary hover:bg-primary-hover active:bg-primary-active',
        secondary: 'bg-raised text-body border border-strong hover:bg-inset active:bg-inset',
        danger: 'bg-danger text-on-status hover:bg-danger-hover',
        ghost: 'bg-transparent text-body hover:bg-inset',
    };
    return [base, sizes[props.size], variants[props.variant], props.block ? 'w-full' : ''].join(' ');
});
</script>

<template>
    <component
        :is="href && !isDisabled ? Link : 'button'"
        :href="href"
        :type="href ? undefined : type"
        :disabled="href ? undefined : isDisabled"
        :aria-disabled="isDisabled || undefined"
        :aria-busy="loading || undefined"
        :aria-label="iconOnly ? label : undefined"
        :title="iconOnly ? label : undefined"
        :class="classes"
    >
        <span
            v-if="loading"
            class="inline-block size-4 shrink-0 animate-spin rounded-full border-2 border-current border-t-transparent"
            aria-hidden="true"
        />
        <slot />
    </component>
</template>
