<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import ToastHost from '@/Components/ui/ToastHost.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import KdsIcon from './KdsIcon.vue';
import KdsItemImage from './KdsItemImage.vue';
import KdsNavDrawer from './KdsNavDrawer.vue';
import StationManager from './StationManager.vue';
import {
    createKdsSound,
    createPollingFeed,
    useKdsTheme,
    getOrNull,
    metaFromKdsProps,
    minutesSince,
    slaLevel,
    slaText,
    waitChipClass,
    type KdsFeed,
    type KdsItem,
    type KdsOrderCard,
    type KitchenPayload,
    type SlaLevel,
} from './kds';

/**
 * MUTFAK / BAR EKRANI — BAĞIMSIZ tam ekran, dokunmatik (panel kabuğuna
 * GÖMÜLÜ DEĞİL, kasıtlı: ~2 metreden okunan bir duvar/tezgah ekranı, panelin
 * dar içerik alanına sığmaz). Bar = aynı ekran, istasyon süzgeci "bar".
 *
 * Görsel dil PANELİN --ui-* token'larını kullanır; varsayılan AÇIK/beyaz,
 * ekranın kendi açık/koyu düğmesiyle bağımsız değiştirilebilir (useKdsTheme,
 * localStorage 'kds_theme' — panelin genel tema tercihine dokunmaz).
 * Ekrana özgü düzen/aralık/görsel
 * yerleşim bu dosyada kalır (Components/ui değişmez). Kart üç soruya bakışta
 * cevap verir: hangi masa (büyük başlık) · ne yapılacak (görsel + kalem +
 * TEK eylem) · ne kadar acil (yalnız bekleme çipi renklenir). Ürün görseli
 * (varsa) DESTEKLEYİCİDİR — asla masa/ürün adını küçültmez ya da "…" ile
 * kırpmaz. Renk yalnız alerjen ve gecikmede güçlü konuşur; diyet etiketi
 * sessiz düz metindir. Fiyat/ciro bu ekranda YOKTUR.
 */
const page = usePage();
const meta = metaFromKdsProps(page.props as Record<string, unknown>);
const { success, danger, warning } = useToast();

/* ---- Şube (paylaşılan auth prop'undan) ---- */
const auth = page.props.auth as {
    branches?: { id: number; name: string }[];
    activeBranchId?: number | null;
} | null;
const branches = auth?.branches ?? [];
const branchId = ref<number>(auth?.activeBranchId ?? branches[0]?.id ?? 0);

/* ---- İstasyon süzgeci ---- */
const initialStation = (page.props.initialStation as string) || '';
const station = ref<string>(initialStation);

/* ---- Ekran KULVARI (Mutfak ↔ Barista AYRI) ----
 * lane = 'kitchen' | 'barista' (controller'dan). laneStations = bu kulvarın
 * istasyon anahtarları. Çipler yalnız kendi kulvarını gösterir; "Tümü" de
 * yalnız bu kulvarı kapsar (mutfakta Barista/Kahve/Bar çipleri HİÇ görünmez). */
const lane = (page.props.lane as string) || '';
const laneStations = (page.props.laneStations as string[] | null) ?? null;

const stationChips = computed(() => {
    let list = meta.stations.filter((s) => s.is_active);
    if (laneStations) {
        list = list.filter((s) => laneStations.includes(s.key));
    }
    if (meta.allowedStations) {
        list = list.filter((s) => meta.allowedStations!.includes(s.key));
    }
    return list;
});
// "Tümü" yalnız kulvar içinde birden çok çip varsa anlamlı (kulvar-kapsamlı).
const showAllChip = computed(() => stationChips.value.length > 1);

function stationPending(key: string): number {
    return summary.value.find((r) => r.station === key)?.pending ?? 0;
}

/* ---- Veri + ulaşım katmanı (ADR-006: cursor'lı polling, 204) ---- */
const loading = ref(true);
const orders = ref<KdsOrderCard[]>([]);
const summary = ref<{ station: string | null; station_label: string; pending: number }[]>([]);
const serverSkewMs = ref(0);
const knownOrderIds = new Set<number>();
const newOrderIds = ref<Set<number>>(new Set());
let feed: KdsFeed | null = null;

