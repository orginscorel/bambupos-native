<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue';
import { useId } from '@/composables/useId';

/**
 * Açılır menü. Tetikleyici #trigger slot'undan (open, toggle, ariaAttrs alır);
 * içerik varsayılan slot'ta `role="menuitem"` öğeleriyle verilir.
 * Klavye: Enter/Space/ArrowDown açar, oklar gezdirir, Esc kapatıp odağı döndürür.
 *
 * Konumlandırma — menü `<Teleport to="body">` ile gövdeye taşınır ve tetikleyicinin
 * `getBoundingClientRect()`'inden `position:fixed` ile yerleştirilir. Böylece
 * `overflow-x-auto`/`overflow-hidden` bir kapsayıcı içinde (ör. personel tablosu)
 * menü KIRPILMAZ — eski `position:absolute` kapsayıcıya hapsoluyordu, z-index çözmez.
 * Konum scroll/resize'da güncellenir; dış-tık + Esc ile kapanır, aria korunur.
 */
const props = withDefaults(
    defineProps<{
        align?: 'left' | 'right';
        menuLabel?: string;
    }>(),
    { align: 'right', menuLabel: 'Menü' },
);

const open = ref(false);
const root = ref<HTMLElement | null>(null);
const triggerWrap = ref<HTMLElement | null>(null);
const menu = ref<HTMLElement | null>(null);
const menuId = useId('dropdown');

/** Teleport edilen menünün fixed konumu (trigger rect'ten türetilir). */
const menuStyle = reactive<Record<string, string>>({ position: 'fixed' });

function updatePosition(): void {
    const wrap = triggerWrap.value;
    if (wrap === null) return;
    // Trigger genelde bir buton; asıl öğenin kutusunu ölç (inline span değil).
    const target = (wrap.firstElementChild as HTMLElement | null) ?? wrap;
    const r = target.getBoundingClientRect();
    const gap = 6; // mt-1.5

    menuStyle.top = `${Math.round(r.bottom + gap)}px`;
    if (props.align === 'right') {
        menuStyle.left = 'auto';
        menuStyle.right = `${Math.round(window.innerWidth - r.right)}px`;
    } else {
        menuStyle.right = 'auto';
        menuStyle.left = `${Math.round(r.left)}px`;
    }
}

function onViewportChange(): void {
    if (open.value) updatePosition();
}

watch(open, (isOpen) => {
    if (isOpen) {
        updatePosition();
        window.addEventListener('scroll', onViewportChange, true);
        window.addEventListener('resize', onViewportChange);
    } else {
        window.removeEventListener('scroll', onViewportChange, true);
        window.removeEventListener('resize', onViewportChange);
    }
});

function items(): HTMLElement[] {
    return Array.from(menu.value?.querySelectorAll<HTMLElement>('[role="menuitem"]:not([aria-disabled="true"])') ?? []);
}

async function openMenu(focusFirst = true): Promise<void> {
    open.value = true;
    await nextTick();
    updatePosition();
    if (focusFirst) items()[0]?.focus();
}

function toggle(): void {
    if (open.value) open.value = false;
    else void openMenu(false);
}

function closeAndRestore(): void {
    open.value = false;
    root.value?.querySelector<HTMLElement>('[aria-haspopup]')?.focus();
}

function onTriggerKeydown(e: KeyboardEvent): void {
    if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        void openMenu();
    }
}

function onMenuKeydown(e: KeyboardEvent): void {
    const list = items();
    const i = list.indexOf(document.activeElement as HTMLElement);
    if (e.key === 'ArrowDown') {
        e.preventDefault();
        list[(i + 1) % list.length]?.focus();
    } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        list[(i - 1 + list.length) % list.length]?.focus();
    } else if (e.key === 'Escape') {
        e.preventDefault();
        closeAndRestore();
    } else if (e.key === 'Tab') {
        open.value = false;
    }
}

/** Dış-tık kapatma — menü gövdeye teleport edildiği için hem tetikleyici
 * (root) hem de menü elemanı ayrı ayrı denetlenir. */
function onDocPointerDown(e: MouseEvent): void {
    if (!open.value) return;
    const t = e.target as Node | null;
    if (t !== null && (root.value?.contains(t) || menu.value?.contains(t))) return;
    open.value = false;
}

onMounted(() => document.addEventListener('mousedown', onDocPointerDown));
onBeforeUnmount(() => {
    document.removeEventListener('mousedown', onDocPointerDown);
    window.removeEventListener('scroll', onViewportChange, true);
    window.removeEventListener('resize', onViewportChange);
});

defineExpose({ close: () => (open.value = false) });

const ariaAttrs = () => ({
    'aria-haspopup': 'menu' as const,
    'aria-expanded': open.value ? ('true' as const) : ('false' as const),
    'aria-controls': menuId,
});
</script>

<template>
    <div ref="root" class="relative inline-block">
        <span ref="triggerWrap" @keydown="onTriggerKeydown">
            <slot name="trigger" :open="open" :toggle="toggle" :aria-attrs="ariaAttrs()" />
        </span>
        <Teleport to="body">
            <Transition
                enter-active-class="transition duration-(--dur-fast) ease-out"
                enter-from-class="scale-95 opacity-0"
                leave-active-class="transition duration-(--dur-fast) ease-in"
                leave-to-class="scale-95 opacity-0"
            >
                <div
                    v-if="open"
                    :id="menuId"
                    ref="menu"
                    role="menu"
                    :aria-label="menuLabel"
                    class="z-(--z-dropdown) min-w-48 origin-top rounded-md border border-default bg-raised py-1 shadow-dropdown"
                    :style="menuStyle"
                    @keydown="onMenuKeydown"
                    @click="open = false"
                >
                    <slot />
                </div>
            </Transition>
        </Teleport>
    </div>
</template>
