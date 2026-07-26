<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import { api } from '@/lib/http';
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
        /** Immersive (KDS/mutfak) mod: masaüstü kenar çubuğu VARSAYILAN kapalı
         *  gelir (tam genişlik). Siparişler & Kasa bunu true verir. */
        immersive?: boolean;
    }>(),
    { title: '', notificationCount: 0, immersive: false },
);

const page = usePage();
const { theme, toggleTheme } = useTheme();

/* ===== §13 Terminal KİLİTLİ MOD (kasa / sipariş-giriş / KDS cihazları) =====
 * is_terminal oturumda kenar çubuğu tamamen KAPALI + KİLİTLİ (toggle yok),
 * mobil alt-nav/çekmece gizli, başka sayfaya gidilemez. Üst barda "Terminal ·
 * {istasyon}" kilit rozeti + küçük "Personel değiştir / Çıkış" düğmesi
 * (impersonation DEĞİL → POST /terminal/logout ile terminal oturumu kapanır). */
const isTerminal = computed(() =>
    Boolean((page.props.auth as { is_terminal?: boolean } | null)?.is_terminal),
);

const terminalStationLabel = computed(() => {
    const key = (page.props.auth as { terminal_station?: string | null } | null)?.terminal_station ?? '';
    const map: Record<string, string> = {
        kasa: 'Kasa',
        order_entry: 'Sipariş Girişi',
        kitchen: 'Mutfak',
        barista: 'Barista',
        komi: 'Komi',
    };
    return map[key] ?? key;
});

const terminalLoggingOut = ref(false);

async function terminalLogout(): Promise<void> {
    if (terminalLoggingOut.value) return;
    terminalLoggingOut.value = true;
    try {
        // Terminal oturumunu kapatır (cihazda personel değişimi); redirect → /giris.
        await api('/terminal/logout', { method: 'POST' });
    } catch {
        /* oturum zaten düşmüş olabilir; her durumda giriş ekranına dön */
    }
    window.location.href = '/giris';
}

/** Rol bazlı süzgeç: auth.permissions sayfa prop'u (Çekirdek-Kimlik sağlayacak).
 *  Prop yoksa (henüz auth yok) tüm öğeler görünür. */
const permissions = computed<string[] | null>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
    return auth?.permissions ?? null;
});

/** §12 İstasyon-kapsamı: kullanıcının görebileceği istasyon aileleri
 *  (kitchen/barista). [] = kısıt yok (yönetici/çok-istasyonlu → hepsi).
 *  Prop yoksa (auth yok) null → süzme yapılmaz. */
const stations = computed<string[] | null>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { stations?: string[] } | undefined;
    return auth?.stations ?? null;
});

/** §9 Eklentiler/feature-flag: bu kiracıda açık OPSİYONEL özellikler {key:bool}.
 *  Prop yoksa (auth yok) null → feature süzmesi yapılmaz (eski davranış). */
const features = computed<Record<string, boolean> | null>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { features?: Record<string, boolean> } | undefined;
    return auth?.features ?? null;
});

const navItems = computed<NavItem[]>(() => {
    const items = props.nav ?? defaultNavigation;
    const perms = permissions.value;
    const userStations = stations.value;
    const feats = features.value;

    return items.filter((i) => {
        // 1) İzin süzgeci (perms yoksa hiç süzme — eski davranış korunur)
        if (perms && i.permission && !perms.includes(i.permission)) return false;

        // 2) İstasyon-kapsamı: öğe istasyon ailesi tanımlamışsa VE kullanıcı
        // KISITLIYSA (userStations dolu), yalnız kesişen aile görünür. Atanmamış/
        // yönetici (userStations boş [] ya da null) → kısıt yok, hepsini görür.
        if (i.stations && i.stations.length > 0 && userStations && userStations.length > 0
            && !i.stations.some((s) => userStations.includes(s))) {
            return false;
        }

        // 3) §9 Feature-flag: öğe opsiyonel özelliğe bağlıysa VE o özellik bu
        // kiracıda KAPALIYSA gizle (ADR: kapalı=yok). feats yoksa süzme.
        if (i.feature && feats && feats[i.feature] === false) return false;

        return true;
    });
});

const mobileItems = computed(() => navItems.value.filter((i) => i.mobile).slice(0, 4));
const mobileNavOpen = ref(false);

/* ===== Masaüstü kenar çubuğu daraltma (immersive KDS modu) =====
 * `immersive` sayfalar (Siparişler & Kasa) kenar çubuğunu VARSAYILAN kapalı
 * açar → içerik tam genişlik (büyük, ferah ekran). Diğer sayfalar açık gelir.
 * Kullanıcı üst bardaki menü düğmesiyle aç/kapatır; tercih (immersive olan/
 * olmayan bağlam için AYRI anahtar) localStorage'da tutulur ki varsayılanla
 * çakışmasın. Yalnız masaüstünü (lg) etkiler; mobil (alt nav + çekmece) aynı. */
const collapsed = ref(props.immersive);
const collapsePrefKey = computed(() => (props.immersive ? 'bhx-sidebar-immersive' : 'bhx-sidebar-normal'));

