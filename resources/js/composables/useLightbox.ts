import { reactive } from 'vue';

/**
 * Ürün görseli tam-ekran büyütme (lightbox) — TEK paylaşılan durum (singleton).
 * Herhangi bir ekran `open(src, alt)` çağırır; `<ImageLightbox/>` (teleport→body)
 * overlay'i gösterir. Overlay katmandır → sayfa akışını bozmaz, layout shift yok.
 */
const state = reactive<{ open: boolean; src: string; alt: string }>({
    open: false,
    src: '',
    alt: '',
});

export function useLightbox() {
    return {
        state,
        open(src: string | null | undefined, alt = ''): void {
            if (!src) return;
            state.src = src;
            state.alt = alt;
            state.open = true;
        },
        close(): void {
            state.open = false;
            state.src = '';
            state.alt = '';
        },
    };
}
