<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import ToastHost from '@/Components/ui/ToastHost.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import KdsIcon from './KdsIcon.vue';
import {
    createKdsSound,
    createPollingFeed,
    forceDarkTheme,
    getOrNull,
    metaFromKdsProps,
    minutesSince,
    slaText,
    waitChipClass,
    type KdsFeed,
    type RunnerItem,
    type RunnerPayload,
    type SlaLevel,
} from './kds';

/**
 * KOMİ EKRANI — mutfağın "hazır" verdiği ürünler; en uzun bekleyen üstte.
 * Satır üç soruya bakışta cevap verir: nereye (büyük başlık) · ne (ürün) ·
 * ne kadar acil (yalnız bekleme çipi renklenir). Akış iki adımdır:
 * "Teslim aldım" → "Masaya götürdüm"; yanlış işaret için geri alma vardır.
 * Görsel dil mutfak ekranıyla ve panelin geri kalanıyla birebir aynıdır.
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

let releaseTheme: (() => void) | null = null;
let clockTimer: ReturnType<typeof setInterval> | null = null;
const clockTick = ref(Date.now());

onMounted(() => {
    releaseTheme = forceDarkTheme();
    void restartFeed();
    const unlock = () => sound.unlock();
    window.addEventListener('pointerdown', unlock, { once: true });
    clockTimer = setInterval(() => (clockTick.value = Date.now()), 30000);
});

onBeforeUnmount(() => {
    feed?.stop();
    if (clockTimer) clearInterval(clockTimer);
    releaseTheme?.();
});

function waitMinutes(iso: string | null): number {
    void clockTick.value;
    return minutesSince(iso, serverSkewMs.value);
}

/** Öncelik: en uzun süredir hazır bekleyen üstte. */
const sorted = computed(() =>
    [...items.value].sort((a, b) => new Date(a.updated_at ?? 0).getTime() - new Date(b.updated_at ?? 0).getTime()),
);

