<script setup lang="ts">
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useFocusTrap } from '@/composables/useFocusTrap';
import { useId } from '@/composables/useId';
import AppIcon from './AppIcon.vue';

/**
 * Kenardan açılan panel (drawer). Mobilde tam genişlik, masaüstünde sabit.
 *
 * Yön seçilebilir: ANA MENÜ soldan açılmalıdır — menü her zaman solda durur,
 * sağdan gelmesi yön duygusunu bozuyordu. Detay/filtre panelleri sağda kalır.
 */
const props = withDefaults(
    defineProps<{
        open: boolean;
        title: string;
        /** Tailwind genişlik sınıfı (masaüstü) */
        widthClass?: string;
        /** Açılış kenarı — varsayılan sağ (mevcut kullanımlar değişmez). */
        side?: 'left' | 'right';
    }>(),
    { widthClass: 'sm:max-w-md', side: 'right' },
);

const emit = defineEmits<{ close: [] }>();

const panel = ref<HTMLElement | null>(null);
const titleId = useId('drawer-title');
const isOpen = computed(() => props.open);

useFocusTrap(panel, isOpen);

function onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') emit('close');
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
                class="fixed inset-0 z-(--z-drawer) bg-overlay"
                @mousedown.self="emit('close')"
            />
        </Transition>
        <Transition
            enter-active-class="transition-transform duration-(--dur-slow) ease-out"
            :enter-from-class="props.side === 'left' ? '-translate-x-full' : 'translate-x-full'"
            leave-active-class="transition-transform duration-(--dur-normal) ease-in"
            :leave-to-class="props.side === 'left' ? '-translate-x-full' : 'translate-x-full'"
        >
            <div
                v-if="open"
                ref="panel"
                role="dialog"
                aria-modal="true"
                :aria-labelledby="titleId"
                tabindex="-1"
                class="fixed inset-y-0 z-(--z-drawer) flex w-full flex-col bg-raised shadow-modal outline-none"
                :class="[widthClass, props.side === 'left' ? 'left-0' : 'right-0']"
            >
                <header class="flex items-center justify-between gap-3 border-b border-default px-5 py-4">
                    <h2 :id="titleId" class="text-base font-semibold text-body">{{ title }}</h2>
                    <button
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
        </Transition>
    </Teleport>
</template>
