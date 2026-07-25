<script setup lang="ts">
import { Link } from '@inertiajs/vue3';

/**
 * Stok modülü alt gezinmesi: tüm Inventory sayfalarının üstünde durur.
 * (Ana menüde tek "Stok" bağlantısı vardır; alt sayfalar buradan gezilir.)
 */
const props = defineProps<{ active: string }>();

const tabs = [
    { key: 'items', label: 'Stok Kartları', href: '/panel/stok' },
    { key: 'movements', label: 'Hareket Defteri', href: '/panel/stok/hareketler' },
    { key: 'recipes', label: 'Reçeteler', href: '/panel/stok/receteler' },
    { key: 'counts', label: 'Sayım', href: '/panel/stok/sayim' },
    { key: 'purchasing', label: 'Satın Alma', href: '/panel/stok/satin-alma' },
    { key: 'suppliers', label: 'Tedarikçiler', href: '/panel/stok/tedarikciler' },
    { key: 'alerts', label: 'Uyarılar', href: '/panel/stok/uyarilar' },
];
</script>

<template>
    <nav aria-label="Stok alt menüsü" class="-mx-1 mb-4 overflow-x-auto overscroll-x-contain">
        <ul class="flex min-w-max items-center gap-1 border-b border-default px-1">
            <li v-for="tab in tabs" :key="tab.key">
                <Link
                    :href="tab.href"
                    class="inline-flex items-center gap-1.5 whitespace-nowrap border-b-2 px-3 py-2 text-sm font-medium transition-colors"
                    :class="tab.key === props.active
                        ? 'border-primary text-primary'
                        : 'border-transparent text-muted hover:text-body'"
                    :aria-current="tab.key === props.active ? 'page' : undefined"
                >
                    {{ tab.label }}
                </Link>
            </li>
        </ul>
    </nav>
</template>
