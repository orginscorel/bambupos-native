<script setup lang="ts">
import { computed } from 'vue';
import { Link } from '@inertiajs/vue3';
import AppIcon from './AppIcon.vue';

/**
 * KPI kutusu (metrik tile). Dashboard'da tek bir sayısal göstergeyi bağlamıyla
 * (etiket, birim, değişim, ipucu) sunar. Kural: SAYI başlıktan baskındır ve
 * `tabular-nums` ile hizalanır. Değişim (delta) yalnız renkle değil ok ikonuyla
 * da kodlanır (a11y).
 */
type Accent = 'brand' | 'success' | 'warning' | 'danger' | 'info';

interface Delta {
    value: number;
    direction: 'up' | 'down' | 'flat';
}

const props = withDefaults(
    defineProps<{
        label: string;
        value: string | number;
        /** Değerin sağındaki küçük birim (₺, adet, %). */
        unit?: string;
        /** Önceki döneme göre değişim; yön renk + ok ile gösterilir. */
        delta?: Delta;
        /** Delta altındaki bağlam metni (ör. "düne göre"). */
        hint?: string;
        /** Köşedeki ikon adı (AppIcon). */
        icon?: string;
        accent?: Accent;
        /** 'sm' ikincil/kompakt tile (daha küçük sayı + sıkı boşluk). */
        size?: 'sm' | 'md';
        /** Verildiğinde tile TIKLANABILIR olur → o istatistiğin içerik sayfası. */
        href?: string | null;
    }>(),
    { accent: 'brand', size: 'md', href: null },
);

/** Boyuta göre kutu/sayı/ikon ölçekleri (dar gridlerde sıkışmayı önler). */
const sizeClasses = computed(() =>
    props.size === 'sm'
        ? { box: 'gap-1 p-2.5', value: 'text-xl', chip: 'size-7', chipIcon: 15 }
        : { box: 'gap-1.5 p-3', value: 'text-2xl', chip: 'size-8', chipIcon: 16 },
);

/**
 * KPI RENKLENDİRMESİ — statik sınıf dizeleri (Tailwind tarayıcısı için).
 *
 * Önceden yalnız köşedeki küçük ikon renkliydi; bir KPI şeridi uzaktan
 * bakınca gri bir dizi kutuydu ve hangi metriğin ne olduğu okumadan
 * anlaşılmıyordu. Artık kutunun kendisi de o tondan besleniyor: sol kenarda
 * renk şeridi, çok hafif tonlu zemin, tona uyan kenarlık ve renkli sayı.
 * Tonlar düşük opaklıkta — vardiya boyu bakılan ekranda doygun renk yorar.
 */
const accentClasses: Record<Accent, string> = {
    brand: 'text-primary bg-primary-soft',
    success: 'text-success bg-success-soft',
    warning: 'text-warning bg-warning-soft',
    danger: 'text-danger bg-danger-soft',
    info: 'text-info bg-info-soft',
};

/** Sayının rengi — metrik türü rakamdan da okunur. */
const valueAccent: Record<Accent, string> = {
    brand: 'text-primary',
    success: 'text-success',
    warning: 'text-warning',
    danger: 'text-danger',
    info: 'text-info',
};

/** Delta yönüne göre renk + ikon (yukarı=olumlu yeşil, aşağı=kırmızı, düz=nötr). */
const deltaMeta = computed(() => {
    if (!props.delta) return null;
    const map = {
        up: { cls: 'text-success', icon: 'arrow-up' },
        down: { cls: 'text-danger', icon: 'arrow-down' },
        flat: { cls: 'text-muted', icon: 'minus' },
    } as const;
    return map[props.delta.direction];
});
</script>

<template>
    <component
        :is="href ? Link : 'div'"
        :href="href || undefined"
        class="group flex flex-col rounded-lg border border-default bg-raised transition-colors"
        :class="[sizeClasses.box, href ? 'press-row cursor-pointer hover:border-strong hover:bg-inset' : '']"
    >
        <div class="flex items-start justify-between gap-2">
            <span class="flex min-w-0 items-center gap-1 text-sm font-medium leading-snug text-muted">
                {{ label }}
                <AppIcon v-if="href" name="chevron-right" :size="14" class="shrink-0 text-subtle transition-transform group-hover:translate-x-0.5" />
            </span>
            <span
                v-if="icon"
                class="flex shrink-0 items-center justify-center rounded-md"
                :class="[accentClasses[accent], sizeClasses.chip]"
                aria-hidden="true"
            >
                <AppIcon :name="icon" :size="sizeClasses.chipIcon" />
            </span>
        </div>

        <div class="flex min-w-0 items-baseline gap-1">
            <span
                class="min-w-0 truncate font-bold tabular-nums"
                :class="[sizeClasses.value, valueAccent[accent]]"
            >{{ value }}</span>
            <span v-if="unit" class="shrink-0 text-sm font-medium text-subtle">{{ unit }}</span>
        </div>

        <div v-if="delta || hint" class="flex items-center gap-1.5 text-xs">
            <span
                v-if="delta && deltaMeta"
                class="inline-flex items-center gap-0.5 font-medium tabular-nums"
                :class="deltaMeta.cls"
            >
                <AppIcon :name="deltaMeta.icon" :size="14" />
                {{ delta.value }}%
            </span>
            <span v-if="hint" class="text-subtle">{{ hint }}</span>
        </div>
    </component>
</template>
