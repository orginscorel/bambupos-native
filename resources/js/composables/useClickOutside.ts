import { onBeforeUnmount, onMounted, type Ref } from 'vue';

/** Eleman dışına tıklanınca callback çağırır (dropdown/menu kapatma). */
export function useClickOutside(target: Ref<HTMLElement | null>, handler: (e: MouseEvent) => void): void {
    const listener = (e: MouseEvent) => {
        const el = target.value;
        if (el && e.target instanceof Node && !el.contains(e.target)) {
            handler(e);
        }
    };
    onMounted(() => document.addEventListener('mousedown', listener));
    onBeforeUnmount(() => document.removeEventListener('mousedown', listener));
}
