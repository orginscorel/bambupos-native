<script setup lang="ts">
import { computed } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import PanelShell from '@/Components/panel/PanelShell.vue';

/**
 * Katalog bölümü kabuğu: PanelShell + katalog alt gezinmesi.
 * Alt sekmeler yalnız gerçekten var olan sayfalara gider.
 */
const props = defineProps<{ title: string }>();

const page = usePage();
const permissions = computed<string[]>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
    return auth?.permissions ?? [];
});

const tabs = [
    { key: 'products', label: 'Ürünler', href: '/panel/menu' },
    { key: 'categories', label: 'Kategoriler', href: '/panel/menu/kategoriler' },
    { key: 'options', label: 'Seçenek Grupları', href: '/panel/menu/secenekler' },
    { key: 'allergens', label: 'Alerjenler & Diyet', href: '/panel/menu/alerjenler' },
    { key: 'menus', label: 'Menü Planlama', href: '/panel/menu/menuler' },
];

const currentPath = typeof window !== 'undefined' ? window.location.pathname : '';
const isActive = (href: string) =>
    href === '/panel/menu'
        ? currentPath === '/panel/menu' || currentPath.startsWith('/panel/menu/urunler')
        : currentPath === href;
</script>

<template>
    <PanelShell :title="props.title">
        <div class="flex flex-col gap-4">
            <nav class="flex gap-1 overflow-x-auto border-b border-default" aria-label="Katalog bölümleri">
                <Link
                    v-for="tab in tabs"
                    :key="tab.key"
                    :href="tab.href"
                    class="-mb-px inline-flex h-10 items-center border-b-2 px-3 text-sm font-medium whitespace-nowrap transition-colors duration-(--dur-fast)"
                    :class="
                        isActive(tab.href)
                            ? 'border-primary text-primary'
                            : 'border-transparent text-muted hover:border-strong hover:text-body'
                    "
                    :aria-current="isActive(tab.href) ? 'page' : undefined"
                >
                    {{ tab.label }}
                </Link>
            </nav>
            <slot :permissions="permissions" />
        </div>
    </PanelShell>
</template>