const sound = createKdsSound('kds_kitchen_sound');
const soundOn = ref(sound.enabled());

function queueUrl(): string {
    const p = new URLSearchParams({ mode: 'kitchen', branch_id: String(branchId.value) });
    if (station.value) p.set('station', station.value);
    if (lane) p.set('lane', lane);
    return `/api/v1/kds/queue?${p}`;
}

function updatesUrl(cursor: number): string {
    const p = new URLSearchParams({ mode: 'kitchen', branch_id: String(branchId.value), cursor: String(cursor) });
    if (station.value) p.set('station', station.value);
    if (lane) p.set('lane', lane);
    return `/api/v1/kds/updates?${p}`;
}

function applyPayload(payload: KitchenPayload, silent = false): void {
    serverSkewMs.value = new Date(payload.server_time).getTime() - Date.now();

    const fresh = new Set<number>();
    for (const o of payload.orders) {
        if (!knownOrderIds.has(o.id)) fresh.add(o.id);
        knownOrderIds.add(o.id);
    }

    orders.value = payload.orders;
    summary.value = payload.summary;
    loading.value = false;

    if (!silent && fresh.size > 0) {
        newOrderIds.value = fresh;
        sound.beep(2);
        setTimeout(() => (newOrderIds.value = new Set()), 12000);
    }
}

function buildFeed(): KdsFeed {
    let first = true;
    return createPollingFeed<KitchenPayload>({
        fetchFull: () => api<KitchenPayload>(queueUrl()),
        fetchDelta: (cursor) => getOrNull<KitchenPayload>(updatesUrl(cursor)),
        onData: (payload) => {
            applyPayload(payload, first);
            first = false;
        },
        onError: () => {
            /* geçici ağ hatası — bir sonraki yoklamada düzelir */
        },
        intervalMs: meta.config.poll_interval_seconds * 1000,
    });
}

async function restartFeed(): Promise<void> {
    feed?.stop();
    knownOrderIds.clear();
    newOrderIds.value = new Set();
    loading.value = true;
    feed = buildFeed();
    try {
        await feed.load();
    } catch (e) {
        loading.value = false;
        danger('Kuyruk yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Bağlantıyı kontrol edin.');
    }
    feed.start();
}

const kdsTheme = useKdsTheme();
let clockTimer: ReturnType<typeof setInterval> | null = null;
const clockTick = ref(Date.now());

onMounted(() => {
    void restartFeed();
    // Otomatik oynatma kısıtı: ilk dokunuş sesi kilitten çıkarır.
    const unlock = () => sound.unlock();
    window.addEventListener('pointerdown', unlock, { once: true });
    // Süre çipleri payload değişmese de tazelensin.
    clockTimer = setInterval(() => (clockTick.value = Date.now()), 30000);
});

onBeforeUnmount(() => {
    feed?.stop();
    if (clockTimer) clearInterval(clockTimer);
    kdsTheme.release();
});

function selectStation(key: string): void {
    station.value = key;
    void restartFeed();
}

function selectBranch(id: string): void {
    branchId.value = Number(id);
    void restartFeed();
}

/* ---- SLA ---- */
function waitMinutes(iso: string | null): number {
    void clockTick.value; // reaktif tazeleme
    return minutesSince(iso, serverSkewMs.value);
}

function itemSla(item: KdsItem): SlaLevel {
    if (item.status === 'ready') return 'ok';
    return slaLevel(waitMinutes(item.created_at), item.target_minutes, meta.config.late_ratio);
}

function cardSla(card: KdsOrderCard): SlaLevel {
    let level: SlaLevel = 'ok';
    for (const i of card.items) {
        const l = itemSla(i);
        if (l === 'late') return 'late';
        if (l === 'warn') level = 'warn';
    }
    return level;
}

const lateCount = computed(() => orders.value.filter((o) => cardSla(o) === 'late').length);
const totalPending = computed(() =>
    orders.value.reduce((n, o) => n + o.items.filter((i) => i.status !== 'ready').length, 0),
);

