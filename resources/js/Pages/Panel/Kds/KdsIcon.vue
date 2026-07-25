<script setup lang="ts">
import { computed } from 'vue';

/**
 * KDS'ye özgü birkaç ek ikon (Components/ui/AppIcon dokunulmaz olduğundan
 * modülün kendi küçük seti). Stroke tabanlı, currentColor — AppIcon ile
 * birebir aynı çizim dili. Yalnız KDS ekranlarında kullanılan adlar tutulur.
 */
const paths: Record<string, string> = {
    tray: '<path d="M4 11h16a1 1 0 0 1 1 1v.5a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 12.5V12a1 1 0 0 1 1-1Z"/><path d="M12 4a7 7 0 0 1 7 7H5a7 7 0 0 1 7-7Z"/><path d="M12 4V2"/><path d="M5 19h14"/>',
    undo: '<path d="M3 7v6h6"/><path d="M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/>',
    swap: '<path d="m16 3 4 4-4 4"/><path d="M20 7H4"/><path d="m8 21-4-4 4-4"/><path d="M4 17h16"/>',
    'volume-on': '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>',
    'volume-off': '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><line x1="22" x2="16" y1="9" y2="15"/><line x1="16" x2="22" y1="9" y2="15"/>',
    expand: '<path d="M8 3H5a2 2 0 0 0-2 2v3"/><path d="M21 8V5a2 2 0 0 0-2-2h-3"/><path d="M3 16v3a2 2 0 0 0 2 2h3"/><path d="M16 21h3a2 2 0 0 0 2-2v-3"/>',
    compress: '<path d="M8 3v3a2 2 0 0 1-2 2H3"/><path d="M21 8h-3a2 2 0 0 1-2-2V3"/><path d="M3 16h3a2 2 0 0 1 2 2v3"/><path d="M16 21v-3a2 2 0 0 1 2-2h3"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>',
    moon: '<path d="M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.003.803.401Z"/>',
};

const props = withDefaults(
    defineProps<{ name: string; size?: number; label?: string }>(),
    { size: 20, label: '' },
);

const path = computed(() => paths[props.name] ?? '');
</script>

<template>
    <svg
        :width="size"
        :height="size"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        :aria-hidden="label ? undefined : 'true'"
        :aria-label="label || undefined"
        :role="label ? 'img' : undefined"
        v-html="path"
    />
</template>
