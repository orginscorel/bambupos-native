<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import type { NavItem } from '@/types/nav';
import { defaultNavigation } from '@/config/navigation';
import { useTheme } from '@/composables/useTheme';
import { useTerminalOperator, type TerminalStaffOption } from '@/composables/useTerminalOperator';
import { useTerminalHeartbeat } from '@/composables/useTerminalHeartbeat';
import { useTerminalIdleLock } from '@/composables/useTerminalIdleLock';
import AppIcon from '@/Components/ui/AppIcon.vue';
import CommandPalette from '@/Components/panel/CommandPalette.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import ToastHost from '@/Components/ui/ToastHost.vue';
import TerminalOperatorGate from '@/Components/panel/TerminalOperatorGate.vue';
import LockOverlay from '@/Components/panel/LockOverlay.vue';
import MobileTabBar from '@/Components/panel/MobileTabBar.vue';
import KdsIcon from '@/Pages/Panel/Kds/KdsIcon.vue';

const props = withDefaults(
    defineProps<{
        title?: string;
        nav?: NavItem[];
        /** Bildirim zili rozet sayısı (Notify modülü dolduracak) */
        notificationCount?: number;
        /** Immersive (KDS/mutfak) mod: masaüstü kenar çubuğu VARSAYILAN kapalı
         *  gelir (tam genişlik). Siparişler & Kasa bunu true verir. */
        immersive?: boolean;
        /** Tam kaplama: içerik alanının dolgusu kalkar, kaydırmayı sayfa yönetir. */
        flush?: boolean;
        /**
         * TUVAL MODU (Kasa/Siparişler dili): masaüstü kenar çubuğu HİÇ
         * çizilmez, gezinme üst çubuktaki menü düğmesinden açılan çekmeceye
         * taşınır ve içerik ekranın TAMAMINI kullanır. Kenar çubuğu her
         * ekranda 240px yiyordu; POS düzeninde bu alan içeriğe geçer.
         */
        canvas?: boolean;
    }>(),
    { title: '', notificationCount: 0, immersive: false, flush: false, canvas: false },
);

const page = usePage();
const { theme, toggleTheme } = useTheme();

/* ===== §13 Terminal KİLİTLİ MOD (kasa / sipariş-giriş / KDS cihazları) =====
 * is_terminal oturumda tam kenar çubuğu + mobil alt-nav/çekmece GİZLİ kalır
 * (sadeleştirilmiş cihaz kabuğu). ANCAK erişim modeli güncellendi: terminal
 * artık tek ekrana kilitli değil — üst barda yönetim-DIŞI operasyon ekranlarına
 * küçük bir geçiş nav'ı gösterilir (terminalNavItems) + "kendi istasyonuna dön"
 * rozeti. Yönetim/hassas öğeler gizli (sunucudaki EnsureTerminalLocked block-
 * list'iyle birebir). "Personel değiştir / Çıkış" düğmesi korunur (impersonation
 * DEĞİL → POST /terminal/logout ile terminal oturumu kapanır). */
const isTerminal = computed(() =>
    Boolean((page.props.auth as { is_terminal?: boolean } | null)?.is_terminal),
);

// Terminal cihazsa: last_seen_at'i canlı tut (panel "Çevrimiçi" rozeti doğru kalsın).
useTerminalHeartbeat();

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

/** §13 Terminalin KENDİ istasyon ekranı yolu (sunucudaki
 *  TerminalStation::screenFor karşılığı) — "kendi istasyonuna dön" düğmesi ve
 *  varsayılan açılış için. Bilinmeyen istasyon → genel panel. */