/* ---- Eylemler (409 → çakışma uyarısı + tazeleme) ---- */
const busy = ref(false);

async function runAction(fn: () => Promise<unknown>, okMsg: string): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    try {
        await fn();
        if (okMsg) success(okMsg, '');
        await feed?.refresh();
    } catch (e) {
        if (e instanceof ApiError && e.status === 409) {
            warning('Eşzamanlı değişiklik', 'Sipariş bu sırada başka ekrandan değişti; kuyruk tazelendi.');
            await feed?.refresh();
        } else {
            danger('İşlem tamamlanamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
        }
    } finally {
        busy.value = false;
    }
}

/** Kalemin zincirdeki O ANKİ adımı — karttaki TEK primary buton budur. */
function nextStep(item: KdsItem): { to: string; label: string } | null {
    if (item.status === 'placed' || item.status === 'sent_to_station') return { to: 'accepted', label: 'Kabul' };
    if (item.status === 'accepted') return { to: 'preparing', label: 'Başlat' };
    if (item.status === 'preparing') return { to: 'ready', label: 'Bitir' };
    return null;
}

function advance(card: KdsOrderCard, item: KdsItem, to: string): void {
    void runAction(
        () => api(`/api/v1/kds/items/${item.id}/status`, { method: 'POST', body: { to, expected_version: card.version } }),
        to === 'ready' ? `${item.name} hazır` : '',
    );
}

function undoItem(card: KdsOrderCard, item: KdsItem): void {
    void runAction(
        () => api(`/api/v1/kds/items/${item.id}/undo`, { method: 'POST', body: { expected_version: card.version } }),
        'İşaret geri alındı',
    );
}

function allReady(card: KdsOrderCard): void {
    void runAction(
        () =>
            api(`/api/v1/kds/orders/${card.id}/station-ready`, {
                method: 'POST',
                body: { station: station.value || null, lane: lane || null, expected_version: card.version },
            }),
        'Sipariş hazır olarak işaretlendi',
    );
}

/* ---- İstasyon transferi (ikincil eylem) ---- */
const transferTarget = ref<{ card: KdsOrderCard; item: KdsItem } | null>(null);
const transferStation = ref('');

const transferOptions = computed(() =>
    meta.stations
        .filter((s) => s.is_active && s.key !== transferTarget.value?.item.station)
        .map((s) => ({ value: s.key, label: s.name })),
);

function openTransfer(card: KdsOrderCard, item: KdsItem): void {
    transferTarget.value = { card, item };
    transferStation.value = '';
}

function doTransfer(): void {
    const t = transferTarget.value;
    if (!t || !transferStation.value) return;
    void runAction(
        () =>
            api(`/api/v1/kds/items/${t.item.id}/transfer`, {
                method: 'POST',
                body: { station: transferStation.value, expected_version: t.card.version },
            }),
        'Kalem transfer edildi',
    ).then(() => (transferTarget.value = null));
}

/* ---- Görünüm ---- */
const isFullscreen = ref(false);
function toggleFullscreen(): void {
    if (document.fullscreenElement) {
        void document.exitFullscreen();
        isFullscreen.value = false;
    } else {
        void document.documentElement.requestFullscreen?.();
        isFullscreen.value = true;
    }
}

function toggleSound(): void {
    sound.unlock();
    sound.setEnabled(!soundOn.value);
    soundOn.value = !soundOn.value;
    if (soundOn.value) sound.beep(1);
}

const showStations = ref(false);
// Nav çekmecesi (soldan overlay) — diğer panel bölümlerine kaçış-kapısı.
const showNav = ref(false);

// §13 Terminal kilitli mod: cihaz oturumunda nav çekmecesi GİZLENİR (başka
// sayfaya geçilemez) ve "Terminal · {istasyon}" kilit rozeti gösterilir.
const isTerminal = computed(() => Boolean((page.props.auth as { is_terminal?: boolean } | null)?.is_terminal));
const terminalStationLabel = computed(() => {
    const key = (page.props.auth as { terminal_station?: string | null } | null)?.terminal_station ?? '';
    if (key === 'barista') return 'Barista';
    if (key === 'komi') return 'Komi';
    if (key === 'kitchen') return 'Mutfak';
    return key;
});

