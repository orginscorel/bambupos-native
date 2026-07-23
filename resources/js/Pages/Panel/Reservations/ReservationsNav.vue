<script setup lang="ts">
import { computed } from 'vue';
import { Link } from '@inertiajs/vue3';
import AppIcon from '@/Components/ui/AppIcon.vue';

/** Rezervasyon sayfaları arası ikincil gezinme (Venue deseni). */
const items = [
    { href: '/panel/rezervasyonlar', label: 'Takvim ve Liste', icon: 'dashboard', exact: true },
    { href: '/panel/rezervasyonlar/bekleme-listesi', label: 'Bekleme Listesi', icon: 'inbox', exact: false },
    { href: '/panel/rezervasyonlar/no-show', label: 'No-Show Raporu', icon: 'chart', exact: false },
];

const currentPath = computed(() => (typeof window !== 'undefined' ? window.location.pathname : ''));
const isActive = (item: { href: string; exact: boolean }) =>
    item.exact ? currentPath.value === item.href : currentPath.value.startsWith(item.href);
</script>

<template>
    <nav class="mb-4 flex flex-wrap gap-1" aria-label="Rezervasyon bölümleri">
        <Link
            v-for="item in items"
            :key="item.href"
            :href="item.href"
            class="flex h-9 items-center gap-2 rounded-md px-3 text-sm font-medium transition-colors duration-(--dur-fast)"
            :class="isActive(item) ? 'bg-primary-soft text-primary' : 'text-muted hover:bg-inset hover:text-body'"
            :aria-current="isActive(item) ? 'page' : undefined"
        >
            <AppIcon :name="item.icon" :size="16" />
            {{ item.label }}
        </Link>
    </nav>
</template>
