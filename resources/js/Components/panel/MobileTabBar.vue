<script setup lang="ts">
import { Link } from '@inertiajs/vue3';
import type { NavItem } from '@/types/nav';
import AppIcon from '@/Components/ui/AppIcon.vue';
import FabButton from '@/Components/ui/FabButton.vue';

/**
 * Native alt sekme çubuğu (yalnız mobil). Yerleşim:
 *   [sol1] [sol2]  ( FAB )  [sağ1] [Tümü]
 * FAB ana operasyona (masa panosu / QR) gider ve çubuğun ortasında hafif yukarı
 * taşar (notch). Aktif sekme marka rengi; pasif koyu gri. Safe-area korunur.
 * Süzme/aktiflik ebeveyn (PanelLayout) tarafında; bu bileşen salt görünüm.
 */
defineProps<{
    leftItems: NavItem[];
    rightItems: NavItem[];
    fab: { href: string; icon: string; label: string } | null;
    active: (item: NavItem) => boolean;
}>();

const emit = defineEmits<{ menu: [] }>();
</script>

<template>
    <nav
        class="fixed inset-x-0 bottom-0 z-(--z-sticky) bg-surface pb-[env(safe-area-inset-bottom)] shadow-[var(--shadow-tabbar)] lg:hidden"
        aria-label="Ana menü (mobil)"
    >
        <ul class="mx-auto flex max-w-lg items-stretch" :style="{ height: 'var(--h-tabbar)' }">
            <!-- Sol sekmeler -->
            <li v-for="item in leftItems" :key="item.key" class="min-w-0 flex-1">
                <Link
                    :href="item.href"
                    class="flex h-full flex-col items-center justify-center gap-1 px-1 transition-colors duration-(--dur-fast) active:bg-inset"
                    :class="active(item) ? 'text-primary' : 'text-muted'"
                    :aria-current="active(item) ? 'page' : undefined"
                >
                    <AppIcon :name="item.icon" :size="21" />
                    <span class="w-full truncate text-center text-[10px] font-medium leading-none">{{ item.label }}</span>
                </Link>
            </li>

            <!-- Orta FAB (ana operasyon) -->
            <li v-if="fab" class="flex w-16 shrink-0 items-start justify-center">
                <FabButton :href="fab.href" :icon="fab.icon" :label="fab.label" notch />
            </li>

            <!-- Sağ sekmeler -->
            <li v-for="item in rightItems" :key="item.key" class="min-w-0 flex-1">
                <Link
                    :href="item.href"
                    class="flex h-full flex-col items-center justify-center gap-1 px-1 transition-colors duration-(--dur-fast) active:bg-inset"
                    :class="active(item) ? 'text-primary' : 'text-muted'"
                    :aria-current="active(item) ? 'page' : undefined"
                >
                    <AppIcon :name="item.icon" :size="21" />
                    <span class="w-full truncate text-center text-[10px] font-medium leading-none">{{ item.label }}</span>
                </Link>
            </li>

            <!-- Tümü (çekmece) -->
            <li class="min-w-0 flex-1">
                <button
                    type="button"
                    class="flex h-full w-full flex-col items-center justify-center gap-1 px-1 text-muted transition-colors duration-(--dur-fast) active:bg-inset"
                    aria-label="Tüm menü"
                    @click="emit('menu')"
                >
                    <AppIcon name="menu" :size="21" />
                    <span class="text-[10px] font-medium leading-none">Tümü</span>
                </button>
            </li>
        </ul>
    </nav>
</template>
