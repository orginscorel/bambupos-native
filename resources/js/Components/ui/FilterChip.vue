<script setup lang="ts">
import AppIcon from './AppIcon.vue';

/**
 * Yatay kaydırılabilir filtre çipi (native). Aktifken marka rengi (dolu),
 * pasifken açık outline. İkon + etiket + opsiyonel sayaç. Ebeveyn
 * `overflow-x-auto` bir şeritte dizer.
 */
withDefaults(
    defineProps<{
        label: string;
        active?: boolean;
        icon?: string;
        /** Sağda küçük sayaç (ör. sonuç adedi). */
        count?: number | string;
    }>(),
    { active: false },
);
</script>

<template>
    <button
        type="button"
        class="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full border px-3.5 text-[13px] font-medium whitespace-nowrap transition-colors duration-(--dur-fast) active:scale-[0.97]"
        :class="
            active
                ? 'border-primary bg-primary text-on-primary'
                : 'border-default bg-surface text-muted hover:bg-inset'
        "
        :aria-pressed="active"
    >
        <AppIcon v-if="icon" :name="icon" :size="15" />
        <span>{{ label }}</span>
        <span
            v-if="count !== undefined && count !== ''"
            class="tabular-nums"
            :class="active ? 'text-on-primary/80' : 'text-subtle'"
        >
            {{ count }}
        </span>
    </button>
</template>
