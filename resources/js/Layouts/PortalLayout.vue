<script setup lang="ts">
/**
 * Personel Portalı layout — mobil-öncelikli, kurulabilir PWA.
 *
 * ÖZEL GÖRSEL KİMLİK (QR panelinden ayrı bir ürün gibi): üstte indigo→violet→
 * sky imza gradyanı (hero) + avatar/ad, altında içeriğin gradyanın üstüne
 * yükseldiği yuvarlak "sheet". Alt gezinmede aktif sekme pill'i. Tüm stiller
 * .portal-root'a scope'lu (app.css) → panel görünümünü etkilemez.
 */
import { computed, onMounted, ref } from 'vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';
import { authFromPage } from '@/types/auth';
import { useTheme } from '@/composables/useTheme';
import { useNotifications } from '@/composables/useNotifications';
import { useNotificationSound } from '@/composables/useNotificationSound';
import { useVersionWatch } from '@/composables/useVersionWatch';
import { usePortalPush } from '@/composables/usePortalPush';
import { api } from '@/lib/http';
import AppIcon from '@/Components/ui/AppIcon.vue';

const props = withDefaults(
    defineProps<{
        title: string;
        active: 'home' | 'shift' | 'schedule' | 'tasks' | 'reports' | 'deliveries' | 'profile';
        /** Hero'da gösterilen büyük başlık (verilmezse title). */
        heading?: string;
        /** Hero başlığı altındaki küçük satır (tarih/rol vb.). */
        subtitle?: string;
    }>(),
    { heading: undefined, subtitle: undefined },
);

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));
const user = computed(() => auth.value?.user ?? null);
const tenantName = computed(() => auth.value?.tenant?.name ?? '');
const heading = computed(() => props.heading ?? props.title);

/* Teslimatlarım'a kalıcı erişim yalnız kurye izni (delivery.deliver) olan
 * personele gösterilir — "Daha fazla" sayfasında/menüsünde. Aktif teslimat
 * yokken de erişilebilsin diye Dashboard kartına bağımlı kalınmıyor. */
const canCourier = computed(() => (auth.value?.permissions ?? []).includes('delivery.deliver'));

const { theme, toggleTheme } = useTheme();

/* Bildirim zili (panel-içi bildirimler; portal duvarlı bahçesi api/v1/notifications'ı geçirir) */
const { items: notifItems, unreadCount, markRead, markAllRead } = useNotifications();

/* Sürüm gözcüsü: yeni sürüm yayınlanınca "yenile" toast'ı (ekrandaki ToastHost gösterir) */
useVersionWatch();

const showNotif = ref(false);

/* Alt-nav "Daha fazla" sayfası: Raporlarım (herkes) + Teslimatlarım (yalnız
 * kurye izni). Bu iki sayfanın kalıcı bir giriş noktası vardı (Dashboard
 * linkleri) ama alt-nav'da sekmesi yoktu; aktif teslimatı olmayan kurye
 * /teslimatlarim'e hiç ulaşamıyordu. */
