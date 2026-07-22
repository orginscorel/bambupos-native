<script setup lang="ts">
import { computed } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import PanelShell from '@/Components/panel/PanelShell.vue';

/**
 * Personel bölümü kabuğu: PanelShell + Personel/Roller sekmeleri.
 * Sekmeler izne göre süzülür (roles.view yoksa Roller görünmez).
 */
const props = defineProps<{ title: string }>();

const page = usePage();
const permissions = computed<string[]>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
    return auth?.permissions ?? [];
});

const tabs = computed(() => {
    const items = [
        { key: 'staff', label: 'Personel', href: '/panel/personel', permission: 'staff.view' },
        { key: 'roles', label: 'Roller & Yetkiler', href: '/panel/personel/roller', permission: 'roles.view' },
    ];
    return items.filter((t) => !t.permission || permissions.value.includes(t.permission) || permissions.value.includes(t.permission.split('.')[0] + '.manage'));
});

const currentPath = typeof window !== 'undefined' ? window.location.pathname : '';
const isActive = (href: string) =>
    href === '/panel/personel' ? currentPath === '/panel/personel' : currentPath.startsWith(href);
</script>

<template>
    <PanelShell :title="props.title">
        <div class="flex flex-col gap-4">
            <nav class="flex gap-1 overflow-x-auto border-b border-default" aria-label="Personel bölümleri">
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