function toggleSidebar(): void {
    collapsed.value = !collapsed.value;
    try {
        localStorage.setItem(collapsePrefKey.value, collapsed.value ? '1' : '0');
    } catch {
        /* localStorage engelliyse tercih hatırlanmaz — sorun değil */
    }
}

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
    // İmmersive sayfalar (Siparişler/Kasa) HER girişte KAPALI başlar (kullanıcı
    // talebi): tercih HATIRLANMAZ → sayfaya tekrar girince sidebar oto-kapanır,
    // açmak manueldir. Yalnız normal sayfalarda daraltma tercihi geri yüklenir.
    // Terminal kilitli modda kenar çubuğu HER ZAMAN kapalı — tercih okunmaz.
    if (!props.immersive && !isTerminal.value) {
        try {
            const storedCollapse = localStorage.getItem(collapsePrefKey.value);
            if (storedCollapse !== null) collapsed.value = storedCollapse === '1';
        } catch {
            /* localStorage okunamıyorsa varsayılan geçerli */
        }
    }

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
        <!-- §13 Terminal kilitli modda kenar çubuğu HİÇ render edilmez. -->
        <aside
            v-if="!isTerminal"
            class="fixed inset-y-0 left-0 z-(--z-sticky) hidden w-60 flex-col border-r border-default bg-surface transition-transform duration-(--dur-normal) lg:flex"
            :class="collapsed ? 'lg:-translate-x-full' : 'lg:translate-x-0'"
            :inert="collapsed || undefined"
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
            class="sticky top-0 z-(--z-sticky) flex h-14 items-center gap-2 border-b border-default bg-surface px-3 transition-[margin] duration-(--dur-normal) sm:px-4"
            :class="isTerminal || collapsed ? 'lg:ml-0' : 'lg:ml-60'"
        >
            <!-- Kenar çubuğu aç/kapa (masaüstü). Kapalıyken içerik tam genişlik
                 olur; bu düğme sol üstte KALICI kalır ve çubuğu geri getirir.
                 Terminal kilitli modda TOGGLE YOK (nav kilitli). -->
            <button
                v-if="!isTerminal"
                type="button"
                class="hidden size-10 shrink-0 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body lg:flex"
                :aria-label="collapsed ? 'Menüyü aç' : 'Menüyü kapat'"
                :aria-pressed="!collapsed"
                @click="toggleSidebar"
            >
                <AppIcon :name="collapsed ? 'menu' : 'x'" :size="18" />
            </button>

            <!-- §13 Terminal kilit rozeti (kasa / sipariş-giriş / KDS cihazı) -->
            <span
                v-if="isTerminal"
                class="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-default bg-inset px-2.5 py-1 text-xs font-semibold text-muted"
                title="Bu cihaz istasyon terminaline kilitlidir"
            >
                <AppIcon name="tablet" :size="13" />
                Terminal · {{ terminalStationLabel }}
            </span>

            <!-- Şube değiştirici yeri: PanelShell doldurur (yönetici + çok-şube +
                 >1 şubede görünür). Tek şube / kilitli personel / terminalde HİÇ
                 gösterilmez — fallback yer-tutucu YOK (aksi halde tek şubede
                 "Şube listesi buraya gelecek" görünüyordu). -->
            <div v-if="!isTerminal" class="min-w-0">
                <slot name="branch-switcher" />
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

            <!-- Bildirim zili yeri (Notify modülü dolduracak) — terminalde gizli -->
            <template v-if="!isTerminal">
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
            </template>

            <!-- Kullanıcı menüsü yeri (Identity modülü dolduracak) — terminalde gizli -->
            <template v-if="!isTerminal">
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
            </template>

            <!-- §13 Terminal: kullanıcı menüsü YOK; küçük "Personel değiştir /
                 Çıkış" düğmesi (terminal oturumunu kapatır — impersonation değil). -->
            <button
                v-if="isTerminal"
                type="button"
                class="flex h-10 shrink-0 items-center gap-2 rounded-md border border-default px-3 text-sm font-medium text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body disabled:opacity-60"
                :disabled="terminalLoggingOut"
                aria-label="Personel değiştir veya çıkış"
                @click="terminalLogout"
            >
                <AppIcon name="logout" :size="16" />
                <span class="hidden sm:inline">Personel değiştir / Çıkış</span>
            </button>
        </header>

        <!-- ===== İçerik ===== -->
        <main
            id="icerik"
            class="p-4 pb-24 transition-[margin] duration-(--dur-normal) sm:p-6 lg:pb-6"
            :class="[isTerminal || collapsed ? 'lg:ml-0' : 'lg:ml-60', isTerminal ? 'pb-6' : '']"
            tabindex="-1"
        >
            <slot />
        </main>

        <!-- ===== Alt navigasyon (mobil) ===== — terminalde gizli (nav kilitli) -->
        <nav
            v-if="!isTerminal"
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

        <!-- Mobil tam menü çekmecesi — terminalde render edilmez (nav kilitli) -->
        <BaseDrawer v-if="!isTerminal" :open="mobileNavOpen" title="Menü" @close="mobileNavOpen = false">
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
