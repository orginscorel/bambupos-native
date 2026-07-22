<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import ToastHost from '@/Components/ui/ToastHost.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import KdsIcon from './KdsIcon.vue';
import StationManager from './StationManager.vue';
import './kds-theme.css';
import {
    createKdsSound,
    createPollingFeed,
    getOrNull,
    metaFromKdsProps,
    minutesSince,
    slaLevel,
    slaText,
    type KdsFeed,
    type KdsItem,
    type KdsOrderCard,
    type KitchenPayload,
    type SlaLevel,
} from './kds';

/**
 * MUTFAK / BAR EKRANI — tam ekran, dokunmatik, 2 metreden okunur.
 * Bar = aynı ekran, istasyon süzgeci "bar" (ya da ?istasyon=bar).
 * Gerçek zamanlılık: KdsFeed (bugün cursor'lı polling — ADR-006).
 * Görsel dil: kds-theme.css (--kds-* katmanı, panel temasından bağımsız koyu).
 */
const page = usePage();
const meta = metaFromKdsProps(page.props as Record<string, unknown>);
const { success, danger, warning } = useToast();

/* ---- Şube (paylaşılan auth prop'undan) ---- */
const auth = page.props.auth as {
    branches?: { id: number; name: string }[];
    activeBranchId?: number | null;
    user?: { name?: string };
} | null;
const branches = auth?.branches ?? [];
const branchId = ref<number>(auth?.activeBranchId ?? branches[0]?.id ?? 0);

/* ---- İstasyon süzgeci ---- */
const initialStation = (page.props.initialStation as string) || '';
const station = ref<string>(initialStation);

const stationChips = computed(() => {
    let list = meta.stations.filter((s) => s.is_active);
    if (meta.allowedStations) {
        list = list.filter((s) => meta.allowedStations!.includes(s.key));
    }
    return list;
});
const showAllChip = computed(() => meta.allowedStations === null || meta.allowedStations.length > 1);

/* ---- Veri + ulaşım katmanı ---- */
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
    return `/api/v1/kds/queue?${p}`;
}

function updatesUrl(cursor: number): string {
    const p = new URLSearchParams({ mode: 'kitchen', branch_id: String(branchId.value), cursor: String(cursor) });
    if (station.value) p.set('station', station.value);
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

onMounted(() => {
    void restartFeed();
    // Otomatik oynatma kısıtı: ilk dokunuş sesi kilitten çıkarır.
    const unlock = () => sound.unlock();
    window.addEventListener('pointerdown', unlock, { once: true });
    // Süre çipleri dakikada bir tazelensin (payload değişmese de).
    clockTimer = setInterval(() => (clockTick.value = Date.now()), 30000);
});

onBeforeUnmount(() => {
    feed?.stop();
    if (clockTimer) clearInterval(clockTimer);
});

let clockTimer: ReturnType<typeof setInterval> | null = null;
const clockTick = ref(Date.now());

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
                body: { station: station.value || null, expected_version: card.version },
            }),
        'Sipariş hazır olarak işaretlendi',
    );
}

/* ---- İstasyon transferi ---- */
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
const compact = ref(localStorage.getItem('kds_compact') === '1');
function toggleCompact(): void {
    compact.value = !compact.value;
    localStorage.setItem('kds_compact', compact.value ? '1' : '0');
}

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

/* Kart durum yardımcıları */
function pendingItems(card: KdsOrderCard): KdsItem[] {
    return card.items.filter((i) => i.status !== 'ready');
}

/** Kart çerçevesi: yeni > gecikmiş > uyarı > nötr (renk + üst şerit). */
function cardStateClass(card: KdsOrderCard): string {
    if (newOrderIds.value.has(card.id)) return 'kds-card--new';
    const sla = cardSla(card);
    if (sla === 'late') return 'kds-card--late';
    if (sla === 'warn') return 'kds-card--warn';
    return '';
}

function slaBadgeClass(level: SlaLevel): string {
    return level === 'late' ? 'kds-sla--late' : level === 'warn' ? 'kds-sla--warn' : 'kds-sla--ok';
}

/** Kalem süresi metin rengi (küçük süre etiketi). */
function itemTimeClass(item: KdsItem): string {
    const l = itemSla(item);
    if (l === 'late') return 'text-[var(--kds-late)]';
    if (l === 'warn') return 'text-[var(--kds-warn)]';
    return 'text-[var(--kds-text-3)]';
}