/** Servis aciliyeti: 5+ dk gecikmiş, 2+ dk uyarı (yemek soğur). */
function waitLevel(item: RunnerItem): SlaLevel {
    const m = waitMinutes(item.updated_at);
    return m >= 5 ? 'late' : m >= 2 ? 'warn' : 'ok';
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

    <div class="fixed inset-0 flex flex-col overflow-hidden bg-surface-alt text-body">
        <!-- ================= Üst çubuk (mutfakla aynı dil) ================= -->
        <header class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-default bg-raised px-3 py-2">
            <BaseButton variant="ghost" size="lg" icon-only label="Panele dön" href="/panel">
                <AppIcon name="arrow-left" :size="20" />
            </BaseButton>

            <h1 class="text-lg font-semibold">Komi Ekranı</h1>

            <span class="text-sm text-muted tabular-nums">{{ items.length }} hazır ürün</span>

            <div class="ml-auto flex flex-wrap items-center gap-1.5">
                <div v-if="branchOptions.length > 1" class="w-44">
                    <BaseSelect
                        :model-value="String(branchId)"
                        :options="branchOptions"
                        @update:model-value="selectBranch(String($event))"
                    />
                </div>

                <BaseButton
                    variant="ghost"
                    size="lg"
                    icon-only
                    :label="soundOn ? 'Yeni ürün sesi: açık' : 'Yeni ürün sesi: kapalı'"
                    :class="soundOn ? '' : 'text-subtle'"
                    @click="toggleSound"
                >
                    <KdsIcon :name="soundOn ? 'volume-on' : 'volume-off'" :size="20" />
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

        <!-- ================= Servis kuyruğu ================= -->
        <main class="flex-1 overflow-y-auto p-4">
            <p v-if="loading" class="flex h-full items-center justify-center text-muted">Liste yükleniyor…</p>

            <div v-else-if="sorted.length === 0" class="flex h-full items-center justify-center">
                <EmptyState
                    icon="check-circle"
                    title="Taşınacak ürün yok"
                    :description="`Mutfak 'hazır' verdiğinde ürünler burada görünür — ekran her ${meta.config.poll_interval_seconds} saniyede bir kendini yeniler.`"
                />
            </div>

            <ul v-else class="mx-auto flex max-w-6xl flex-col gap-3">
                <li
                    v-for="item in sorted"
                    :key="item.id"
                    class="rounded-lg border bg-raised shadow-card"
                    :class="newItemIds.has(item.id) ? 'border-primary-soft-border' : 'border-default'"
                >
                    <div class="flex flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3">
                        <!-- NEREYE: en baskın öğe -->
                        <div class="min-w-40">
                            <p class="text-2xl font-semibold leading-tight">
                                {{ item.table_name ?? item.channel_label }}
                            </p>
                            <p class="mt-0.5 text-sm text-muted">
                                <template v-if="item.area_name">{{ item.area_name }}</template><template v-if="item.area_name && item.waiter"> · </template><template v-if="item.waiter">{{ item.waiter }}</template>
                            </p>
                        </div>

                        <!-- NE: ürün -->
                        <div class="min-w-0 flex-1 basis-64">
                            <p class="text-lg font-semibold leading-snug">
                                <span class="tabular-nums">{{ item.qty }}×</span>
                                {{ item.name }}<span v-if="item.variant_name" class="font-normal text-muted"> — {{ item.variant_name }}</span>
                            </p>
                            <p class="mt-0.5 text-sm text-muted">
                                {{ item.station_label }}<span v-if="item.note" class="font-medium text-info"> · Not: {{ item.note }}</span>
                            </p>
                            <p v-if="item.allergens.length || item.diets.length" class="mt-1.5 flex flex-wrap items-center gap-1.5">
                                <BaseBadge v-for="a in item.allergens" :key="a.name" variant="danger" no-icon>
                                    <AppIcon name="alert-triangle" :size="12" />
                                    {{ a.name }}
                                </BaseBadge>
                                <BaseBadge v-for="d in item.diets" :key="d" variant="neutral">{{ d }}</BaseBadge>
                            </p>
                        </div>

                        <!-- NE KADAR ACİL: tek çip (hazır olalı geçen süre) -->
                        <span
                            class="inline-flex shrink-0 items-center rounded-md border px-3 py-1.5 text-lg font-semibold tabular-nums"
                            :class="waitChipClass(waitLevel(item))"
                            title="Hazır olalı geçen süre"
                        >
                            {{ slaText(waitMinutes(item.updated_at)) }}<template v-if="waitLevel(item) === 'late'">&nbsp;· gecikti</template>
                        </span>

                        <!-- İki adım: Teslim aldım → Masaya götürdüm -->
                        <div class="flex shrink-0 flex-wrap items-center gap-2">
                            <BaseButton v-if="!item.picked_up_at" size="lg" :disabled="busy" @click="pickup(item)">
                                Teslim aldım
                            </BaseButton>
                            <template v-else>
                                <!-- geri al: birincil butondan uzakta, grubun solunda -->
                                <BaseButton
                                    variant="ghost"
                                    size="lg"
                                    icon-only
                                    label="Teslim işaretini geri al"
                                    :disabled="busy"
                                    @click="undoPickup(item)"
                                >
                                    <KdsIcon name="undo" :size="16" />
                                </BaseButton>
                                <span class="inline-flex items-center gap-1 text-sm font-medium text-success">
                                    <AppIcon name="check" :size="14" />
                                    {{ item.picked_up_by ?? 'Alındı' }}
                                </span>
                                <BaseButton size="lg" :disabled="busy" @click="delivered(item)">
                                    Masaya götürdüm
                                </BaseButton>
                            </template>
                        </div>
                    </div>
                </li>
            </ul>
        </main>

        <!-- Son götürülenler: yanlış işareti geri alma şeridi -->
        <footer
            v-if="recentDelivered.length > 0"
            class="flex flex-wrap items-center gap-2 border-t border-default bg-raised px-4 py-2"
        >
            <span class="text-xs font-medium uppercase tracking-wide text-subtle">Son götürülenler</span>
            <span
                v-for="r in recentDelivered"
                :key="r.id"
                class="inline-flex items-center gap-1 rounded-md border border-default bg-inset py-0.5 pl-3 pr-1 text-sm text-muted"
            >
                {{ r.label }}
                <BaseButton variant="ghost" size="lg" :disabled="busy" @click="undoServe(r.id)">
                    <KdsIcon name="undo" :size="14" />
                    Geri al
                </BaseButton>
            </span>
        </footer>
    </div>

    <ToastHost />
</template>
