<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import { useVersionWatch } from '@/composables/useVersionWatch';
import ToastHost from '@/Components/ui/ToastHost.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import ImageLightbox from '@/Components/ui/ImageLightbox.vue';
import KdsIcon from './KdsIcon.vue';
import KdsItemImage from './KdsItemImage.vue';
import KdsNavDrawer from './KdsNavDrawer.vue';
import KdsTicket from './KdsTicket.vue';
import StationManager from './StationManager.vue';
import { useReceiptPrint, formatReceiptTime, type ReceiptData } from './useReceiptPrint';
import { useThermalPrinter, bindUsbPrinter, bindSerialPrinter, unbindThermal, setPaperWidth, setKioskPrint } from './useThermalPrinter';
import { useTerminalHeartbeat } from '@/composables/useTerminalHeartbeat';
import { useTerminalIdleLock } from '@/composables/useTerminalIdleLock';
import { useTerminalOperator } from '@/composables/useTerminalOperator';
import TerminalOperatorGate from '@/Components/panel/TerminalOperatorGate.vue';
import LockOverlay from '@/Components/panel/LockOverlay.vue';
import TerminalTopBar from '@/Components/panel/TerminalTopBar.vue';
import {
    createKdsSound,
    createPollingFeed,
    useKdsTheme,
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
useVersionWatch();

/* ---- Şube (paylaşılan auth prop'undan) ---- */
const auth = page.props.auth as {
    branches?: { id: number; name: string }[];
    activeBranchId?: number | null;
    tenant?: { name?: string } | null;
} | null;
const branches = auth?.branches ?? [];
const branchId = ref<number>(auth?.activeBranchId ?? branches[0]?.id ?? 0);
const businessName = auth?.tenant?.name ?? '';
const branchName = computed(() => branches.find((b) => b.id === branchId.value)?.name ?? '');

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
const knownItemIds = new Set<number>(); // yeni-KALEM tespiti (mevcut adisyona ek sipariş)
const newOrderIds = ref<Set<number>>(new Set());
let newHighlightTimer: ReturnType<typeof setTimeout> | null = null;
let feed: KdsFeed | null = null;

const sound = createKdsSound('kds_kitchen_sound');
const soundOn = ref(sound.enabled());

/* ---- İstasyon fişi (§13 FAZ C-1: oto-yazdır + önizleme, PARA GÖRMEZ) ----
 * Fiş bu ekranın KENDİ kulvarına/istasyonuna ait kalemleri taşır (backend
 * kuyruğu zaten §12 kalem-düzeyinde süzer — card.items yalnız bu ekranın
 * kalemleridir). Fiyat/tutar YOKTUR. */
const receipt = useReceiptPrint();

// Fişin büyük yönlendirme etiketi: seçili istasyon adı, yoksa kulvar
// (Barista / Mutfak). "Tümü" görünümünde kulvar adı kullanılır.
const ticketStationLabel = computed(() => {
    if (station.value) {
        return meta.stations.find((x) => x.key === station.value)?.name ?? station.value;
    }
    return laneLabel.value;
});

// Kulvar etiketi (Mutfak / Barista / Nargile) — başlık + fiş + "Tümü" görünümü.
const laneLabel = computed(() => (lane === 'barista' ? 'Barista' : lane === 'nargile' ? 'Nargile' : 'Mutfak'));

/** Fiş — YALNIZ verilen kalemlerle (oto-fişte sonradan eklenen kalemler için). */
function buildCardTicketForItems(card: KdsOrderCard, items: KdsOrderCard['items']): ReceiptData {
    return {
        business: businessName,
        branch: branchName.value,
        station: ticketStationLabel.value,
        orderNo: card.id,
        destination: card.table_name ?? card.customer_name ?? `Sipariş #${card.id}`,
        serviceType: card.service_type_label ?? card.channel_label,
        areaWaiter: [card.area_name, card.waiter].filter(Boolean).join(' · ') || null,
        time: formatReceiptTime(card.placed_at),
        note: card.note,
        lines: items.map((i) => ({
            qty: i.qty,
            name: i.name,
            variant: i.variant_name,
            options: i.options,
            note: i.note,
        })),
        kind: 'station',
    };
}

/** Fiş — adisyonun TÜM kalemleriyle (manuel önizleme/yazdırma). */
function buildCardTicket(card: KdsOrderCard): ReceiptData {
    return buildCardTicketForItems(card, card.items);
}

/* ---- Oto-fiş: KALEM bazlı — her kalem bir kez basılır ----
 * Aç/kapa localStorage 'bhx-kds-autoprint' (varsayılan AÇIK). Yazdırılan KALEM
 * anahtarları 'bhx-kds-printed-items' localStorage'ında tutulur. Böylece: yeni
 * adisyon VE mevcut adisyona SONRADAN eklenen kalemler ayrı ayrı basılır
 * (eski sürüm yalnız adisyon ilk açıldığındaki kalemi basıp gerisini kaçırıyordu). */
const AUTOPRINT_KEY = 'bhx-kds-autoprint';
const PRINTED_KEY = 'bhx-kds-printed-items';
const autoPrint = ref(readAutoPrint());

function readAutoPrint(): boolean {
    try {
        return localStorage.getItem(AUTOPRINT_KEY) !== 'off';
    } catch {
        return true;
    }
}
function toggleAutoPrint(): void {
    autoPrint.value = !autoPrint.value;
    try {
        localStorage.setItem(AUTOPRINT_KEY, autoPrint.value ? 'on' : 'off');
    } catch {
        /* gizli mod — bu oturumda hatırlanmaz */
    }
}

function loadPrinted(): Set<string> {
    try {
        return new Set(JSON.parse(localStorage.getItem(PRINTED_KEY) ?? '[]') as string[]);
    } catch {
        return new Set();
    }
}
const printedItems = loadPrinted();
function itemKey(itemId: number): string {
    // Ekran kulvarı + şube + kalem: aynı kalem yeniden basılmaz.
    return `${lane || 'kitchen'}:${branchId.value}:${itemId}`;
}
function savePrinted(): void {
    try {
        // sınırsız büyümeyi engelle — son ~2000 kalem yeter.
        localStorage.setItem(PRINTED_KEY, JSON.stringify(Array.from(printedItems).slice(-2000)));
    } catch {
        /* yok say */
    }
}

/**
 * Bu ekrana YENİ düşen kalemleri (her biri BİR KEZ) otomatik yazdırır.
 * Yeni adisyon VEYA mevcut adisyona eklenen kalemler — hepsi yakalanır.
 * İlk tam yüklemede (silent=true) yalnız "görüldü" işaretlenir, BASILMAZ
 * (ekran açılınca eski kalemler toplu basılmasın).
 */
function autoPrintNewItems(silent: boolean): void {
    if (!autoPrint.value) return;
    let changed = false;
    for (const o of orders.value) {
        const freshItems = o.items.filter((it) => !printedItems.has(itemKey(it.id)));
        if (freshItems.length === 0) continue;
        freshItems.forEach((it) => printedItems.add(itemKey(it.id)));
        changed = true;
        if (!silent) {
            receipt.print(buildCardTicketForItems(o, freshItems), { silentOnly: true });
        }
    }
    if (changed) savePrinted();
}

/* ---- Termal yazıcı (sessiz ESC/POS) bağlama ---- */
const thermal = useThermalPrinter();
const showPrinter = ref(false);
const terminalUrl = typeof window !== 'undefined' ? window.location.href : '';

async function connectUsbPrinter(): Promise<void> {
    try {
        await bindUsbPrinter();
        success('Yazıcı bağlandı', thermal.boundName.value);
    } catch (e) {
        danger('Yazıcı bağlanamadı', e instanceof Error ? e.message : 'USB izni verilmedi.');
    }
}
async function connectSerialPrinter(): Promise<void> {
    try {
        await bindSerialPrinter();
        success('Yazıcı bağlandı', 'Seri yazıcı');
    } catch (e) {
        danger('Yazıcı bağlanamadı', e instanceof Error ? e.message : 'Port izni verilmedi.');
    }
}
async function testThermal(): Promise<void> {
    try {
        await thermal.printTest();
        success('Test fişi gönderildi', '');
    } catch (e) {
        danger('Test başarısız', e instanceof Error ? e.message : 'Yazıcıya ulaşılamadı.');
    }
}
/** Tarayıcı yoluyla örnek fiş — kiosk-printing kuruluysa DİYALOGSUZ basar,
 * değilse yazdırma penceresi açılır (kiosk kurulumunu doğrulamak için). */
function testBrowserPrint(): void {
    receipt.print(
        {
            business: businessName,
            branch: branchName.value,
            station: ticketStationLabel.value,
            orderNo: 0,
            destination: 'Deneme fişi',
            serviceType: null,
            areaWaiter: null,
            time: formatReceiptTime(new Date().toISOString()),
            note: null,
            lines: [{ qty: 1, name: 'Tarayıcı yazdırma testi', options: [], note: null }],
            kind: 'station',
        },
        { silentOnly: false },
    );
}
function disconnectPrinter(): void {
    unbindThermal();
    warning('Yazıcı bağlantısı kaldırıldı', 'Fişler tekrar tarayıcı yazdırmasıyla alınır.');
}

/* ---- Reçete: MODAL (kart içi açılım kartı şişiriyordu; artık odaklı modal) ---- */
const recipeItem = ref<KdsItem | null>(null);
function openRecipe(item: KdsItem): void {
    recipeItem.value = item;
}

/* ---- Fiş önizleme (manuel) ---- */
const previewCard = ref<KdsOrderCard | null>(null);
const previewData = computed(() => (previewCard.value ? buildCardTicket(previewCard.value) : null));
function printPreview(): void {
    if (previewData.value) receipt.print(previewData.value);
}

// ŞUBE KAPSAMI backend'de OTURUMDAN çözülür (BranchContext), istekten ASLA
// alınmaz — branch_id burada bilerek GÖNDERİLMEZ (bkz. selectBranch altındaki not).
function queueUrl(): string {
    const p = new URLSearchParams({ mode: 'kitchen' });
    if (station.value) p.set('station', station.value);
    if (lane) p.set('lane', lane);
    return `/api/v1/kds/queue?${p}`;
}

function updatesUrl(cursor: number): string {
    const p = new URLSearchParams({ mode: 'kitchen', cursor: String(cursor) });
    if (station.value) p.set('station', station.value);
    if (lane) p.set('lane', lane);
    return `/api/v1/kds/updates?${p}`;
}

function applyPayload(payload: KitchenPayload, silent = false): void {
    serverSkewMs.value = new Date(payload.server_time).getTime() - Date.now();

    const fresh = new Set<number>();          // yeni SİPARİŞ id'leri
    const addedTo = new Set<number>();        // MEVCUT adisyon + SONRADAN eklenen kalem (denetim #4)
    for (const o of payload.orders) {
        const isNewOrder = !knownOrderIds.has(o.id);
        if (isNewOrder) fresh.add(o.id);
        knownOrderIds.add(o.id);
        for (const it of o.items) {
            const isNewItem = !knownItemIds.has(it.id);
            knownItemIds.add(it.id);
            // Yeni kalem + adisyon YENİ DEĞİL → mevcut masaya ek sipariş düştü.
            if (isNewItem && !isNewOrder) addedTo.add(o.id);
        }
    }

    orders.value = payload.orders;
    summary.value = payload.summary;
    loading.value = false;

    // SİNYAL: yeni sipariş VEYA mevcut adisyona eklenen kalem (ikisi de ses+vurgu).
    // Eskiden yalnız yeni sipariş sinyal veriyordu → ikinci tur (ör. içecek) sessizdi.
    if (!silent && (fresh.size > 0 || addedTo.size > 0)) {
        newOrderIds.value = new Set<number>([...fresh, ...addedTo]);
        sound.beep(2);

        if (fresh.size > 0) {
            const freshOrders = payload.orders.filter((o) => fresh.has(o.id));
            const head = freshOrders[0];
            const label = head
                ? head.table_name ?? head.customer_name ?? head.channel_label ?? `#${head.id}`
                : '';
            success(
                fresh.size === 1 ? 'Yeni sipariş geldi' : `${fresh.size} yeni sipariş geldi`,
                fresh.size === 1 ? `${label} · #${head?.id}` : 'Kuyruğa yeni siparişler düştü.',
            );
        }
        if (addedTo.size > 0) {
            const head = payload.orders.find((o) => addedTo.has(o.id));
            const label = head ? (head.table_name ?? head.customer_name ?? `#${head.id}`) : '';
            success(
                'Masaya ek sipariş',
                addedTo.size === 1 ? `${label} · yeni kalem eklendi` : `${addedTo.size} adisyona yeni kalem eklendi`,
            );
        }

        // Önceki vurgu timer'ını iptal et → ikinci parti erken silinmez.
        if (newHighlightTimer) clearTimeout(newHighlightTimer);
        newHighlightTimer = setTimeout(() => (newOrderIds.value = new Set()), 12000);
    }

    // Oto-fiş (KALEM bazlı): yeni düşen kalemleri her biri bir kez bas. İlk tam
    // yüklemede (silent) yalnız işaretlenir. Bu çağrı `fresh` şartından BAĞIMSIZ
    // çalışır — mevcut adisyona SONRADAN eklenen kalemleri de yakalar.
    autoPrintNewItems(silent);
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
    knownItemIds.clear();
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

/*
 * Şube değiştirici (yalnız çok-şubeli yönetici, >1 şubede görünür — bkz.
 * template). Denetim notu: bu, KDS sorgu ucuna branch_id GEÇİRMİYORDU — o
 * parametre backend'de (KdsQueueController) BİLEREK yok sayılır, çünkü
 * ŞUBE KAPSAMI güvenlik sınırıdır ve istekten ASLA alınmaz (bkz.
 * BranchContext). Doğru/tek güvenli yol: panelin geri kalanının (PanelShell
 * şube değiştirici) kullandığı GERÇEK uç — POST /api/v1/auth/active-branch —
 * ile oturumdaki aktif şubeyi bizzat değiştirmek, ardından akışı o yeni
 * şubeyle yeniden başlatmak. Böylece KdsQueueController hiç değişmeden
 * (currentBranchId() zaten oturumu okur) seçim gerçekten etkili olur.
 */
const switchingBranch = ref(false);
async function selectBranch(id: string): Promise<void> {
    const nextId = Number(id);
    if (nextId === branchId.value || switchingBranch.value) return;
    switchingBranch.value = true;
    try {
        await api('/api/v1/auth/active-branch', { method: 'POST', body: { branch_id: nextId } });
        branchId.value = nextId;
        await restartFeed();
    } catch (e) {
        danger('Şube değiştirilemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        switchingBranch.value = false;
    }
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
/** Son ~12 sn içinde gelen yeni adisyon sayısı (bildirim şeridi + zil rozeti). */
const newCount = computed(() => newOrderIds.value.size);

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

/* ---- Görünüm ----
 * Tam ekran + hesap/operatör menüsü artık ORTAK <TerminalTopBar> bileşeninde
 * (§13 denetim 2026-08-06 — dört terminal ekranı aynı üst çubuk deseni). */
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

// Terminal cihazsa: last_seen_at'i canlı tut (panel "Çevrimiçi" rozeti).
useTerminalHeartbeat();

/* §13 Faz D (FAZ3 entegrasyon): boşta-kalma kilidi — PanelLayout/Cashier.vue/
 * Board.vue ile BİREBİR AYNI desen (yalnız aktif operatör varken izlenir).
 * `activeOperator` AYNI kaynaktan (useTerminalOperator) — kopya mantık yok. */
const { current: activeOperator } = useTerminalOperator();
const idleLockEnabled = computed(() => isTerminal.value && Boolean(activeOperator.value));
const { locked: idleLocked, unlock: unlockIdle } = useTerminalIdleLock({ enabled: idleLockEnabled });

function pendingItems(card: KdsOrderCard): KdsItem[] {
    return card.items.filter((i) => i.status !== 'ready');
}

/**
 * Kart çerçevesi: yalnız YENİ sipariş vurgulanır (12 sn). Aciliyet kartta
 * TEK yerde konuşur — sağ üstteki bekleme çipi (renk + "gecikti" sözcüğü).
 */
function cardBorderClass(card: KdsOrderCard): string {
    // Aciliyet kart kenarını da sürükler → duvarda bakışta ayrışır.
    const sla = cardSla(card);
    if (sla === 'late') return 'border-danger';
    if (sla === 'warn') return 'border-warning';
    return newOrderIds.value.has(card.id) ? 'border-primary-soft-border' : 'border-default';
}

/** Kart başlığı aciliyet tonu: zemin + sayaç metni. Kartlar "hepsi aynı"
 *  görünmesin diye başlık rengi doğrudan aciliyeti anlatır. */
function slaHeader(card: KdsOrderCard): { bg: string; timer: string } {
    switch (cardSla(card)) {
        case 'late':
            return { bg: 'bg-danger-soft', timer: 'text-danger' };
        case 'warn':
            return { bg: 'bg-warning-soft', timer: 'text-warning' };
        default:
            return { bg: 'bg-surface-alt', timer: 'text-body' };
    }
}

const branchOptions = computed(() => branches.map((b) => ({ value: String(b.id), label: b.name })));

// Başlık seçili istasyonun adını izler (Mutfak / Barista / Izgara …); süzgeç
// "Tümü" ise genel "Mutfak Ekranı" başlığı kalır (istasyonlar mutfak tarafıdır).
const pageTitle = computed(() => {
    if (!station.value) return `${laneLabel.value} Ekranı`;
    const s = meta.stations.find((x) => x.key === station.value);
    return `${s?.name ?? laneLabel.value} Ekranı`;
});
</script>

<template>
    <Head :title="pageTitle" />

    <div class="kds-canvas fixed inset-0 flex flex-col overflow-hidden text-body">
        <!-- ================= Üst çubuk (ortak terminal deseni) ================= -->
        <TerminalTopBar
            :screen-label="`${laneLabel} Hazırlık Ekranı`"
            :theme="kdsTheme.theme.value"
            @toggle-theme="kdsTheme.toggle()"
            @open-nav="showNav = true"
        >
            <template #status>
                <!-- Bekleyen + gecikme sayaçları: kompakt pill grubu -->
                <span class="ml-1 inline-flex shrink-0 items-center gap-1.5 rounded-full border border-default bg-inset px-2.5 py-1 text-xs font-semibold text-muted tabular-nums">
                    {{ totalPending }} bekleyen
                </span>

                <span
                    v-if="lateCount > 0"
                    role="alert"
                    class="inline-flex shrink-0 items-center gap-1 rounded-full border border-danger bg-danger px-2.5 py-1 text-xs font-semibold text-on-status"
                >
                    <AppIcon name="alert-triangle" :size="13" />
                    {{ lateCount }} gecikti
                </span>
            </template>

            <template #actions>
                <div v-if="branchOptions.length > 1" class="w-40">
                    <BaseSelect
                        :model-value="String(branchId)"
                        :options="branchOptions"
                        size="sm"
                        :disabled="switchingBranch"
                        @update:model-value="selectBranch(String($event))"
                    />
                </div>

                <BaseButton v-if="meta.canDeliver" variant="secondary" size="md" href="/panel/komi">
                    <KdsIcon name="tray" :size="17" />
                    Komi
                </BaseButton>

                <BaseButton
                    v-if="meta.canManageStations"
                    variant="ghost"
                    size="md"
                    icon-only
                    label="İstasyon yönetimi"
                    @click="showStations = true"
                >
                    <AppIcon name="settings" :size="18" />
                </BaseButton>

                <!-- Oto-fiş: durumu AÇIKÇA gösteren etiketli anahtar (varsayılan açık) -->
                <button
                    type="button"
                    class="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-lg border px-2.5 text-sm font-semibold transition-colors duration-(--dur-fast)"
                    :class="autoPrint ? 'border-success bg-success-soft text-success' : 'border-default text-subtle hover:bg-inset'"
                    :aria-pressed="autoPrint"
                    :title="autoPrint ? 'Oto-fiş açık: yeni sipariş otomatik yazdırılır' : 'Oto-fiş kapalı'"
                    @click="toggleAutoPrint"
                >
                    <KdsIcon name="printer" :size="17" />
                    <span class="hidden sm:inline">Oto-fiş {{ autoPrint ? 'açık' : 'kapalı' }}</span>
                </button>

                <BaseButton
                    variant="ghost"
                    size="md"
                    icon-only
                    :label="thermal.bound.value ? `Termal yazıcı bağlı (${thermal.boundName.value}) — ayarlar` : 'Termal yazıcı bağla (sessiz otomatik fiş)'"
                    :class="thermal.bound.value ? 'text-success' : 'text-subtle'"
                    @click="showPrinter = true"
                >
                    <AppIcon name="plug" :size="18" />
                </BaseButton>

                <BaseButton
                    variant="ghost"
                    size="md"
                    icon-only
                    :label="soundOn ? 'Yeni sipariş sesi: açık' : 'Yeni sipariş sesi: kapalı'"
                    :class="soundOn ? '' : 'text-subtle'"
                    @click="toggleSound"
                >
                    <KdsIcon :name="soundOn ? 'volume-on' : 'volume-off'" :size="18" />
                </BaseButton>
            </template>
        </TerminalTopBar>

        <!-- İstasyon süzgeci KALDIRILDI (kullanıcı isteği): kulvara ait TÜM
             kalemler tek akışta görünür → hiçbir istasyon "gözden kaçmaz". -->

        <!-- ================= Yeni sipariş bildirim şeridi ================= -->
        <Transition
            enter-active-class="transition-all duration-(--dur-normal) ease-out"
            enter-from-class="-translate-y-2 opacity-0"
            leave-active-class="transition-all duration-(--dur-fast) ease-in"
            leave-to-class="-translate-y-2 opacity-0"
        >
            <div
                v-if="newCount > 0"
                class="flex items-center justify-center gap-2 bg-primary px-4 py-2 text-sm font-semibold text-on-primary"
                role="status"
            >
                <span class="relative flex size-2.5">
                    <span class="absolute inline-flex size-full animate-ping rounded-full bg-on-primary/70" />
                    <span class="relative inline-flex size-2.5 rounded-full bg-on-primary" />
                </span>
                {{ newCount }} yeni sipariş geldi
            </div>
        </Transition>

        <!-- ================= Kuyruk ================= -->
        <main class="min-h-0 flex-1 overflow-y-auto p-3">
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
                    class="flex flex-col overflow-hidden rounded-2xl border-2 bg-raised shadow-card"
                    :class="cardBorderClass(card)"
                >
                    <!-- Başlık: aciliyet-renkli şerit (masa büyük · sayaç renkli) -->
                    <header class="flex items-center justify-between gap-2.5 px-3 py-2" :class="slaHeader(card).bg">
                        <div class="min-w-0">
                            <p class="truncate text-xl font-bold leading-tight text-body">
                                {{ card.table_name ?? card.customer_name ?? `Sipariş #${card.id}` }}
                            </p>
                            <p class="mt-0.5 truncate text-[12px] text-muted">
                                {{ card.channel_label }}<template v-if="card.area_name"> · {{ card.area_name }}</template><template v-if="card.waiter"> · {{ card.waiter }}</template>
                            </p>
                        </div>
                        <div class="flex shrink-0 items-center gap-0.5">
                            <span
                                class="inline-flex items-center gap-1.5 text-lg font-bold tabular-nums"
                                :class="slaHeader(card).timer"
                                title="Sipariş verileli geçen süre"
                            >
                                <AppIcon name="clock" :size="16" />
                                {{ slaText(waitMinutes(card.placed_at)) }}
                            </span>
                            <BaseButton variant="ghost" size="sm" icon-only label="Fiş önizle ve yazdır" @click="previewCard = card">
                                <KdsIcon name="printer" :size="16" />
                            </BaseButton>
                        </div>
                    </header>

                    <!-- Gecikti şeridi (sadece geç kalanlar) -->
                    <p
                        v-if="cardSla(card) === 'late'"
                        class="flex items-center gap-1.5 bg-danger px-3 py-1 text-[11px] font-bold tracking-wide text-on-status uppercase"
                    >
                        <AppIcon name="alert-triangle" :size="13" /> Gecikti
                    </p>

                    <!-- Sipariş notu -->
                    <p v-if="card.note" class="flex items-start gap-1.5 border-b border-default bg-info-soft px-3 py-1.5 text-[13px] font-medium text-info">
                        <AppIcon name="alert-circle" :size="15" class="mt-0.5 shrink-0" />
                        <span>{{ card.note }}</span>
                    </p>

                    <!-- Kalemler -->
                    <ul class="flex-1 divide-y divide-default">
                        <li
                            v-for="item in card.items"
                            :key="item.id"
                            class="px-3 py-2.5"
                            :class="item.status === 'ready' ? 'opacity-55' : ''"
                        >
                            <!-- ÜST SATIR: adet · görsel · ürün adı.
                                 Önceki düzende eylem butonu SAĞ SÜTUNDA duruyordu;
                                 300px'lik kartta metin sütununu eziyor, ürün adı
                                 alta kayıyordu. Eylem artık kendi satırında. -->
                            <div class="flex items-start gap-2.5">
                                <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-inset text-[15px] font-bold tabular-nums text-body">
                                    {{ item.qty }}
                                </span>

                                <KdsItemImage :src="item.image_url" :alt="item.name" class="shrink-0" />

                                <div class="min-w-0 flex-1">
                                    <p
                                        class="text-[17px] font-bold leading-tight text-body"
                                        :class="item.status === 'ready' ? 'line-through' : ''"
                                    >{{ item.name }}</p>
                                    <p v-if="item.variant_name" class="truncate text-[13px] text-muted">{{ item.variant_name }}</p>
                                    <p v-if="item.options.length" class="text-[13px] leading-snug text-muted">{{ item.options.join(' · ') }}</p>
                                </div>
                            </div>

                            <!-- UYARILAR: not + alerjen (renkli, dikkat çeken) -->
                            <p v-if="item.note" class="mt-1.5 flex items-start gap-1.5 rounded-md bg-info-soft px-2 py-1 text-[13px] font-medium text-info">
                                <AppIcon name="alert-circle" :size="14" class="mt-0.5 shrink-0" />
                                <span>{{ item.note }}</span>
                            </p>
                            <p v-if="item.allergens.length" class="mt-1.5 flex items-start gap-1.5 rounded-md bg-danger-soft px-2 py-1">
                                <AppIcon name="alert-triangle" :size="14" class="mt-0.5 shrink-0 text-danger" />
                                <span class="text-[13px] font-bold leading-snug text-danger">
                                    {{ item.allergens.map((a) => a.name).join(' · ') }}
                                </span>
                            </p>

                            <!-- META: diyet · reçete · istasyon (sessiz, tek satır) -->
                            <div
                                v-if="item.diets.length || item.recipe || !station"
                                class="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-[12px]"
                            >
                                <span v-if="item.diets.length" class="text-subtle">
                                    <span class="font-semibold">Diyet:</span> {{ item.diets.join(' · ') }}
                                </span>
                                <button
                                    v-if="item.recipe"
                                    type="button"
                                    class="inline-flex items-center gap-1 font-semibold text-primary transition-colors hover:underline"
                                    @click="openRecipe(item)"
                                >
                                    <AppIcon name="clipboard" :size="13" /> Reçete
                                </button>
                                <span v-if="!station" class="text-subtle/70">{{ item.station_label }}</span>
                            </div>

                            <!-- EYLEM SATIRI: tam genişlik birincil buton + ikon eylemler.
                                 Metinle yarışmaz, dokunmatikte rahat hedef. -->
                            <div class="mt-2 flex items-center gap-1.5">
                                <BaseButton
                                    v-if="nextStep(item)"
                                    size="md"
                                    class="grow"
                                    :disabled="busy"
                                    @click="advance(card, item, nextStep(item)!.to)"
                                >
                                    <AppIcon name="check" :size="16" />
                                    {{ nextStep(item)!.label }}
                                </BaseButton>

                                <span
                                    v-else-if="item.status === 'ready'"
                                    class="flex grow items-center justify-center gap-1.5 rounded-md bg-success-soft px-2 py-2 text-[13px] font-bold text-success"
                                >
                                    <AppIcon name="check-circle" :size="15" /> Hazır
                                </span>

                                <BaseButton
                                    v-if="item.status === 'ready'"
                                    variant="ghost"
                                    size="md"
                                    icon-only
                                    label="Geri al"
                                    :disabled="busy"
                                    @click="undoItem(card, item)"
                                >
                                    <KdsIcon name="undo" :size="17" />
                                </BaseButton>

                                <BaseButton
                                    v-if="item.status !== 'ready'"
                                    variant="ghost"
                                    size="md"
                                    icon-only
                                    :label="`${item.name} kalemini başka istasyona aktar`"
                                    :disabled="busy"
                                    @click="openTransfer(card, item)"
                                >
                                    <KdsIcon name="swap" :size="17" />
                                </BaseButton>
                            </div>
                        </li>
                    </ul>

                    <!-- Footer: tek birincil eylem -->
                    <div class="border-t border-default p-2">
                        <BaseButton
                            v-if="pendingItems(card).length > 0"
                            size="lg"
                            block
                            :disabled="busy"
                            @click="allReady(card)"
                        >
                            <AppIcon name="check-circle" :size="18" />
                            Tümünü hazırla ({{ pendingItems(card).length }})
                        </BaseButton>
                        <p v-else class="flex h-10 items-center justify-center gap-2 text-[15px] font-semibold text-success">
                            <KdsIcon name="tray" :size="18" />
                            Garson &amp; Komi bekliyor
                        </p>
                    </div>
                </article>
            </div>
        </main>
    </div>

    <!-- ================= Termal yazıcı modalı ================= -->
    <BaseModal :open="showPrinter" title="Termal yazıcı" size="sm" @close="showPrinter = false">
        <div class="flex flex-col gap-4 text-sm">
            <!-- Durum -->
            <div class="rounded-lg border border-default bg-inset/60 p-3">
                <p class="font-medium text-body">
                    Durum:
                    <span v-if="thermal.bound.value" class="text-success">Doğrudan yazıcı bağlı ({{ thermal.boundName.value }})</span>
                    <span v-else-if="thermal.kioskPrint.value" class="text-success">Sessiz yazdırma (kiosk) açık</span>
                    <span v-else class="text-subtle">Sessiz yazdırma kapalı</span>
                </p>
                <p class="mt-1 text-xs text-muted">
                    Sessiz yazdırma açıkken sipariş girilince fiş <strong>arka planda otomatik</strong> basılır (diyalog açılmaz).
                </p>
            </div>

            <!-- BİRİNCİL: kiosk sessiz yazdırma (pos-58 gibi Windows'a kurulu yazıcılar) -->
            <div class="rounded-lg border border-primary-soft-border bg-primary-soft/40 p-3">
                <div class="flex items-center justify-between gap-3">
                    <span class="text-sm font-semibold text-body">Sessiz otomatik yazdırma (önerilen)</span>
                    <BaseButton
                        size="sm"
                        :variant="thermal.kioskPrint.value ? 'primary' : 'ghost'"
                        @click="setKioskPrint(!thermal.kioskPrint.value)"
                    >{{ thermal.kioskPrint.value ? 'Açık' : 'Kapalı' }}</BaseButton>
                </div>
                <ol class="mt-2 list-decimal space-y-1 pl-4 text-xs text-muted">
                    <li>Windows'ta <strong>pos-58'i varsayılan yazıcı</strong> yapın.</li>
                    <li>Chrome'u <strong>tamamen kapatın</strong>; kısayol <em>Hedef</em>ine
                        <code class="rounded bg-inset px-1">--kiosk-printing</code> ekleyip yeniden açın.</li>
                    <li>Bu seçeneği <strong>Açık</strong> yapın ve aşağıdan test edin.</li>
                </ol>
                <p class="mt-1.5 text-[11px] break-all text-subtle">
                    <code class="rounded bg-inset px-1">chrome.exe --kiosk-printing "{{ terminalUrl }}"</code>
                </p>
                <BaseButton size="sm" variant="secondary" class="mt-2" @click="testBrowserPrint">
                    Örnek fiş yazdır (tarayıcı)
                </BaseButton>
            </div>

            <!-- Kağıt genişliği -->
            <div class="flex items-center gap-2">
                <span class="text-xs font-medium text-muted">Kağıt genişliği:</span>
                <BaseButton
                    size="sm"
                    :variant="thermal.paperWidth.value === '58' ? 'primary' : 'ghost'"
                    @click="setPaperWidth('58')"
                >58 mm</BaseButton>
                <BaseButton
                    size="sm"
                    :variant="thermal.paperWidth.value === '80' ? 'primary' : 'ghost'"
                    @click="setPaperWidth('80')"
                >80 mm</BaseButton>
            </div>

            <!-- GELİŞMİŞ: doğrudan USB/Seri (ham yazıcılar) -->
            <div v-if="thermal.supported" class="rounded-lg border border-default p-3">
                <p class="text-xs font-semibold text-body">Gelişmiş: doğrudan yazıcı bağla</p>
                <p class="mt-1 text-[11px] text-subtle">
                    Yalnız Windows sürücüsü OLMADAN takılı ham USB/seri yazıcılar için. pos-58 gibi
                    kurulu yazıcılar “Access denied” verir → yukarıdaki kiosk yöntemini kullanın.
                </p>
                <div class="mt-2 flex flex-wrap gap-2">
                    <BaseButton size="sm" variant="secondary" @click="connectUsbPrinter">
                        <AppIcon name="plug" :size="15" /> USB
                    </BaseButton>
                    <BaseButton size="sm" variant="secondary" @click="connectSerialPrinter">
                        <AppIcon name="plug" :size="15" /> Seri (USB-COM)
                    </BaseButton>
                </div>
            </div>

            <div class="flex items-center justify-between gap-2 border-t border-default pt-3">
                <BaseButton size="sm" variant="secondary" :disabled="!thermal.bound.value" @click="testThermal">
                    Test fişi bas
                </BaseButton>
                <BaseButton
                    v-if="thermal.bound.value"
                    size="sm"
                    variant="ghost"
                    class="text-danger"
                    @click="disconnectPrinter"
                >
                    Bağlantıyı kaldır
                </BaseButton>
            </div>
        </div>
        <template #footer>
            <BaseButton variant="secondary" @click="showPrinter = false">Kapat</BaseButton>
        </template>
    </BaseModal>

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

    <!-- ================= Fiş önizleme + yazdır ================= -->
    <BaseModal :open="previewCard !== null" title="İstasyon fişi önizleme" size="sm" @close="previewCard = null">
        <KdsTicket v-if="previewData" :data="previewData" />
        <template #footer>
            <BaseButton variant="secondary" @click="previewCard = null">Kapat</BaseButton>
            <BaseButton @click="printPreview">
                <KdsIcon name="printer" :size="16" />
                Yazdır
            </BaseButton>
        </template>
    </BaseModal>

    <!-- ================= Reçete / hazırlama modalı ================= -->
    <BaseModal :open="recipeItem !== null" title="Reçete / hazırlama" size="sm" @close="recipeItem = null">
        <div v-if="recipeItem" class="flex flex-col gap-3">
            <div class="flex items-start gap-3">
                <KdsItemImage :src="recipeItem.image_url" :alt="recipeItem.name" />
                <div class="min-w-0">
                    <p class="text-lg font-semibold leading-snug text-body">
                        <span class="tabular-nums">{{ recipeItem.qty }}×</span> {{ recipeItem.name }}
                    </p>
                    <p v-if="recipeItem.variant_name" class="text-sm text-muted">{{ recipeItem.variant_name }}</p>
                </div>
            </div>

            <div v-if="recipeItem.allergens.length" class="flex flex-wrap items-center gap-1.5">
                <span class="inline-flex items-center gap-1 text-xs font-bold text-danger">
                    <AppIcon name="alert-triangle" :size="13" /> Alerjen:
                </span>
                <span
                    v-for="a in recipeItem.allergens"
                    :key="a.name"
                    class="rounded border border-danger px-1.5 py-0.5 text-xs font-semibold text-danger"
                >{{ a.name }}</span>
            </div>

            <p
                class="rounded-lg border border-default bg-inset/60 px-3.5 py-3 text-[15px] leading-relaxed whitespace-pre-line text-body"
            >{{ recipeItem.recipe }}</p>
        </div>
        <template #footer>
            <BaseButton block @click="recipeItem = null">Kapat</BaseButton>
        </template>
    </BaseModal>

    <!-- ================= İstasyon yönetimi ================= -->
    <StationManager v-if="meta.canManageStations" :open="showStations" @close="showStations = false" />

    <!-- ================= Nav çekmecesi (soldan overlay) ================= -->
    <KdsNavDrawer v-if="!isTerminal" :open="showNav" @close="showNav = false" />

    <!-- Terminalde: zorunlu personel giriş gate'i + personel barı -->
    <TerminalOperatorGate />

    <!-- §13 Faz D: boşta-kalma sonrası ekran kilidi (yalnız aktif operatör varken) -->
    <LockOverlay v-if="idleLocked" @unlocked="unlockIdle" />

    <ToastHost />
    <ImageLightbox />
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
 * Kart ızgarası: DENGELİ eşit-sütun grid. Masonry (çoklu-sütun) sütun-öncelikli
 * ve düzensiz okuma sırası veriyordu ("dengesiz/eşit değil"); yerine doğal
 * soldan-sağa, eşit genişlikli sütunlar (auto-fill minmax) kondu. Kartlar
 * sütun başına hizalanır (align-items:start) → nizami, profesyonel duvar.
 * Sütun sayısı genişliğe göre otomatik (dar 1 → geniş çok).
 */
.kds-masonry {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
    grid-auto-rows: min-content;
    align-content: start;
    gap: 1rem;
}
@media (min-width: 1536px) {
    .kds-masonry {
        grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
    }
}
</style>