const branchOptions = computed(() => branches.map((b) => ({ value: String(b.id), label: b.name })));
const pageTitle = computed(() => (station.value === 'bar' ? 'Bar Ekranı' : 'Mutfak Ekranı'));
</script>

<template>
    <Head :title="pageTitle" />

    <div class="kds-root fixed inset-0 flex flex-col overflow-hidden">
        <!-- ================= Üst çubuk ================= -->
        <header
            class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b px-4 py-2.5"
            style="background-color: var(--kds-bar); border-color: var(--kds-border)"
        >
            <a href="/panel" class="kds-btn kds-btn--neutral w-11 px-0" aria-label="Panele dön">
                <AppIcon name="arrow-left" :size="22" />
            </a>

            <h1 class="flex items-center gap-2.5 text-xl font-bold tracking-wide">
                <span
                    class="flex h-9 w-9 items-center justify-center rounded-lg"
                    style="background-color: var(--kds-accent-soft); color: var(--kds-accent)"
                >
                    <KdsIcon :name="station === 'bar' ? 'glass' : 'flame'" :size="22" />
                </span>
                {{ pageTitle }}
            </h1>

            <!-- Sayaçlar: sayı + etiket + (gecikende) ikon — yalnız renge güvenmez -->
            <span class="kds-chip kds-num text-base" title="Bekleyen kalem">
                <strong class="text-lg" style="color: var(--kds-text)">{{ totalPending }}</strong>
                bekleyen
            </span>

            <span
                v-if="lateCount > 0"
                class="kds-chip kds-late-badge kds-num text-base"
                style="background-color: var(--kds-late-fill); color: #fff"
                role="alert"
            >
                <AppIcon name="alert-triangle" :size="18" />
                <strong class="text-lg">{{ lateCount }}</strong>
                GECİKEN
            </span>

            <div class="ml-auto flex flex-wrap items-center gap-2">
                <div v-if="branchOptions.length > 1" class="kds-select w-44">
                    <BaseSelect
                        :model-value="String(branchId)"
                        :options="branchOptions"
                        @update:model-value="selectBranch(String($event))"
                    />
                </div>

                <a v-if="meta.canDeliver" href="/panel/komi" class="kds-btn kds-btn--neutral text-base">
                    <KdsIcon name="tray" :size="20" />
                    Komi
                </a>

                <button
                    v-if="meta.canManageStations"
                    class="kds-btn kds-btn--neutral text-base"
                    @click="showStations = true"
                >
                    <AppIcon name="settings" :size="20" />
                    İstasyonlar
                </button>

                <!-- görünüm anahtarları: tek grup halinde -->
                <div
                    class="flex items-center gap-1 rounded-xl p-1"
                    style="background-color: var(--kds-inset)"
                >
                    <button
                        class="kds-btn w-11 min-h-[2.25rem] rounded-lg px-0"
                        :style="soundOn
                            ? 'background-color: var(--kds-ok-fill); color: #fff'
                            : 'background-color: transparent; color: var(--kds-text-2)'"
                        :aria-label="soundOn ? 'Sesi kapat' : 'Sesi aç'"
                        :title="soundOn ? 'Yeni sipariş sesi: AÇIK' : 'Yeni sipariş sesi: KAPALI'"
                        @click="toggleSound"
                    >
                        <KdsIcon :name="soundOn ? 'volume-on' : 'volume-off'" :size="21" />
                    </button>
                    <button
                        class="kds-btn w-11 min-h-[2.25rem] rounded-lg px-0"
                        :style="compact
                            ? 'background-color: var(--kds-inset-hover); color: var(--kds-text)'
                            : 'background-color: transparent; color: var(--kds-text-2)'"
                        :aria-label="compact ? 'Normal görünüm' : 'Yoğun görünüm'"
                        :title="compact ? 'Normal görünüm' : 'Yoğun görünüm (daha çok kart)'"
                        @click="toggleCompact"
                    >
                        <AppIcon name="dashboard" :size="21" />
                    </button>
                    <button
                        class="kds-btn w-11 min-h-[2.25rem] rounded-lg px-0"
                        style="background-color: transparent; color: var(--kds-text-2)"
                        :aria-label="isFullscreen ? 'Tam ekrandan çık' : 'Tam ekran'"
                        @click="toggleFullscreen"
                    >
                        <KdsIcon :name="isFullscreen ? 'compress' : 'expand'" :size="21" />
                    </button>
                </div>
            </div>
        </header>

        <!-- ================= İstasyon süzgeci ================= -->
        <div
            class="flex flex-wrap items-center gap-2 border-b px-4 py-2.5"
            style="background-color: var(--kds-bg); border-color: var(--kds-border)"
        >
            <button
                v-if="showAllChip"
                class="kds-pill"
                :class="station === '' ? 'kds-pill--active' : ''"
                @click="selectStation('')"
            >
                Tümü
            </button>
            <button
                v-for="s in stationChips"
                :key="s.key"
                class="kds-pill"
                :class="station === s.key ? 'kds-pill--active' : ''"
                @click="selectStation(s.key)"
            >
                {{ s.name }}
                <span
                    v-for="row in summary.filter((r) => r.station === s.key && r.pending > 0)"
                    :key="row.station ?? '_'"
                    class="kds-pill__count kds-num"
                >
                    {{ row.pending }}
                </span>
            </button>
        </div>

        <!-- ================= Kuyruk ================= -->
        <main class="flex-1 overflow-y-auto" :class="compact ? 'p-3' : 'p-4'">
            <div
                v-if="loading"
                class="flex h-full items-center justify-center gap-3 text-2xl"
                style="color: var(--kds-text-2)"
            >
                <span class="kds-live-dot h-3 w-3 rounded-full" style="background-color: var(--kds-accent)" />
                Kuyruk yükleniyor…
            </div>

            <!-- Boş durum: sakin, bilgilendirici -->
            <div v-else-if="orders.length === 0" class="flex h-full flex-col items-center justify-center gap-5 px-6">
                <span
                    class="flex h-28 w-28 items-center justify-center rounded-full border"
                    style="background-color: var(--kds-card); border-color: var(--kds-border-strong); color: var(--kds-ok)"
                >
                    <AppIcon name="check-circle" :size="56" />
                </span>
                <div class="text-center">
                    <p class="text-3xl font-bold">Bekleyen sipariş yok</p>
                    <p class="mt-2 text-lg" style="color: var(--kds-text-2)">
                        Yeni sipariş geldiğinde burada belirir<span v-if="soundOn"> ve ses çalar</span>.
                    </p>
                </div>
                <span class="kds-chip text-sm font-medium">
                    <span class="kds-live-dot h-2.5 w-2.5 rounded-full" style="background-color: var(--kds-ok)" />
                    Canlı — her {{ meta.config.poll_interval_seconds }} saniyede bir yenilenir
                </span>
            </div>

            <div
                v-else
                class="grid items-start"
                :class="compact ? 'gap-3' : 'gap-4'"
                :style="`grid-template-columns: repeat(auto-fill, minmax(${compact ? '300px' : '370px'}, 1fr))`"
            >
                <article v-for="card in orders" :key="card.id" class="kds-card" :class="cardStateClass(card)">
                    <!-- Kart başlığı: MASA en baskın öğe -->
                    <div
                        class="flex items-start justify-between gap-3 border-b px-4 pb-2.5 pt-2"
                        style="border-color: var(--kds-border); background-color: var(--kds-card-head)"
                    >
                        <div class="min-w-0">
                            <p
                                class="truncate font-bold leading-tight tracking-tight"
                                :class="compact ? 'text-2xl' : 'text-3xl'"
                            >
                                {{ card.table_name ?? card.customer_name ?? `Sipariş #${card.id}` }}
                            </p>
                            <p
                                class="mt-1 flex flex-wrap items-center gap-x-2.5 gap-y-0.5 text-sm font-medium"
                                style="color: var(--kds-text-3)"
                            >
                                <span class="inline-flex items-center gap-1 uppercase tracking-wide">
                                    <AppIcon :name="card.channel_icon" :size="14" />
                                    {{ card.channel_label }}
                                </span>
                                <span v-if="card.area_name">· {{ card.area_name }}</span>
                                <span v-if="card.waiter" class="inline-flex items-center gap-1">
                                    · <AppIcon name="user" :size="14" /> {{ card.waiter }}
                                </span>
                                <span v-if="card.guest_count" class="inline-flex items-center gap-1">
                                    · <AppIcon name="users" :size="14" /> {{ card.guest_count }}
                                </span>
                            </p>
                        </div>

                        <!-- SLA: renk + ikon + süre + durum SÖZCÜĞÜ birlikte -->
                        <span class="kds-sla shrink-0" :class="slaBadgeClass(cardSla(card))">
                            <span class="kds-num flex items-center gap-1.5 text-lg font-bold leading-none">
                                <KdsIcon :name="cardSla(card) === 'ok' ? 'clock' : 'timer'" :size="18" />
                                {{ slaText(waitMinutes(card.placed_at)) }}
                            </span>
                            <span class="mt-0.5 text-[11px] font-bold tracking-widest">
                                {{ cardSla(card) === 'late' ? 'GECİKTİ' : cardSla(card) === 'warn' ? 'UYARI' : 'SÜRE' }}
                            </span>
                        </span>
                    </div>

                    <!-- Sipariş notu -->
                    <p
                        v-if="card.note"
                        class="flex items-start gap-2 border-b px-4 py-2 text-base font-medium"
                        style="background-color: var(--kds-note); border-color: var(--kds-border); color: var(--kds-info)"
                    >
                        <AppIcon name="info" :size="18" class="mt-0.5 shrink-0" />
                        {{ card.note }}
                    </p>

                    <!-- Kalemler -->
                    <ul class="flex-1 divide-y" style="border-color: var(--kds-border); --tw-divide-opacity: 1">
                        <li
                            v-for="item in card.items"
                            :key="item.id"
                            class="px-4"
                            :class="compact ? 'py-2' : 'py-2.5'"
                            :style="`border-color: var(--kds-border);${item.status === 'ready' ? 'background-color: rgb(74 222 128 / 0.05)' : ''}`"
                        >
                            <div class="flex items-start gap-3">
                                <span class="kds-qty shrink-0" :class="item.status === 'ready' ? 'kds-qty--done' : ''">
                                    {{ item.qty }}×
                                </span>

                                <div class="min-w-0 flex-1">
                                    <p
                                        class="font-bold leading-snug"
                                        :class="compact ? 'text-lg' : 'text-xl'"
                                        :style="item.status === 'ready' ? 'color: var(--kds-text-3)' : ''"
                                    >
                                        {{ item.name }}
                                        <span
                                            v-if="item.variant_name"
                                            class="font-medium"
                                            style="color: var(--kds-text-2)"
                                        >
                                            — {{ item.variant_name }}
                                        </span>
                                    </p>
                                    <p v-if="item.options.length" class="mt-0.5 text-base" style="color: var(--kds-text-2)">
                                        {{ item.options.join(' · ') }}
                                    </p>
                                    <p v-if="item.note" class="mt-0.5 text-base font-medium" style="color: var(--kds-info)">
                                        Not: {{ item.note }}
                                    </p>

                                    <!-- ALERJEN — ikinci en baskın öğe -->
                                    <p v-if="item.allergens.length" class="mt-1.5 flex flex-wrap items-center gap-1.5" role="alert">
                                        <span class="kds-allergen text-sm">
                                            <AppIcon name="alert-triangle" :size="15" />
                                            ALERJEN
                                        </span>
                                        <span v-for="a in item.allergens" :key="a.name" class="kds-allergen-tag text-sm">
                                            {{ a.name }}
                                        </span>
                                    </p>

                                    <!-- Diyet etiketleri — nötr, alerjenle karışmaz -->
                                    <p v-if="item.diets.length" class="mt-1 flex flex-wrap items-center gap-1.5">
                                        <span v-for="d in item.diets" :key="d" class="kds-diet-tag text-sm">{{ d }}</span>
                                    </p>

                                    <p
                                        v-if="!station"
                                        class="mt-1 text-xs font-bold uppercase tracking-widest"
                                        style="color: var(--kds-text-3)"
                                    >
                                        {{ item.station_label }}
                                    </p>

                                    <!-- Geri al: bilinçli olarak SOL tarafta — sağdaki
                                         "Hazır/Başlat" sütunundan uzak (yanlış dokunma) -->
                                    <button
                                        v-if="item.status === 'ready'"
                                        class="kds-btn kds-btn--ghost mt-2 text-sm"
                                        :disabled="busy"
                                        title="Yanlışlıkla hazır işaretlendiyse geri al"
                                        @click="undoItem(card, item)"
                                    >
                                        <KdsIcon name="undo" :size="15" /> Geri al
                                    </button>
                                </div>

                                <!-- Sağ sütun: süre + birincil eylem -->
                                <div class="flex shrink-0 flex-col items-end gap-2">
                                    <span
                                        class="kds-num flex items-center gap-1 text-sm font-bold"
                                        :class="itemTimeClass(item)"
                                    >
                                        <KdsIcon name="clock" :size="14" />
                                        {{ slaText(waitMinutes(item.created_at)) }}
                                    </span>

                                    <button
                                        v-if="['placed', 'sent_to_station'].includes(item.status)"
                                        class="kds-btn kds-btn--info kds-btn--lg min-w-[7.5rem]"
                                        :disabled="busy"
                                        @click="advance(card, item, 'accepted')"
                                    >
                                        Kabul
                                    </button>
                                    <button
                                        v-else-if="item.status === 'accepted'"
                                        class="kds-btn kds-btn--warn kds-btn--lg min-w-[7.5rem]"
                                        :disabled="busy"
                                        @click="advance(card, item, 'preparing')"
                                    >
                                        Başlat
                                    </button>
                                    <button
                                        v-else-if="item.status === 'preparing'"
                                        class="kds-btn kds-btn--success kds-btn--lg min-w-[7.5rem]"
                                        :disabled="busy"
                                        @click="advance(card, item, 'ready')"
                                    >
                                        Hazır
                                    </button>
                                    <span
                                        v-else-if="item.status === 'ready'"
                                        class="flex items-center gap-1.5 text-lg font-bold"
                                        style="color: var(--kds-ok)"
                                    >
                                        <AppIcon name="check-circle" :size="20" /> Hazır
                                    </span>

                                    <!-- İstasyon transferi: ikincil, hayalet -->
                                    <button
                                        v-if="item.status !== 'ready'"
                                        class="kds-btn kds-btn--ghost w-11 px-0"
                                        :disabled="busy"
                                        title="Başka istasyona transfer et"
                                        :aria-label="'Transfer: ' + item.name"
                                        @click="openTransfer(card, item)"
                                    >
                                        <KdsIcon name="swap" :size="17" />
                                    </button>
                                </div>
                            </div>
                        </li>
                    </ul>

                    <!-- Kart altı: tümü hazır -->
                    <div class="border-t p-2.5" style="border-color: var(--kds-border)">
                        <button
                            v-if="pendingItems(card).length > 0"
                            class="kds-btn kds-btn--success h-14 w-full text-lg font-bold tracking-wide"
                            :disabled="busy"
                            @click="allReady(card)"
                        >
                            <AppIcon name="check-circle" :size="22" />
                            TÜMÜ HAZIR ({{ pendingItems(card).length }})
                        </button>
                        <p
                            v-else
                            class="flex h-12 items-center justify-center gap-2 rounded-lg text-base font-bold"
                            style="background-color: rgb(74 222 128 / 0.1); color: var(--kds-ok)"
                        >
                            <KdsIcon name="tray" :size="20" />
                            Servis bekliyor — komi çağrıldı
                        </p>
                    </div>
                </article>
            </div>
        </main>
    </div>

    <!-- ================= Transfer modalı ================= -->
    <BaseModal :open="transferTarget !== null" title="İstasyon transferi" @close="transferTarget = null">
        <div v-if="transferTarget" class="space-y-4">
            <p class="text-base">
                <strong>{{ transferTarget.item.qty }}× {{ transferTarget.item.name }}</strong>
                kalemi <strong>{{ transferTarget.item.station_label }}</strong> istasyonundan taşınacak.
            </p>
            <BaseSelect v-model="transferStation" :options="transferOptions" placeholder="Hedef istasyon seçin" />
            <div class="flex justify-end gap-2">
                <button
                    class="h-11 rounded-lg bg-inset px-4 font-semibold text-body"
                    @click="transferTarget = null"
                >
                    Vazgeç
                </button>
                <button
                    class="h-11 rounded-lg bg-primary px-4 font-bold text-on-primary disabled:opacity-50"
                    :disabled="!transferStation || busy"
                    @click="doTransfer"
                >
                    Transfer et
                </button>
            </div>
        </div>
    </BaseModal>

    <!-- ================= İstasyon yönetimi ================= -->
    <StationManager v-if="meta.canManageStations" :open="showStations" @close="showStations = false" />

    <ToastHost />
</template>
