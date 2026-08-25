<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue';
import { router } from '@inertiajs/vue3';
import type { NavItem } from '@/types/nav';
import { useFocusTrap } from '@/composables/useFocusTrap';
import AppIcon from '@/Components/ui/AppIcon.vue';

/**
 * Hafif komut paleti (⌘K / Ctrl+K veya üst çubuktaki "Ara…" ile açılır).
 *
 * Kapsam BİLİNÇLİ dar tutuldu: gerçek varlık-arama (sipariş/ürün/müşteri)
 * DEĞİL — yalnız panel içi sayfalara hızlı geçiş. `items` PanelLayout'un
 * zaten izin + istasyon-kapsamı + feature-flag ile süzdüğü `navItems`
 * listesidir; palet asla kullanıcının menüde göremediği bir sayfayı
 * göstermez (aynı süzgeç, tek kaynak).
 */
const props = defineProps<{ open: boolean; items: NavItem[] }>();
const emit = defineEmits<{ 'update:open': [boolean] }>();

const query = ref('');
const activeIndex = ref(0);
const panel = ref<HTMLElement | null>(null);
const listEl = ref<HTMLElement | null>(null);

const isOpen = computed(() => props.open);
useFocusTrap(panel, isOpen);

const results = computed<NavItem[]>(() => {
    const q = query.value.trim().toLocaleLowerCase('tr-TR');
    if (!q) return props.items;
    return props.items.filter((i) => i.label.toLocaleLowerCase('tr-TR').includes(q));
});

watch(results, () => {
    activeIndex.value = 0;
});

watch(isOpen, (v) => {
    if (v) {
        query.value = '';
        activeIndex.value = 0;
    }
});

function close(): void {
    emit('update:open', false);
}

function go(item: NavItem | undefined): void {
    if (!item) return;
    close();
    router.visit(item.href);
}

function scrollActiveIntoView(): void {
    nextTick(() => {
        listEl.value?.querySelector<HTMLElement>('[data-active="true"]')?.scrollIntoView({ block: 'nearest' });
    });
}

function onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') {
        e.preventDefault();
        close();
        return;
    }
    if (e.key === 'ArrowDown') {
        e.preventDefault();
        if (results.value.length) activeIndex.value = (activeIndex.value + 1) % results.value.length;
        scrollActiveIntoView();
        return;
    }
    if (e.key === 'ArrowUp') {
        e.preventDefault();
        if (results.value.length) activeIndex.value = (activeIndex.value - 1 + results.value.length) % results.value.length;
        scrollActiveIntoView();
        return;
    }
    if (e.key === 'Enter') {
        e.preventDefault();
        go(results.value[activeIndex.value]);
    }
}
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
                class="fixed inset-0 z-(--z-modal) flex items-start justify-center bg-overlay px-4 pt-[12vh]"
                @mousedown.self="close"
            >
                <div
                    ref="panel"
                    role="dialog"
                    aria-modal="true"
                    aria-label="Komut paleti"
                    class="flex max-h-[70vh] w-full max-w-lg flex-col overflow-hidden rounded-xl bg-raised shadow-modal outline-none"
                >
                    <div class="flex items-center gap-2 border-b border-default px-4 py-3">
                        <AppIcon name="search" :size="17" class="shrink-0 text-subtle" aria-hidden="true" />
                        <input
                            v-model="query"
                            data-autofocus
                            type="text"
                            placeholder="Sayfa ara…"
                            class="min-w-0 grow bg-transparent text-sm text-body outline-none placeholder:text-subtle"
                            aria-label="Sayfa ara"
                            role="combobox"
                            aria-expanded="true"
                            aria-controls="command-palette-list"
                            @keydown="onKeydown"
                        />
                        <kbd class="hidden shrink-0 items-center rounded border border-default bg-surface px-1.5 py-0.5 text-[11px] leading-none font-medium text-subtle sm:inline-flex">
                            Esc
                        </kbd>
                    </div>

                    <ul id="command-palette-list" ref="listEl" role="listbox" aria-label="Sayfalar" class="grow overflow-y-auto p-1.5">
                        <li v-if="!results.length" class="px-3 py-6 text-center text-sm text-muted">Sonuç yok.</li>
                        <li
                            v-for="(item, idx) in results"
                            :key="item.key"
                            role="option"
                            :aria-selected="idx === activeIndex"
                            :data-active="idx === activeIndex ? 'true' : undefined"
                        >
                            <button
                                type="button"
                                class="flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left text-sm transition-colors duration-(--dur-fast)"
                                :class="idx === activeIndex ? 'bg-primary-soft text-primary' : 'text-body hover:bg-inset'"
                                @mouseenter="activeIndex = idx"
                                @click="go(item)"
                            >
                                <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-inset text-muted">
                                    <AppIcon :name="item.icon" :size="16" />
                                </span>
                                <span class="min-w-0 grow truncate font-medium">{{ item.label }}</span>
                                <span v-if="item.group" class="ml-auto shrink-0 text-xs text-subtle">{{ item.group }}</span>
                            </button>
                        </li>
                    </ul>
                </div>
            </div>
        </Transition>
    </Teleport>
</template>
