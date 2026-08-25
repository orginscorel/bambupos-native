<script setup lang="ts">
/**
 * Ürün görseli tam-ekran büyüteç (lightbox). TEK paylaşılan durum (useLightbox).
 * Overlay body'ye teleport edilir → hangi ekrandan açılırsa açılsın üstte gelir,
 * sayfa akışını bozmaz (layout shift YOK). Büyüt/küçült: buton + fare tekeri +
 * çift dokunma + iki parmak pinch; büyütünce sürükle-kaydır. Tüm cihazlara uyumlu.
 */
import { computed, ref, watch } from 'vue';
import { useLightbox } from '@/composables/useLightbox';
import AppIcon from './AppIcon.vue';

const { state, close } = useLightbox();

const MIN = 1;
const MAX = 4;
const scale = ref(1);
const tx = ref(0);
const ty = ref(0);

function reset(): void {
    scale.value = 1;
    tx.value = 0;
    ty.value = 0;
}

// Görsel/aç-kapa değişince sıfırla + body scroll kilidi.
watch(
    () => [state.open, state.src] as const,
    () => {
        reset();
        if (typeof document !== 'undefined') {
            document.body.style.overflow = state.open ? 'hidden' : '';
        }
    },
);

function clampScale(s: number): number {
    return Math.min(MAX, Math.max(MIN, s));
}

function zoomBy(delta: number): void {
    scale.value = clampScale(scale.value + delta);
    if (scale.value === 1) {
        tx.value = 0;
        ty.value = 0;
    }
}

function onWheel(e: WheelEvent): void {
    e.preventDefault();
    zoomBy(e.deltaY < 0 ? 0.35 : -0.35);
}

/* Çift dokunma/çift tık: 1 ↔ 2.5 aç/kapa */
function toggleZoom(): void {
    if (scale.value > 1) {
        reset();
    } else {
        scale.value = 2.5;
    }
}

/* Tek parmak/fare sürükleme: büyütülmüşken kaydır (pan) */
const dragging = ref(false);
let startX = 0;
let startY = 0;
let baseTx = 0;
let baseTy = 0;

function onPointerDown(e: PointerEvent): void {
    if (scale.value <= 1) return;
    dragging.value = true;
    startX = e.clientX;
    startY = e.clientY;
    baseTx = tx.value;
    baseTy = ty.value;
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
}
function onPointerMove(e: PointerEvent): void {
    if (!dragging.value) return;
    tx.value = baseTx + (e.clientX - startX);
    ty.value = baseTy + (e.clientY - startY);
}
function onPointerUp(): void {
    dragging.value = false;
}

/* İki parmak pinch (dokunmatik) */
let pinchStartDist = 0;
let pinchStartScale = 1;
function dist(t: TouchList): number {
    const dx = t[0].clientX - t[1].clientX;
    const dy = t[0].clientY - t[1].clientY;
    return Math.hypot(dx, dy);
}
function onTouchStart(e: TouchEvent): void {
    if (e.touches.length === 2) {
        pinchStartDist = dist(e.touches);
        pinchStartScale = scale.value;
    }
}
function onTouchMove(e: TouchEvent): void {
    if (e.touches.length === 2 && pinchStartDist > 0) {
        e.preventDefault();
        scale.value = clampScale(pinchStartScale * (dist(e.touches) / pinchStartDist));
        if (scale.value === 1) {
            tx.value = 0;
            ty.value = 0;
        }
    }
}
function onTouchEnd(e: TouchEvent): void {
    if (e.touches.length < 2) pinchStartDist = 0;
}

const imgStyle = computed(() => ({
    transform: `translate(${tx.value}px, ${ty.value}px) scale(${scale.value})`,
    cursor: scale.value > 1 ? (dragging.value ? 'grabbing' : 'grab') : 'zoom-in',
}));

/* Esc ile kapat */
function onKey(e: KeyboardEvent): void {
    if (e.key === 'Escape') close();
    else if (e.key === '+' || e.key === '=') zoomBy(0.35);
    else if (e.key === '-') zoomBy(-0.35);
}
watch(
    () => state.open,
    (open) => {
        if (typeof window === 'undefined') return;
        if (open) window.addEventListener('keydown', onKey);
        else window.removeEventListener('keydown', onKey);
    },
);
</script>

<template>
    <Teleport to="body">
        <Transition name="lb-fade">
            <div
                v-if="state.open"
                class="fixed inset-0 z-[200] flex flex-col bg-black/85 backdrop-blur-sm"
                style="padding: max(env(safe-area-inset-top), 12px) 12px max(env(safe-area-inset-bottom), 12px)"
                role="dialog"
                aria-modal="true"
                aria-label="Ürün görseli"
                @click.self="close"
            >
                <!-- Üst bar: kapat -->
                <div class="flex shrink-0 items-center justify-between text-white">
                    <p class="truncate px-1 text-sm font-medium text-white/80">{{ state.alt }}</p>
                    <button
                        type="button"
                        class="flex size-11 items-center justify-center rounded-full bg-white/10 transition-colors hover:bg-white/20 active:scale-95"
                        aria-label="Kapat"
                        @click="close"
                    >
                        <AppIcon name="x" :size="22" />
                    </button>
                </div>

                <!-- Görsel sahnesi -->
                <div
                    class="flex min-h-0 flex-1 touch-none select-none items-center justify-center overflow-hidden"
                    @click.self="close"
                    @wheel="onWheel"
                    @dblclick="toggleZoom"
                    @pointerdown="onPointerDown"
                    @pointermove="onPointerMove"
                    @pointerup="onPointerUp"
                    @pointercancel="onPointerUp"
                    @touchstart.passive="onTouchStart"
                    @touchmove="onTouchMove"
                    @touchend="onTouchEnd"
                >
                    <img
                        :src="state.src"
                        :alt="state.alt"
                        draggable="false"
                        class="max-h-full max-w-full rounded-lg object-contain shadow-2xl transition-transform"
                        :class="dragging ? '!transition-none' : ''"
                        :style="imgStyle"
                    />
                </div>

                <!-- Alt kontrol: büyüt / küçült / sıfırla -->
                <div class="flex shrink-0 items-center justify-center gap-2 pt-2">
                    <button
                        type="button"
                        class="flex size-12 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20 active:scale-95 disabled:opacity-40"
                        aria-label="Küçült"
                        :disabled="scale <= 1"
                        @click="zoomBy(-0.5)"
                    >
                        <AppIcon name="minus" :size="22" />
                    </button>
                    <button
                        type="button"
                        class="rounded-full bg-white/10 px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-white/20 active:scale-95"
                        @click="reset"
                    >
                        {{ Math.round(scale * 100) }}%
                    </button>
                    <button
                        type="button"
                        class="flex size-12 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20 active:scale-95 disabled:opacity-40"
                        aria-label="Büyüt"
                        :disabled="scale >= 4"
                        @click="zoomBy(0.5)"
                    >
                        <AppIcon name="plus" :size="22" />
                    </button>
                </div>
            </div>
        </Transition>
    </Teleport>
</template>

<style scoped>
.lb-fade-enter-active,
.lb-fade-leave-active {
    transition: opacity 180ms ease;
}
.lb-fade-enter-from,
.lb-fade-leave-to {
    opacity: 0;
}
@media (prefers-reduced-motion: reduce) {
    .lb-fade-enter-active,
    .lb-fade-leave-active {
        transition: none;
    }
}
</style>
