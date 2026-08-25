<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from './AppIcon.vue';

/**
 * Durum rozeti (domain). Sipariş / masa / stok gibi ANLAM taşıyan durumları
 * gösterir. Kural: durum yalnız renkle değil, HER ZAMAN ikon + metin ile de
 * anlatılır (renk körlüğü / a11y). Dot varyantı yalnız görsel yoğunluğu
 * azaltmak içindir; metin etiketi zaten anlamı taşıdığından erişilebilirdir.
 */
type PillKind =
    | 'order-new'
    | 'order-preparing'
    | 'order-ready'
    | 'order-served'
    | 'table-empty'
    | 'table-occupied'
    | 'table-delayed'
    | 'stock-critical'
    | 'success'
    | 'warning'
    | 'danger'
    | 'info';

const props = withDefaults(
    defineProps<{
        kind: PillKind;
        /** Görünen metin (zorunlu — durum yalnız renkle anlatılmaz). */
        label: string;
        /** Varsayılan ikonu ezmek için AppIcon adı. */
        icon?: string;
        size?: 'sm' | 'md';
        /** İkon yerine küçük renk noktası göster (metin yine görünür). */
        dot?: boolean;
    }>(),
    { size: 'md', dot: false },
);

/** Tam sınıf dizeleri statik yazılır ki Tailwind tarayıcısı üretebilsin. */
const kindClasses: Record<PillKind, string> = {
    'order-new': 'text-order-new bg-order-new/10 border-order-new/25',
    'order-preparing': 'text-order-preparing bg-order-preparing/10 border-order-preparing/25',
    'order-ready': 'text-order-ready bg-order-ready/10 border-order-ready/25',
    'order-served': 'text-order-served bg-order-served/10 border-order-served/25',
    'table-empty': 'text-table-empty bg-table-empty/10 border-table-empty/25',
    'table-occupied': 'text-table-occupied bg-table-occupied/10 border-table-occupied/25',
    'table-delayed': 'text-table-delayed bg-table-delayed/10 border-table-delayed/25',
    'stock-critical': 'text-stock-critical bg-stock-critical/10 border-stock-critical/25',
    success: 'text-success bg-success-soft border-success-border',
    warning: 'text-warning bg-warning-soft border-warning-border',
    danger: 'text-danger bg-danger-soft border-danger-border',
    info: 'text-info bg-info-soft border-info-border',
};

/** Her durum için varsayılan ikon (renk-dışı kodlama). */
const defaultIcons: Record<PillKind, string> = {
    'order-new': 'bell',
    'order-preparing': 'clock',
    'order-ready': 'check-circle',
    'order-served': 'check',
    'table-empty': 'check-circle',
    'table-occupied': 'users',
    'table-delayed': 'alert-triangle',
    'stock-critical': 'alert-triangle',
    success: 'check-circle',
    warning: 'alert-triangle',
    danger: 'x-circle',
    info: 'info',
};

const sizeClasses = computed(() =>
    props.size === 'sm' ? 'h-6 gap-1 px-2 text-xs' : 'h-7 gap-1.5 px-2.5 text-sm',
);

const iconSize = computed(() => (props.size === 'sm' ? 12 : 14));
const iconName = computed(() => props.icon ?? defaultIcons[props.kind]);
</script>

<template>
    <span
        class="inline-flex items-center rounded-full border font-medium whitespace-nowrap"
        :class="[kindClasses[kind], sizeClasses]"
    >
        <span
            v-if="dot"
            class="size-2 shrink-0 rounded-full bg-current"
            aria-hidden="true"
        />
        <AppIcon v-else :name="iconName" :size="iconSize" />
        {{ label }}
    </span>
</template>
