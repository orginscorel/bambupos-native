<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import ToastHost from '@/Components/ui/ToastHost.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import KdsIcon from './KdsIcon.vue';
import './kds-theme.css';
import {
    createKdsSound,
    createPollingFeed,
    getOrNull,
    metaFromKdsProps,
    minutesSince,
    slaText,
    type KdsFeed,
    type RunnerItem,
    type RunnerPayload,
} from './kds';

/**
 * KOMİ EKRANI — hazır ürünler: masa/salon, ürün, hazırlayan istasyon,
 * bekleme süresi, öncelik (en uzun bekleyen üstte), alerjen notu.
 * "Teslim aldım" (pickup) ve "Masaya götürdüm" (served) AYRI adımlardır —
 * görsel dil mutfakla ortak (kds-theme.css), iş akışı iki adımlı şerit.
 */
const page = usePage();
const meta = metaFromKdsProps(page.props as Record<string, unknown>);
const { success, danger, warning } = useToast();

const auth = page.props.auth as {
    branches?: { id: number; name: string }[];
    activeBranchId?: number | null;
} | null;
const branches = auth?.branches ?? [];
const branchId = ref<number>(auth?.activeBranchId ?? branches[0]?.id ?? 0);

const loading = ref(true);
const items = ref<RunnerItem[]>([]);
const serverSkewMs = ref(0);
const knownItemIds = new Set<number>();
const newItemIds = ref<Set<number>>(new Set());
let feed: KdsFeed | null = null;

const sound = createKdsSound('kds_runner_sound');
const soundOn = ref(sound.enabled());

function applyPayload(payload: RunnerPayload, silent = false): void {
    serverSkewMs.value = new Date(payload.server_time).getTime() - Date.now();

    const fresh = new Set<number>();
    for (const i of payload.items) {
        if (!knownItemIds.has(i.id)) fresh.add(i.id);
        knownItemIds.add(i.id);
    }

    items.value = payload.items;
    loading.value = false;

    if (!silent && fresh.size > 0) {
        newItemIds.value = fresh;
        sound.beep(2);
        setTimeout(() => (newItemIds.value = new Set()), 10000);
    }
}

function buildFeed(): KdsFeed {
    let first = true;
    return createPollingFeed<RunnerPayload>({
        fetchFull: () => api<RunnerPayload>(`/api/v1/kds/queue?mode=runner&branch_id=${branchId.value}`),
        fetchDelta: (cursor) =>
            getOrNull<RunnerPayload>(`/api/v1/kds/updates?mode=runner&branch_id=${branchId.value}&cursor=${cursor}`),
        onData: (payload) => {
            applyPayload(payload, first);
            first = false;
        },
        onError: () => {
            /* geçici ağ hatası — sonraki yoklamada düzelir */
        },
        intervalMs: meta.config.poll_interval_seconds * 1000,
    });
}

async function restartFeed(): Promise<void> {
    feed?.stop();
    knownItemIds.clear();
    loading.value = true;
    feed = buildFeed();
    try {
        await feed.load();
    } catch (e) {
        loading.value = false;
        danger('Liste yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Bağlantıyı kontrol edin.');
    }
    feed.start();
}

let clockTimer: ReturnType<typeof setInterval> | null = null;
const clockTick = ref(Date.now());

onMounted(() => {
    void restartFeed();
    const unlock = () => sound.unlock();
    window.addEventListener('pointerdown', unlock, { once: true });
    clockTimer = setInterval(() => (clockTick.value = Date.now()), 30000);
});

onBeforeUnmount(() => {
    feed?.stop();
    if (clockTimer) clearInterval(clockTimer);
});

function waitMinutes(iso: string | null): number {
    void clockTick.value;
    return minutesSince(iso, serverSkewMs.value);
}

/** Öncelik: en uzun süredir hazır bekleyen üstte. */
const sorted = computed(() =>
    [...items.value].sort((a, b) => new Date(a.updated_at ?? 0).getTime() - new Date(b.updated_at ?? 0).getTime()),
);

