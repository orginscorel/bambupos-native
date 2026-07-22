<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import type { NavItem } from '@/types/nav';
import { defaultNavigation } from '@/config/navigation';
import { useTheme } from '@/composables/useTheme';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import ToastHost from '@/Components/ui/ToastHost.vue';

const props = withDefaults(
    defineProps<{
        title?: string;
        nav?: NavItem[];
        /** Bildirim zili rozet sayısı (Notify modülü dolduracak) */
        notificationCount?: number;
    }>(),
    { title: '', notificationCount: 0 },
);

const page = usePage();
const { theme, toggleTheme } = useTheme();

/** Rol bazlı süzgeç: auth.permissions sayfa prop'u (Çekirdek-Kimlik sağlayacak).
 *  Prop yoksa (henüz auth yok) tüm öğeler görünür. */
const permissions = computed<string[] | null>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
    return auth?.permissions ?? null;
});

const navItems = computed<NavItem[]>(() => {
    const items = props.nav ?? defaultNavigation;
    const perms = permissions.value;
    if (!perms) return items;
    return items.filter((i) => !i.permission || perms.includes(i.permission));
});

const mobileItems = computed(() => navItems.value.filter((i) => i.mobile).slice(0, 4));
const mobileNavOpen = ref(false);

/* ===== Üst çubuk saati =====
 * - Şube saat dilimi esastır (auth.branches[].timezone + activeBranchId).
 * - İstemcinin duvar saatine güvenilmez: app.blade.php'deki
 *   "app-server-epoch" meta'sından sunucu-istemci ofseti alınır.
 * - Dakikada bir, dakika başına hizalı güncellenir; sekme arka
 *   plandayken sayaç durur, öne gelince anında senkronlanır. */
const branchTimezone = computed<string>(() => {
    const auth = (page.props as Record<string, unknown>).auth as
        | { branches?: { id: number | string; timezone?: string }[]; activeBranchId?: number | null }
        | null
        | undefined;
    const active = auth?.branches?.find((b) => Number(b.id) === Number(auth?.activeBranchId));
    return active?.timezone || 'Europe/Istanbul';
});

const serverOffsetMs = ref(0); // sunucu saati - istemci saati (ms)
const nowMs = ref(Date.now());
let clockTimer: ReturnType<typeof setTimeout> | undefined;

const syncClock = () => {
    nowMs.value = Date.now() + serverOffsetMs.value;
};

const scheduleClockTick = () => {
    // bir sonraki dakika başına hizala (+250ms tampon) — saniyelik tick YOK
    const wait = 60_000 - (nowMs.value % 60_000) + 250;
    clockTimer = setTimeout(() => {
        syncClock();
        scheduleClockTick();
    }, wait);
};

const onClockVisibility = () => {
    if (document.hidden) {
        if (clockTimer) clearTimeout(clockTimer);
        clockTimer = undefined;
    } else {
        syncClock();
        if (!clockTimer) scheduleClockTick();
    }
};

onMounted(() => {
    const epoch = Number(document.querySelector('meta[name="app-server-epoch"]')?.getAttribute('content'));
    if (Number.isFinite(epoch)) serverOffsetMs.value = epoch - Date.now();
    syncClock();
    scheduleClockTick();
    document.addEventListener('visibilitychange', onClockVisibility);
});

onBeforeUnmount(() => {
    if (clockTimer) clearTimeout(clockTimer);
    document.removeEventListener('visibilitychange', onClockVisibility);
});

/** Şube dilimine göre biçimle; dilim adı bozuksa yerel dilime düş. */
const formatInBranchTz = (opts: Intl.DateTimeFormatOptions): string => {
    try {
        return new Intl.DateTimeFormat('tr-TR', { ...opts, timeZone: branchTimezone.value }).format(nowMs.value);
    } catch {
        return new Intl.DateTimeFormat('tr-TR', opts).format(nowMs.value);
    }
};

const clockTime = computed(() => formatInBranchTz({ hour: '2-digit', minute: '2-digit' }));
const clockDate = computed(() => formatInBranchTz({ day: 'numeric', month: 'long', weekday: 'long' }));

