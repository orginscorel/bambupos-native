<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import ToastHost from '@/Components/ui/ToastHost.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import KdsIcon from './KdsIcon.vue';
import KdsItemImage from './KdsItemImage.vue';
import KdsNavDrawer from './KdsNavDrawer.vue';
import KdsTicket from './KdsTicket.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import { useReceiptPrint, formatReceiptTime, type ReceiptData } from './useReceiptPrint';
import {
    createKdsSound,
    createPollingFeed,
    useKdsTheme,
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
 * KOMİ EKRANI — BAĞIMSIZ tam ekran (panel kabuğuna gömülü değil, kasıtlı);
 * mutfağın "hazır" verdiği ürünler, en uzun bekleyen üstte. Satır üç soruya
 * bakışta cevap verir: nereye (büyük başlık) · ne (görsel + ürün, hiç
 * kırpılmaz) · ne kadar acil (yalnız bekleme çipi renklenir). Akış iki
 * adımdır: "Teslim aldım" → "Masaya götürdüm"; yanlış işaret için geri alma
 * vardır. Görsel dil mutfak ekranıyla ve panelin geri kalanıyla birebir
 * aynıdır (--ui-* token'ları); yerleşim bu dosyaya özgüdür. Varsayılan
 * AÇIK tema; ekranın kendi açık/koyu düğmesi vardır (useKdsTheme,
 * localStorage 'kds_theme' — panelin genel tema tercihinden bağımsız).
 */
const page = usePage();
const meta = metaFromKdsProps(page.props as Record<string, unknown>);
const { success, danger, warning } = useToast();

const auth = page.props.auth as {
    branches?: { id: number; name: string }[];
    activeBranchId?: number | null;
    tenant?: { name?: string } | null;
} | null;
const branches = auth?.branches ?? [];
const branchId = ref<number>(auth?.activeBranchId ?? branches[0]?.id ?? 0);
const businessName = auth?.tenant?.name ?? '';
const branchName = computed(() => branches.find((b) => b.id === branchId.value)?.name ?? '');

/* ---- Teslim fişi (§13 FAZ C-1: komi masaya götürürken, PARA GÖRMEZ) ---- */
const receipt = useReceiptPrint();

function buildDeliveryTicket(item: RunnerItem): ReceiptData {
    return {
        business: businessName,
        branch: branchName.value,
        station: 'Teslim',
        orderNo: item.order_id,
        destination: item.table_name ?? item.channel_label,
        serviceType: item.channel_label,
        areaWaiter: [item.area_name, item.waiter].filter(Boolean).join(' · ') || null,
        time: formatReceiptTime(item.updated_at),
        note: item.order_note,
        lines: [{ qty: item.qty, name: item.name, variant: item.variant_name, options: item.options, note: item.note }],
        kind: 'delivery',
    };
}

const previewItem = ref<RunnerItem | null>(null);
const previewData = computed(() => (previewItem.value ? buildDeliveryTicket(previewItem.value) : null));
function printPreview(): void {
    if (previewData.value) receipt.print(previewData.value);
}

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

const kdsTheme = useKdsTheme();
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
    kdsTheme.release();
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

// Nav çekmecesi (soldan overlay) — diğer panel bölümlerine kaçış-kapısı.
const showNav = ref(false);

// §13 Terminal kilitli mod: cihaz oturumunda nav çekmecesi GİZLENİR + rozet.
const isTerminal = computed(() => Boolean((page.props.auth as { is_terminal?: boolean } | null)?.is_terminal));
const terminalStationLabel = computed(() => {
    const key = (page.props.auth as { terminal_station?: string | null } | null)?.terminal_station ?? '';
    if (key === 'barista') return 'Barista';
    if (key === 'komi') return 'Komi';
    if (key === 'kitchen') return 'Mutfak';
    return key;
});

/* §13 Terminal oturumunu kapat (yöneticiye dönüş): POST /terminal/logout → /giris. */
const terminalLoggingOut = ref(false);
async function terminalLogout(): Promise<void> {
    if (terminalLoggingOut.value) return;
    terminalLoggingOut.value = true;
    try {
        await api('/terminal/logout', { method: 'POST' });
    } catch {
        /* oturum düşmüş olabilir; her durumda giriş ekranına dön */
    }
    window.location.href = '/giris';
}

const branchOptions = computed(() => branches.map((b) => ({ value: String(b.id), label: b.name })));
function selectBranch(id: string): void {
    branchId.value = Number(id);
    void restartFeed();
}
</script>

<template>
    <Head title="Komi Ekranı" />

    <div class="kds-canvas fixed inset-0 flex flex-col overflow-hidden text-body">
        <!-- ================= Üst çubuk (mutfakla aynı dil) ================= -->
        <header
            class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-default bg-raised px-3 py-2 shadow-[0_6px_16px_-12px_rgba(0,0,0,0.6)]"
        >
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
            <BaseButton
                v-if="isTerminal"
                variant="ghost"
                size="sm"
                :loading="terminalLoggingOut"
                label="Terminal oturumunu kapat (yöneticiye dön)"
                @click="terminalLogout"
            >
                <AppIcon name="logout" :size="15" />
                Çıkış
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
                    class="rounded-xl border bg-raised shadow-[0_1px_2px_0_rgb(28_25_23_/_0.05),inset_0_1px_0_0_rgba(255,255,255,0.05)]"
                    :class="newItemIds.has(item.id) ? 'border-primary-soft-border' : 'border-default'"
                >
                    <div class="flex flex-wrap items-center gap-x-5 gap-y-2 px-4 py-3.5">
                        <KdsItemImage :src="item.image_url" :alt="item.name" size="lg" />

                        <!-- NEREYE: en baskın öğe -->
                        <div class="min-w-40">
                            <p class="text-2xl font-semibold leading-tight text-balance">
                                {{ item.table_name ?? item.channel_label }}
                            </p>
                            <p class="mt-0.5 text-sm text-muted">
                                <template v-if="item.area_name">{{ item.area_name }}</template><template v-if="item.area_name && item.waiter"> · </template><template v-if="item.waiter">{{ item.waiter }}</template>
                            </p>
                        </div>

                        <!-- NE: ürün -->
                        <div class="min-w-0 flex-1 basis-64">
                            <p class="text-lg font-semibold leading-snug text-balance">
                                <span class="tabular-nums">{{ item.qty }}×</span>
                                {{ item.name }}<span v-if="item.variant_name" class="font-normal text-muted"> — {{ item.variant_name }}</span>
                            </p>
                            <!-- Komi istasyon ayrımıyla ilgilenmez (süzmez, taşımaz) — yalnız
                                 gerçekten faydalı bilgi olan not burada kalır. -->
                            <p v-if="item.note" class="mt-0.5 text-sm font-medium text-info">Not: {{ item.note }}</p>
                            <!-- Renk YALNIZ alerjende güçlü; diyet etiketi sessiz düz metin.
                                 Dolu (solid) kırmızı — bkz. Kitchen.vue'daki AA notu:
                                 soft-danger ikilisi açık temada 4.41:1 (AA 4.5:1 altı) ölçüldü. -->
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
                            <BaseButton
                                variant="ghost"
                                size="lg"
                                icon-only
                                label="Teslim fişini önizle ve yazdır"
                                @click="previewItem = item"
                            >
                                <KdsIcon name="printer" :size="18" />
                            </BaseButton>
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
            class="flex flex-wrap items-center gap-2 border-t border-default bg-raised px-4 py-2 shadow-[0_-6px_16px_-12px_rgba(0,0,0,0.6)]"
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

    <!-- ================= Teslim fişi önizleme + yazdır ================= -->
    <BaseModal :open="previewItem !== null" title="Teslim fişi önizleme" size="sm" @close="previewItem = null">
        <KdsTicket v-if="previewData" :data="previewData" />
        <template #footer>
            <BaseButton variant="secondary" @click="previewItem = null">Kapat</BaseButton>
            <BaseButton @click="printPreview">
                <KdsIcon name="printer" :size="16" />
                Yazdır
            </BaseButton>
        </template>
    </BaseModal>

    <!-- ================= Nav çekmecesi (soldan overlay) ================= -->
    <KdsNavDrawer v-if="!isTerminal" :open="showNav" @close="showNav = false" />

    <ToastHost />
</template>

<style scoped>
/*
 * Zemin: mutfak ekranıyla birebir aynı katmanlı yüzey (bkz. Kitchen.vue) —
 * --ui-surface üstünde çok hafif üstten ışık düşümü, düz siyah yerine.
 */
.kds-canvas {
    background-color: var(--ui-surface);
    background-image: radial-gradient(1200px 640px at 50% -12%, rgb(255 255 255 / 0.035), transparent 60%);
}
</style>
