<script setup lang="ts">
import { Link } from '@inertiajs/vue3';
import AppIcon from './AppIcon.vue';

/**
 * Floating action button (ana operasyon — ör. QR / hızlı sipariş). Native his:
 * dolu marka rengi, yumuşak yükselti gölgesi (shadow-fab), basınca hafif scale.
 * Alt sekme çubuğunun ortasında "notch" olarak da kullanılabilir (`notch`).
 * href verilirse Inertia Link, yoksa buton (@click).
 */
withDefaults(
    defineProps<{
        icon?: string;
        label: string;
        href?: string;
        /** Tab bar ortasına gömülü (biraz yukarı taşan) yerleşim. */
        notch?: boolean;
    }>(),
    { icon: 'qr-code', notch: false },
);
</script>

<template>
    <component
        :is="href ? Link : 'button'"
        :href="href || undefined"
        :type="href ? undefined : 'button'"
        :aria-label="label"
        class="flex items-center justify-center rounded-full bg-primary text-on-primary shadow-fab
               transition-transform duration-(--dur-fast) active:scale-90 hover:bg-primary-hover
               ring-4 ring-surface"
        :class="notch ? '-mt-6' : ''"
        :style="{ width: 'var(--size-fab)', height: 'var(--size-fab)' }"
    >
        <AppIcon :name="icon" :size="24" />
    </component>
</template>