/** Bekleme aciliyeti: 5+ dk gecikmiş, 2+ dk uyarı. */
function waitLevel(item: RunnerItem): 'ok' | 'warn' | 'late' {
    const m = waitMinutes(item.updated_at);
    return m >= 5 ? 'late' : m >= 2 ? 'warn' : 'ok';
}

function rowStateClass(item: RunnerItem): string {
    if (newItemIds.value.has(item.id)) return 'kds-card--new';
    const l = waitLevel(item);
    return l === 'late' ? 'kds-card--late' : l === 'warn' ? 'kds-card--warn' : '';
}

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
            warning('Eşzamanlı değişiklik', 'Sipariş başka ekrandan değişti; liste tazelendi.');
            await feed?.refresh();
        } else {
            danger('İşlem tamamlanamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
        }
    } finally {
        busy.value = false;
    }
}

function pickup(item: RunnerItem): void {
    void runAction(() => api(`/api/v1/kds/items/${item.id}/pickup`, { method: 'POST' }), 'Teslim alındı');
}

function undoPickup(item: RunnerItem): void {
    void runAction(() => api(`/api/v1/kds/items/${item.id}/pickup`, { method: 'DELETE' }), 'Teslim işareti geri alındı');
}

/** Yanlış "götürdüm" işaretini geri alabilmek için son teslimler tutulur. */
const recentDelivered = ref<{ id: number; label: string; at: number }[]>([]);

function delivered(item: RunnerItem): void {
    void runAction(
        () =>
            api(`/api/v1/kds/items/${item.id}/status`, {
                method: 'POST',
                body: { to: 'served', expected_version: item.order_version },
            }),
        'Masaya götürüldü',
    ).then(() => {
        recentDelivered.value = [
            { id: item.id, label: `${item.qty}× ${item.name} → ${item.table_name ?? item.channel_label}`, at: Date.now() },
            ...recentDelivered.value.filter((r) => r.id !== item.id),
        ].slice(0, 5);
    });
}

function undoServe(id: number): void {
    void runAction(() => api(`/api/v1/kds/items/${id}/undo`, { method: 'POST', body: {} }), 'Servis işareti geri alındı').then(
        () => (recentDelivered.value = recentDelivered.value.filter((r) => r.id !== id)),
    );
}

