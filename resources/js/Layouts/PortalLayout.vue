<script setup lang="ts">
/**
 * Personel Portalı layout — mobil-öncelikli, kurulabilir PWA.
 *
 * PanelShell/PanelLayout DEĞİL: sade, kendi alt-nav'lı (Mesaim · Raporlarım ·
 * Profilim) profesyonel kabuk. Turuncu-beyaz token, dark/light, masaüstünde
 * ortalanmış dar sütun. Portal service worker'ı burada kaydeder.
 */
import { computed, onMounted } from 'vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';
import { authFromPage } from '@/types/auth';
import { useTheme } from '@/composables/useTheme';
import { api } from '@/lib/http';
import AppIcon from '@/Components/ui/AppIcon.vue';

const props = defineProps<{
    title: string;
    active: 'shift' | 'reports' | 'profile';
}>();

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));
const user = computed(() => auth.value?.user ?? null);
const tenantName = computed(() => auth.value?.tenant?.name ?? '');

const { theme, toggleTheme } = useTheme();

const nav = [
    { key: 'shift', label: 'Mesaim', icon: 'clock', href: '/mesaim' },
    { key: 'reports', label: 'Raporlarım', icon: 'chart', href: '/raporlarim' },
    { key: 'profile', label: 'Profilim', icon: 'user', href: '/profilim' },
] as const;

const initial = computed(() => (user.value?.name?.trim()?.charAt(0) ?? '?').toUpperCase());

async function persistTheme(): Promise<void> {
    try {
        await api('/api/v1/auth/preferences', { method: 'PUT', body: { theme: theme.value } });
    } catch {
        /* tema yereldir; kalıcılaştırma best-effort */
    }
}

function onToggleTheme(): void {
    toggleTheme();
    void persistTheme();
}

async function logout(): Promise<void> {
    try {
        await api('/api/v1/auth/logout', { method: 'POST' });
    } catch {
        /* yine de giriş ekranına dön */
    }
    router.visit('/giris');
}

onMounted(() => {
    // Kurulabilir PWA + push (push-sw.js importScripts ile dahildir).
    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('/portal-sw.js', { scope: '/' }).catch(() => {
            /* SW kaydı başarısızsa portal yine çalışır */
        });
    }
});
</script>

<template>
    <div class="portal-root flex min-h-dvh flex-col bg-surface text-body">
        <Head :title="title" />

        <!-- Üst bar -->
        <header
            class="sticky top-0 z-30 border-b border-(--ui-border) bg-surface/95 backdrop-blur supports-[backdrop-filter]:bg-surface/80"
            style="padding-top: env(safe-area-inset-top)"
        >
            <div class="mx-auto flex w-full max-w-xl items-center gap-3 px-4 py-3">
                <div class="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary text-sm font-bold text-on-primary">
                    {{ initial }}
                </div>
                <div class="min-w-0 flex-1">
                    <p class="truncate text-sm font-semibold text-body">{{ user?.name ?? 'Personel' }}</p>
                    <p v-if="tenantName" class="truncate text-xs text-muted">{{ tenantName }}</p>
                </div>
                <button
                    type="button"
                    class="flex size-9 items-center justify-center rounded-full text-muted transition hover:bg-(--color-inset) hover:text-body"
                    :aria-label="theme === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç'"
                    @click="onToggleTheme"
                >
                    <AppIcon :name="theme === 'dark' ? 'sun' : 'moon'" :size="18" />
                </button>
                <button
                    type="button"
                    class="flex size-9 items-center justify-center rounded-full text-muted transition hover:bg-(--color-danger-soft) hover:text-(--ui-danger)"
                    aria-label="Çıkış yap"
                    @click="logout"
                >
                    <AppIcon name="logout" :size="18" />
                </button>
            </div>
        </header>

        <!-- İçerik -->
        <main class="mx-auto w-full max-w-xl flex-1 px-4 pb-28 pt-5">
            <h1 class="mb-4 text-xl font-semibold text-body">{{ title }}</h1>
            <slot />
        </main>

        <!-- Alt gezinme -->
        <nav
            class="fixed inset-x-0 bottom-0 z-30 border-t border-(--ui-border) bg-surface/95 backdrop-blur"
            style="padding-bottom: env(safe-area-inset-bottom)"
        >
            <div class="mx-auto grid w-full max-w-xl grid-cols-3">
                <Link
                    v-for="item in nav"
                    :key="item.key"
                    :href="item.href"
                    class="flex flex-col items-center gap-1 py-2.5 text-xs font-medium transition"
                    :class="props.active === item.key ? 'text-primary' : 'text-muted hover:text-body'"
                >
                    <AppIcon :name="item.icon" :size="22" />
                    <span>{{ item.label }}</span>
                </Link>
            </div>
        </nav>
    </div>
</template>