const showMore = ref(false);
const moreActive = computed(() => props.active === 'reports' || props.active === 'deliveries');
function closeMore(): void {
    showMore.value = false;
}
const notifFmt = new Intl.DateTimeFormat('tr-TR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
const notifTime = (iso: string | null): string => (iso ? notifFmt.format(new Date(iso)) : '');
function onNotifClick(item: { id: number; url: string }): void {
    void markRead(item.id);
    showNotif.value = false;
    if (item.url) router.visit(item.url);
}

/* Bu cihazda ses (WebAudio bip) — zil panelindeki aç/kapa switch'i */
const { enabled: soundEnabled, toggle: toggleSound } = useNotificationSound();

/* Push izni istemi (0 aboneliğin çözümü) — panelle AYNI CTA, portal token'larıyla.
 * Notification.permission === 'default' && abone değilken sheet üstünde ve zil
 * panelinde gösterilir; kapatılırsa localStorage'da hatırlanır. */
const { supported: pushSupported, permission: pushPermission, subscribed: pushSubscribed, enable: pushEnable } = usePortalPush();

const PORTAL_PUSH_CTA_KEY = 'portal_push_cta_dismissed';
const pushCtaDismissed = ref(false);

const canPromptPush = computed(
    () => pushSupported.value && pushPermission.value === 'default' && !pushSubscribed.value,
);
const showPushCta = computed(() => canPromptPush.value && !pushCtaDismissed.value);

function dismissPushCta(): void {
    pushCtaDismissed.value = true;
    try {
        localStorage.setItem(PORTAL_PUSH_CTA_KEY, '1');
    } catch {
        /* gizli mod — bu oturumda hatırlanır */
    }
}

async function enablePush(): Promise<void> {
    const ok = await pushEnable();
    showNotif.value = false;
    if (ok) dismissPushCta();
}

const nav = [
    { key: 'home', label: 'Panelim', icon: 'dashboard', href: '/panelim' },
    { key: 'shift', label: 'Mesaim', icon: 'clock', href: '/mesaim' },
    { key: 'tasks', label: 'Görevler', icon: 'clipboard', href: '/gorevlerim' },
    { key: 'schedule', label: 'Takvim', icon: 'calendar', href: '/takvim' },
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
    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('/portal-sw.js', { scope: '/' }).catch(() => {
            /* SW kaydı başarısızsa portal yine çalışır */
        });
    }
    try {
        pushCtaDismissed.value = localStorage.getItem(PORTAL_PUSH_CTA_KEY) === '1';
    } catch {
        /* erişilemezse CTA gösterilebilir kalır */
    }
});
</script>