function pendingItems(card: KdsOrderCard): KdsItem[] {
    return card.items.filter((i) => i.status !== 'ready');
}

/**
 * Kart çerçevesi: yalnız YENİ sipariş vurgulanır (12 sn). Aciliyet kartta
 * TEK yerde konuşur — sağ üstteki bekleme çipi (renk + "gecikti" sözcüğü).
 */
function cardBorderClass(card: KdsOrderCard): string {
    return newOrderIds.value.has(card.id) ? 'border-primary-soft-border' : 'border-default';
}

const branchOptions = computed(() => branches.map((b) => ({ value: String(b.id), label: b.name })));

// Başlık seçili istasyonun adını izler (Mutfak / Barista / Izgara …); süzgeç
// "Tümü" ise genel "Mutfak Ekranı" başlığı kalır (istasyonlar mutfak tarafıdır).
const pageTitle = computed(() => {
    if (!station.value) return 'Mutfak Ekranı';
    const s = meta.stations.find((x) => x.key === station.value);
    return `${s?.name ?? 'Mutfak'} Ekranı`;
});
</script>

<template>
    <Head :title="pageTitle" />

    <div class="kds-canvas fixed inset-0 flex flex-col overflow-hidden text-body">
        <!-- ================= Üst çubuk (panel başlık dili) ================= -->
        <header class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-default bg-raised px-3 py-2">
            <BaseButton v-if="!isTerminal" variant="ghost" size="lg" icon-only label="Panele dön" href="/panel">
                <AppIcon name="arrow-left" :size="20" />
            </BaseButton>

            <BaseButton v-if="!isTerminal" variant="ghost" size="lg" icon-only label="Menüyü aç" @click="showNav = true">
                <AppIcon name="menu" :size="20" />
            </BaseButton>

            <!-- §13 Terminal kilit rozeti (cihaz oturumu) -->
            <span
                v-if="isTerminal"
                class="inline-flex items-center gap-1.5 rounded-full border border-default bg-inset px-2.5 py-1 text-xs font-semibold text-muted"
                title="Bu cihaz istasyon terminaline kilitlidir"
            >
                <AppIcon name="tablet" :size="13" />
                Terminal · {{ terminalStationLabel }}
            </span>

            <h1 class="text-lg font-semibold">{{ pageTitle }}</h1>

            <span class="text-sm text-muted tabular-nums">{{ totalPending }} bekleyen</span>

            <span
                v-if="lateCount > 0"
                role="alert"
                class="inline-flex items-center gap-1 rounded-full border border-danger bg-danger px-2.5 py-1 text-xs font-semibold text-on-status"
            >
                <AppIcon name="alert-triangle" :size="13" />
                {{ lateCount }} gecikti
            </span>

            <div class="ml-auto flex flex-wrap items-center gap-1.5">
                <div v-if="branchOptions.length > 1" class="w-44">
                    <BaseSelect
                        :model-value="String(branchId)"
                        :options="branchOptions"
                        @update:model-value="selectBranch(String($event))"
                    />
                </div>

                <BaseButton v-if="meta.canDeliver" variant="secondary" size="lg" href="/panel/komi">
                    <KdsIcon name="tray" :size="18" />
                    Komi
                </BaseButton>

                <BaseButton
                    v-if="meta.canManageStations"
                    variant="ghost"
                    size="lg"
                    icon-only
                    label="İstasyon yönetimi"
                    @click="showStations = true"
                >
                    <AppIcon name="settings" :size="20" />
                </BaseButton>

                <BaseButton
                    variant="ghost"
                    size="lg"
                    icon-only
                    :label="soundOn ? 'Yeni sipariş sesi: açık' : 'Yeni sipariş sesi: kapalı'"
                    :class="soundOn ? '' : 'text-subtle'"
                    @click="toggleSound"
                >
                    <KdsIcon :name="soundOn ? 'volume-on' : 'volume-off'" :size="20" />
                </BaseButton>

                <BaseButton
                    variant="ghost"
                    size="lg"
                    icon-only
                    :label="kdsTheme.theme.value === 'dark' ? 'Açık temaya geç' : 'Koyu temaya geç'"
                    @click="kdsTheme.toggle()"
                >
                    <KdsIcon :name="kdsTheme.theme.value === 'dark' ? 'sun' : 'moon'" :size="20" />
                </BaseButton>

                <BaseButton
                    variant="ghost"
                    size="lg"
                    icon-only
                    :label="isFullscreen ? 'Tam ekrandan çık' : 'Tam ekran'"
                    @click="toggleFullscreen"
                >
                    <KdsIcon :name="isFullscreen ? 'compress' : 'expand'" :size="20" />
                </BaseButton>
            </div>
        </header>

        <!-- ================= İstasyon süzgeci ================= -->
        <nav
            class="flex flex-wrap items-center gap-2 border-b border-default bg-surface-alt px-3 py-2 shadow-[0_6px_16px_-12px_rgba(0,0,0,0.6)]"
            aria-label="İstasyon süzgeci"
        >
            <button
                v-if="showAllChip"
                type="button"
                class="inline-flex h-11 items-center rounded-full border px-4 text-sm font-medium transition-colors"
                :class="station === '' ? 'border-primary bg-primary text-on-primary' : 'border-default bg-raised text-body hover:bg-inset'"
                @click="selectStation('')"
            >
                Tümü
            </button>
            <button
                v-for="s in stationChips"
                :key="s.key"
                type="button"
                class="inline-flex h-11 items-center gap-2 rounded-full border px-4 text-sm font-medium transition-colors"
                :class="station === s.key ? 'border-primary bg-primary text-on-primary' : 'border-default bg-raised text-body hover:bg-inset'"
                @click="selectStation(s.key)"
            >
                {{ s.name }}
                <span
                    v-if="stationPending(s.key) > 0"
                    class="tabular-nums font-semibold"
                    :class="station === s.key ? 'text-on-primary' : 'text-muted'"
                >
                    {{ stationPending(s.key) }}
                </span>
            </button>
        </nav>

        <!-- ================= Kuyruk ================= -->
        <main class="flex-1 overflow-y-auto p-4">
            <p v-if="loading" class="flex h-full items-center justify-center text-muted">Kuyruk yükleniyor…</p>

            <div v-else-if="orders.length === 0" class="flex h-full items-center justify-center">
                <EmptyState
                    icon="check-circle"
                    title="Bekleyen sipariş yok"
                    :description="`Yeni sipariş geldiğinde burada görünür — ekran her ${meta.config.poll_interval_seconds} saniyede bir kendini yeniler.`"
                />
            </div>

            <div v-else class="kds-masonry">
                <article
                    v-for="card in orders"
                    :key="card.id"
                    class="flex flex-col overflow-hidden rounded-xl border bg-raised shadow-[0_1px_2px_0_rgb(28_25_23_/_0.05),inset_0_1px_0_0_rgba(255,255,255,0.05)]"
                    :class="cardBorderClass(card)"
                >
                    <!-- Başlık: HANGİ MASA (büyük, hiç kırpılmaz) · NE KADAR ACİL (tek çip) -->
                    <div class="flex items-start justify-between gap-3 border-b border-default px-4 py-3.5">
                        <div class="min-w-0">
                            <p class="text-2xl font-semibold leading-tight text-balance">
                                {{ card.table_name ?? card.customer_name ?? `Sipariş #${card.id}` }}
                            </p>
                            <p class="mt-1 text-sm text-muted">
                                {{ card.channel_label }}<template v-if="card.area_name"> · {{ card.area_name }}</template><template v-if="card.waiter"> · {{ card.waiter }}</template>
                            </p>
                        </div>
                        <span
                            class="inline-flex shrink-0 items-center rounded-md border px-3 py-1.5 text-lg font-semibold tabular-nums"
                            :class="waitChipClass(cardSla(card))"
                            title="Sipariş verileli geçen süre"
                        >
                            {{ slaText(waitMinutes(card.placed_at)) }}<template v-if="cardSla(card) === 'late'">&nbsp;· gecikti</template>
                        </span>
                    </div>

                    <!-- Sipariş notu -->
                    <p v-if="card.note" class="border-b border-default bg-info-soft px-4 py-2 text-sm font-medium text-info">
                        Not: {{ card.note }}
                    </p>

                    <!-- Kalemler: görsel · adet+ad (hiç kırpılmaz) · (varsa) not/alerjen + TEK eylem -->
                    <ul class="flex-1 divide-y divide-default">
                        <li
                            v-for="item in card.items"
                            :key="item.id"
                            class="flex items-start gap-3 px-4 py-3.5"
                            :class="item.status === 'ready' ? 'opacity-60' : ''"
                        >
                            <KdsItemImage :src="item.image_url" :alt="item.name" />

                            <div class="min-w-0 flex-1">
                                <p class="text-lg font-semibold leading-snug text-balance" :class="item.status === 'ready' ? 'line-through' : ''">
                                    <span class="tabular-nums">{{ item.qty }}×</span>
                                    {{ item.name }}<span v-if="item.variant_name" class="font-normal text-muted"> — {{ item.variant_name }}</span>
                                </p>
                                <p v-if="item.options.length" class="mt-0.5 text-sm text-muted">{{ item.options.join(' · ') }}</p>
                                <p v-if="item.note" class="mt-0.5 text-sm font-medium text-info">Not: {{ item.note }}</p>

                                <!-- Renk YALNIZ alerjende güçlü; diyet etiketi sessiz düz metin.
                                     Dolgu (soft) rozet yerine DOLU kırmızı: açık temada
                                     BaseBadge'in soft-danger ikilisi AA'nın (4.5:1) az altında
                                     kalıyor (ölçülen 4.41:1) — alerjen güvenlik bilgisi olduğundan
                                     burada dolu bg-danger/text-on-status kullanılır (ölçülen
                                     4.83:1 açık, 6.32:1 koyu — her iki temada da AA geçer). -->
                                <p v-if="item.allergens.length || item.diets.length" class="mt-1.5 flex flex-wrap items-center gap-x-2.5 gap-y-1">
                                    <span
                                        v-for="a in item.allergens"
                                        :key="a.name"
                                        class="inline-flex items-center gap-1 rounded-full border border-danger bg-danger px-2 py-0.5 text-xs font-semibold text-on-status"
                                    >
                                        <AppIcon name="alert-triangle" :size="12" />
                                        {{ a.name }}
                                    </span>
                                    <span v-if="item.diets.length" class="text-xs text-subtle">{{ item.diets.join(' · ') }}</span>
                                </p>

                                <!-- Yalnız "Tümü" görünümünde ve çok sessiz: üstteki süzme çipi zaten
                                     istasyonu belirtir, kart içi etiket yalnız karışık listede yön verir. -->
                                <p v-if="!station" class="mt-1 text-[11px] text-subtle/70">
                                    {{ item.station_label }}
                                </p>

                                <!-- Geri al: bilinçli olarak SOLDA — sağdaki eylem sütunundan uzak -->
                                <BaseButton
                                    v-if="item.status === 'ready'"
                                    variant="ghost"
                                    size="lg"
                                    class="-ml-4 mt-1"
                                    :disabled="busy"
                                    @click="undoItem(card, item)"
                                >
                                    <KdsIcon name="undo" :size="16" />
                                    Geri al
                                </BaseButton>
                            </div>

                            <!-- Sağ sütun: kalemin TEK sıradaki adımı (primary) ya da durum rozeti -->
                            <div class="flex shrink-0 flex-col items-end gap-1.5">
                                <BaseButton
                                    v-if="nextStep(item)"
                                    size="lg"
                                    class="min-w-24"
                                    :disabled="busy"
                                    @click="advance(card, item, nextStep(item)!.to)"
                                >
                                    {{ nextStep(item)!.label }}
                                </BaseButton>
                                <BaseBadge v-else-if="item.status === 'ready'" variant="success">{{ item.status_label }}</BaseBadge>

                                <BaseButton
                                    v-if="item.status !== 'ready'"
                                    variant="ghost"
                                    size="lg"
                                    icon-only
                                    :label="`${item.name} kalemini başka istasyona aktar`"
                                    :disabled="busy"
                                    @click="openTransfer(card, item)"
                                >
                                    <KdsIcon name="swap" :size="16" />
                                </BaseButton>
                            </div>
                        </li>
                    </ul>

                    <!-- Toplu kısayol: ikincil — kalemlerin kendi adımları asıl akıştır -->
                    <div class="border-t border-default p-3">
                        <BaseButton
                            v-if="pendingItems(card).length > 0"
                            variant="secondary"
                            size="lg"
                            block
                            :disabled="busy"
                            @click="allReady(card)"
                        >
                            <AppIcon name="check-circle" :size="18" />
                            Tümünü bitir ({{ pendingItems(card).length }})
                        </BaseButton>
                        <p v-else class="flex h-11 items-center justify-center gap-2 text-base font-medium text-success">
                            <KdsIcon name="tray" :size="18" />
                            Garson & Komi bekliyor
                        </p>
                    </div>
                </article>
            </div>
        </main>
    </div>

    <!-- ================= Transfer modalı ================= -->
    <BaseModal :open="transferTarget !== null" title="İstasyon transferi" size="sm" @close="transferTarget = null">
        <div v-if="transferTarget" class="flex flex-col gap-3">
            <p class="text-sm">
                <strong>{{ transferTarget.item.qty }}× {{ transferTarget.item.name }}</strong>
                kalemi <strong>{{ transferTarget.item.station_label }}</strong> istasyonundan taşınacak.
            </p>
            <BaseSelect v-model="transferStation" :options="transferOptions" placeholder="Hedef istasyon seçin" />
        </div>
        <template #footer>
            <BaseButton variant="secondary" @click="transferTarget = null">Vazgeç</BaseButton>
            <BaseButton :disabled="!transferStation || busy" @click="doTransfer">Transfer et</BaseButton>
        </template>
    </BaseModal>

    <!-- ================= İstasyon yönetimi ================= -->
    <StationManager v-if="meta.canManageStations" :open="showStations" @close="showStations = false" />

    <!-- ================= Nav çekmecesi (soldan overlay) ================= -->
    <KdsNavDrawer v-if="!isTerminal" :open="showNav" @close="showNav = false" />

    <ToastHost />
