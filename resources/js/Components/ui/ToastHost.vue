<script setup lang="ts">
import { useToast, type ToastVariant } from '@/composables/useToast';
import AppIcon from './AppIcon.vue';

const { toasts, dismiss } = useToast();

const icons: Record<ToastVariant, string> = {
    success: 'check-circle',
    warning: 'alert-triangle',
    danger: 'x-circle',
    info: 'info',
};

const accent: Record<ToastVariant, string> = {
    success: 'text-success',
    warning: 'text-warning',
    danger: 'text-danger',
    info: 'text-info',
};
</script>

<template>
    <Teleport to="body">
        <!-- aria-live: yeni toast'lar ekran okuyucuya duyurulur -->
        <div
            class="pointer-events-none fixed inset-x-0 bottom-0 z-(--z-toast) flex flex-col items-center gap-2 p-4 sm:items-end"
            aria-live="polite"
            aria-atomic="false"
        >
            <TransitionGroup
                enter-active-class="transition duration-(--dur-normal) ease-out"
                enter-from-class="translate-y-2 opacity-0"
                leave-active-class="transition duration-(--dur-fast) ease-in"
                leave-to-class="opacity-0"
            >
                <div
                    v-for="t in toasts"
                    :key="t.id"
                    role="status"
                    class="pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-lg border border-default bg-raised p-3.5 shadow-dropdown"
                >
                    <span :class="accent[t.variant]" class="mt-0.5">
                        <AppIcon :name="icons[t.variant]" :size="18" />
                    </span>
                    <div class="min-w-0 grow">
                        <p class="text-sm font-semibold text-body">{{ t.title }}</p>
                        <p v-if="t.message" class="mt-0.5 text-sm text-muted">{{ t.message }}</p>
                    </div>
                    <button
                        type="button"
                        class="flex size-7 shrink-0 items-center justify-center rounded-md text-subtle transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                        aria-label="Bildirimi kapat"
                        @click="dismiss(t.id)"
                    >
                        <AppIcon name="x" :size="14" />
                    </button>
                </div>
            </TransitionGroup>
        </div>
    </Teleport>
</template>
