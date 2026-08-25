<script setup lang="ts">
/**
 * PATRON PANELİ kabuğu — operasyon panelinden AYRI, yönetsel/executive deneyim.
 * Operasyon kenar çubuğu YOK; koyu marka-gradyanlı üst bar + odaklı içerik.
 * Patron buraya kullanıcı menüsünden gelir; "Panele dön" ile operasyona döner.
 */
import { computed } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import { useTheme } from '@/composables/useTheme';
import { useVersionWatch } from '@/composables/useVersionWatch';
import AppIcon from '@/Components/ui/AppIcon.vue';
import ToastHost from '@/Components/ui/ToastHost.vue';

withDefaults(defineProps<{ title?: string; subtitle?: string }>(), { title: 'Patron Paneli', subtitle: '' });

const { theme, toggleTheme } = useTheme();

/* Sürüm gözcüsü: yeni sürüm yayınlanınca "yenile" toast'ı */
useVersionWatch();

/* Navigasyon: Patron Paneli YALNIZ kendi subdomain'inde (patron.*) kökte açılır. */
const page = usePage();
const navItems = [
    { key: 'ozet', label: 'Özet', icon: 'gauge', href: '/' },
    { key: 'vardiya', label: 'Vardiya', icon: 'calendar', href: '/vardiya' },
    { key: 'gorevler', label: 'Görevler', icon: 'clipboard', href: '/gorevler' },
];
const currentPath = computed(() => String(page.url || '').split('?')[0].replace(/\/$/, '') || '/');
function isActive(href: string): boolean {
    const h = href.replace(/\/$/, '') || '/';
    return currentPath.value === h;
}
</script>

<template>
    <!-- TAM EKRAN KABUK (panel ve POS ekranlarıyla aynı dil): kabuk viewport'a
         sabit, üst çubuk hep yerinde, yalnız içerik kendi içinde kayar. -->
    <div class="boss-root fixed inset-0 flex flex-col overflow-hidden bg-surface-alt">
        <!-- ===== Executive üst bar (marka gradyanı) ===== -->
        <header class="boss-topbar z-(--z-sticky) shrink-0 text-white shadow-lg">
            <div class="mx-auto flex max-w-7xl flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3 sm:px-6">
                <div class="flex min-w-0 items-center gap-3">
                    <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-white/15 ring-1 ring-white/25 backdrop-blur">
                        <AppIcon name="gauge" :size="22" />
                    </span>
                    <div class="min-w-0 leading-tight">
                        <p class="truncate text-base font-bold sm:text-lg">{{ title }}</p>
                        <p v-if="subtitle" class="truncate text-[12px] text-white/70">{{ subtitle }}</p>
                    </div>
                </div>

                <!-- Sayfa aksiyonları (dönem seçici vb.) -->
                <div class="flex min-w-0 grow items-center justify-end gap-1.5">
                    <slot name="actions" />

                    <button
                        type="button"
                        class="flex size-10 items-center justify-center rounded-lg text-white/80 transition-colors hover:bg-white/15 hover:text-white"
                        :aria-label="theme === 'dark' ? 'Açık tema' : 'Koyu tema'"
                        @click="toggleTheme"
                    >
                        <AppIcon :name="theme === 'dark' ? 'sun' : 'moon'" :size="18" />
                    </button>

                    <Link
                        href="/panel"
                        class="inline-flex h-10 items-center gap-1.5 rounded-lg bg-white/15 px-3 text-sm font-semibold text-white ring-1 ring-white/25 transition-colors hover:bg-white/25"
                    >
                        <AppIcon name="arrow-left" :size="15" />
                        <span class="hidden sm:inline">Panele dön</span>
                    </Link>
                </div>
            </div>

            <!-- ===== Navigasyon: segmented pill kontrol ===== -->
            <nav class="mx-auto max-w-7xl px-3 pb-3 sm:px-6">
                <ul class="flex items-center gap-1 rounded-2xl bg-black/15 p-1 ring-1 ring-white/10 backdrop-blur-sm">
                    <li v-for="item in navItems" :key="item.key" class="min-w-0 flex-1">
                        <Link
                            :href="item.href"
                            class="group relative flex items-center justify-center gap-2 rounded-xl px-3 py-2.5 text-[13px] font-bold transition-all duration-200 sm:text-sm"
                            :class="isActive(item.href)
                                ? 'bg-surface text-primary shadow-md'
                                : 'text-white/80 hover:bg-white/10 hover:text-white'"
                            :aria-current="isActive(item.href) ? 'page' : undefined"
                        >
                            <span
                                class="flex size-6 shrink-0 items-center justify-center rounded-lg transition-colors"
                                :class="isActive(item.href) ? 'bg-primary-soft' : 'bg-white/10 group-hover:bg-white/15'"
                            >
                                <AppIcon :name="item.icon" :size="15" />
                            </span>
                            <span class="truncate">{{ item.label }}</span>
                        </Link>
                    </li>
                </ul>
            </nav>
        </header>

        <!-- ===== İçerik ===== -->
        <main class="min-h-0 flex-1 overflow-y-auto overscroll-contain">
            <div class="mx-auto w-full max-w-[1440px] p-3 pb-16 sm:p-4">
            <slot />
        </div>
        </main>

        <ToastHost />
    </div>
</template>

<style scoped>
/* Executive gradyan: marka MAVİSİ derin→parlak; koyu temada biraz daha koyu. */
.boss-topbar {
    background-image: linear-gradient(120deg, var(--brand-900) 0%, var(--brand-700) 55%, var(--brand-600) 100%);
}
:root[data-theme='dark'] .boss-topbar {
    background-image: linear-gradient(120deg, #0b1f4d 0%, var(--brand-800) 60%, var(--brand-700) 100%);
}
</style>
