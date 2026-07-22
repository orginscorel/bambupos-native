import { nextTick, onBeforeUnmount, watch, type Ref } from 'vue';

const FOCUSABLE =
    'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

/**
 * Modal/drawer için odak tuzağı: açılınca ilk odaklanabilir öğeye gider,
 * Tab döngüsü kap içinde kalır, kapanınca odak tetikleyiciye döner.
 */
export function useFocusTrap(container: Ref<HTMLElement | null>, active: Ref<boolean>): void {
    let previouslyFocused: HTMLElement | null = null;

    const keyHandler = (e: KeyboardEvent) => {
        if (e.key !== 'Tab' || !container.value) return;
        const nodes = Array.from(container.value.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
            (n) => n.offsetParent !== null,
        );
        if (nodes.length === 0) return;
        const first = nodes[0];
        const last = nodes[nodes.length - 1];
        if (e.shiftKey && document.activeElement === first) {
            e.preventDefault();
            last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
            e.preventDefault();
            first.focus();
        }
    };

    watch(active, async (isActive) => {
        if (isActive) {
            previouslyFocused = document.activeElement as HTMLElement | null;
            document.addEventListener('keydown', keyHandler);
            await nextTick();
            const el = container.value?.querySelector<HTMLElement>('[data-autofocus]') ??
                container.value?.querySelector<HTMLElement>(FOCUSABLE);
            (el ?? container.value)?.focus();
        } else {
            document.removeEventListener('keydown', keyHandler);
            previouslyFocused?.focus();
            previouslyFocused = null;
        }
    });

    onBeforeUnmount(() => document.removeEventListener('keydown', keyHandler));
}