function toggleSound(): void {
    sound.unlock();
    sound.setEnabled(!soundOn.value);
    soundOn.value = !soundOn.value;
    if (soundOn.value) sound.beep(1);
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

const branchOptions = computed(() => branches.map((b) => ({ value: String(b.id), label: b.name })));
function selectBranch(id: string): void {
    branchId.value = Number(id);
    void restartFeed();
}
</script>

<template>
    <Head title="Komi Ekranı" />

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
                    <KdsIcon name="tray" :size="22" />
                </span>
                Komi Ekranı
            </h1>

            <span class="kds-chip kds-num text-base" title="Servis bekleyen hazır ürün">
                <strong class="text-lg" style="color: var(--kds-text)">{{ items.length }}</strong>
                hazır ürün
            </span>

            <span v-if="items.length > 1" class="hidden text-sm font-medium sm:inline" style="color: var(--kds-text-3)">
                En uzun bekleyen üstte
            </span>

            <div class="ml-auto flex flex-wrap items-center gap-2">
                <div v-if="branchOptions.length > 1" class="kds-select w-44">
                    <BaseSelect
                        :model-value="String(branchId)"
                        :options="branchOptions"
                        @update:model-value="selectBranch(String($event))"
                    />
                </div>
                <div class="flex items-center gap-1 rounded-xl p-1" style="background-color: var(--kds-inset)">
                    <button
                        class="kds-btn w-11 min-h-[2.25rem] rounded-lg px-0"
                        :style="soundOn
                            ? 'background-color: var(--kds-ok-fill); color: #fff'
                            : 'background-color: transparent; color: var(--kds-text-2)'"
                        :aria-label="soundOn ? 'Sesi kapat' : 'Sesi aç'"
                        @click="toggleSound"
                    >
                        <KdsIcon :name="soundOn ? 'volume-on' : 'volume-off'" :size="21" />
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

        <!-- ================= Servis kuyruğu ================= -->
        <main class="flex-1 overflow-y-auto p-4">
            <div
                v-if="loading"
                class="flex h-full items-center justify-center gap-3 text-2xl"
                style="color: var(--kds-text-2)"
            >
                <span class="kds-live-dot h-3 w-3 rounded-full" style="background-color: var(--kds-accent)" />
                Liste yükleniyor…
            </div>

            <div v-else-if="sorted.length === 0" class="flex h-full flex-col items-center justify-center gap-5 px-6">
                <span
                    class="flex h-28 w-28 items-center justify-center rounded-full border"
                    style="background-color: var(--kds-card); border-color: var(--kds-border-strong); color: var(--kds-ok)"
                >
                    <KdsIcon name="tray" :size="52" />
                </span>
                <div class="text-center">
                    <p class="text-3xl font-bold">Taşınacak ürün yok</p>
                    <p class="mt-2 text-lg" style="color: var(--kds-text-2)">
                        Mutfak "hazır" verdiğinde ürünler burada belirir<span v-if="soundOn"> ve ses çalar</span>.
                    </p>
                </div>
                <span class="kds-chip text-sm font-medium">
                    <span class="kds-live-dot h-2.5 w-2.5 rounded-full" style="background-color: var(--kds-ok)" />
                    Canlı — her {{ meta.config.poll_interval_seconds }} saniyede bir yenilenir
                </span>
            </div>

            <ul v-else class="mx-auto max-w-[1600px] space-y-3">
                <li v-for="item in sorted" :key="item.id" class="kds-card" :class="rowStateClass(item)">
                    <div class="flex flex-wrap items-center gap-x-6 gap-y-3 px-4 py-3">
                        <!-- HEDEF: en baskın öğe — komi nereye gideceğini uzaktan okur -->
                        <div class="min-w-[11rem]">
                            <p class="text-3xl font-bold leading-none tracking-tight">
                                {{ item.table_name ?? item.channel_label }}
                            </p>
                            <p class="mt-1.5 text-sm font-medium" style="color: var(--kds-text-3)">
                                <span v-if="item.area_name">{{ item.area_name }} · </span>{{ item.channel_label }}
                                <span v-if="item.waiter"> · {{ item.waiter }}</span>
                            </p>
                        </div>

                        <!-- Ürün -->
                        <div class="min-w-0 flex-1 basis-72">
                            <p class="flex flex-wrap items-center gap-2">
                                <span class="kds-qty">{{ item.qty }}×</span>
                                <span class="text-xl font-bold leading-snug">
                                    {{ item.name }}
                                    <span v-if="item.variant_name" class="font-medium" style="color: var(--kds-text-2)">
                                        — {{ item.variant_name }}
                                    </span>
                                </span>
                            </p>
                            <p class="mt-1 flex flex-wrap items-center gap-x-2 text-base" style="color: var(--kds-text-2)">
                                <span class="inline-flex items-center gap-1">
                                    <KdsIcon name="flame" :size="14" /> {{ item.station_label }}
                                </span>
                                <span v-if="item.note" class="font-medium" style="color: var(--kds-info)">
                                    · Not: {{ item.note }}
                                </span>
                            </p>
                            <p v-if="item.allergens.length" class="mt-1.5 flex flex-wrap items-center gap-1.5" role="alert">
                                <span class="kds-allergen text-sm">
                                    <AppIcon name="alert-triangle" :size="14" /> ALERJEN
                                </span>
                                <span v-for="a in item.allergens" :key="a.name" class="kds-allergen-tag text-sm">
                                    {{ a.name }}
                                </span>
                                <span v-for="d in item.diets" :key="d" class="kds-diet-tag text-sm">{{ d }}</span>
                            </p>
                        </div>

                        <!-- Bekleme (hazır olalı): renk + ikon + metin + etiket -->
                        <span class="kds-sla shrink-0" :class="`kds-sla--${waitLevel(item)}`" title="Hazır olalı geçen süre">
                            <span class="kds-num flex items-center gap-1.5 text-lg font-bold leading-none">
                                <KdsIcon :name="waitLevel(item) === 'ok' ? 'clock' : 'timer'" :size="18" />
                                {{ slaText(waitMinutes(item.updated_at)) }}
                            </span>
                            <span class="mt-0.5 text-[11px] font-bold tracking-widest">
                                {{ waitLevel(item) === 'late' ? 'SOĞUYOR' : 'BEKLİYOR' }}
                            </span>
                        </span>

                        <!-- İki adımlı akış: 1 Teslim al → 2 Masaya götür -->
                        <div class="flex shrink-0 flex-wrap items-center gap-3">
                            <template v-if="!item.picked_up_at">
                                <button class="kds-btn kds-btn--info h-14 px-5 text-lg" :disabled="busy" @click="pickup(item)">
                                    <KdsIcon name="hand" :size="22" />
                                    <span><span class="mr-1.5 opacity-75">1</span>Teslim aldım</span>
                                </button>
                                <!-- 2. adım ipucu: henüz pasif -->
                                <span
                                    class="hidden items-center gap-2 rounded-[0.625rem] border border-dashed px-4 text-base font-bold lg:inline-flex"
                                    style="border-color: var(--kds-border-strong); color: var(--kds-text-3); min-height: 3.5rem"
                                >
                                    <KdsIcon name="tray" :size="20" />
                                    <span><span class="mr-1.5">2</span>Masaya götür</span>
                                </span>
                            </template>
                            <template v-else>
                                <!-- geri al: birincil butondan uzakta, "alındı" çipinin solunda -->
                                <button
                                    class="kds-btn kds-btn--ghost w-11 px-0"
                                    :disabled="busy"
                                    title="Teslim işaretini geri al"
                                    aria-label="Teslim işaretini geri al"
                                    @click="undoPickup(item)"
                                >
                                    <KdsIcon name="undo" :size="17" />
                                </button>
                                <span class="kds-chip text-sm" style="color: var(--kds-ok)">
                                    <AppIcon name="check" :size="16" />
                                    {{ item.picked_up_by ?? 'Alındı' }}
                                </span>
                                <button
                                    class="kds-btn kds-btn--success h-14 px-5 text-lg"
                                    :disabled="busy"
                                    @click="delivered(item)"
                                >
                                    <KdsIcon name="tray" :size="22" />
                                    <span><span class="mr-1.5 opacity-75">2</span>Masaya götürdüm</span>
                                </button>
                            </template>
                        </div>
                    </div>
                </li>
            </ul>
        </main>

        <!-- Son götürülenler: yanlış işareti geri alma şeridi -->
        <footer
            v-if="recentDelivered.length > 0"
            class="flex flex-wrap items-center gap-2 border-t px-4 py-2.5"
            style="background-color: var(--kds-bar); border-color: var(--kds-border)"
        >
            <span class="text-sm font-bold uppercase tracking-wider" style="color: var(--kds-text-3)">
                Son götürülenler
            </span>
            <span
                v-for="r in recentDelivered"
                :key="r.id"
                class="flex items-center gap-2.5 rounded-lg py-1 pl-3 pr-1"
                style="background-color: var(--kds-inset); color: var(--kds-text-2)"
            >
                <span class="text-base font-medium">{{ r.label }}</span>
                <button
                    class="kds-btn kds-btn--ghost text-sm"
                    :disabled="busy"
                    title="Yanlış işaretlendiyse geri al"
                    @click="undoServe(r.id)"
                >
                    <KdsIcon name="undo" :size="14" /> Geri al
                </button>
            </span>
        </footer>
    </div>

    <ToastHost />
</template>
