<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from './AppIcon.vue';

/**
 * Durum rozeti. Durum YALNIZ renkle anlatılmaz: durum varyantları
 * varsayılan olarak ikon da taşır (renk körlüğü desteği).
 */
const props = withDefaults(
    defineProps<{
        variant?: 'neutral' | 'primary' | 'success' | 'warning' | 'danger' | 'info';
        /** İkonu gizle (yalnız görsel süs olduğunda) */
        noIcon?: boolean;
    }>(),
    { variant: 'neutral', noIcon: false },
);

const icons: Record<string, string> = {
    success: 'check-circle',
    warning: 'alert-triangle',
    danger: 'x-circle',
    info: 'info',
};

const classes = computed(() => {
    const map = {
        neutral: 'bg-inset text-muted border-default',
        primary: 'bg-primary-soft text-primary border-primary-soft-border',
        success: 'bg-success-soft text-success border-success-border',
        warning: 'bg-warning-soft text-warning border-warning-border',
        danger: 'bg-danger-soft text-danger border-danger-border',
        info: 'bg-info-soft text-info border-info-border',
    };
    return map[props.variant];
});

const icon = computed(() => (props.noIcon ? '' : (icons[props.variant] ?? '')));
</script>

<template>
    <span
        class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium whitespace-nowrap"
        :class="classes"
    >
        <AppIcon v-if="icon" :name="icon" :size="12" />
        <slot />
    </span>
</template>
