<script setup lang="ts">
import { ref } from 'vue';
import AppIcon from './AppIcon.vue';

/**
 * Açılır/kapanır bölüm (native accordion): başlık solda, sağda chevron; açılınca
 * içerik yumuşak yükseklik animasyonuyla gelir. `grid-rows` [0fr→1fr] tekniğiyle
 * içerik ölçülmeden akıcı geçiş. Tek dosya, bağımsız kullanılır.
 */
const props = withDefaults(
    defineProps<{
        title: string;
        subtitle?: string;
        icon?: string;
        /** Başlangıçta açık mı. */
        open?: boolean;
    }>(),
    { open: false },
);

const isOpen = ref(props.open);
</script>

<template>
    <div class="overflow-hidden rounded-2xl border border-default bg-surface shadow-card">
        <button
            type="button"
            class="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors duration-(--dur-fast) active:bg-inset"
            :aria-expanded="isOpen"
            @click="isOpen = !isOpen"
        >
            <span
                v-if="icon"
                class="flex size-9 shrink-0 items-center justify-center rounded-[10px] bg-inset text-muted"
            >
                <AppIcon :name="icon" :size="19" />
            </span>
            <span class="flex min-w-0 grow flex-col">
                <span class="truncate text-[15px] font-semibold text-body">{{ title }}</span>
                <span v-if="subtitle" class="truncate text-[13px] text-muted">{{ subtitle }}</span>
            </span>
            <AppIcon
                name="chevron-down"
                :size="18"
                class="shrink-0 text-subtle transition-transform duration-(--dur-normal)"
                :class="isOpen ? 'rotate-180' : ''"
            />
        </button>

        <div
            class="grid transition-[grid-template-rows] duration-(--dur-normal) ease-out"
            :class="isOpen ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'"
        >
            <div class="min-h-0 overflow-hidden">
                <div class="border-t border-default px-4 py-3">
                    <slot />
                </div>
            </div>
        </div>
    </div>
</template>
