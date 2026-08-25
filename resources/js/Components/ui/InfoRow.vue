<script setup lang="ts">
/**
 * Salt-okunur anahtar/değer satırı (detay ekranları): solda etiket, sağda değer.
 * `MobileListGroup` içinde hairline ayraçla dizilir. Değer slot ile rozet/link de
 * olabilir. İki-satırlı (dikey) düzen için `stacked`.
 */
withDefaults(
    defineProps<{
        label: string;
        value?: string | number;
        /** Değeri vurgulu göster. */
        strong?: boolean;
        /** Etiket üstte, değer altta (uzun değerler için). */
        stacked?: boolean;
    }>(),
    { strong: false, stacked: false },
);
</script>

<template>
    <div
        class="flex px-4 py-3"
        :class="stacked ? 'flex-col gap-0.5' : 'items-center justify-between gap-4'"
    >
        <span class="shrink-0 text-[14px] text-muted">{{ label }}</span>
        <span
            class="min-w-0 text-[14px]"
            :class="[
                stacked ? 'text-left' : 'text-right',
                strong ? 'font-semibold text-body tabular-nums' : 'text-body',
            ]"
        >
            <slot>{{ value }}</slot>
        </span>
    </div>
</template>
