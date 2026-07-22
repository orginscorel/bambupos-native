<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import ToastHost from '@/Components/ui/ToastHost.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import KdsIcon from './KdsIcon.vue';
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
 * "Teslim aldım" (pickup) ve "Masaya götürdüm" (served) AYRI adımlardır.
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

    <div class="fixed inset-0 flex flex-col overflow-hidden bg-slate-950 text-slate-100">
        <header class="flex flex-wrap items-center gap-2 border-b border-slate-800 bg-slate-900 px-3 py-2">
            <a
                href="/panel"
                class="flex h-11 w-11 items-center justify-center rounded-lg bg-slate-800 text-slate-300 hover:bg-slate-700"
                aria-label="Panele dön"
            >
                <AppIcon name="arrow-left" :size="22" />
            </a>

            <h1 class="flex items-center gap-2 text-xl font-bold tracking-wide">
                <KdsIcon name="tray" :size="24" class="text-emerald-400" />
                Komi Ekranı
            </h1>

            <span class="ml-1 rounded-full bg-slate-800 px-3 py-1 text-base font-semibold text-slate-300">
                {{ items.length }} hazır ürün
            </span>

            <div class="ml-auto flex items-center gap-2">
                <BaseSelect
                    v-if="branchOptions.length > 1"
                    :model-value="String(branchId)"
                    :options="branchOptions"
                    class="w-40"
                    @update:model-value="selectBranch(String($event))"
                />
                <button
                    class="flex h-11 w-11 items-center justify-center rounded-lg text-slate-200"
                    :class="soundOn ? 'bg-emerald-700 hover:bg-emerald-600' : 'bg-slate-800 hover:bg-slate-700'"
                    :aria-label="soundOn ? 'Sesi kapat' : 'Sesi aç'"
                    @click="toggleSound"
                >
                    <KdsIcon :name="soundOn ? 'volume-on' : 'volume-off'" :size="22" />
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

        <main class="flex-1 overflow-y-auto p-3">
            <div v-if="loading" class="flex h-full items-center justify-center text-2xl text-slate-400">
                Liste yükleniyor…
            </div>

            <div v-else-if="sorted.length === 0" class="flex h-full flex-col items-center justify-center gap-3 text-slate-400">
                <AppIcon name="check-circle" :size="64" class="text-emerald-500" />
                <p class="text-3xl font-bold">Taşınacak ürün yok</p>
                <p class="text-lg">Mutfak "hazır" verdiğinde ürünler burada belirir.</p>
            </div>

            <ul v-else class="space-y-2">
                <li
                    v-for="item in sorted"
                    :key="item.id"
                    class="flex flex-wrap items-center gap-3 rounded-xl border-2 bg-slate-900 px-3 py-2.5"
                    :class="newItemIds.has(item.id) ? 'border-sky-400' : item.picked_up_at ? 'border-emerald-700' : 'border-slate-700'"
                >
                    <!-- Masa / hedef -->
                    <div class="min-w-[9rem]">
                        <p class="text-2xl font-black leading-tight">
                            {{ item.table_name ?? item.channel_label }}
                        </p>
                        <p class="text-base text-slate-400">
                            <span v-if="item.area_name">{{ item.area_name }} · </span>{{ item.channel_label }}
                            <span v-if="item.waiter"> · {{ item.waiter }}</span>
                        </p>
                    </div>

                    <!-- Ürün -->
                    <div class="min-w-0 flex-1">
                        <p class="text-xl font-bold">
                            <span class="mr-1 inline-block rounded-md bg-slate-800 px-2 text-orange-300">{{ item.qty }}×</span>
                            {{ item.name }}
                            <span v-if="item.variant_name" class="text-slate-400">— {{ item.variant_name }}</span>
                        </p>
                        <p class="text-base text-slate-400">
                            <KdsIcon name="flame" :size="14" class="inline" />
                            {{ item.station_label }}
                            <span v-if="item.note" class="font-semibold text-sky-300"> · Not: {{ item.note }}</span>
                        </p>
                        <p v-if="item.allergens.length" class="mt-1 flex flex-wrap items-center gap-1.5" role="alert">
                            <span class="flex items-center gap-1 rounded-md bg-red-600 px-2 py-0.5 text-sm font-black text-white">
                                <AppIcon name="alert-triangle" :size="14" /> ALERJEN
                            </span>
                            <span
                                v-for="a in item.allergens"
                                :key="a.name"
                                class="rounded-md border border-red-500 px-1.5 py-0.5 text-sm font-bold text-red-300"
                            >
                                {{ a.name }}
                            </span>
                            <span
                                v-for="d in item.diets"
                                :key="d"
                                class="rounded-md border border-slate-600 px-1.5 py-0.5 text-sm font-semibold text-slate-400"
                            >
                                {{ d }}
                            </span>
                        </p>
                    </div>

                    <!-- Bekleme (hazırdan beri) — renk + ikon + metin -->
                    <span
                        class="flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-lg font-black"
                        :class="waitMinutes(item.updated_at) >= 5 ? 'bg-red-600 text-white' : waitMinutes(item.updated_at) >= 2 ? 'bg-amber-500 text-slate-950' : 'bg-slate-700 text-slate-100'"
                        :title="'Hazır olalı geçen süre'"
                    >
                        <KdsIcon name="clock" :size="18" />
                        {{ slaText(waitMinutes(item.updated_at)) }}
                    </span>

                    <!-- Eylemler: teslim aldım → masaya götürdüm (+ geri al) -->
                    <div class="flex items-center gap-2">
                        <template v-if="!item.picked_up_at">
                            <button
                                class="flex h-14 items-center gap-2 rounded-lg bg-sky-600 px-4 text-lg font-bold text-white hover:bg-sky-500"
                                :disabled="busy"
                                @click="pickup(item)"
                            >
                                <KdsIcon name="hand" :size="22" /> Teslim aldım
                            </button>
                        </template>
                        <template v-else>
                            <span class="flex items-center gap-1 text-base font-semibold text-emerald-400">
                                <AppIcon name="check" :size="18" />
                                {{ item.picked_up_by ?? 'Alındı' }}
                            </span>
                            <button
                                class="flex h-11 items-center gap-1 rounded-lg bg-slate-800 px-2.5 text-base font-semibold text-slate-300 hover:bg-slate-700"
                                :disabled="busy"
                                title="Teslim işaretini geri al"
                                @click="undoPickup(item)"
                            >
                                <KdsIcon name="undo" :size="16" />
                            </button>
                            <button
                                class="flex h-14 items-center gap-2 rounded-lg bg-emerald-600 px-4 text-lg font-bold text-white hover:bg-emerald-500"
                                :disabled="busy"
                                @click="delivered(item)"
                            >
                                <KdsIcon name="tray" :size="22" /> Masaya götürdüm
                            </button>
                        </template>
                    </div>
                </li>
            </ul>
        </main>

        <!-- Son götürülenler: yanlış işareti geri alma şeridi -->
        <footer
            v-if="recentDelivered.length > 0"
            class="flex flex-wrap items-center gap-2 border-t border-slate-800 bg-slate-900 px-3 py-2"
        >
            <span class="text-base font-semibold text-slate-400">Son götürülenler:</span>
            <span
                v-for="r in recentDelivered"
                :key="r.id"
                class="flex items-center gap-2 rounded-lg bg-slate-800 px-2.5 py-1.5 text-base text-slate-200"
            >
                {{ r.label }}
                <button
                    class="flex h-9 items-center gap-1 rounded-md bg-slate-700 px-2 text-sm font-semibold text-slate-100 hover:bg-slate-600"
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
