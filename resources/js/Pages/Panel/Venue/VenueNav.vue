<script setup lang="ts">
import { computed } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import AppIcon from '@/Components/ui/AppIcon.vue';

/**
 * Venue sayfaları arası ikincil gezinme (Masalar / Alanlar / QR / Şubeler).
 * Şubeler bağlantısı branches.view izni olmayana gösterilmez.
 */
const page = usePage();

const permissions = computed<string[]>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
    return auth?.permissions ?? [];
});

const items = computed(() => {
    const list = [
        { href: '/panel/masalar', label: 'Masalar', icon: 'dashboard', exact: true },
    ];

    // Masa yönetimi (oluştur/düzenle/sil) izni olmayan (ör. görüntüleyen
    // garson) yalnız "Masalar" listesini görür; Alan/Kat + QR yönetim
    // sekmeleri gizlenir.
    const canManageTables = ['tables.create', 'tables.update', 'tables.delete']
        .some((k) => permissions.value.includes(k));

    if (canManageTables) {
        list.push(
            { href: '/panel/masalar/alanlar', label: 'Alanlar ve Katlar', icon: 'home', exact: false },
            { href: '/panel/masalar/qr', label: 'QR Yönetimi', icon: 'qr-code', exact: false },
        );
    }

    if (permissions.value.includes('branches.view')) {
        list.push({ href: '/panel/subeler', label: 'Şubeler', icon: 'store', exact: false });
    }

    return list;
});

const currentPath = computed(() => (typeof window !== 'undefined' ? window.location.pathname : ''));
const isActive = (item: { href: string; exact: boolean }) =>
    item.exact ? currentPath.value === item.href : currentPath.value.startsWith(item.href);
</script>

<template>
    <nav class="mb-4 flex flex-wrap gap-1" aria-label="Masa yönetimi bölümleri">
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