</template>

<style scoped>
/*
 * Zemin: --ui-surface üstünde çok hafif üstten ışık düşümü — düz/tek
 * tondan "katmanlı yüzey" hissine geçiş; hem açık hem koyu temada çalışır
 * (renk katkısı yok, yalnız beyaz alfa). Kartlar (--ui-surface-raised)
 * zeminden daha açık kalarak ikinci kademeyi oluşturur. Kademeler:
 * header/nav (raised → surface-alt) > zemin (surface) — bkz. şablondaki
 * bg-raised / bg-surface-alt sınıfları.
 */
.kds-canvas {
    background-color: var(--ui-surface);
    background-image: radial-gradient(1200px 640px at 50% -12%, rgb(255 255 255 / 0.035), transparent 60%);
}

/*
 * Kart ızgarası: masonry (CSS çoklu sütun). Sabit satır hizası YOK — her
 * sütun kendi içinde akar, kısa kartın altında uzun bir satırın boşluğu
 * kalmaz. Sütun sayısı genişliğe göre uyarlanır (dar 1 → geniş 5).
 */
.kds-masonry {
    column-gap: 1rem;
    column-count: 1;
}
@media (min-width: 640px) {
    .kds-masonry {
        column-count: 2;
    }
}
@media (min-width: 1024px) {
    .kds-masonry {
        column-count: 3;
    }
}
@media (min-width: 1280px) {
    .kds-masonry {
        column-count: 4;
    }
}
@media (min-width: 1536px) {
    .kds-masonry {
        column-count: 5;
    }
}
.kds-masonry > * {
    break-inside: avoid;
    -webkit-column-break-inside: avoid;
    margin-bottom: 1rem;
}
</style>
