import { reactive, readonly } from 'vue';

export type ToastVariant = 'success' | 'warning' | 'danger' | 'info';

export interface Toast {
    id: number;
    variant: ToastVariant;
    title: string;
    message?: string;
    duration: number;
}

let nextId = 1;
const toasts = reactive<Toast[]>([]);

function dismiss(id: number): void {
    const i = toasts.findIndex((t) => t.id === id);
    if (i !== -1) toasts.splice(i, 1);
}

function push(input: { variant?: ToastVariant; title: string; message?: string; duration?: number }): number {
    const toast: Toast = {
        id: nextId++,
        variant: input.variant ?? 'info',
        title: input.title,
        message: input.message,
        duration: input.duration ?? 4500,
    };
    toasts.push(toast);
    if (toast.duration > 0) {
        window.setTimeout(() => dismiss(toast.id), toast.duration);
    }
    return toast.id;
}

/** Uygulama-geneli toast durumu; <ToastHost /> panel kabuğunda bir kez yer alır. */
export function useToast() {
    return {
        toasts: readonly(toasts) as readonly Toast[],
        toast: push,
        dismiss,
        success: (title: string, message?: string) => push({ variant: 'success', title, message }),
        warning: (title: string, message?: string) => push({ variant: 'warning', title, message }),
        danger: (title: string, message?: string) => push({ variant: 'danger', title, message }),
        info: (title: string, message?: string) => push({ variant: 'info', title, message }),
    };
}
