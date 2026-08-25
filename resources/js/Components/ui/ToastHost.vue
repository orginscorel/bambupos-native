<script setup lang="ts">
import { router } from '@inertiajs/vue3';
import { useToast, type ToastVariant, type Toast } from '@/composables/useToast';
import AppIcon from './AppIcon.vue';

const { toasts, dismiss } = useToast();

const icons: Record<ToastVariant, string> = {
    success: 'check-circle',
    warning: 'alert-triangle',
    danger: 'x-circle',
    info: 'info',
};

/** Tıklanabilir toast: reload → sayfayı tam yenile; url → ilgili sayfaya git. */
function isClickable(t: Toast): boolean {
    return t.reload === true || !!t.url;
}

/** Tıklanınca: sürüm toast'ı → tam yenile; url'li toast → ilgili sayfaya git + kapat. */
function activate(t: Toast): void {
    if (t.reload) {
        window.location.reload();
        return;
    }
    if (!t.url) return;
    dismiss(t.id);
    try {
        // Aynı origin panel yolu → Inertia; dış/farklı yol → tam gezinme.
        if (t.url.startsWith('/')) router.visit(t.url);
        else window.location.href = t.url;
    } catch {
        window.location.href = t.url;
    }
}

const accent: Record<ToastVariant, string> = {
    success: 'text-success',
    warning: 'text-warning',
    danger: 'text-danger',
    info: 'text-info',
};

const softBg: Record<ToastVariant, string> = {
    success: 'bg-success-soft',
    warning: 'bg-warning-soft',
    danger: 'bg-danger-soft',
    info: 'bg-info-soft',
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
                    class="pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-xl border border-default bg-raised p-3.5 shadow-dropdown"
                    :class="isClickable(t) ? 'cursor-pointer transition-colors hover:bg-inset/50' : ''"
                    @click="isClickable(t) ? activate(t) : undefined"
                >
                    <span
                        class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg"
                        :class="[accent[t.variant], softBg[t.variant]]"
                    >
                        <AppIcon :name="t.icon || icons[t.variant]" :size="18" />
                    </span>
                    <div class="min-w-0 grow">
                        <p class="text-sm font-semibold text-body">{{ t.title }}</p>
                        <p v-if="t.message" class="mt-0.5 text-sm text-muted">{{ t.message }}</p>
                        <p v-if="t.reload" class="mt-1 text-xs font-medium" :class="accent[t.variant]">Yenile →</p>
                        <p v-else-if="t.url" class="mt-1 text-xs font-medium" :class="accent[t.variant]">Görüntüle →</p>
                    </div>
                    <button
                        type="button"
                        class="flex size-7 shrink-0 items-center justify-center rounded-md text-subtle transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                        aria-label="Bildirimi kapat"
                        @click.stop="dismiss(t.id)"
                    >
                        <AppIcon name="x" :size="14" />
                    </button>
                </div>
            </TransitionGroup>
        </div>
    </Teleport>
</template>
