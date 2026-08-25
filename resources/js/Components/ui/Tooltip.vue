<script setup lang="ts">
import { computed, ref, onBeforeUnmount } from 'vue';
import { useId } from '@/composables/useId';

/**
 * İpucu (tooltip): tetikleyici öğe üzerine gelince/odaklanınca kısa açıklama
 * gösterir. Klavye erişilebilir (focus'ta görünür), role="tooltip" +
 * aria-describedby ile bağlanır, küçük gecikmeyle açılır. Popover gölgesi.
 * NOT: İçerik yalnız ipucudur; kritik bilgi tooltip'e SAKLANMAMALI (dokunmatik
 * cihazlarda hover yoktur).
 */
const props = withDefaults(
    defineProps<{
        content: string;
        placement?: 'top' | 'bottom' | 'left' | 'right';
        /** Göstermeden önce beklenecek süre (ms). */
        delay?: number;
    }>(),
    { placement: 'top', delay: 200 },
);

const id = useId('tooltip');
const visible = ref(false);
let timer: number | undefined;

function show(): void {
    window.clearTimeout(timer);
    timer = window.setTimeout(() => (visible.value = true), props.delay);
}

function hide(): void {
    window.clearTimeout(timer);
    visible.value = false;
}

onBeforeUnmount(() => window.clearTimeout(timer));

/** Yerleşim sınıfları — tetikleyiciye göre konum + küçük boşluk. */
const placementClass = computed(
    () =>
        ({
            top: 'bottom-full left-1/2 mb-2 -translate-x-1/2',
            bottom: 'top-full left-1/2 mt-2 -translate-x-1/2',
            left: 'right-full top-1/2 mr-2 -translate-y-1/2',
            right: 'left-full top-1/2 ml-2 -translate-y-1/2',
        })[props.placement],
);
</script>

<template>
    <span
        class="relative inline-flex"
        @mouseenter="show"
        @mouseleave="hide"
        @focusin="show"
        @focusout="hide"
    >
        <!-- Tetikleyici: slot prop ile aria-describedby bağlanır (ipucuna işaret) -->
        <slot :ariaDescribedby="visible ? id : undefined" />

        <Transition
            enter-active-class="transition duration-(--dur-fast)"
            enter-from-class="opacity-0 scale-95"
            leave-active-class="transition duration-(--dur-fast)"
            leave-to-class="opacity-0 scale-95"
        >
            <span
                v-if="visible"
                :id="id"
                role="tooltip"
                class="pointer-events-none absolute z-(--z-dropdown) w-max max-w-56 rounded-md border border-default bg-raised px-2.5 py-1.5 text-xs font-medium text-body shadow-dropdown"
                :class="placementClass"
            >
                {{ content }}
            </span>
        </Transition>
    </span>
</template>