const currentPath = computed(() => (typeof window !== 'undefined' ? window.location.pathname : ''));
const isActive = (item: NavItem) =>
    item.exact
        ? currentPath.value === item.href
        : currentPath.value === item.href || currentPath.value.startsWith(item.href + '/');
</script>

<template>
    <div class="min-h-dvh bg-surface-alt">
        <a
            href="#icerik"
            class="sr-only rounded-md bg-primary px-3 py-2 text-sm font-medium text-on-primary focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-(--z-toast)"
        >
            İçeriğe atla
        </a>

        <!-- ===== Sol menü (masaüstü) ===== -->
        <aside
            class="fixed inset-y-0 left-0 z-(--z-sticky) hidden w-60 flex-col border-r border-default bg-surface lg:flex"
            aria-label="Ana menü"
        >
            <div class="flex h-14 items-center gap-2.5 border-b border-default px-4">
                <!-- Ürün logosu yeri: kiracı teması ileride buradaki markayı değiştirir -->
                <span class="flex size-8 items-center justify-center rounded-md bg-primary text-on-primary">
                    <AppIcon name="qr-code" :size="18" />
                </span>
                <span class="truncate text-sm font-semibold text-body">
                    <slot name="brand">QR Menü</slot>
                </span>
            </div>
            <nav class="grow overflow-y-auto p-2" aria-label="Bölümler">
                <ul class="flex flex-col gap-0.5">
                    <li v-for="item in navItems" :key="item.key">
                        <Link
                            :href="item.href"
                            class="flex h-10 items-center gap-3 rounded-md px-3 text-sm font-medium transition-colors duration-(--dur-fast)"
                            :class="
                                isActive(item)
                                    ? 'bg-primary-soft text-primary'
                                    : 'text-muted hover:bg-inset hover:text-body'
                            "
                            :aria-current="isActive(item) ? 'page' : undefined"
                        >
                            <AppIcon :name="item.icon" :size="18" />
                            <span class="grow truncate">{{ item.label }}</span>
                            <span
                                v-if="item.badge"
                                class="rounded-full bg-primary px-1.5 py-0.5 text-[11px] leading-none font-semibold text-on-primary"
                            >
                                {{ item.badge }}
                            </span>
                        </Link>
                    </li>
                </ul>
            </nav>
            <div class="border-t border-default p-3 text-xs text-subtle">
                <slot name="sidebar-footer" />
            </div>
        </aside>

        <!-- ===== Üst çubuk ===== -->
        <header
            class="sticky top-0 z-(--z-sticky) flex h-14 items-center gap-2 border-b border-default bg-surface px-3 sm:px-4 lg:ml-60"
        >
            <!-- Şube değiştirici yeri (Tenancy modülü dolduracak) -->
            <div class="min-w-0">
                <slot name="branch-switcher">
                    <BaseDropdown align="left" menu-label="Şube seçimi">
                        <template #trigger="{ toggle, ariaAttrs }">
                            <button
                                type="button"
                                v-bind="ariaAttrs"
                                class="flex h-10 max-w-52 items-center gap-2 rounded-md px-2.5 text-sm font-medium text-body transition-colors duration-(--dur-fast) hover:bg-inset"
                                @click="toggle"
                            >
                                <AppIcon name="store" :size="17" class="text-muted" />
                                <span class="truncate">Şube</span>
                                <AppIcon name="chevron-down" :size="14" class="text-subtle" />
                            </button>
                        </template>
                        <DropdownItem icon="store">Şube listesi buraya gelecek</DropdownItem>
                    </BaseDropdown>
                </slot>
            </div>

            <h1 v-if="title" class="hidden truncate text-sm font-semibold text-body sm:block">{{ title }}</h1>

            <div class="grow" />

            <!-- Şube saati: dakikada bir güncellenir; dar ekranda tarih gizli -->
            <div
                class="flex shrink-0 items-center text-sm select-none"
                :title="`Şube saati · ${branchTimezone}`"
            >
                <span class="hidden text-muted md:inline">{{ clockDate }}</span>
                <span class="hidden text-subtle md:inline" aria-hidden="true">&nbsp;·&nbsp;</span>
                <span class="font-bold text-body tabular-nums">{{ clockTime }}</span>
            </div>

            <slot name="topbar-actions" />

            <!-- Tema düğmesi -->
            <button
                type="button"
                class="flex size-10 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                :aria-label="theme === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç'"
                @click="toggleTheme"
            >
                <AppIcon :name="theme === 'dark' ? 'sun' : 'moon'" :size="18" />
            </button>

            <!-- Bildirim zili yeri (Notify modülü dolduracak) -->
            <slot name="notifications">
                <button
                    type="button"
                    class="relative flex size-10 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                    :aria-label="notificationCount ? `Bildirimler (${notificationCount} yeni)` : 'Bildirimler'"
                >
                    <AppIcon name="bell" :size="18" />
                    <span
                        v-if="notificationCount"
                        class="absolute top-1 right-1 flex min-w-4 items-center justify-center rounded-full bg-danger px-1 text-[10px] leading-4 font-bold text-on-status"
                        aria-hidden="true"
                    >
                        {{ notificationCount > 99 ? '99+' : notificationCount }}
                    </span>
                </button>
            </slot>

            <!-- Kullanıcı menüsü yeri (Identity modülü dolduracak) -->
            <slot name="user-menu">
                <BaseDropdown menu-label="Kullanıcı menüsü">
                    <template #trigger="{ toggle, ariaAttrs }">
                        <button
                            type="button"
                            v-bind="ariaAttrs"
                            class="flex size-10 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                            aria-label="Kullanıcı menüsü"
                            @click="toggle"
                        >
                            <span class="flex size-8 items-center justify-center rounded-full bg-inset">
                                <AppIcon name="user" :size="16" />
                            </span>
                        </button>
                    </template>
                    <DropdownItem icon="user">Profil</DropdownItem>
                    <DropdownItem icon="settings">Hesap ayarları</DropdownItem>
                    <DropdownItem icon="logout" danger>Çıkış yap</DropdownItem>
                </BaseDropdown>
            </slot>
        </header>

        <!-- ===== İçerik ===== -->
        <main id="icerik" class="p-4 pb-24 sm:p-6 lg:ml-60 lg:pb-6" tabindex="-1">
            <slot />
        </main>

        <!-- ===== Alt navigasyon (mobil) ===== -->
        <nav
            class="fixed inset-x-0 bottom-0 z-(--z-sticky) border-t border-default bg-surface pb-[env(safe-area-inset-bottom)] lg:hidden"
            aria-label="Ana menü (mobil)"
        >
            <ul class="flex">
                <li v-for="item in mobileItems" :key="item.key" class="min-w-0 flex-1">
                    <Link
                        :href="item.href"
                        class="flex min-h-14 flex-col items-center justify-center gap-0.5 px-1 text-[11px] font-medium"
                        :class="isActive(item) ? 'text-primary' : 'text-muted'"
                        :aria-current="isActive(item) ? 'page' : undefined"
                    >
                        <AppIcon :name="item.icon" :size="20" />
                        <span class="w-full truncate text-center">{{ item.label }}</span>
                    </Link>
                </li>
                <li class="min-w-0 flex-1">
                    <button
                        type="button"
                        class="flex min-h-14 w-full flex-col items-center justify-center gap-0.5 px-1 text-[11px] font-medium text-muted"
                        aria-label="Tüm menü"
                        @click="mobileNavOpen = true"
                    >
                        <AppIcon name="menu" :size="20" />
                        <span>Tümü</span>
                    </button>
                </li>
            </ul>
        </nav>

        <!-- Mobil tam menü çekmecesi -->
        <BaseDrawer :open="mobileNavOpen" title="Menü" @close="mobileNavOpen = false">
            <ul class="flex flex-col gap-0.5">
                <li v-for="item in navItems" :key="item.key">
                    <Link
                        :href="item.href"
                        class="flex min-h-12 items-center gap-3 rounded-md px-3 text-sm font-medium"
                        :class="isActive(item) ? 'bg-primary-soft text-primary' : 'text-body hover:bg-inset'"
                        @click="mobileNavOpen = false"
                    >
                        <AppIcon :name="item.icon" :size="20" />
                        {{ item.label }}
                    </Link>
                </li>
            </ul>
        </BaseDrawer>

        <ToastHost />
    </div>
</template>