const terminalStationScreen = computed<string>(() => {
    const key = (page.props.auth as { terminal_station?: string | null } | null)?.terminal_station ?? '';
    const map: Record<string, string> = {
        kasa: '/panel/kasa',
        order_entry: '/panel/siparisler',
        kitchen: '/panel/mutfak',
        barista: '/panel/barista',
        komi: '/panel/komi',
    };
    return map[key] ?? '/panel';
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

/* Normal (terminal-olmayan) oturum çıkışı — Kullanıcı menüsü "Çıkış yap".
 * Aynı uç/desen PanelShell.vue ve PortalLayout.vue'de zaten kullanılıyor
 * (api('/api/v1/auth/logout') + /giris'e yönlendirme); DENETİM 2026-08-06
 * öncesi bu öğe placeholder'dı (tıklamanın hiçbir etkisi yoktu). */
const loggingOut = ref(false);
async function logout(): Promise<void> {
    if (loggingOut.value) return;
    loggingOut.value = true;
    try {
        await api('/api/v1/auth/logout', { method: 'POST' });
    } catch {
        /* oturum zaten düşmüş olabilir; her durumda giriş ekranına dön */
    }
    window.location.href = '/giris';
}

/* §13 Terminal modunda tam ekran — dört terminal ekranıyla (TerminalTopBar)
 * AYNI davranış (fullscreenchange dinlenir, Esc ile çıkışta ikon senkron kalır). */
const isFullscreen = ref(Boolean(document.fullscreenElement));
function toggleFullscreen(): void {
    if (document.fullscreenElement) {
        void document.exitFullscreen();
    } else {
        void document.documentElement.requestFullscreen?.();
    }
}
function onFsChange(): void {
    isFullscreen.value = Boolean(document.fullscreenElement);
}

/* ===== §13 Faz C: Aktif operatör (paylaşımlı cihazda "kim çalışıyor") =====
 * Kasa/sipariş-giriş cihazı GİZLİ bir kullanıcıyla çalışır; açılan adisyon /
 * alınan ödeme, kendini PIN'le aktif eden GERÇEK personele atfedilir. Üst
 * bardaki çip aktif operatörü gösterir; tıklayınca personel seçim + PIN modalı
 * açılır. Geçerli operatör sunucudan (auth prop) reaktif gelir. */
const { current: activeOperator, loadOperators, setOperator, clearOperator } = useTerminalOperator();

/* ===== §13 Faz D: Terminal OTOMATİK KİLİTLEME (boşta-kalma) =====
 * Yalnız AKTİF OPERATÖR varken izlenir — operatör yoksa zaten yukarıdaki
 * TerminalOperatorGate ekranı tam kilitliyor, ayrıca bir "boşta" kilidine
 * gerek yok (ve idle-timer'ın operatör-yokken biriken süresi gereksiz yere
 * ilk etkileşimde hemen kilit tetiklemesin). Süre terminal ayarından/
 * varsayılandan (~3 dk) composable içinde çözülür. #183: unlock TEK PIN'le
 * (LockOverlay), personel yeniden SEÇİLMEZ. */
const idleLockEnabled = computed(() => isTerminal.value && Boolean(activeOperator.value));
const { locked: idleLocked, unlock: unlockIdle } = useTerminalIdleLock({ enabled: idleLockEnabled });

const operatorModalOpen = ref(false);
const operatorList = ref<TerminalStaffOption[]>([]);
const operatorLoading = ref(false);
const operatorSubmitting = ref(false);
const operatorError = ref('');
const selectedStaffId = ref<number | null>(null);
const operatorPin = ref('');

const selectedStaffName = computed<string>(
    () => operatorList.value.find((o) => o.id === selectedStaffId.value)?.name ?? '',
);

async function openOperatorModal(): Promise<void> {
    operatorModalOpen.value = true;
    resetOperatorForm();
    operatorLoading.value = true;
    try {
        operatorList.value = await loadOperators();
    } catch (e) {
        operatorError.value = e instanceof ApiError ? e.displayMessage : 'Personel listesi alınamadı.';
    } finally {
        operatorLoading.value = false;
    }
}

function resetOperatorForm(): void {
    operatorError.value = '';
    selectedStaffId.value = null;
    operatorPin.value = '';
}

/** Bir personel seçilince PIN adımı görünür (aynı modalda). */
function selectStaff(id: number): void {
    selectedStaffId.value = id;
    operatorPin.value = '';
    operatorError.value = '';
}

async function submitOperator(): Promise<void> {
    if (selectedStaffId.value === null || !operatorPin.value || operatorSubmitting.value) return;
    operatorSubmitting.value = true;
    operatorError.value = '';
    try {
        await setOperator(selectedStaffId.value, operatorPin.value);
        operatorModalOpen.value = false;
    } catch (e) {
        operatorError.value = e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.';
    } finally {
        operatorSubmitting.value = false;
    }
}

/** PIN adımından personel listesine geri dön. */
function backToStaffList(): void {
    selectedStaffId.value = null;
    operatorPin.value = '';
    operatorError.value = '';
}

async function clearActiveOperator(): Promise<void> {
    try {
        await clearOperator();
        operatorModalOpen.value = false;
    } catch {
        /* oturum düşmüş olabilir; sessizce geç */
    }
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

/* ===== Native alt sekme çubuğu yerleşimi =====
 * FAB = ana operasyon (masa panosu / QR). Çubukta: 2 sol sekme · FAB · 1 sağ
 * sekme · "Tümü". FAB hedefi izinliyse öğe listesinden çıkarılır (yinelenmesin);
 * izin yoksa FAB gösterilmez ve o slot sekmeye döner. */
const mobileItems = computed(() => navItems.value.filter((i) => i.mobile));

const fabConfig = computed<{ href: string; icon: string; label: string } | null>(() => {
    const target = mobileItems.value.find((i) => i.key === 'tables');
    return target ? { href: target.href, icon: 'qr-code', label: 'Masalar' } : null;
});

/** FAB hedefi hariç mobil öğeler (yinelenmesin). */
const tabItems = computed<NavItem[]>(() =>
    fabConfig.value ? mobileItems.value.filter((i) => i.key !== 'tables') : mobileItems.value,
);
const tabLeftItems = computed<NavItem[]>(() => tabItems.value.slice(0, 2));
const tabRightItems = computed<NavItem[]>(() => tabItems.value.slice(2, fabConfig.value ? 3 : 4));

const mobileNavOpen = ref(false);

/** Kenar çubuğunu bölüm başlıklarına göre grupla (ardışık aynı `group`). */
const navGroups = computed<{ label: string | null; items: NavItem[] }[]>(() => {
    const groups: { label: string | null; items: NavItem[] }[] = [];
    for (const item of navItems.value) {
        const g = item.group ?? null;
        const last = groups[groups.length - 1];
        if (last && last.label === g) {
            last.items.push(item);
        } else {
            groups.push({ label: g, items: [item] });
        }
    }
    return groups;
});

/* ===== §13 Terminal OPERASYON nav'ı (kilitli mod, güncellenmiş erişim modeli)
 * Terminal artık tek ekrana kilitli DEĞİL: sahip olduğu izinlere karşılık gelen
 * YÖNETİM-DIŞI operasyon ekranlarına gidebilir. navItems zaten izin + istasyon-
 * kapsamı + feature süzer; burada EK olarak YÖNETİM/hassas öğeleri gizleriz —
 * sunucudaki EnsureTerminalLocked block-list'iyle birebir (Ayarlar, Personel,
 * Roller, Raporlar, BOSS, Entegrasyonlar, Prim, Şubeler, Vardiya, Kiosk,
 * Terminaller + genel Panel/dashboard). Kendi istasyon ekranı ayrı "ev"
 * düğmesiyle sunulur → nav çiplerinden çıkarılır (yinelenmesin). */
const terminalHiddenGroups = new Set<string>([
    'Personel & Yönetim',
    'Cihazlar & Entegrasyonlar',
    'Sistem',
    // Terminal SIZINTISI kapatıldı: menü/rezervasyon + stok/finans terminalde
    // görünmez (yönetim işleri). (Sunucudaki EnsureTerminalLocked ile birlikte.)
    'Menü & Rezervasyon',
    'Stok & Finans',
]);
const terminalHiddenKeys = new Set<string>([
    'dashboard', 'boss', 'reports', 'commission',
    // Grup adı değişse bile kilit kalsın diye anahtarlar da açıkça listelenir.
    'catalog', 'reservations', 'inventory', 'receivables',
]);

const terminalNavItems = computed<NavItem[]>(() =>
    navItems.value.filter(
        (i) =>
            !terminalHiddenKeys.has(i.key) &&
            !(i.group !== undefined && terminalHiddenGroups.has(i.group)) &&
            i.href !== terminalStationScreen.value,
    ),
);

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

/* ===== Masaüstü ikon-only RAY (rail) modu =====
 * `collapsed` (immersive tam-genişlik GİZLEME) davranışından BAĞIMSIZ ikinci
 * bir daraltma: kenar çubuğu görünürken tam genişlik (w-60) ⇄ yalnız-ikon ray
 * (w-16; etiketler tooltip'e düşer). Ray, kenar çubuğunu gizlemez — yalnız
 * daraltır; böylece collapsed'ın immersive tam-ekran ihtiyacı bozulmaz.
 * Tercih AYRI anahtarda tutulur. */
const rail = ref(false);
const RAIL_PREF_KEY = 'bhx-sidebar-rail';

function toggleRail(): void {
    rail.value = !rail.value;
    try {
        localStorage.setItem(RAIL_PREF_KEY, rail.value ? '1' : '0');
    } catch {
        /* localStorage engelliyse tercih hatırlanmaz */
    }
}

/* ===== Komut paleti (⌘K / Ctrl+K) =====
 * Üst bardaki "Ara…" düğmesi (masaüstü + mobil ikon) ve kısayol aynı
 * paleti açar; palet yalnız `navItems`'ı (izin/istasyon/feature zaten
 * süzülmüş) sorguya göre filtreler — tam varlık-arama değildir.
 * Terminal kilitli modda arama UI'ı hiç render edilmediği için kısayol da
 * orada devre dışı bırakılır. */
const globalSearch = ref<HTMLButtonElement | null>(null);
const commandPaletteOpen = ref(false);

function onGlobalSearchKey(e: KeyboardEvent): void {
    if (isTerminal.value) return;
    if ((e.metaKey || e.ctrlKey) && (e.key === 'k' || e.key === 'K')) {
        e.preventDefault();
        commandPaletteOpen.value = true;
    }
}

/** İçerik/üst bar sol boşluğu: terminal veya gizli kenar çubuğu → 0;
 *  ray → 4rem; tam → 15rem. (Yalnız masaüstü/lg; mobilde her zaman 0.) */
const shellMargin = computed<string>(() => {
    if (props.canvas || isTerminal.value || collapsed.value) return 'lg:ml-0';
    return rail.value ? 'lg:ml-16' : 'lg:ml-60';
});

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

    // Ray (ikon-only) tercihi — terminal-dışı, kenar çubuğu görünür sayfalarda.
    if (!isTerminal.value) {
        try {
            const storedRail = localStorage.getItem(RAIL_PREF_KEY);
            if (storedRail !== null) rail.value = storedRail === '1';
        } catch {
            /* varsayılan geçerli */
        }
    }

    window.addEventListener('keydown', onGlobalSearchKey);

    const epoch = Number(document.querySelector('meta[name="app-server-epoch"]')?.getAttribute('content'));
    if (Number.isFinite(epoch)) serverOffsetMs.value = epoch - Date.now();
    syncClock();
    scheduleClockTick();
    document.addEventListener('visibilitychange', onClockVisibility);
    document.addEventListener('fullscreenchange', onFsChange);
});

onBeforeUnmount(() => {
    if (clockTimer) clearTimeout(clockTimer);
    document.removeEventListener('visibilitychange', onClockVisibility);
    window.removeEventListener('keydown', onGlobalSearchKey);
    document.removeEventListener('fullscreenchange', onFsChange);
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
    <!-- TAM EKRAN UYGULAMA KABUĞU.
         Panel eskiden normal bir web sayfası gibi belge kaydırmasıyla
         çalışıyordu: uzun listelerde üst çubuk yukarı kaçıyor, tarayıcı
         kaydırma çubuğu tüm ekranı kaplıyor, mobilde adres çubuğu açılıp
         kapandıkça yerleşim zıplıyordu. Terminal ekranları (Mutfak/Kasa/
         Siparişler) zaten tam ekran kabukla çalışıyordu ve belirgin biçimde
         daha "uygulama" gibi duruyordu.
         Artık TÜM panel aynı kabukta: kabuk viewport'a sabitlenir, üst çubuk
         ve menü hep yerinde kalır, YALNIZ içerik kendi içinde kayar. -->
    <div class="panel-canvas fixed inset-0 flex flex-col overflow-hidden">
        <a
            href="#icerik"
            class="sr-only rounded-md bg-primary px-3 py-2 text-sm font-medium text-on-primary focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-(--z-toast)"
        >
            İçeriğe atla
        </a>

        <!-- ===== Sol menü (masaüstü) ===== -->
        <!-- §13 Terminal kilitli modda kenar çubuğu HİÇ render edilmez.
             Ray (w-16 = 4rem) ⇄ tam (w-60); collapsed → tamamen gizli (immersive).
             Genişlik shellMargin (lg:ml-16 / lg:ml-60) ile BİREBİR eşleşmeli. -->
        <aside
            v-if="!isTerminal && !canvas"
            class="fixed inset-y-0 left-0 z-(--z-sticky) hidden flex-col border-r border-default bg-surface transition-[transform,width] duration-(--dur-normal) lg:flex"
            :class="[
                collapsed ? 'lg:-translate-x-full' : 'lg:translate-x-0',
                rail ? 'w-16' : 'w-60',
            ]"
            :inert="collapsed || undefined"
            aria-label="Ana menü"
        >
            <!-- Marka bloğu -->
            <div
                class="flex h-14 shrink-0 items-center border-b border-default"
                :class="rail ? 'justify-center px-0' : 'gap-2.5 px-4'"
            >
                <span class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary text-on-primary shadow-card">
                    <AppIcon name="qr-code" :size="19" />
                </span>
                <span v-if="!rail" class="flex min-w-0 flex-col leading-tight">
                    <span class="truncate text-sm font-semibold text-body">
                        <slot name="brand">QR Menü</slot>
                    </span>
                    <span class="truncate text-[11px] font-medium text-subtle">Yönetim Paneli</span>
                </span>
            </div>

            <!-- İşletme / şube seçici alanı — belirgin, kenar çubuğu üstünde.
                 İçerik PanelShell'in #branch-switcher slot'undan gelir; switcher
                 yoksa (tek şube/kilitli) hiç DOM üretmez → boş alan oluşmaz.
                 Ray modunda gizli (dropdown dar rayda sığmaz; genişletince gelir). -->
            <div v-if="!rail" class="contents"><slot name="branch-switcher" /></div>

            <nav class="grow overflow-x-hidden overflow-y-auto py-2" :class="rail ? 'px-2' : 'px-3'" aria-label="Bölümler">
                <template v-for="(grp, gi) in navGroups" :key="gi">
                    <!-- Tam: bölüm başlığı ince ritimle. Ray: yalnız ayraç. -->
                    <p
                        v-if="grp.label && !rail"
                        class="px-2 pt-5 pb-1.5 text-[11px] font-semibold tracking-wider text-subtle uppercase first:pt-1"
                    >
                        {{ grp.label }}
                    </p>
                    <div
                        v-else-if="grp.label && rail"
                        class="mx-auto my-2 h-px w-6 bg-default first:hidden"
                        aria-hidden="true"
                    />
                    <ul class="flex flex-col gap-0.5">
                        <li v-for="item in grp.items" :key="item.key">
                            <Link
                                :href="item.href"
                                :title="rail ? item.label : undefined"
                                class="group relative flex h-10 items-center rounded-lg font-medium transition-colors duration-(--dur-fast)"
                                :class="[
                                    rail ? 'justify-center px-0' : 'gap-3 pr-2.5 pl-3',
                                    isActive(item)
                                        ? 'bg-primary-soft text-primary'
                                        : 'text-muted hover:bg-inset hover:text-body',
                                ]"
                                :aria-current="isActive(item) ? 'page' : undefined"
                            >
                                <!-- Aktif sol accent bar (mavi) -->
                                <span
                                    v-if="isActive(item)"
                                    class="absolute top-1/2 left-0 h-5 w-1 -translate-y-1/2 rounded-r-full bg-primary"
                                    aria-hidden="true"
                                />
                                <!-- Sabit-genişlik ikon kutusu → tüm ikonlar hizalı -->
                                <span class="relative flex size-5 shrink-0 items-center justify-center">
                                    <AppIcon :name="item.icon" :size="18" />
                                    <!-- Ray modunda rozet → küçük nokta -->
                                    <span
                                        v-if="item.badge && rail"
                                        class="absolute -top-1 -right-1 size-2 rounded-full bg-primary ring-2 ring-surface"
                                        aria-hidden="true"
                                    />
                                </span>
                                <template v-if="!rail">
                                    <span class="min-w-0 grow truncate text-sm">{{ item.label }}</span>
                                    <span
                                        v-if="item.badge"
                                        class="shrink-0 rounded-full bg-primary px-1.5 py-0.5 text-[11px] leading-none font-semibold text-on-primary tabular-nums"
                                    >
                                        {{ item.badge }}
                                    </span>
                                </template>
                            </Link>
                        </li>
                    </ul>
                </template>
            </nav>

            <!-- Alt: (tam) sürüm/işletme rozetleri slot'u + ray daralt düğmesi -->
            <div class="shrink-0 border-t border-default" :class="rail ? 'p-2' : 'p-3'">
                <div v-if="!rail" class="mb-2 text-xs text-subtle">
                    <slot name="sidebar-footer" />
                </div>
                <button
                    type="button"
                    class="flex h-9 items-center rounded-lg text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                    :class="rail ? 'w-full justify-center px-0' : 'w-full gap-2.5 px-2.5'"
                    :title="rail ? 'Menüyü genişlet' : undefined"
                    :aria-label="rail ? 'Menüyü genişlet' : 'Menüyü daralt'"
                    :aria-pressed="rail"
                    @click="toggleRail"
                >
                    <span class="flex size-5 shrink-0 items-center justify-center">
                        <AppIcon :name="rail ? 'chevron-right' : 'chevron-left'" :size="18" />
                    </span>
                    <span v-if="!rail" class="text-xs font-medium">Menüyü daralt</span>
                </button>
            </div>
        </aside>

        <!-- ===== Üst çubuk ===== -->
        <header
            class="z-(--z-sticky) flex h-14 shrink-0 items-center gap-1.5 border-b border-default bg-surface px-3 shadow-[0_6px_16px_-14px_rgba(0,0,0,0.6)] transition-[margin] duration-(--dur-normal) sm:px-4"
            :class="shellMargin"
        >
            <!-- Kenar çubuğu aç/kapa (masaüstü). Kapalıyken içerik tam genişlik
                 olur; bu düğme sol üstte KALICI kalır ve çubuğu geri getirir.
                 Terminal kilitli modda TOGGLE YOK (nav kilitli). -->
            <!-- Tuval modunda kenar çubuğu yoktur → menü ÇEKMECEDEN açılır
                 (Kasa/Siparişler ekranlarındaki desenle aynı). -->
            <button
                v-if="!isTerminal && canvas"
                type="button"
                class="flex size-11 shrink-0 items-center justify-center rounded-lg text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                aria-label="Menüyü aç"
                @click="mobileNavOpen = true"
            >
                <AppIcon name="menu" :size="18" />
            </button>

            <button
                v-else-if="!isTerminal"
                type="button"
                class="hidden size-11 shrink-0 items-center justify-center rounded-lg text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body lg:flex"
                :aria-label="collapsed ? 'Menüyü aç' : 'Menüyü kapat'"
                :aria-pressed="!collapsed"
                @click="toggleSidebar"
            >
                <AppIcon :name="collapsed ? 'menu' : 'x'" :size="18" />
            </button>

            <!-- §13 Terminal erişim çubuğu (güncellenmiş model): kendi istasyonuna
                 dön düğmesi (rozet) + yönetim-DIŞI operasyon ekranları nav'ı.
                 Yönetim öğeleri gizli; nav çipleri izin + istasyon-kapsamı +
                 feature ile zaten süzülür (terminalNavItems). -->
            <template v-if="isTerminal">
                <!-- Kendi istasyon ekranına dön (varsayılan/ana ekran) -->
                <Link
                    :href="terminalStationScreen"
                    class="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-default bg-inset px-2.5 py-1 text-xs font-semibold text-muted transition-colors duration-(--dur-fast) hover:bg-primary-soft hover:text-primary"
                    title="Kendi istasyon ekranına dön"
                    aria-label="Kendi istasyon ekranına dön"
                >
                    <AppIcon name="tablet" :size="13" />
                    <span>Terminal · {{ terminalStationLabel }}</span>
                </Link>

                <!-- §13 Faz C AKTİF OPERATÖR çipi buradan KALDIRILDI (denetim 2026-08-06,
                     header konsolidasyonu) — artık sağ uçtaki TEK hesap/operatör
                     dropdown'unda (operatör adı + Personel değiştir + Çıkış). Operatör
                     yokken zaten TerminalOperatorGate tüm ekranı örter; bu chip'in
                     "Personel Seç" uyarısı orada zaten zorunlu adım olarak sunulur. -->

                <!-- Erişilebilir operasyon ekranları (yönetim-dışı) — yatay kaydır -->
                <nav
                    v-if="terminalNavItems.length"
                    class="flex min-w-0 items-center gap-1 overflow-x-auto"
                    aria-label="Terminal operasyon menüsü"
                >
                    <Link
                        v-for="item in terminalNavItems"
                        :key="item.key"
                        :href="item.href"
                        class="flex h-8 shrink-0 items-center gap-1.5 rounded-md px-2.5 text-xs font-medium transition-colors duration-(--dur-fast)"
                        :class="
                            isActive(item)
                                ? 'bg-primary-soft text-primary'
                                : 'text-muted hover:bg-inset hover:text-body'
                        "
                        :aria-current="isActive(item) ? 'page' : undefined"
                    >
                        <AppIcon :name="item.icon" :size="15" />
                        <span class="whitespace-nowrap">{{ item.label }}</span>
                    </Link>
                </nav>
            </template>

            <!-- Sol: MARKA + sayfa bağlamı.
                 Panel ile terminal ekranlarının (Kasa/Siparişler/Mutfak/Komi)
                 başlıkları farklı duruyordu: birinde marka bloğu vardı,
                 diğerinde yalnız düz bir sayfa adı. Artık İKİSİ DE aynı:
                 marka karesi + "BamBumPOS" + altında sayfa adı. -->
            <Link
                v-if="!isTerminal"
                href="/panel"
                class="flex min-w-0 items-center gap-2 rounded-lg pe-1 transition-colors duration-(--dur-fast) hover:bg-inset"
                title="Panele dön"
            >
                <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary text-on-primary shadow-sm ring-1 ring-black/5">
                    <AppIcon name="qr-code" :size="17" />
                </span>
                <span class="min-w-0 leading-tight">
                    <span class="block truncate text-[13px] font-extrabold tracking-tight text-body">BamBumPOS</span>
                    <span v-if="title" class="block truncate text-[10.5px] font-semibold uppercase tracking-wide text-muted">{{ title }}</span>
                </span>
            </Link>

            <!-- Orta: komut paleti tetikleyici (⌘K). -->
            <div v-if="!isTerminal" class="flex min-w-0 grow items-center justify-center px-1 sm:px-2">
                <button
                    ref="globalSearch"
                    type="button"
                    class="hidden h-10 w-full max-w-md items-center gap-2 rounded-lg border border-default bg-inset px-3 text-sm text-subtle transition-colors duration-(--dur-fast) hover:border-strong hover:text-muted sm:flex"
                    aria-label="Ara (Ctrl+K veya ⌘K)"
                    aria-keyshortcuts="Meta+K Control+K"
                    @click="commandPaletteOpen = true"
                >
                    <AppIcon name="search" :size="16" />
                    <span class="grow truncate text-left">Ara…</span>
                    <kbd class="hidden shrink-0 items-center rounded border border-default bg-surface px-1.5 py-0.5 text-[11px] leading-none font-medium text-subtle md:inline-flex">
                        ⌘K
                    </kbd>
                </button>
            </div>
            <!-- Terminal: sağ kümeyi hizalamak için esnek boşluk -->
            <div v-else class="grow" />

            <!-- Mobil arama ikonu (dar ekran, terminal-dışı) -->
            <button
                v-if="!isTerminal"
                type="button"
                class="flex size-11 shrink-0 items-center justify-center rounded-lg text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body sm:hidden"
                aria-label="Ara"
                @click="commandPaletteOpen = true"
            >
                <AppIcon name="search" :size="18" />
            </button>

            <!-- Aktif vardiya / bağlantı göstergesi (yer tutucu; modül dolduracak) -->
            <slot name="shift-status">
                <span
                    v-if="!isTerminal"
                    class="hidden items-center gap-1.5 rounded-full border border-default bg-inset px-2.5 py-1 text-xs font-medium text-muted xl:inline-flex"
                    title="Bağlantı durumu"
                >
                    <span class="size-1.5 rounded-full bg-success" aria-hidden="true" />
                    Çevrimiçi
                </span>
            </slot>

            <!-- Şube saati: dakikada bir güncellenir; dar ekranda tarih gizli -->
            <div
                class="flex shrink-0 items-center text-sm select-none"
                :title="`Şube saati · ${branchTimezone}`"
            >
                <span class="hidden text-muted md:inline">{{ clockDate }}</span>
                <span class="hidden text-subtle md:inline" aria-hidden="true">&nbsp;·&nbsp;</span>
                <span class="font-bold text-body tabular-nums">{{ clockTime }}</span>
            </div>

            <!-- Hızlı işlem alanı (sayfa doldurur) -->
            <slot name="topbar-actions" />

            <!-- Tema düğmesi -->
            <button
                type="button"
                class="flex size-11 shrink-0 items-center justify-center rounded-lg text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                :aria-label="theme === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç'"
                @click="toggleTheme"
            >
                <AppIcon :name="theme === 'dark' ? 'sun' : 'moon'" :size="18" />
            </button>

            <!-- Tam ekran (yalnız terminal — dört terminal ekranıyla AYNI dil) -->
            <button
                v-if="isTerminal"
                type="button"
                class="flex size-11 shrink-0 items-center justify-center rounded-lg text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                :aria-label="isFullscreen ? 'Tam ekrandan çık' : 'Tam ekran'"
                @click="toggleFullscreen"
            >
                <KdsIcon :name="isFullscreen ? 'compress' : 'expand'" :size="18" />
            </button>

            <!-- Bildirim zili yeri (Notify modülü dolduracak) — terminalde gizli -->
            <template v-if="!isTerminal">
                <slot name="notifications">
                    <button
                        type="button"
                        class="relative flex size-11 shrink-0 items-center justify-center rounded-lg text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                        :aria-label="notificationCount ? `Bildirimler (${notificationCount} yeni)` : 'Bildirimler'"
                    >
                        <AppIcon name="bell" :size="18" />
                        <span
                            v-if="notificationCount"
                            class="absolute top-1.5 right-1.5 flex min-w-4 items-center justify-center rounded-full bg-danger px-1 text-[10px] leading-4 font-bold text-on-status"
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
                                class="flex size-11 shrink-0 items-center justify-center rounded-lg text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
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
                        <DropdownItem icon="logout" danger :disabled="loggingOut" @select="logout">Çıkış yap</DropdownItem>
                    </BaseDropdown>
                </slot>
            </template>

            <!-- §13 Terminal: TEK hesap/operatör menüsü (denetim 2026-08-06 —
                 önceden AYRI bir operatör çipi + AYRI bir "Personel değiştir /
                 Çıkış" düğmesi vardı; artık dört terminal ekranıyla (KDS/Kasa/
                 Sipariş-Girişi) AYNI dropdown deseni: operatör adı + Personel
                 değiştir (zengin modal — belirli bir personeli PIN'le doğrudan
                 aktif eder) + Çıkış (POST /terminal/logout). Backend uçları
                 DEĞİŞMEDİ, yalnız tek yere taşındı. -->
            <BaseDropdown v-if="isTerminal" menu-label="Hesap / operatör menüsü">
                <template #trigger="{ toggle, ariaAttrs }">
                    <button
                        type="button"
                        v-bind="ariaAttrs"
                        class="flex h-9 shrink-0 items-center gap-1.5 rounded-full border border-default bg-inset pr-2.5 pl-1 text-xs font-semibold text-body transition-colors duration-(--dur-fast) hover:bg-primary-soft hover:text-primary"
                        :aria-label="activeOperator ? `Hesap menüsü · ${activeOperator.name}` : 'Hesap menüsü · Personel Seç'"
                        @click="toggle"
                    >
                        <span
                            class="flex size-7 shrink-0 items-center justify-center rounded-full"
                            :class="activeOperator ? 'bg-primary-soft text-primary' : 'bg-warning-soft text-warning'"
                        >
                            <AppIcon :name="activeOperator ? 'user' : 'users'" :size="14" />
                        </span>
                        <span class="hidden max-w-28 truncate sm:inline">{{ activeOperator?.name ?? 'Personel Seç' }}</span>
                        <AppIcon name="chevron-down" :size="13" class="shrink-0 text-subtle" />
                    </button>
                </template>

                <div class="border-b border-default px-3 py-2">
                    <p class="truncate text-sm font-bold text-body">{{ activeOperator?.name ?? 'Personel seçilmedi' }}</p>
                    <p class="truncate text-[11px] text-muted">Terminal · {{ terminalStationLabel }}</p>
                </div>

                <DropdownItem icon="users" @select="openOperatorModal">Personel değiştir</DropdownItem>
                <DropdownItem icon="logout" danger :disabled="terminalLoggingOut" @select="terminalLogout">Çıkış</DropdownItem>
            </BaseDropdown>
        </header>

        <!-- ===== İçerik ===== -->
        <!-- Kaydırılan TEK alan burasıdır (belge değil): üst çubuk ve kenar
             çubuğu sabit kalır, uzun listelerde bile kaybolmaz. -->
        <main
            id="icerik"
            class="min-h-0 flex-1 transition-[margin] duration-(--dur-normal)"
            :class="[
                shellMargin,
                flush
                    ? 'flex flex-col overflow-hidden'
                    : ['overflow-y-auto overscroll-contain p-4 pb-24 sm:p-6 lg:pb-6', isTerminal ? 'pb-6' : ''],
            ]"
            tabindex="-1"
        >
            <!-- Faz 5: sayfa yolu değişince yumuşak beliriş (query değişimi tetiklemez;
                 reduced-motion'da global olarak kapalı). Tam kaplamada animasyon
                 sarmalayıcısı da esner ki sayfa yüksekliği devralabilsin. -->
            <div
                :key="(page.url || '').split('?')[0]"
                class="animate-rise"
                :class="flush ? 'flex min-h-0 flex-1 flex-col' : ''"
            >
                <slot />
            </div>
        </main>

        <!-- ===== Alt navigasyon (mobil) ===== — terminalde gizli (nav kilitli).
             Native sekme çubuğu: 2 sol sekme · FAB (masa/QR) · 1 sağ sekme · Tümü. -->
        <MobileTabBar
            v-if="!isTerminal"
            :left-items="tabLeftItems"
            :right-items="tabRightItems"
            :fab="fabConfig"
            :active="isActive"
            @menu="mobileNavOpen = true"
        />

        <!-- Mobil tam menü çekmecesi — terminalde render edilmez (nav kilitli) -->
        <!-- Ana menü SOLDAN açılır: menü her zaman solda durur; sağdan gelmesi
             (özellikle tuval modunda, kenar çubuğu yokken) yön duygusunu bozuyordu. -->
        <BaseDrawer v-if="!isTerminal" :open="mobileNavOpen" title="Menü" side="left" @close="mobileNavOpen = false">
            <!-- İşletme / şube seçici (mobil) — masaüstü kenar çubuğunun karşılığı.
                 Switcher yoksa hiç DOM üretmez (contents sarmalayıcı → boşluk yok). -->
            <div class="contents"><slot name="branch-switcher" /></div>
            <template v-for="(grp, gi) in navGroups" :key="gi">
                <p
                    v-if="grp.label"
                    class="px-2 pt-4 pb-1.5 text-[11px] font-semibold tracking-wider text-subtle uppercase first:pt-0"
                >
                    {{ grp.label }}
                </p>
                <ul class="mb-1 flex flex-col gap-0.5">
                    <li v-for="item in grp.items" :key="item.key">
                        <Link
                            :href="item.href"
                            class="relative flex min-h-12 items-center gap-3 rounded-lg pr-2.5 pl-3 text-sm font-medium"
                            :class="isActive(item) ? 'bg-primary-soft text-primary' : 'text-body hover:bg-inset'"
                            @click="mobileNavOpen = false"
                        >
                            <span
                                v-if="isActive(item)"
                                class="absolute top-1/2 left-0 h-5 w-1 -translate-y-1/2 rounded-r-full bg-primary"
                                aria-hidden="true"
                            />
                            <span class="flex size-5 shrink-0 items-center justify-center">
                                <AppIcon :name="item.icon" :size="20" />
                            </span>
                            <span class="min-w-0 grow truncate">{{ item.label }}</span>
                            <span
                                v-if="item.badge"
                                class="shrink-0 rounded-full bg-primary px-1.5 py-0.5 text-[11px] leading-none font-semibold text-on-primary tabular-nums"
                            >
                                {{ item.badge }}
                            </span>
                        </Link>
                    </li>
                </ul>
            </template>
        </BaseDrawer>

        <!-- §13 Faz C: Aktif operatör seçim + PIN modalı (paylaşımlı terminal) -->
        <BaseModal
            :open="operatorModalOpen"
            title="Aktif personel"
            size="sm"
            @close="operatorModalOpen = false"
        >
            <p class="mb-3 text-sm text-muted">
                Bu cihazdan açılan sipariş ve alınan ödeme seçtiğiniz personele atfedilir.
                Devam etmek için personelinizi seçip PIN'inizi girin.
            </p>

            <p v-if="operatorLoading" class="py-6 text-center text-sm text-muted">Yükleniyor…</p>

            <!-- Adım 1: personel listesi -->
            <ul v-else-if="selectedStaffId === null" class="flex flex-col gap-1">
                <li v-if="!operatorList.length" class="py-4 text-center text-sm text-muted">
                    Bu şubede seçilebilir personel yok.
                </li>
                <li v-for="op in operatorList" :key="op.id">
                    <button
                        type="button"
                        class="flex min-h-11 w-full items-center gap-3 rounded-md border border-default px-3 text-left text-sm font-medium text-body transition-colors duration-(--dur-fast) hover:bg-primary-soft hover:text-primary"
                        @click="selectStaff(op.id)"
                    >
                        <AppIcon name="user" :size="16" />
                        <span class="min-w-0 grow truncate">{{ op.name }}</span>
                        <span v-if="op.position" class="shrink-0 text-xs text-muted">{{ op.position }}</span>
                    </button>
                </li>
            </ul>

            <!-- Adım 2: seçilen personel için PIN -->
            <form v-else class="flex flex-col gap-3" @submit.prevent="submitOperator">
                <button
                    type="button"
                    class="inline-flex items-center gap-1 self-start text-xs font-medium text-muted hover:text-body"
                    @click="backToStaffList"
                >
                    <AppIcon name="chevron-left" :size="14" /> Personel listesi
                </button>

                <p class="text-sm text-body">
                    <span class="font-semibold">{{ selectedStaffName }}</span> için PIN girin:
                </p>

                <input
                    v-model="operatorPin"
                    type="password"
                    inputmode="numeric"
                    autocomplete="off"
                    placeholder="PIN"
                    class="min-h-11 rounded-md border border-default bg-surface px-3 text-base text-body outline-none focus:border-primary"
                    :aria-invalid="operatorError ? 'true' : undefined"
                />

                <p v-if="operatorError" class="text-sm text-danger">{{ operatorError }}</p>
            </form>

            <template #footer>
                <button
                    v-if="activeOperator"
                    type="button"
                    class="mr-auto inline-flex min-h-11 items-center rounded-md px-3 text-sm font-medium text-danger hover:bg-danger-soft"
                    @click="clearActiveOperator"
                >
                    Aktif personeli kaldır
                </button>
                <button
                    type="button"
                    class="inline-flex min-h-11 items-center rounded-md border border-default px-4 text-sm font-medium text-body hover:bg-inset"
                    @click="operatorModalOpen = false"
                >
                    İptal
                </button>
                <button
                    v-if="selectedStaffId !== null"
                    type="button"
                    class="inline-flex min-h-11 items-center rounded-md bg-primary px-4 text-sm font-semibold text-on-primary hover:bg-primary-hover disabled:opacity-60"
                    :disabled="!operatorPin || operatorSubmitting"
                    @click="submitOperator"
                >
                    {{ operatorSubmitting ? 'Doğrulanıyor…' : 'Aktif et' }}
                </button>
            </template>
        </BaseModal>

        <!-- Terminalde: zorunlu personel giriş gate'i + personel barı -->
        <TerminalOperatorGate />

        <!-- §13 Faz D: boşta-kalma sonrası ekran kilidi (yalnız aktif operatör
             varken; personel gate'in ÜSTÜNE değil, YERİNE geçer — operatör
             yoksa zaten TerminalOperatorGate tam kilitliyor). -->
        <LockOverlay v-if="idleLocked" @unlocked="unlockIdle" />

        <!-- Komut paleti (⌘K): navItems zaten izin/istasyon/feature süzülmüş. -->
        <CommandPalette v-if="!isTerminal" v-model:open="commandPaletteOpen" :items="navItems" />

        <ToastHost />
    </div>
</template>

<style scoped>
/*
 * Zemin: KDS/Kasa/Siparişler tam ekran ekranlarıyla BİREBİR aynı katmanlı
 * yüzey — --ui-surface-alt üstünde çok hafif üstten ışık düşümü. Böylece
 * panelin geri kalanı da o ekranlarla aynı görsel dile oturur.
 */
.panel-canvas {
    background-color: var(--ui-surface-alt);
    background-image: radial-gradient(1200px 640px at 50% -12%, rgb(255 255 255 / 0.035), transparent 60%);
}
</style>
