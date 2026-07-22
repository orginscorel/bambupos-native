<script setup lang="ts">
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useFocusTrap } from '@/composables/useFocusTrap';
import { useId } from '@/composables/useId';
import AppIcon from './AppIcon.vue';

const props = withDefaults(
    defineProps<{
        open: boolean;
        title: string;
        size?: 'sm' | 'md' | 'lg';
        /** Overlay tıklaması ve Esc ile kapanabilsin mi */
        dismissable?: boolean;
    }>(),
    { size: 'md', dismissable: true },
);

const emit = defineEmits<{ close: [] }>();

const panel = ref<HTMLElement | null>(null);
const titleId = useId('modal-title');
const isOpen = computed(() => props.open);

useFocusTrap(panel, isOpen);

function close(): void {
    if (props.dismissable) emit('close');
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

const sizeClass = computed(
    () => ({ sm: 'max-w-sm', md: 'max-w-lg', lg: 'max-w-2xl' })[props.size],
);
</script>

<template>
    <Teleport to="body">
        <Transition
            enter-active-class="transition-opacity duration-(--dur-normal)"
            enter-from-class="opacity-0"
            leave-active-class="transition-opacity duration-(--dur-fast)"
            leave-to-class="opacity-0"
        >
            <div
                v-if="open"
                class="fixed inset-0 z-(--z-modal) flex items-end justify-center bg-overlay p-0 sm:items-center sm:p-6"
                @mousedown.self="close"
            >
                <div
                    ref="panel"
                    role="dialog"
                    aria-modal="true"
                    :aria-labelledby="titleId"
                    tabindex="-1"
                    class="flex max-h-[90dvh] w-full flex-col rounded-t-xl bg-raised shadow-modal outline-none sm:rounded-xl"
                    :class="sizeClass"
                >
                    <header class="flex items-center justify-between gap-3 border-b border-default px-5 py-4">
                        <h2 :id="titleId" class="text-base font-semibold text-body">{{ title }}</h2>
                        <button
                            v-if="dismissable"
                            type="button"
                            class="flex size-9 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                            aria-label="Kapat"
                            @click="emit('close')"
                        >
                            <AppIcon name="x" :size="18" />
                        </button>
                    </header>
                    <div class="grow overflow-y-auto px-5 py-4">
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
