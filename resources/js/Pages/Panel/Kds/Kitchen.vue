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

function cardBorder(card: KdsOrderCard): string {
    if (newOrderIds.value.has(card.id)) return 'border-sky-400 ring-4 ring-sky-400/40 kds-new';
    const sla = cardSla(card);
    if (sla === 'late') return 'border-red-500 ring-2 ring-red-500/40';
    if (sla === 'warn') return 'border-amber-400';
    return 'border-slate-700';
}

function slaChipClass(level: SlaLevel): string {
    if (level === 'late') return 'bg-red-600 text-white';
    if (level === 'warn') return 'bg-amber-500 text-slate-950';
    return 'bg-slate-700 text-slate-100';
}

const branchOptions = computed(() => branches.map((b) => ({ value: String(b.id), label: b.name })));
const pageTitle = computed(() => (station.value === 'bar' ? 'Bar Ekranı' : 'Mutfak Ekranı'));
</script>

<template>
    <Head :title="pageTitle" />

    <div class="fixed inset-0 flex flex-col overflow-hidden bg-slate-950 text-slate-100">
        <!-- ================= Üst çubuk ================= -->
        <header class="flex flex-wrap items-center gap-2 border-b border-slate-800 bg-slate-900 px-3 py-2">
            <a
                href="/panel"
                class="flex h-11 w-11 items-center justify-center rounded-lg bg-slate-800 text-slate-300 hover:bg-slate-700"
                aria-label="Panele dön"
            >
                <AppIcon name="arrow-left" :size="22" />
            </a>

            <h1 class="flex items-center gap-2 text-xl font-bold tracking-wide">
                <KdsIcon :name="station === 'bar' ? 'glass' : 'flame'" :size="24" class="text-orange-400" />
                {{ pageTitle }}
            </h1>

            <span
                class="ml-1 rounded-full bg-slate-800 px-3 py-1 text-base font-semibold text-slate-300"
                :title="'Bekleyen kalem'"
            >
                {{ totalPending }} bekleyen
            </span>

            <span
                v-if="lateCount > 0"
                class="flex items-center gap-1 rounded-full bg-red-600 px-3 py-1 text-base font-bold text-white"
                role="alert"
            >
                <AppIcon name="alert-triangle" :size="18" />
                {{ lateCount }} GECİKEN
            </span>

            <div class="ml-auto flex items-center gap-2">
                <BaseSelect
                    v-if="branchOptions.length > 1"
                    :model-value="String(branchId)"
                    :options="branchOptions"
                    class="w-40"
                    @update:model-value="selectBranch(String($event))"
                />

                <a
                    v-if="meta.canDeliver"
                    href="/panel/komi"
                    class="flex h-11 items-center gap-2 rounded-lg bg-slate-800 px-3 text-base font-semibold text-slate-200 hover:bg-slate-700"
                >
                    <KdsIcon name="tray" :size="20" />
                    Komi
                </a>

                <button
                    v-if="meta.canManageStations"
                    class="flex h-11 items-center gap-2 rounded-lg bg-slate-800 px-3 text-base font-semibold text-slate-200 hover:bg-slate-700"
                    @click="showStations = true"
                >
                    <AppIcon name="settings" :size="20" />
                    İstasyonlar
                </button>

                <button
                    class="flex h-11 w-11 items-center justify-center rounded-lg text-slate-200"
                    :class="soundOn ? 'bg-emerald-700 hover:bg-emerald-600' : 'bg-slate-800 hover:bg-slate-700'"
                    :aria-label="soundOn ? 'Sesi kapat' : 'Sesi aç'"
                    :title="soundOn ? 'Yeni sipariş sesi: AÇIK' : 'Yeni sipariş sesi: KAPALI'"
                    @click="toggleSound"
                >
                    <KdsIcon :name="soundOn ? 'volume-on' : 'volume-off'" :size="22" />
                </button>

                <button
                    class="flex h-11 w-11 items-center justify-center rounded-lg bg-slate-800 text-slate-200 hover:bg-slate-700"
                    :aria-label="compact ? 'Normal görünüm' : 'Yoğun görünüm'"
                    :title="compact ? 'Normal görünüm' : 'Yoğun görünüm (daha çok kart)'"
                    @click="toggleCompact"
                >
                    <AppIcon name="dashboard" :size="22" />
                </button>

                <button
                    class="flex h-11 w-11 items-center justify-center rounded-lg bg-slate-800 text-slate-200 hover:bg-slate-700"
                    :aria-label="isFullscreen ? 'Tam ekrandan çık' : 'Tam ekran'"
                    @click="toggleFullscreen"
                >
                    <KdsIcon :name="isFullscreen ? 'compress' : 'expand'" :size="22" />
                </button>
            </div>
        </header>

        <!-- ================= İstasyon süzgeci + özet ================= -->
        <div class="flex flex-wrap items-center gap-2 border-b border-slate-800 bg-slate-900/60 px-3 py-2">
            <button
                v-if="showAllChip"
                class="h-11 rounded-full px-4 text-base font-bold"
                :class="station === '' ? 'bg-orange-500 text-slate-950' : 'bg-slate-800 text-slate-300 hover:bg-slate-700'"
                @click="selectStation('')"
            >
                Tümü
            </button>
            <button
                v-for="s in stationChips"
                :key="s.key"
                class="h-11 rounded-full px-4 text-base font-bold"
                :class="station === s.key ? 'bg-orange-500 text-slate-950' : 'bg-slate-800 text-slate-300 hover:bg-slate-700'"
                @click="selectStation(s.key)"
            >
                {{ s.name }}
                <span
                    v-for="row in summary.filter((r) => r.station === s.key && r.pending > 0)"
                    :key="row.station ?? '_'"
                    class="ml-1 rounded-full bg-slate-950/40 px-2 py-0.5 text-sm"
                >
                    {{ row.pending }}
                </span>
            </button>
        </div>

        <!-- ================= Kuyruk ================= -->
        <main class="flex-1 overflow-y-auto p-3">
            <div v-if="loading" class="flex h-full items-center justify-center text-2xl text-slate-400">
                Kuyruk yükleniyor…
            </div>

            <div
                v-else-if="orders.length === 0"
                class="flex h-full flex-col items-center justify-center gap-3 text-slate-400"
            >
                <AppIcon name="check-circle" :size="64" class="text-emerald-500" />
                <p class="text-3xl font-bold">Bekleyen sipariş yok</p>
                <p class="text-lg">Yeni sipariş geldiğinde burada belirir<span v-if="soundOn"> ve ses çalar</span>.</p>
            </div>

            <div
                v-else
                class="grid gap-3"
                :class="compact ? 'grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5' : 'grid-cols-1 md:grid-cols-2 xl:grid-cols-3'"
            >
                <article
                    v-for="card in orders"
                    :key="card.id"
                    class="flex flex-col overflow-hidden rounded-xl border-2 bg-slate-900"
                    :class="cardBorder(card)"
                >
                    <!-- Kart başlığı -->
                    <div class="flex items-start justify-between gap-2 border-b border-slate-800 px-3 py-2">
                        <div class="min-w-0">
                            <div class="flex items-center gap-2">
                                <span class="truncate text-2xl font-black leading-tight">
                                    {{ card.table_name ?? card.customer_name ?? `Sipariş #${card.id}` }}
                                </span>
                                <span
                                    class="flex shrink-0 items-center gap-1 rounded-md bg-slate-800 px-2 py-0.5 text-sm font-bold uppercase tracking-wide text-slate-300"
                                >
                                    <AppIcon :name="card.channel_icon" :size="14" />
                                    {{ card.channel_label }}
                                </span>
                            </div>
                            <div class="mt-0.5 flex flex-wrap items-center gap-x-3 text-base text-slate-400">
                                <span v-if="card.area_name">{{ card.area_name }}</span>
                                <span v-if="card.waiter" class="flex items-center gap-1">
                                    <AppIcon name="user" :size="14" /> {{ card.waiter }}
                                </span>
                                <span v-if="card.guest_count" class="flex items-center gap-1">
                                    <AppIcon name="users" :size="14" /> {{ card.guest_count }}
                                </span>
                            </div>
                        </div>

                        <!-- SLA: renk + ikon + süre metni birlikte -->
                        <span
                            class="flex shrink-0 items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-lg font-black"
                            :class="slaChipClass(cardSla(card))"
                        >
                            <KdsIcon :name="cardSla(card) === 'ok' ? 'clock' : 'timer'" :size="20" />
                            {{ slaText(waitMinutes(card.placed_at)) }}
                            <span v-if="cardSla(card) === 'late'" class="text-sm font-bold">GECİKTİ</span>
                            <span v-else-if="cardSla(card) === 'warn'" class="text-sm font-bold">UYARI</span>
                        </span>
                    </div>

                    <!-- Sipariş notu -->
                    <p
                        v-if="card.note"
                        class="flex items-start gap-2 border-b border-slate-800 bg-sky-950/60 px-3 py-2 text-lg font-semibold text-sky-200"
                    >
                        <AppIcon name="info" :size="20" class="mt-0.5 shrink-0" />
                        {{ card.note }}
                    </p>

                    <!-- Kalemler -->
                    <ul class="flex-1 divide-y divide-slate-800">
                        <li v-for="item in card.items" :key="item.id" class="px-3 py-2">
                            <div class="flex items-start justify-between gap-2">
                                <div class="min-w-0">
                                    <p class="text-xl font-bold leading-snug" :class="item.status === 'ready' ? 'text-emerald-400' : ''">
                                        <span class="mr-1 inline-block rounded-md bg-slate-800 px-2 text-orange-300">{{ item.qty }}×</span>
                                        {{ item.name }}
                                        <span v-if="item.variant_name" class="text-slate-400">— {{ item.variant_name }}</span>
                                    </p>
                                    <p v-if="item.options.length" class="mt-0.5 text-base text-slate-400">
                                        {{ item.options.join(' · ') }}
                                    </p>
                                    <p v-if="item.note" class="mt-0.5 text-base font-semibold text-sky-300">
                                        Not: {{ item.note }}
                                    </p>

                                    <!-- ALERJEN — belirgin -->
                                    <p
                                        v-if="item.allergens.length"
                                        class="mt-1 flex flex-wrap items-center gap-1.5"
                                        role="alert"
                                    >
                                        <span
                                            class="flex items-center gap-1 rounded-md bg-red-600 px-2 py-0.5 text-base font-black text-white"
                                        >
                                            <AppIcon name="alert-triangle" :size="16" />
                                            ALERJEN
                                        </span>
                                        <span
                                            v-for="a in item.allergens"
                                            :key="a.name"
                                            class="rounded-md border border-red-500 px-2 py-0.5 text-base font-bold text-red-300"
                                        >
                                            {{ a.name }}
                                        </span>
                                    </p>

                                    <!-- Diyet etiketleri (vegan vb.) — nötr, alerjenle karışmaz -->
                                    <p v-if="item.diets.length" class="mt-1 flex flex-wrap items-center gap-1.5">
                                        <span
                                            v-for="d in item.diets"
                                            :key="d"
                                            class="rounded-md border border-slate-600 px-2 py-0.5 text-sm font-semibold text-slate-400"
                                        >
                                            {{ d }}
                                        </span>
                                    </p>

                                    <p v-if="!station" class="mt-1 text-sm font-semibold uppercase tracking-wide text-slate-500">
                                        {{ item.station_label }}
                                    </p>
                                </div>

                                <!-- Kalem eylemi -->
                                <div class="flex shrink-0 flex-col items-end gap-1.5">
                                    <span
                                        class="flex items-center gap-1 text-sm font-bold"
                                        :class="itemSla(item) === 'late' ? 'text-red-400' : itemSla(item) === 'warn' ? 'text-amber-300' : 'text-slate-500'"
                                    >
                                        <KdsIcon name="clock" :size="14" />
                                        {{ slaText(waitMinutes(item.created_at)) }}
                                    </span>

                                    <button
                                        v-if="['placed', 'sent_to_station'].includes(item.status)"
                                        class="h-12 min-w-[7rem] rounded-lg bg-sky-600 px-3 text-lg font-bold text-white hover:bg-sky-500"
                                        :disabled="busy"
                                        @click="advance(card, item, 'accepted')"
                                    >
                                        Kabul
                                    </button>
                                    <button
                                        v-else-if="item.status === 'accepted'"
                                        class="h-12 min-w-[7rem] rounded-lg bg-amber-500 px-3 text-lg font-bold text-slate-950 hover:bg-amber-400"
                                        :disabled="busy"
                                        @click="advance(card, item, 'preparing')"
                                    >
                                        Başlat
                                    </button>
                                    <button
                                        v-else-if="item.status === 'preparing'"
                                        class="h-12 min-w-[7rem] rounded-lg bg-emerald-600 px-3 text-lg font-bold text-white hover:bg-emerald-500"
                                        :disabled="busy"
                                        @click="advance(card, item, 'ready')"
                                    >
                                        Hazır
                                    </button>
                                    <span
                                        v-else-if="item.status === 'ready'"
                                        class="flex items-center gap-1 text-lg font-bold text-emerald-400"
                                    >
                                        <AppIcon name="check-circle" :size="20" /> Hazır
                                    </span>

                                    <div class="flex gap-1.5">
                                        <!-- Geri al (yanlış işaret) -->
                                        <button
                                            v-if="item.status === 'ready'"
                                            class="flex h-10 items-center gap-1 rounded-lg bg-slate-800 px-2.5 text-base font-semibold text-slate-300 hover:bg-slate-700"
                                            :disabled="busy"
                                            title="Yanlışlıkla hazır işaretlendiyse geri al"
                                            @click="undoItem(card, item)"
                                        >
                                            <KdsIcon name="undo" :size="16" /> Geri al
                                        </button>
                                        <!-- İstasyon transferi -->
                                        <button
                                            v-if="!['ready'].includes(item.status)"
                                            class="flex h-10 items-center gap-1 rounded-lg bg-slate-800 px-2.5 text-base font-semibold text-slate-300 hover:bg-slate-700"
                                            :disabled="busy"
                                            title="Başka istasyona transfer et"
                                            @click="openTransfer(card, item)"
                                        >
                                            <KdsIcon name="swap" :size="16" />
                                        </button>
                                    </div>
                                </div>
                            </div>
                        </li>
                    </ul>

                    <!-- Kart altı: tümü hazır -->
                    <div class="border-t border-slate-800 p-2">
                        <button
                            v-if="pendingItems(card).length > 0"
                            class="h-14 w-full rounded-lg bg-emerald-600 text-xl font-black text-white hover:bg-emerald-500"
                            :disabled="busy"
                            @click="allReady(card)"
                        >
                            TÜMÜ HAZIR ({{ pendingItems(card).length }})
                        </button>
                        <p v-else class="flex h-12 items-center justify-center gap-2 text-lg font-bold text-emerald-400">
                            <KdsIcon name="tray" :size="22" />
                            Servis bekliyor — komi çağrıldı
                        </p>
                    </div>
                </article>
            </div>
        </main>
    </div>

    <!-- ================= Transfer modalı ================= -->
    <BaseModal
        :open="transferTarget !== null"
        title="İstasyon transferi"
        @close="transferTarget = null"
    >
        <div v-if="transferTarget" class="space-y-4">
            <p class="text-base">
                <strong>{{ transferTarget.item.qty }}× {{ transferTarget.item.name }}</strong>
                kalemi <strong>{{ transferTarget.item.station_label }}</strong> istasyonundan taşınacak.
            </p>
            <BaseSelect v-model="transferStation" :options="transferOptions" placeholder="Hedef istasyon seçin" />
            <div class="flex justify-end gap-2">
                <button
                    class="h-11 rounded-lg bg-slate-200 px-4 font-semibold text-slate-800 dark:bg-slate-700 dark:text-slate-100"
                    @click="transferTarget = null"
                >
                    Vazgeç
                </button>
                <button
                    class="h-11 rounded-lg bg-orange-500 px-4 font-bold text-white disabled:opacity-50"
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

<style scoped>
@keyframes kds-pulse {
    0%, 100% { box-shadow: 0 0 0 0 rgba(56, 189, 248, 0.55); }
    50% { box-shadow: 0 0 0 10px rgba(56, 189, 248, 0); }
}
.kds-new {
    animation: kds-pulse 1.2s ease-in-out 6;
}
</style>