<template>
    <!-- TAM EKRAN KABUK: personel portalı da panel/POS ile aynı dilde —
         kabuk sabit, başlık yerinde kalır, yalnız içerik kayar. -->
    <div class="portal-root fixed inset-0 flex flex-col overflow-hidden text-body">
        <Head :title="title" />

        <!-- İmza gradient hero -->
        <header class="p-hero relative shrink-0 overflow-hidden" style="padding-top: env(safe-area-inset-top)">
            <div class="p-dots pointer-events-none absolute inset-0 opacity-20" />
            <!-- Dekoratif vektörel şemalar (premium his) -->
            <svg
                class="pointer-events-none absolute -right-6 top-0 h-full w-3/4"
                viewBox="0 0 260 180"
                fill="none"
                preserveAspectRatio="xMaxYMid slice"
                aria-hidden="true"
            >
                <!-- yumuşak ışıltı blob'ları -->
                <circle cx="220" cy="26" r="78" fill="#fff" opacity="0.06" />
                <circle cx="246" cy="96" r="48" fill="#fff" opacity="0.05" />
                <!-- eşmerkezli halkalar -->
                <circle cx="204" cy="40" r="58" stroke="#fff" stroke-opacity="0.14" stroke-width="1.4" />
                <circle cx="204" cy="40" r="40" stroke="#fff" stroke-opacity="0.11" stroke-width="1.4" />
                <circle cx="204" cy="40" r="22" stroke="#fff" stroke-opacity="0.09" stroke-width="1.4" />
                <!-- yükselen mini alan-grafik -->
                <path d="M150 150 L172 128 L194 138 L216 108 L238 118 L260 96 L260 180 L150 180 Z" fill="#fff" opacity="0.05" />
                <polyline
                    points="150,150 172,128 194,138 216,108 238,118 260,96"
                    stroke="#fff"
                    stroke-opacity="0.4"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                />
                <circle cx="216" cy="108" r="2.6" fill="#fff" opacity="0.7" />
                <!-- minik bar dizisi -->
                <g opacity="0.28" fill="#fff">
                    <rect x="150" y="150" width="6" height="16" rx="2" />
                    <rect x="162" y="142" width="6" height="24" rx="2" />
                    <rect x="174" y="134" width="6" height="32" rx="2" />
                </g>
                <!-- kıvılcımlar -->
                <circle cx="150" cy="34" r="2" fill="#fff" opacity="0.55" />
                <circle cx="176" cy="20" r="1.5" fill="#fff" opacity="0.4" />
                <circle cx="238" cy="52" r="1.6" fill="#fff" opacity="0.45" />
            </svg>
            <div class="relative mx-auto w-full max-w-xl px-4 pb-10 pt-4">
                <!-- Üst satır: avatar + ad + aksiyonlar -->
                <div class="flex items-center gap-3">
                    <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-white/20 text-base font-bold text-white ring-2 ring-white/30 backdrop-blur">
                        {{ initial }}
                    </div>
                    <div class="min-w-0 flex-1">
                        <p class="truncate text-sm font-semibold text-white">{{ user?.name ?? 'Personel' }}</p>
                        <p v-if="tenantName" class="truncate text-xs text-white/70">{{ tenantName }}</p>
                    </div>
                    <!-- Bildirim zili -->
                    <button
                        type="button"
                        class="relative flex size-9 items-center justify-center rounded-full text-white/90 transition hover:bg-white/15"
                        aria-label="Bildirimler"
                        @click="showNotif = !showNotif"
                    >
                        <AppIcon name="bell" :size="18" />
                        <span
                            v-if="unreadCount > 0"
                            class="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-(--p-rose) px-1 text-[0.6rem] font-bold text-white ring-2 ring-[color-mix(in_srgb,var(--p-hero-via),black_8%)]"
                        >
                            {{ unreadCount > 9 ? '9+' : unreadCount }}
                        </span>
                    </button>
                    <button
                        type="button"
                        class="flex size-9 items-center justify-center rounded-full text-white/90 transition hover:bg-white/15"
                        :aria-label="theme === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç'"
                        @click="onToggleTheme"
                    >
                        <AppIcon :name="theme === 'dark' ? 'sun' : 'moon'" :size="18" />
                    </button>
                    <button
                        type="button"
                        class="flex size-9 items-center justify-center rounded-full text-white/90 transition hover:bg-white/15"
                        aria-label="Çıkış yap"
                        @click="logout"
                    >
                        <AppIcon name="logout" :size="18" />
                    </button>
                </div>

                <!-- Büyük başlık + alt satır -->
                <div class="mt-5">
                    <h1 class="text-2xl font-bold leading-tight text-white">{{ heading }}</h1>
                    <p v-if="subtitle" class="mt-1 text-sm text-white/80">{{ subtitle }}</p>
                </div>
            </div>
        </header>

        <!-- Bildirim paneli (zil) -->
        <div v-if="showNotif" class="fixed inset-0 z-40" @click="showNotif = false">
            <div
                class="absolute right-3 top-16 max-h-[70vh] w-[min(22rem,calc(100vw-1.5rem))] overflow-hidden rounded-2xl border border-(--p-card-border) bg-(--p-card) shadow-(--p-card-shadow)"
                style="box-shadow: 0 20px 50px -12px rgb(30 27 75 / 0.35)"
                @click.stop
            >
                <div class="flex items-center justify-between border-b border-(--p-card-border) px-4 py-3">
                    <p class="font-semibold text-body">Bildirimler</p>
                    <button
                        v-if="unreadCount > 0"
                        type="button"
                        class="text-xs font-semibold text-(--p-indigo)"
                        @click="markAllRead"
                    >
                        Tümünü okundu
                    </button>
                </div>

                <!-- Bu cihazda ses (WebAudio bip) aç/kapa -->
                <button
                    type="button"
                    role="switch"
                    :aria-checked="soundEnabled"
                    class="flex min-h-11 w-full items-center justify-between gap-2 border-b border-(--p-card-border) px-4 py-2.5 text-left"
                    @click.stop="toggleSound"
                >
                    <span class="flex items-center gap-2 text-xs font-medium text-muted">
                        <AppIcon name="bell" :size="14" /> Bu cihazda bildirim sesi
                    </span>
                    <span
                        class="relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors"
                        :class="soundEnabled ? 'bg-(--p-indigo)' : 'bg-(--color-inset)'"
                    >
                        <span
                            class="inline-block size-5 rounded-full bg-white shadow transition-transform"
                            :class="soundEnabled ? 'translate-x-[1.375rem]' : 'translate-x-0.5'"
                        />
                    </span>
                </button>

                <!-- Zil panelinden push açma erişimi -->
                <button
                    v-if="canPromptPush"
                    type="button"
                    class="flex min-h-11 w-full items-center gap-2 border-b border-(--p-card-border) px-4 py-2.5 text-left text-xs font-semibold text-(--p-indigo)"
                    @click.stop="enablePush"
                >
                    <AppIcon name="bell" :size="14" /> Bu cihazda bildirimleri aç
                </button>

                <div class="max-h-[calc(70vh-3rem)] overflow-y-auto">
                    <button
                        v-for="n in notifItems"
                        :key="n.id"
                        type="button"
                        class="flex w-full items-start gap-3 border-b border-(--p-card-border) px-4 py-3 text-left transition hover:bg-(--color-inset)"
                        :class="!n.read ? 'bg-(--p-indigo-soft)/40' : ''"
                        @click="onNotifClick(n)"
                    >
                        <span class="p-chip mt-0.5 !size-8 shrink-0"><AppIcon :name="n.icon" :size="15" /></span>
                        <span class="min-w-0 flex-1">
                            <span class="flex items-center gap-2">
                                <span class="min-w-0 flex-1 truncate text-sm font-semibold text-body">{{ n.title }}</span>
                                <span v-if="!n.read" class="size-2 shrink-0 rounded-full bg-(--p-rose)" />
                            </span>
                            <span v-if="n.body" class="mt-0.5 line-clamp-2 block text-xs text-muted">{{ n.body }}</span>
                            <span class="mt-1 block text-[0.7rem] text-subtle">{{ notifTime(n.created_at) }}</span>
                        </span>
                    </button>
                    <p v-if="!notifItems.length" class="px-4 py-10 text-center text-sm text-muted">Bildirim yok.</p>
                </div>
            </div>
        </div>

        <!-- İçerik "sheet" — gradyanın üstüne yükselir -->
        <main class="relative z-10 -mt-6 min-h-0 flex-1 overflow-y-auto overscroll-contain rounded-t-[1.75rem] bg-(--p-surface) px-4 pb-28 pt-5">
            <div class="mx-auto w-full max-w-xl">
                <!-- Push izni istemi: hafif, kapatılabilir kart (0 aboneliğin çözümü) -->
                <div
                    v-if="showPushCta"
                    class="mb-4 flex items-center gap-3 rounded-2xl border border-(--p-card-border) bg-(--p-card) p-3 shadow-(--p-card-shadow)"
                >
                    <span class="p-chip !size-9 shrink-0"><AppIcon name="bell" :size="18" /></span>
                    <div class="min-w-0 flex-1">
                        <p class="text-sm font-semibold text-body">🔔 Bildirimleri açın</p>
                        <p class="text-xs text-muted">Görev ve mesai bildirimlerini bu cihazda anında alın.</p>
                    </div>
                    <button
                        type="button"
                        class="inline-flex min-h-11 shrink-0 items-center rounded-xl bg-(--p-indigo) px-3.5 text-sm font-semibold text-white"
                        @click="enablePush"
                    >
                        Aç
                    </button>
                    <button
                        type="button"
                        aria-label="Bu istemi kapat"
                        class="inline-flex size-11 shrink-0 items-center justify-center rounded-xl text-muted transition hover:bg-(--color-inset)"
                        @click="dismissPushCta"
                    >
                        <AppIcon name="x" :size="16" />
                    </button>
                </div>

                <!-- Faz 5: sayfa yolu değişince yumuşak beliriş (reduced-motion'da kapalı). -->
                <div :key="(page.url || '').split('?')[0]" class="animate-rise">
                    <slot />
                </div>
            </div>
        </main>

        <!-- "Daha fazla" sayfası (Raporlarım + kuryeyse Teslimatlarım) -->
        <div v-if="showMore" class="fixed inset-0 z-40" @click="closeMore">
            <div
                class="absolute inset-x-3 bottom-[calc(4.75rem+env(safe-area-inset-bottom))] mx-auto max-w-xl overflow-hidden rounded-2xl border border-(--p-card-border) bg-(--p-card) shadow-(--p-card-shadow)"
                style="box-shadow: 0 20px 50px -12px rgb(30 27 75 / 0.35)"
                @click.stop
            >
                <div class="flex items-center justify-between border-b border-(--p-card-border) px-4 py-3">
                    <p class="font-semibold text-body">Daha fazla</p>
                    <button type="button" aria-label="Kapat" class="flex size-8 items-center justify-center rounded-full text-muted hover:bg-(--color-inset)" @click="closeMore">
                        <AppIcon name="x" :size="16" />
                    </button>
                </div>
                <Link
                    href="/raporlarim"
                    class="flex min-h-14 w-full items-center gap-3 border-b border-(--p-card-border) px-4 py-3 text-left transition hover:bg-(--color-inset)"
                    :class="props.active === 'reports' ? 'bg-(--p-indigo-soft)/40' : ''"
                    @click="closeMore"
                >
                    <span class="p-chip !size-9 shrink-0"><AppIcon name="chart" :size="17" /></span>
                    <span class="min-w-0 flex-1">
                        <span class="block text-sm font-semibold text-body">Raporlarım</span>
                        <span class="block text-xs text-muted">Kendi performans ve mesai özetin</span>
                    </span>
                    <AppIcon name="chevron-right" :size="16" class="shrink-0 text-subtle" />
                </Link>
                <Link
                    v-if="canCourier"
                    href="/teslimatlarim"
                    class="flex min-h-14 w-full items-center gap-3 px-4 py-3 text-left transition hover:bg-(--color-inset)"
                    :class="props.active === 'deliveries' ? 'bg-(--p-indigo-soft)/40' : ''"
                    @click="closeMore"
                >
                    <span class="p-chip !size-9 shrink-0"><AppIcon name="package" :size="17" /></span>
                    <span class="min-w-0 flex-1">
                        <span class="block text-sm font-semibold text-body">Teslimatlarım</span>
                        <span class="block text-xs text-muted">Sana atanan paket teslimatları</span>
                    </span>
                    <AppIcon name="chevron-right" :size="16" class="shrink-0 text-subtle" />
                </Link>
            </div>
        </div>

        <!-- Alt gezinme (aktif sekme pill'i) -->
        <nav
            class="fixed inset-x-0 bottom-0 z-30 border-t border-(--p-card-border) bg-(--p-card)/95 backdrop-blur"
            style="padding-bottom: env(safe-area-inset-bottom)"
        >
            <div class="mx-auto grid w-full max-w-xl grid-cols-6 px-1.5 py-1.5">
                <Link
                    v-for="item in nav"
                    :key="item.key"
                    :href="item.href"
                    class="flex flex-col items-center gap-1 rounded-xl py-2 text-[0.7rem] font-medium transition"
                    :class="props.active === item.key
                        ? 'bg-(--p-indigo-soft) text-(--p-indigo)'
                        : 'text-muted hover:text-body'"
                >
                    <AppIcon :name="item.icon" :size="21" />
                    <span>{{ item.label }}</span>
                </Link>
                <button
                    type="button"
                    class="flex flex-col items-center gap-1 rounded-xl py-2 text-[0.7rem] font-medium transition"
                    :class="moreActive ? 'bg-(--p-indigo-soft) text-(--p-indigo)' : 'text-muted hover:text-body'"
                    @click="showMore = !showMore"
                >
                    <AppIcon name="dots-vertical" :size="21" />
                    <span>Daha fazla</span>
                </button>
            </div>
        </nav>
    </div>
</template>
