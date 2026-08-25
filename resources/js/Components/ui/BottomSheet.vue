<script setup lang="ts">
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useFocusTrap } from '@/composables/useFocusTrap';
import { useId } from '@/composables/useId';
import AppIcon from './AppIcon.vue';

/**
 * Alt sayfa (bottom sheet): mobil/tablette bağlam işlemleri için alttan yukarı
 * kayarak açılır. BaseModal deseninin alttan-yerleşik kardeşi. Aşağı-swipe,
 * backdrop tıklaması veya Esc ile kapanır. safe-area-inset-bottom + focus-trap.
 * Kapanma eşiğine gelmeyen sürükleme geri yaslanır.
 */
const props = withDefaults(
    defineProps<{
        modelValue: boolean;
        title?: string;
        /** Backdrop/Esc/sürükleme ile kapanabilsin mi. */
        dismissable?: boolean;
    }>(),
    { title: '', dismissable: true },
);

const emit = defineEmits<{ 'update:modelValue': [value: boolean] }>();

const panel = ref<HTMLElement | null>(null);
const titleId = useId('sheet-title');
const isOpen = computed(() => props.modelValue);

useFocusTrap(panel, isOpen);

function close(): void {
    if (props.dismissable) emit('update:modelValue', false);
}

function onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') close();
}

watch(isOpen, (v) => {
    document.body.style.overflow = v ? 'hidden' : '';
    if (v) document.addEventListener('keydown', onKeydown);
    else document.removeEventListener('keydown', onKeydown);
});

onBeforeUnmount(() => {
    document.body.style.overflow = '';
    document.removeEventListener('keydown', onKeydown);
});

/* --- Aşağı-swipe ile kapatma (pointer) --- */
const dragY = ref(0);
const dragging = ref(false);
let startY = 0;
const CLOSE_THRESHOLD = 96; // px — bu kadar aşağı çekilince kapan

function onPointerDown(e: PointerEvent): void {
    if (!props.dismissable) return;
    dragging.value = true;
    startY = e.clientY;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
}

function onPointerMove(e: PointerEvent): void {
    if (!dragging.value) return;
    // yalnız aşağı yönde sürüklemeye izin ver
    dragY.value = Math.max(0, e.clientY - startY);
}

function onPointerUp(): void {
    if (!dragging.value) return;
    dragging.value = false;
    if (dragY.value > CLOSE_THRESHOLD) close();
    dragY.value = 0;
}
</script>

<template>
    <Teleport to="body">
        <!-- Backdrop: bağımsız solma geçişi -->
        <Transition
            enter-active-class="transition-opacity duration-(--dur-normal)"
            enter-from-class="opacity-0"
            leave-active-class="transition-opacity duration-(--dur-fast)"
            leave-to-class="opacity-0"
        >
            <div
                v-if="modelValue"
                class="fixed inset-0 z-(--z-modal) bg-overlay"
                @mousedown="close"
            />
        </Transition>

        <!-- Panel: bağımsız yukarı-kayma geçişi (açılışta da kapanışta da oynar) -->
        <Transition
            enter-active-class="transition-transform duration-(--dur-normal) ease-out"
            enter-from-class="translate-y-full"
            leave-active-class="transition-transform duration-(--dur-fast) ease-in"
            leave-to-class="translate-y-full"
        >
            <div
                v-if="modelValue"
                class="fixed inset-x-0 bottom-0 z-(--z-modal) flex justify-center"
                @mousedown.self="close"
            >
                <div
                    ref="panel"
                    role="dialog"
                    aria-modal="true"
                    :aria-labelledby="title ? titleId : undefined"
                    tabindex="-1"
                    class="flex max-h-[90dvh] w-full flex-col rounded-t-xl bg-raised shadow-modal outline-none sm:max-w-md"
                    :style="{
                        transform: dragY ? `translateY(${dragY}px)` : undefined,
                        transition: dragging ? 'none' : undefined,
                        paddingBottom: 'env(safe-area-inset-bottom)',
                    }"
                >
                    <!-- Sürükleme tutamacı + swipe alanı -->
                    <div
                        class="flex shrink-0 cursor-grab touch-none flex-col items-center pt-2 pb-1 active:cursor-grabbing"
                        @pointerdown="onPointerDown"
                        @pointermove="onPointerMove"
                        @pointerup="onPointerUp"
                        @pointercancel="onPointerUp"
                    >
                        <span class="h-1.5 w-10 rounded-full bg-strong" aria-hidden="true" />
                    </div>

                    <header
                        v-if="title || dismissable"
                        class="flex items-center justify-between gap-3 px-5 pb-3"
                    >
                        <h2 v-if="title" :id="titleId" class="text-base font-semibold text-body">{{ title }}</h2>
                        <span v-else />
                        <button
                            v-if="dismissable"
                            type="button"
                            class="flex size-9 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                            aria-label="Kapat"
                            @click="close"
                        >
                            <AppIcon name="x" :size="18" />
                        </button>
                    </header>

                    <div class="grow overflow-y-auto px-5 pb-5" :class="title || dismissable ? '' : 'pt-1'">
                        <slot />
                    </div>

                    <footer v-if="$slots.footer" class="flex justify-end gap-2 border-t border-default px-5 py-4">
                        <slot name="footer" />
                    </footer>
                </div>
            </div>
        </Transition>
    </Teleport>
</template>
