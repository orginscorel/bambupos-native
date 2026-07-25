<script setup lang="ts">
import { computed } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import PanelShell from '@/Components/panel/PanelShell.vue';

/**
 * Vardiya & Mesai bölümü kabuğu: PanelShell + sekmeler.
 * Sekmeler izne göre süzülür (Personel kabuğu deseni).
 */
const props = defineProps<{ title: string }>();

const page = usePage();
const permissions = computed<string[]>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
    return auth?.permissions ?? [];
});

const canManage = computed(() => permissions.value.includes('staff.manage'));
const canView = computed(() => permissions.value.includes('staff.view') || canManage.value);

const tabs = computed(() => {
    const items: Array<{ key: string; label: string; href: string; show: boolean }> = [
        { key: 'schedule', label: 'Vardiya Takvimi', href: '/panel/vardiya', show: true },
        { key: 'entries', label: 'Mesai Kayıtları', href: '/panel/mesai', show: true },
        { key: 'clock', label: 'Giriş / Çıkış', href: '/panel/mesai/giris-cikis', show: true },
        { key: 'leaves', label: 'İzinler', href: '/panel/mesai/izinler', show: true },
        { key: 'approvals', label: 'Onay Bekleyenler', href: '/panel/mesai/talepler', show: canManage.value },
        { key: 'performance', label: 'Performans', href: '/panel/mesai/performans', show: canView.value },
        { key: 'settings', label: 'Ayarlar', href: '/panel/mesai/ayarlar', show: canManage.value },
    ];
    return items.filter((t) => t.show);
});

const currentPath = typeof window !== 'undefined' ? window.location.pathname : '';
const isActive = (href: string) =>
    href === '/panel/mesai' ? currentPath === '/panel/mesai' : currentPath.startsWith(href);
</script>

<template>
    <PanelShell :title="props.title">
        <div class="flex flex-col gap-4">
            <nav class="flex gap-1 overflow-x-auto border-b border-default" aria-label="Vardiya ve mesai bölümleri">
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
            <slot />
        </div>
    </PanelShell>
</template>
