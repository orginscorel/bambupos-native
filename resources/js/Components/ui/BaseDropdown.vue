<script setup lang="ts">
import { nextTick, ref } from 'vue';
import { useClickOutside } from '@/composables/useClickOutside';
import { useId } from '@/composables/useId';

/**
 * Açılır menü. Tetikleyici #trigger slot'undan (open, toggle, ariaAttrs alır);
 * içerik varsayılan slot'ta `role="menuitem"` öğeleriyle verilir.
 * Klavye: Enter/Space/ArrowDown açar, oklar gezdirir, Esc kapatıp odağı döndürür.
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
const menu = ref<HTMLElement | null>(null);
const menuId = useId('dropdown');

useClickOutside(root, () => (open.value = false));

function items(): HTMLElement[] {
    return Array.from(menu.value?.querySelectorAll<HTMLElement>('[role="menuitem"]:not([aria-disabled="true"])') ?? []);
}

async function openMenu(focusFirst = true): Promise<void> {
    open.value = true;
    await nextTick();
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

defineExpose({ close: () => (open.value = false) });

const ariaAttrs = () => ({
    'aria-haspopup': 'menu' as const,
    'aria-expanded': open.value ? ('true' as const) : ('false' as const),
    'aria-controls': menuId,
});
</script>

<template>
    <div ref="root" class="relative inline-block" @keydown="open && onMenuKeydown($event)">
        <span @keydown="onTriggerKeydown">
            <slot name="trigger" :open="open" :toggle="toggle" :aria-attrs="ariaAttrs()" />
        </span>
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
                class="absolute z-(--z-dropdown) mt-1.5 min-w-48 origin-top rounded-md border border-default bg-raised py-1 shadow-dropdown"
                :class="align === 'right' ? 'right-0' : 'left-0'"
                @click="open = false"
            >
                <slot />
            </div>
        </Transition>
    </div>
</template>
