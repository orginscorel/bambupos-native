<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Head, router, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import { useNotificationSound } from '@/composables/useNotificationSound';
import { useVersionWatch } from '@/composables/useVersionWatch';
import { useTerminalPin } from '@/composables/useTerminalPin';
import { useTerminalHeartbeat } from '@/composables/useTerminalHeartbeat';
import { useTerminalIdleLock } from '@/composables/useTerminalIdleLock';
import { useTerminalOperator } from '@/composables/useTerminalOperator';
import { usePermissions } from '@/composables/usePermissions';
import StaffPinDialog from '@/Components/panel/StaffPinDialog.vue';
import TerminalOperatorGate from '@/Components/panel/TerminalOperatorGate.vue';
import LockOverlay from '@/Components/panel/LockOverlay.vue';
import TerminalTopBar from '@/Components/panel/TerminalTopBar.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BottomSheet from '@/Components/ui/BottomSheet.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import ToastHost from '@/Components/ui/ToastHost.vue';
import KdsIcon from '@/Pages/Panel/Kds/KdsIcon.vue';
import KdsNavDrawer from '@/Pages/Panel/Kds/KdsNavDrawer.vue';
import { useKdsTheme } from '@/Pages/Panel/Kds/kds';
import {
    elapsed,
    fetchBoard,
    fetchBranches,
    metaFromProps,
    money,
    orderElapsed,
    type BoardData,
    type BoardTable,
    type BranchRow,
    type OrderSummary,
    type ServiceRequestRow,
} from './orders';

/**
 * GÖRSEL DİL (FAZ 3): bu ekran, sipariş-girişine atanmış bir terminal
 * cihazının ekranıdır (§13 TerminalStation `order_entry`) — Mutfak/Barista/
 * Komi/Kasa ekranlarıyla (Kitchen.vue/Runner.vue/Cashier.vue) AYNI premium,
 * bağımsız tam ekran kabuğu kullanır (PanelShell YOK): --ui-* token'ları,
 * aynı üst çubuk deseni (marka + geri + menü + terminal rozeti/çıkış +
 * tema/tam-ekran), aynı `kds-canvas` zemin. Yalnız SUNUM/yerleşim değişti —
 * masa panosu, PIN kapısı (FAZ1 `collectPin`/`createOrder`) BİREBİR KORUNDU.
 */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger, warning } = useToast();
const { can } = usePermissions();
const canCreateOrders = can('orders.create');
const srSound = useNotificationSound();
useVersionWatch();
// §13 Faz B/C — BUG #1 fix: sipariş-giriş terminalinde aktif operatör yoksa
// (yeniden PIN sorma davranışı KORUNUR — operatör varsa collectPin() `{}`
// döner) Kasa'daki gibi PIN-fallback ile adisyon açılabilsin.
// `isTerminal` AYNI kapıdan (useTerminalPin) okunur — Kitchen/Runner/Cashier
// ile tek kaynaktan tutarlı (terminal rozeti/hesap menüsü artık TerminalTopBar'da).
const { collectPin, isTerminal } = useTerminalPin();

/* ===== FAZ3 entegrasyon (terminal kilit/gate/heartbeat tutarlılığı) =====
 * Sipariş-Girişi de Kasa gibi PanelShell'den bağımsız tam-ekran (kds-canvas)
 * olduğu için PanelLayout'un sağladığı terminal altyapısını KENDİSİ kurmalı —
 * aksi halde uzaktan kilit (heartbeat) + operatör-kapısı (TerminalOperatorGate)
 * + boşta-kalma kilidi (idle-lock) bu ekranda çalışmaz (güvenlik regresyonu).
 * PanelLayout/Kitchen.vue/Runner.vue/Cashier.vue ile BİREBİR AYNI desen;
 * `activeOperator` AYNI kaynaktan (useTerminalOperator) — kopya mantık
 * üretilmedi. */
useTerminalHeartbeat();
const { current: activeOperator } = useTerminalOperator();
const idleLockEnabled = computed(() => isTerminal.value && Boolean(activeOperator.value));
const { locked: idleLocked, unlock: unlockIdle } = useTerminalIdleLock({ enabled: idleLockEnabled });

/* ---- Görsel kabuk: Kitchen.vue/Runner.vue/Cashier.vue ile birebir aynı desen
 * (ortak <TerminalTopBar> — tam ekran + hesap/operatör menüsü artık orada). ---- */
const showNav = ref(false);
const kdsTheme = useKdsTheme();

/* Yeni servis çağrısı (garson çağır / su / hesap) geldiğinde EKRANDA baloncuk +
 * SES: garson panosunda terminal/normal fark etmeksizin görünür-duyulur uyarı.
 * İlk yüklemede sessiz (mevcut çağrılar "görüldü" sayılır). */
let seenServiceIds: Set<number> | null = null;
function alertNewServiceRequests(): void {
    const list = board.value.service_requests ?? [];
    if (seenServiceIds === null) {
        seenServiceIds = new Set(list.map((s) => s.id));
        return;
    }
    let fresh = 0;
    for (const sr of list) {
        if (!seenServiceIds.has(sr.id)) {
            seenServiceIds.add(sr.id);
            fresh++;
            warning(`${sr.kind_label} · ${sr.table_name ?? 'Masa'}`, 'Servis çağrısı — lütfen ilgilenin.');
        }
    }
    if (fresh > 0) srSound.beep();
}

/* ================= Veri + polling (ADR-006: 5 sn) ================= */
const loading = ref(true);
const board = ref<BoardData>({ tables: [], channel_orders: [], pending_approval: [], service_requests: [] });
const branches = ref<BranchRow[]>([]);
const branchId = ref('');
const q = ref('');
const areaFilter = ref('');
const statusFilter = ref('');

let timer: ReturnType<typeof setInterval> | null = null;
let busyModal = false;

async function load(silent = false): Promise<void> {
    if (!silent) loading.value = true;
    try {
        board.value = await fetchBoard(branchId.value ? Number(branchId.value) : null);
        alertNewServiceRequests();
    } catch (e) {
        if (!silent) danger('Pano yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

onMounted(async () => {
    // Ses otomatik-oynatma kilidi: ilk dokunuşta aç (tarayıcı kuralı).
    const unlock = () => srSound.unlock();
    window.addEventListener('pointerdown', unlock, { once: true });
    try {
        branches.value = await fetchBranches();
    } catch {
        /* şube filtresi boş kalır */
    }
    await load();
    timer = setInterval(() => {
        if (!busyModal) void load(true);
    }, 5000);
});

onBeforeUnmount(() => {
    if (timer) clearInterval(timer);
    kdsTheme.release();
});

const branchOptions = computed(() => branches.value.map((b) => ({ value: String(b.id), label: b.name })));

/* Masadaki tüm açık adisyonların aktif kalem + servis edilen toplamı (#4). */
function tableItems(t: BoardTable): number {
    return t.orders.reduce((n, o) => n + o.items_count, 0);
}
function tableServed(t: BoardTable): number {
    return t.orders.reduce((n, o) => n + o.served_count, 0);
}

const areaOptions = computed(() => {
    const names = new Set<string>();
    board.value.tables.forEach((t) => {
        if (t.area_name) names.add(t.area_name);
    });
    return [...names].map((n) => ({ value: n, label: n }));
});

const statusOptions = computed(() => meta.tableStatuses.map((s) => ({ value: s.value, label: s.label })));

/* ================= Görünüm sekmeleri + sıralama =================
 * "Tüm masalar" salonun tamamını, "Açık masalar" yalnız adisyonu olanları
 * gösterir (yoğun serviste garson doğrudan çalıştığı masaları görür);
 * "Paket & Kanal" masa dışı siparişleri öne alır. Sıralama masaların dizilme
 * ölçütüdür — varsayılan salon düzenidir (masa no), fiziksel yerleşimle
 * örtüşsün diye. */
type ViewTab = 'all' | 'open' | 'channel';
const viewTab = ref<ViewTab>('all');

type SortKey = 'default' | 'amount' | 'recent' | 'longest';
const sortKey = ref<SortKey>('default');
const sortOptions = [
    { value: 'default', label: 'Salon düzeni (masa no)' },
    { value: 'amount', label: 'Tutar (yüksekten)' },
    { value: 'recent', label: 'Son sipariş (yeniden)' },
    { value: 'longest', label: 'En uzun oturan' },
];

/** Masanın son sipariş zamanı (en yeni adisyon hareketi) — kart bilgisi + sıralama. */
function tableLastOrderIso(t: BoardTable): string | null {
    let best: string | null = null;
    for (const o of t.orders) {
        const iso = o.placed_at ?? o.created_at;
        if (iso && (best === null || iso > best)) best = iso;
    }
    return best;
}
/** Masanın açılış zamanı (en eski açık adisyon) — "kaç dakikadır oturuyor". */
function tableOpenedIso(t: BoardTable): string | null {
    let best: string | null = null;
    for (const o of t.orders) {
        const iso = o.created_at;
        if (iso && (best === null || iso < best)) best = iso;
    }
    return best;
}
/** "14:32" — mutlak açılış saati (süreyle birlikte gösterilir). */
function clockTime(iso: string | null): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
}

function sortTables(list: BoardTable[]): BoardTable[] {
    const arr = [...list];
    if (sortKey.value === 'amount') {
        arr.sort((a, b) => tableTotal(b) - tableTotal(a));
    } else if (sortKey.value === 'recent') {
        arr.sort((a, b) => (tableLastOrderIso(b) ?? '').localeCompare(tableLastOrderIso(a) ?? ''));
    } else if (sortKey.value === 'longest') {
        // Boş masalar sona; dolu masalarda en eski açılış başa.
        arr.sort((a, b) => {
            const ai = tableOpenedIso(a);
            const bi = tableOpenedIso(b);
            if (ai === null && bi === null) return 0;
            if (ai === null) return 1;
            if (bi === null) return -1;
            return ai.localeCompare(bi);
        });
    } else {
        arr.sort((a, b) => (a.number ?? 9999) - (b.number ?? 9999) || a.name.localeCompare(b.name, 'tr-TR'));
    }
    return arr;
}

const filteredTables = computed(() =>
    board.value.tables.filter((t) => {
        if (areaFilter.value && t.area_name !== areaFilter.value) return false;
        if (statusFilter.value && t.status !== statusFilter.value) return false;
        // "Açık masalar" sekmesi: yalnız açık adisyonu olan masalar.
        if (viewTab.value === 'open' && t.orders.length === 0) return false;
        if (q.value) {
            const needle = q.value.toLocaleLowerCase('tr-TR');
            const hay = `${t.name} ${t.number ?? ''} ${t.area_name ?? ''}`.toLocaleLowerCase('tr-TR');
            if (!hay.includes(needle)) return false;
        }
        return true;
    }),
);

/* ================= Kat / alan gruplaması + masa görsel yardımcıları =================
   Yalnız görünüm (davranış değişmez): masalar aynı alan (+ kat) başlığı altında
   toplanır; kart rengi doluluğu kodlar (açık adisyon = dolu = danger, boş = success). */
interface TableGroup {
    key: string;
    area: string | null;
    floor: string | null;
    tables: BoardTable[];
}

const groupedTables = computed<TableGroup[]>(() => {
    const groups = new Map<string, TableGroup>();
    for (const t of filteredTables.value) {
        const key = `${t.floor_name ?? ''}||${t.area_name ?? ''}`;
        let g = groups.get(key);
        if (!g) {
            g = { key, area: t.area_name, floor: t.floor_name, tables: [] };
            groups.set(key, g);
        }
        g.tables.push(t);
    }
    // Seçili sıralama grup İÇİNDE uygulanır — alan/kat başlıkları korunur.
    return [...groups.values()].map((g) => ({ ...g, tables: sortTables(g.tables) }));
});

/** Masadaki toplam misafir sayısı (adisyonlarda girilmişse). */
function tableGuests(t: BoardTable): number {
    return t.orders.reduce((n, o) => n + (o.guest_count ?? 0), 0);
}

/**
 * "Unutulmuş masa": son siparişin üzerinden 30 dk+ geçmiş ve hâlâ açık.
 * Garsonun gözünden kaçan masayı kartta turuncuya çevirerek yakalatır.
 */
function staleTable(t: BoardTable): boolean {
    const iso = tableLastOrderIso(t);
    if (!iso) return false;
    return Date.now() - new Date(iso).getTime() > 30 * 60 * 1000;
}

/** Masayı açan garson (ilk açık adisyonun sahibi) — kartta ikonla gösterilir. */
function tableWaiter(t: BoardTable): string | null {
    return t.orders[0]?.opened_by ?? null;
}

/** Açık adisyonu olan masa sayısı (sekme rozeti). */
const openTableCount = computed(() => board.value.tables.reduce((n, t) => n + (t.orders.length > 0 ? 1 : 0), 0));

/** Masada açık adisyon var mı → kart rengi (dolu = danger, boş = success). */
function tableOccupied(t: BoardTable): boolean {
    // Birleşik masa da DOLUDUR: grup orada oturuyor, adisyonu komşu masada.
    return t.orders.length > 0 || t.linked_to != null;
}
/** Bir gruptaki dolu masa sayısı (başlık özeti). */
function occupiedCount(list: BoardTable[]): number {
    return list.reduce((n, t) => n + (t.orders.length > 0 ? 1 : 0), 0);
}
/** Masadaki tüm açık adisyonların kalan (ödenecek) toplamı — kuruş. */
function tableTotal(t: BoardTable): number {
    return t.orders.reduce((n, o) => n + o.remaining_minor, 0);
}
/** Kısmi teslim ilerleme çubuğu için yüzde (servis edilen / toplam kalem). */
function servedPct(t: BoardTable): string {
    const items = tableItems(t);
    if (items <= 0) return '0%';
    return `${Math.round((tableServed(t) / items) * 100)}%`;
}
/** Masadaki ödeme özeti — yalnız anlamlı olduğunda rozet çıkar (ödendi / kısmi). */
function tablePayment(t: BoardTable): 'paid' | 'partial' | null {
    if (t.orders.length === 0) return null;
    if (t.orders.every((o) => o.payment_state === 'paid')) return 'paid';
    if (t.orders.some((o) => o.payment_state !== 'unpaid')) return 'partial';
    return null;
}

/* ================= Pano özeti (üst şerit) =================
   Tüm masalar üzerinden anlık operasyon durumu — yalnız görünüm türetmesi. */
const boardSummary = computed(() => {
    const all = board.value.tables;
    const total = all.length;
    const occupied = all.reduce((n, t) => n + (t.orders.length > 0 ? 1 : 0), 0);
    const openTotal = all.reduce((n, t) => n + tableTotal(t), 0);
    const openOrders = all.reduce((n, t) => n + t.orders.length, 0);
    return {
        total,
        occupied,
        empty: total - occupied,
        openTotal,
        openOrders,
        rate: total > 0 ? Math.round((occupied / total) * 100) : 0,
    };
});

/* ================= Mobil filtre çekmecesi ================= */
const filterOpen = ref(false);
const activeFilterCount = computed(
    () => [areaFilter.value, statusFilter.value, q.value].filter((v) => v !== '').length,
);
function clearFilters(): void {
    areaFilter.value = '';
    statusFilter.value = '';
    q.value = '';
}

/* ================= Masa aç / adisyona git =================
   Kişi sayısı AÇILIŞTA SORULMAZ (kullanıcı talebi): masaya tıklayınca boşsa
   direkt adisyon açılır ve içine girilir; tek adisyon varsa ona girilir; birden
   çok adisyon varsa seçtirilir. Misafir adedi opsiyonel — adisyon detayından
   sonradan eklenebilir (backend guest_count nullable). */
const openTable = ref<BoardTable | null>(null);
const openBusy = ref(false);

/* Rezervasyon ↔ walk-in çakışma onayı (§8): boş görünen masaya adisyon
   açılırken masanın yaklaşan/aktif rezervasyonu varsa backend 409 +
   requires_confirmation döndürür; personel onaylarsa confirm=true ile açılır. */
interface ReservationConflict {
    message: string;
    table: BoardTable;
    reservation?: { customer_name?: string; reserved_time?: string; party_size?: number; status_label?: string };
    // §13 Faz B/C: ilk denemede toplanan PIN alanları (varsa) — onay sonrası
    // yeniden POST'ta AYNI PIN kullanılır, personel ikinci kez PIN girmez.
    pinFields?: Record<string, unknown> | null;
}
const reservationConflict = ref<ReservationConflict | null>(null);

/** Bu masa başka adisyona bağlı mı (grup birleştirmesi)? */
function linkedTo(t: BoardTable) {
    return t.linked_to ?? null;
}

function onTableClick(table: BoardTable): void {
    // Birleşik masa: adisyon komşu masada — doğrudan ANA adisyona git.
    if (table.linked_to != null) {
        router.visit(`/panel/siparisler/${table.linked_to.order_id}`);
        return;
    }
    if (table.orders.length === 1) {
        router.visit(`/panel/siparisler/${table.orders[0].id}`);
        return;
    }
    if (table.orders.length === 0) {
        if (!canCreateOrders) return; // orders.create yok → buton zaten devre dışı, savunma amaçlı ikinci kapı
        void createOrder(table); // boş masa → doğrudan adisyon aç + içine gir
        return;
    }
    // Birden çok açık adisyon → hangisine gireceğini seçtir.
    openTable.value = table;
    busyModal = true;
}

function closeTableModal(): void {
    openTable.value = null;
    busyModal = false;
}

async function createOrder(
    table: BoardTable,
    confirm = false,
    knownPinFields: Record<string, unknown> | null = null,
): Promise<void> {
    if (openBusy.value) return;
    // Çift-tıklama kilidi: await'lerden (collectPin/PIN modalı) ÖNCE senkron kur.
    openBusy.value = true;
    // §13 Faz B/C — BUG #1 fix: sipariş-giriş terminalinde aktif operatör
    // yoksa (Kasa'daki gibi) PIN istenir; operatör varsa collectPin() `{}`
    // döner (yeniden PIN SORULMAZ — #183 davranışı korunur). İptal edilirse
    // adisyon açılmaz. `let` (try/catch dışında da erişim — rezervasyon-
    // çakışma onayında AYNI PIN saklanıp tekrar kullanılabilsin diye).
    let pinFields: Record<string, unknown> | null = knownPinFields;
    try {
        if (pinFields === null) {
            pinFields = await collectPin();
            if (pinFields === null) return;
        }

        const res = await api<{ order: OrderSummary }>('/api/v1/orders', {
            method: 'POST',
            body: {
                branch_id: branchId.value ? Number(branchId.value) : branches.value[0]?.id,
                channel: 'table',
                table_id: table.id,
                guest_count: null,
                confirm,
                ...pinFields,
            },
        });
        success('Adisyon açıldı', `${table.name} için yeni adisyon oluşturuldu.`);
        reservationConflict.value = null;
        closeTableModal();
        router.visit(`/panel/siparisler/${res.order.id}`);
    } catch (e) {
        // Rezervasyon çakışması: onay iste (adisyon henüz açılmadı).
        if (e instanceof ApiError && e.status === 409 && e.data?.requires_confirmation) {
            const r = e.data.reservation as ReservationConflict['reservation'];
            reservationConflict.value = {
                message: typeof e.data.message === 'string' ? e.data.message : 'Bu masa rezerve — yine de açılsın mı?',
                table,
                reservation: r,
                pinFields,
            };
            busyModal = true;
            return;
        }
        danger('Adisyon açılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        openBusy.value = false;
    }
}

function cancelReservationConflict(): void {
    reservationConflict.value = null;
    busyModal = false;
}

async function confirmReservationConflict(): Promise<void> {
    const pending = reservationConflict.value;
    if (!pending) return;
    reservationConflict.value = null;
    busyModal = false;
    // İlk denemede toplanan PIN (varsa) yeniden kullanılır — personel ikinci
    // kez PIN girmek zorunda kalmaz.
    await createOrder(pending.table, true, pending.pinFields ?? null);
}

/* ================= Masasız kanal siparişi (paket / gel-al / kiosk) ================= */
const channelModal = ref(false);
const channelForm = ref({ channel: 'package', customer_name: '', customer_phone: '', note: '' });
const channelBusy = ref(false);

const channelOptions = computed(() =>
    meta.channels.filter((c) => c.value !== 'table' && c.value !== 'qr').map((c) => ({ value: c.value, label: c.label })),
);

function openChannelModal(): void {
    channelForm.value = { channel: 'package', customer_name: '', customer_phone: '', note: '' };
    channelModal.value = true;
    busyModal = true;
}

function closeChannelModal(): void {
    channelModal.value = false;
    busyModal = false;
}

async function createChannelOrder(): Promise<void> {
    if (channelBusy.value) return;
    // Çift-tıklama kilidi: await'lerden (collectPin/PIN modalı) ÖNCE senkron kur.
    channelBusy.value = true;
    try {
        // §13 Faz B/C — BUG #1 fix (bkz. createOrder): masasız kanal siparişi
        // de aynı PIN-fallback kapısından geçer.
        const pinFields = await collectPin();
        if (pinFields === null) return;

        const res = await api<{ order: OrderSummary }>('/api/v1/orders', {
            method: 'POST',
            body: {
                branch_id: branchId.value ? Number(branchId.value) : branches.value[0]?.id,
                channel: channelForm.value.channel,
                customer_name: channelForm.value.customer_name || null,
                customer_phone: channelForm.value.customer_phone || null,
                note: channelForm.value.note || null,
                ...pinFields,
            },
        });
        success('Sipariş açıldı', 'Ürünleri ekleyebilirsiniz.');
        closeChannelModal();
        router.visit(`/panel/siparisler/${res.order.id}`);
    } catch (e) {
        danger('Sipariş açılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        channelBusy.value = false;
    }
}

/* ================= Servis talepleri ================= */
const resolvingRequest = ref<number | null>(null);

async function resolveRequest(sr: ServiceRequestRow): Promise<void> {
    if (resolvingRequest.value !== null) return;
    resolvingRequest.value = sr.id;
    try {
        await api(`/api/v1/orders/service-requests/${sr.id}/done`, { method: 'POST' });
        success('Talep kapatıldı', `${sr.table_name ?? 'Masa'} — ${sr.kind_label}`);
        await load(true);
    } catch (e) {
        danger('Kapatılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        resolvingRequest.value = null;
    }
}

/* ================= QR onayı ================= */
const approving = ref<number | null>(null);

async function approveOrder(order: OrderSummary): Promise<void> {
    if (approving.value !== null) return;
    approving.value = order.id;
    try {
        await api(`/api/v1/orders/${order.id}/approve`, { method: 'POST' });
        success('Sipariş onaylandı', `${order.table_name ?? 'Masa'} siparişi mutfağa düşebilir.`);
        await load(true);
    } catch (e) {
        danger('Onaylanamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        approving.value = null;
    }
}
</script>

<template>
    <Head title="Siparişler" />

    <div class="kds-canvas fixed inset-0 flex flex-col overflow-hidden text-body">
        <!-- ================= Üst çubuk (Kitchen.vue/Runner.vue/Cashier.vue ile aynı dil) ================= -->
        <TerminalTopBar
            screen-label="Sipariş Girişi Ekranı"
            :theme="kdsTheme.theme.value"
            @toggle-theme="kdsTheme.toggle()"
            @open-nav="showNav = true"
        >
            <template #status>
                <!-- Doluluk özeti: kompakt pill (Kitchen'daki "bekleyen" rozetiyle aynı dil) -->
                <span
                    v-if="boardSummary.total > 0"
                    class="ml-1 inline-flex shrink-0 items-center gap-1.5 rounded-full border border-default bg-inset px-2.5 py-1 text-xs font-semibold text-muted tabular-nums"
                >
                    {{ boardSummary.occupied }}/{{ boardSummary.total }} masa dolu
                </span>

                <span
                    v-if="board.service_requests.length > 0"
                    role="alert"
                    class="inline-flex shrink-0 items-center gap-1 rounded-full border border-danger bg-danger px-2.5 py-1 text-xs font-semibold text-on-status"
                >
                    <AppIcon name="bell" :size="13" />
                    {{ board.service_requests.length }} servis çağrısı
                </span>
            </template>
        </TerminalTopBar>

        <!-- ================= İçerik (kaydırılabilir) ================= -->
        <main class="flex-1 overflow-y-auto p-4">
        <div class="flex flex-col gap-4">
            <!-- Açık servis talepleri (garson çağır / hesap iste / su iste) -->
            <BaseCard v-if="board.service_requests.length > 0">
                <div class="flex items-center gap-2 pb-2">
                    <AppIcon name="bell" :size="18" class="text-danger" />
                    <h2 class="text-sm font-semibold text-body">Servis talepleri ({{ board.service_requests.length }})</h2>
                </div>
                <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                    <div
                        v-for="sr in board.service_requests"
                        :key="sr.id"
                        class="flex items-center gap-3 rounded-xl border border-danger-border bg-danger-soft/40 p-3"
                    >
                        <span class="flex size-11 shrink-0 items-center justify-center rounded-full bg-danger text-white shadow-sm">
                            <AppIcon :name="sr.kind_icon" :size="20" />
                        </span>
                        <div class="min-w-0 flex-1">
                            <p class="truncate text-[15px] font-bold leading-tight text-body">{{ sr.kind_label }}</p>
                            <p class="mt-0.5 flex items-center gap-1.5 text-sm text-muted">
                                <AppIcon name="store" :size="13" class="shrink-0 text-danger" />
                                <span class="truncate font-semibold text-body">{{ sr.table_name ?? 'Masa' }}</span>
                                <span class="text-subtle">·</span>
                                <span class="whitespace-nowrap">{{ elapsed(sr.created_at) }} önce</span>
                            </p>
                        </div>
                        <BaseButton size="sm" variant="secondary" class="shrink-0" :loading="resolvingRequest === sr.id" @click="resolveRequest(sr)">
                            <AppIcon name="check" :size="14" />
                            İlgilenildi
                        </BaseButton>
                    </div>
                </div>
            </BaseCard>

            <!-- Onay bekleyen QR siparişleri -->
            <BaseCard v-if="board.pending_approval.length > 0">
                <div class="flex items-center gap-2 pb-2">
                    <AppIcon name="bell" :size="18" class="text-warning" />
                    <h2 class="text-sm font-semibold text-body">Onay bekleyen QR siparişleri ({{ board.pending_approval.length }})</h2>
                </div>
                <div class="flex flex-col gap-2">
                    <div
                        v-for="o in board.pending_approval"
                        :key="o.id"
                        class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-default p-3"
                    >
                        <div class="flex items-center gap-3">
                            <BaseBadge :variant="o.status_variant" no-icon>
                                <AppIcon :name="o.status_icon" :size="12" />
                                {{ o.status_label }}
                            </BaseBadge>
                            <span class="font-medium">{{ o.table_name ?? o.channel_label }}</span>
                            <span class="text-sm text-muted">{{ o.items_count }} kalem</span>
                            <span class="whitespace-nowrap text-sm font-semibold tabular-nums text-body">{{ o.total_display }} ₺</span>
                            <span class="text-xs text-subtle">{{ orderElapsed(o) }} önce</span>
                        </div>
                        <div class="flex gap-2">
                            <BaseButton size="sm" variant="secondary" @click="router.visit(`/panel/siparisler/${o.id}`)">İncele</BaseButton>
                            <BaseButton size="sm" :loading="approving === o.id" @click="approveOrder(o)">
                                <AppIcon name="check" :size="14" />
                                Onayla
                            </BaseButton>
                        </div>
                    </div>
                </div>
            </BaseCard>

            <!-- Pano özeti: her kutuda İKON + sayı; etiketler kısaldı, göz
                 rakamı önce yakalar (yoğun serviste okunacak metin azalır). -->
            <div v-if="boardSummary.total > 0" class="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <div class="rounded-xl border border-default bg-raised p-3.5">
                    <p class="flex items-center gap-1.5 text-xs font-medium text-muted">
                        <AppIcon name="gauge" :size="14" class="text-subtle" /> Doluluk
                    </p>
                    <p class="mt-0.5 text-2xl font-bold tabular-nums text-body">%{{ boardSummary.rate }}</p>
                    <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-inset">
                        <div class="h-full rounded-full bg-primary transition-[width] duration-(--dur-normal)" :style="{ width: boardSummary.rate + '%' }" />
                    </div>
                </div>
                <div class="rounded-xl border border-default bg-raised p-3.5">
                    <p class="flex items-center gap-1.5 text-xs font-medium text-muted">
                        <AppIcon name="utensils" :size="14" class="text-subtle" /> Dolu / Boş
                    </p>
                    <p class="mt-0.5 text-2xl font-bold leading-none tabular-nums">
                        <span class="text-danger">{{ boardSummary.occupied }}</span>
                        <span class="text-subtle"> / </span>
                        <span class="text-success">{{ boardSummary.empty }}</span>
                    </p>
                    <p class="mt-2 text-xs text-subtle">{{ boardSummary.total }} masa</p>
                </div>
                <div class="rounded-xl border border-default bg-raised p-3.5">
                    <p class="flex items-center gap-1.5 text-xs font-medium text-muted">
                        <AppIcon name="wallet" :size="14" class="text-subtle" /> Açık tutar
                    </p>
                    <p class="mt-0.5 flex items-baseline gap-1 text-2xl font-bold leading-none text-body tabular-nums">
                        {{ money(boardSummary.openTotal) }}<span class="text-base font-semibold text-muted">₺</span>
                    </p>
                    <p class="mt-2 text-xs text-subtle">tahsil edilecek</p>
                </div>
                <div class="rounded-xl border border-default bg-raised p-3.5">
                    <p class="flex items-center gap-1.5 text-xs font-medium text-muted">
                        <AppIcon name="orders" :size="14" class="text-subtle" /> Açık adisyon
                    </p>
                    <p class="mt-0.5 text-2xl font-bold leading-none text-body tabular-nums">{{ boardSummary.openOrders }}</p>
                    <p class="mt-2 flex items-center gap-1 text-xs" :class="board.service_requests.length > 0 ? 'font-semibold text-warning' : 'text-subtle'">
                        <AppIcon name="bell" :size="12" /> {{ board.service_requests.length }} servis çağrısı
                    </p>
                </div>
            </div>

            <!-- Görünüm sekmeleri: tüm salon / yalnız açık masalar / masa dışı kanallar -->
            <div class="flex items-center gap-1 rounded-lg border border-default bg-raised p-1">
                <button
                    v-for="tab in ([
                        { key: 'all', label: 'Tüm masalar', icon: 'utensils', count: board.tables.length },
                        { key: 'open', label: 'Açık masalar', icon: 'cart', count: openTableCount },
                        { key: 'channel', label: 'Paket & Kanal', icon: 'truck', count: board.channel_orders.length },
                    ] as const)"
                    :key="tab.key"
                    type="button"
                    class="flex flex-1 items-center justify-center gap-1.5 rounded-md px-3 py-2 text-sm font-semibold transition"
                    :class="viewTab === tab.key ? 'bg-primary text-on-primary shadow-sm' : 'text-muted hover:bg-inset hover:text-body'"
                    :aria-pressed="viewTab === tab.key"
                    @click="viewTab = tab.key"
                >
                    <AppIcon :name="tab.icon" :size="15" />
                    <span class="hidden sm:inline">{{ tab.label }}</span>
                    <span
                        class="rounded-full px-1.5 text-xs tabular-nums"
                        :class="viewTab === tab.key ? 'bg-black/15' : 'bg-inset'"
                    >{{ tab.count }}</span>
                </button>
            </div>

            <!-- Filtreler: TEK SATIR araç çubuğu.
                 Önceki düzende beş ayrı etiketli alan (Şube/Ara/Alan/Durum/
                 Sıralama) iki satır yer kaplıyordu ve masalar aşağı itiliyordu.
                 Artık: arama solda, sıralama ikon menüsü, süzgeçler tek "Filtre"
                 menüsünde (uygulanan varsa rozetle sayılır). -->
            <div class="hidden items-center gap-2 rounded-lg border border-default bg-raised p-2 md:flex">
                <div class="min-w-0 grow">
                    <SearchInput v-model="q" placeholder="Masa adı veya no…" />
                </div>

                <!-- Sıralama: ikon + seçili seçeneğin adı -->
                <BaseDropdown align="right" menu-label="Sıralama">
                    <template #trigger="{ toggle, ariaAttrs }">
                        <button
                            type="button"
                            v-bind="ariaAttrs"
                            class="flex h-9 shrink-0 items-center gap-1.5 rounded-md border border-default bg-raised px-2.5 text-sm font-medium text-body transition hover:border-strong"
                            title="Sıralama"
                            @click="toggle"
                        >
                            <AppIcon name="filter" :size="15" class="text-subtle" />
                            <span class="hidden lg:inline">{{ sortOptions.find((o) => o.value === sortKey)?.label }}</span>
                            <AppIcon name="chevron-down" :size="14" class="text-subtle" />
                        </button>
                    </template>
                    <DropdownItem
                        v-for="o in sortOptions"
                        :key="o.value"
                        :icon="sortKey === o.value ? 'check' : ''"
                        @select="sortKey = o.value as SortKey"
                    >
                        {{ o.label }}
                    </DropdownItem>
                </BaseDropdown>

                <!-- Süzgeçler: şube + alan + masa durumu tek menüde -->
                <BaseDropdown align="right" menu-label="Filtreler">
                    <template #trigger="{ toggle, ariaAttrs }">
                        <button
                            type="button"
                            v-bind="ariaAttrs"
                            class="flex h-9 shrink-0 items-center gap-1.5 rounded-md border px-2.5 text-sm font-medium transition"
                            :class="activeFilterCount > 0
                                ? 'border-primary bg-primary-soft text-primary'
                                : 'border-default bg-raised text-body hover:border-strong'"
                            title="Filtrele"
                            @click="toggle"
                        >
                            <AppIcon name="settings" :size="15" />
                            <span class="hidden lg:inline">Filtre</span>
                            <span
                                v-if="activeFilterCount > 0"
                                class="flex size-5 items-center justify-center rounded-full bg-primary text-[11px] font-bold text-on-primary tabular-nums"
                            >{{ activeFilterCount }}</span>
                        </button>
                    </template>
                    <div class="flex w-64 flex-col gap-3 p-3" @click.stop>
                        <FormField v-if="branchOptions.length > 1" label="Şube">
                            <BaseSelect v-model="branchId" :options="branchOptions" placeholder="Tümü" size="sm" @update:model-value="() => load()" />
                        </FormField>
                        <FormField v-if="areaOptions.length > 1" label="Alan">
                            <BaseSelect v-model="areaFilter" :options="areaOptions" placeholder="Tümü" size="sm" />
                        </FormField>
                        <FormField label="Masa durumu">
                            <BaseSelect v-model="statusFilter" :options="statusOptions" placeholder="Tümü" size="sm" />
                        </FormField>
                        <BaseButton v-if="activeFilterCount > 0" variant="ghost" size="sm" @click="clearFilters">
                            Filtreleri temizle
                        </BaseButton>
                    </div>
                </BaseDropdown>

                <BaseButton v-if="canCreateOrders" variant="secondary" @click="openChannelModal">
                    <AppIcon name="truck" :size="16" />
                    <span class="hidden lg:inline">Paket / Gel-Al</span>
                </BaseButton>
            </div>

            <!-- Filtreler: mobil bar (masalar hemen altında görünür) -->
            <div class="flex items-center gap-2 md:hidden">
                <BaseButton variant="secondary" class="grow justify-center" @click="filterOpen = true">
                    <AppIcon name="filter" :size="16" />
                    Filtrele
                    <span
                        v-if="activeFilterCount > 0"
                        class="ml-0.5 flex h-5 min-w-5 items-center justify-center rounded-full bg-primary px-1 text-xs font-bold text-white tabular-nums"
                    >{{ activeFilterCount }}</span>
                </BaseButton>
                <BaseButton v-if="canCreateOrders" variant="secondary" aria-label="Paket / Gel-Al / Kiosk" @click="openChannelModal">
                    <AppIcon name="cart" :size="16" />
                </BaseButton>
            </div>

            <!-- Masa panosu: kat/alan gruplu, büyük dokunmatik kartlar. Kart rengi
                 doluluğu kodlar (dolu = kırmızı şerit, boş = yeşil). Durum rozeti
                 (3'lü) yalnız görüntüdür — buradan durum ilerletilmez. -->
            <template v-if="viewTab !== 'channel' && filteredTables.length > 0">
                <section v-for="g in groupedTables" :key="g.key" class="flex flex-col gap-3">
                    <!-- Grup başlığı: alan/kat + doluluk özeti (renk anahtarı) -->
                    <div class="flex flex-wrap items-center gap-x-3 gap-y-1 px-0.5">
                        <span class="flex h-8 w-8 items-center justify-center rounded-lg bg-primary-soft text-primary">
                            <AppIcon name="utensils" :size="16" />
                        </span>
                        <h2 class="text-base font-bold text-body">{{ g.area ?? g.floor ?? 'Masalar' }}</h2>
                        <span v-if="g.area && g.floor" class="text-xs font-medium text-subtle">· {{ g.floor }}</span>
                        <span class="ml-auto flex items-center gap-3 text-xs font-semibold">
                            <span class="flex items-center gap-1.5 text-danger">
                                <span class="h-2 w-2 rounded-full bg-danger"></span>{{ occupiedCount(g.tables) }} dolu
                            </span>
                            <span class="flex items-center gap-1.5 text-success">
                                <span class="h-2 w-2 rounded-full bg-success"></span>{{ g.tables.length - occupiedCount(g.tables) }} boş
                            </span>
                        </span>
                    </div>

                    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 sm:gap-4 lg:grid-cols-3 xl:grid-cols-4">
                        <button
                            v-for="t in g.tables"
                            :key="t.id"
                            type="button"
                            class="group relative flex min-h-36 flex-col gap-3 overflow-hidden rounded-2xl border p-4 text-left shadow-sm transition-all duration-150 hover:-translate-y-0.5 hover:shadow-lg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:translate-y-0 disabled:hover:shadow-sm"
                            :class="tableOccupied(t)
                                ? (staleTable(t) ? 'border-danger-border bg-danger-soft' : 'border-warning-border bg-warning-soft')
                                : (t.reservation ? 'border-warning-border bg-warning-soft/40' : 'border-success-border bg-success-soft/50')"
                            :aria-label="`${t.name} — ${t.status_label}`"
                            :disabled="t.orders.length === 0 && !canCreateOrders"
                            :title="t.orders.length === 0 && !canCreateOrders ? 'Adisyon açma yetkiniz yok' : undefined"
                            @click="onTableClick(t)"
                        >
                            <!-- BAŞLIK ŞERİDİ (referans düzen): masa adı ORTALANMIŞ
                                 yumuşak bir hapta; durum rengi haptan okunur. Alan/
                                 kapasite ikinci satırda, küçük. -->
                            <div class="-mx-4 -mt-4 flex flex-col items-center gap-0.5 border-b border-default px-4 pb-2.5 pt-3">
                                <span
                                    class="max-w-full truncate rounded-full px-3 py-1 text-sm font-bold"
                                    :class="tableOccupied(t)
                                        ? 'bg-danger-soft text-danger'
                                        : (t.reservation ? 'bg-warning-soft text-warning' : 'bg-success-soft text-success')"
                                >
                                    {{ t.name }}<span v-if="t.number !== null" class="font-mono text-[11px] opacity-70"> #{{ t.number }}</span>
                                </span>
                                <span class="flex max-w-full items-center gap-1.5 truncate text-[11px] text-subtle">
                                    <span v-if="t.area_name" class="truncate">{{ t.area_name }}</span>
                                    <span v-if="t.area_name" aria-hidden="true">·</span>
                                    <span class="inline-flex shrink-0 items-center gap-0.5">
                                        <AppIcon name="users" :size="10" />{{ t.capacity }}
                                    </span>
                                </span>
                            </div>

                            <!-- BİRLEŞİK MASA: hesap komşu masada; burada yalnız bağ
                                 gösterilir (çift tutar/çift sayım olmaz). -->
                            <template v-if="t.linked_to">
                                <div class="mt-auto flex flex-col items-center gap-1.5 text-center">
                                    <span class="inline-flex items-center gap-1.5 rounded-full border border-primary bg-primary-soft px-2.5 py-1 text-xs font-bold text-primary">
                                        <AppIcon name="merge" :size="13" />
                                        Birleşik masa
                                    </span>
                                    <p class="text-xs text-muted">
                                        Hesap <span class="font-semibold text-body">{{ t.linked_to.table_name ?? `#${t.linked_to.order_id}` }}</span> masasında
                                    </p>
                                    <p class="text-sm font-bold tabular-nums text-body">
                                        {{ money(t.linked_to.remaining_minor) }} ₺
                                        <span class="text-xs font-medium text-muted">· {{ t.linked_to.items_count }} kalem</span>
                                    </p>
                                </div>
                            </template>

                            <!-- DOLU: iki sütun özet (Toplam tutar / Son sipariş) + açılış satırı -->
                            <template v-else-if="tableOccupied(t)">
                                <div class="mt-auto flex flex-col gap-2">
                                    <div class="grid grid-cols-2 gap-2 text-center">
                                        <div class="min-w-0">
                                            <p class="text-[11px] font-medium text-muted">Toplam tutar</p>
                                            <p class="truncate text-lg font-extrabold tabular-nums text-body">
                                                {{ money(tableTotal(t)) }} <span class="text-sm font-bold text-muted">₺</span>
                                            </p>
                                        </div>
                                        <div class="min-w-0">
                                            <p class="text-[11px] font-medium text-muted">Son sipariş</p>
                                            <p
                                                class="truncate text-lg font-extrabold tabular-nums"
                                                :class="staleTable(t) ? 'text-warning' : 'text-body'"
                                                :title="staleTable(t) ? 'Son siparişin üzerinden 30 dakikadan fazla geçti' : 'Son sipariş'"
                                            >
                                                {{ elapsed(tableLastOrderIso(t)) || '—' }}
                                            </p>
                                        </div>
                                    </div>

                                    <!-- Açılış: saat + oturma süresi (referanstaki alt satır) -->
                                    <!-- Açılış saati AYRI TONDA: masanın ne zaman
                                         oturduğu, tutar ve son sipariş gibi "para/
                                         aciliyet" bilgilerinden görsel olarak ayrılsın
                                         diye mavi (bilgi) tonunda ve kendi rozetinde. -->
                                    <p class="flex items-center justify-center gap-1.5 rounded-md border border-warning-border bg-warning-soft px-2 py-1 text-[11px] font-semibold text-warning">
                                        <AppIcon name="clock" :size="12" />
                                        Açılış <span class="tabular-nums">{{ clockTime(tableOpenedIso(t)) }}</span>
                                        <span class="tabular-nums opacity-80">· {{ orderElapsed(t.orders[0]) }}</span>
                                    </p>

                                    <!-- Kısmi teslim ilerleme çubuğu -->
                                    <div v-if="tableItems(t) > 0 && tableServed(t) < tableItems(t)">
                                        <div class="mb-1 flex items-center justify-between text-[11px] font-medium text-subtle">
                                            <span class="inline-flex items-center gap-1"><AppIcon name="utensils" :size="11" /> Servis</span>
                                            <span class="tabular-nums">{{ tableServed(t) }}/{{ tableItems(t) }}</span>
                                        </div>
                                        <div class="h-1.5 w-full overflow-hidden rounded-full bg-inset">
                                            <div class="h-full rounded-full bg-success transition-all" :style="{ width: servedPct(t) }"></div>
                                        </div>
                                    </div>

                                    <!-- Ayrıntı satırı: kalem · kişi · adisyon · garson (hepsi ikon) -->
                                    <div class="flex flex-wrap items-center justify-center gap-x-2.5 gap-y-1 border-t border-default pt-2 text-[11px] font-medium text-muted">
                                        <span class="inline-flex items-center gap-1" :title="`${tableItems(t)} kalem`">
                                            <AppIcon name="utensils" :size="11" class="text-subtle" />
                                            <span class="tabular-nums">{{ tableItems(t) }}</span>
                                        </span>
                                        <span v-if="tableGuests(t)" class="inline-flex items-center gap-1" :title="`${tableGuests(t)} kişi`">
                                            <AppIcon name="users" :size="11" class="text-subtle" />
                                            <span class="tabular-nums">{{ tableGuests(t) }}</span>
                                        </span>
                                        <span v-if="t.orders.length > 1" class="inline-flex items-center gap-1" :title="`${t.orders.length} ayrı adisyon`">
                                            <AppIcon name="orders" :size="11" class="text-subtle" />
                                            <span class="tabular-nums">{{ t.orders.length }}</span>
                                        </span>
                                        <span v-if="tableWaiter(t)" class="inline-flex min-w-0 items-center gap-1" :title="`Açan: ${tableWaiter(t)}`">
                                            <AppIcon name="user" :size="11" class="text-subtle" />
                                            <span class="max-w-20 truncate">{{ tableWaiter(t) }}</span>
                                        </span>
                                        <span
                                            v-if="tablePayment(t)"
                                            class="inline-flex items-center gap-1 font-semibold"
                                            :class="tablePayment(t) === 'paid' ? 'text-success' : 'text-warning'"
                                            :title="tablePayment(t) === 'paid' ? 'Ödendi' : 'Kısmi ödendi'"
                                        >
                                            <AppIcon :name="tablePayment(t) === 'paid' ? 'check-circle' : 'wallet'" :size="11" />
                                            {{ tablePayment(t) === 'paid' ? 'Ödendi' : 'Kısmi' }}
                                        </span>
                                    </div>
                                </div>
                            </template>

                            <!-- Rezerve (boş ama bugüne ayrılmış): kime/kaça ayrıldığı görünür -->
                            <template v-else-if="t.reservation">
                                <div class="mt-auto flex flex-col gap-2">
                                    <div class="rounded-lg border border-warning-border bg-warning-soft/60 px-2.5 py-2">
                                        <p class="flex items-center gap-1.5 text-xs font-bold text-warning">
                                            <AppIcon name="bell" :size="13" />
                                            {{ t.reservation.time }}–{{ t.reservation.time_end }} · Rezerve
                                        </p>
                                        <p class="mt-0.5 flex items-center gap-1.5 truncate text-sm font-semibold text-body">
                                            {{ t.reservation.name }}
                                            <span class="inline-flex items-center gap-0.5 text-xs font-medium text-muted">
                                                <AppIcon name="users" :size="11" />{{ t.reservation.party }}
                                            </span>
                                        </p>
                                    </div>
                                    <span class="flex items-center justify-center gap-1 text-xs font-semibold text-warning">
                                        <AppIcon name="plus" :size="14" />Yine de adisyon aç
                                    </span>
                                </div>
                            </template>

                            <!-- BOŞ: dolu kartla AYNI iki sütun iskeleti (değerler "—").
                                 Izgara böylece hizalı kalır — kartlar birbirine göre
                                 zıplamaz; dokununca adisyon açılır. -->
                            <template v-else>
                                <div class="mt-auto flex flex-col gap-2">
                                    <div class="grid grid-cols-2 gap-2 text-center">
                                        <div>
                                            <p class="text-[11px] font-medium text-muted">Toplam tutar</p>
                                            <p class="text-lg font-extrabold text-subtle">—</p>
                                        </div>
                                        <div>
                                            <p class="text-[11px] font-medium text-muted">Son sipariş</p>
                                            <p class="text-lg font-extrabold text-subtle">—</p>
                                        </div>
                                    </div>
                                    <span class="flex items-center justify-center gap-1.5 border-t border-default pt-2 text-xs font-semibold text-success">
                                        <AppIcon name="plus" :size="14" class="transition-transform group-hover:scale-125" />
                                        Adisyon aç
                                    </span>
                                </div>
                            </template>
                        </button>
                    </div>
                </section>
            </template>
            <BaseCard v-else-if="viewTab !== 'channel' && !loading">
                <EmptyState
                    :title="viewTab === 'open' ? 'Açık masa yok' : 'Masa bulunamadı'"
                    :description="viewTab === 'open'
                        ? 'Şu an adisyonu açık masa yok. Tüm salonu görmek için “Tüm masalar”a geçin.'
                        : 'Filtreleri değiştirin ya da Masalar sayfasından masa oluşturun.'"
                    :icon="viewTab === 'open' ? 'check-circle' : 'qr-code'"
                />
            </BaseCard>

            <!-- "Paket & Kanal" sekmesinde hiç kanal siparişi yoksa boş durum -->
            <BaseCard v-if="viewTab === 'channel' && board.channel_orders.length === 0 && !loading">
                <EmptyState
                    title="Masa dışı sipariş yok"
                    description="Paket, gel-al ve kiosk siparişleri burada listelenir. Yeni sipariş için “Paket / Gel-Al / Kiosk” düğmesini kullanın."
                    icon="truck"
                />
            </BaseCard>

            <!-- Masasız kanal siparişleri: paket / gel-al / kiosk — şık kart ızgarası -->
            <BaseCard v-if="board.channel_orders.length > 0">
                <template #header>
                    <div class="flex items-center gap-2">
                        <AppIcon name="package" :size="18" class="text-primary" />
                        <h2 class="text-sm font-semibold text-body">Paket / Gel-Al / Kiosk siparişleri</h2>
                        <span class="rounded-full bg-inset px-2 py-0.5 text-xs font-semibold text-muted">{{ board.channel_orders.length }}</span>
                    </div>
                </template>
                <div class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
                    <button
                        v-for="o in board.channel_orders"
                        :key="o.id"
                        type="button"
                        class="group flex flex-col gap-3 rounded-2xl border border-default bg-raised p-4 text-left shadow-sm transition-all duration-150 hover:-translate-y-0.5 hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                        @click="router.visit(`/panel/siparisler/${o.id}`)"
                    >
                        <div class="flex items-start justify-between gap-2">
                            <div class="flex flex-wrap items-center gap-1.5">
                                <!-- Kaynak (nereden: Garson/Kiosk/QR) — tek etiket, ServiceType ile çakışmaz (#3) -->
                                <BaseBadge :variant="o.source_variant" no-icon>
                                    <AppIcon :name="o.source_icon" :size="12" />
                                    {{ o.source_label }}
                                </BaseBadge>
                                <!-- Servis tipi (nasıl: Masada/Gel-al/Paket) -->
                                <BaseBadge :variant="o.service_type_variant" no-icon>
                                    <AppIcon :name="o.service_type_icon" :size="12" />
                                    {{ o.service_type_label }}
                                </BaseBadge>
                            </div>
                            <span class="shrink-0 font-mono text-xs font-semibold text-subtle">#{{ o.id }}</span>
                        </div>

                        <div class="flex items-end justify-between gap-2">
                            <div class="min-w-0">
                                <p v-if="o.customer_name" class="truncate text-sm font-semibold text-body">{{ o.customer_name }}</p>
                                <p class="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-subtle">
                                    <span class="font-medium text-muted">{{ o.items_count }} kalem</span>
                                    <span aria-hidden="true">·</span>
                                    <span>{{ orderElapsed(o) }}</span>
                                </p>
                            </div>
                            <p class="flex shrink-0 items-baseline gap-1 leading-none">
                                <span class="text-xl font-extrabold tabular-nums text-body">{{ o.total_display }}</span>
                                <span class="text-sm font-bold text-muted">₺</span>
                            </p>
                        </div>

                        <div class="flex flex-wrap items-center gap-1.5 border-t border-default pt-2.5">
                            <BaseBadge :variant="o.status_variant" no-icon>
                                <AppIcon :name="o.status_icon" :size="12" />
                                {{ o.status_label }}
                            </BaseBadge>
                            <BaseBadge :variant="o.payment_state === 'paid' ? 'success' : o.payment_state === 'partial' ? 'warning' : 'neutral'" no-icon>
                                <AppIcon :name="o.payment_state === 'paid' ? 'check-circle' : 'cart'" :size="12" />
                                {{ o.payment_label }}
                            </BaseBadge>
                            <!-- Kısmi teslim ilerlemesi (#4): komi kalemleri tek tek teslim eder -->
                            <span v-if="o.items_count > 0 && o.served_count < o.items_count" class="ml-auto text-xs font-medium text-subtle">
                                {{ o.served_count }}/{{ o.items_count }} servis
                            </span>
                        </div>
                    </button>
                </div>
            </BaseCard>
        </div>
        </main>
    </div>

    <!-- Masa modalı: yalnız birden çok açık adisyon varsa çıkar — hangisine
         gireceğini seçtirir ya da yeni adisyon açtırır. Kişi sayısı SORULMAZ. -->
        <BaseModal :open="openTable !== null" :title="openTable?.name ?? 'Masa'" size="sm" @close="closeTableModal">
            <div v-if="openTable && openTable.orders.length > 0" class="flex flex-col gap-2">
                <p class="text-xs font-medium text-muted">Bu masadaki açık adisyonlar</p>
                <button
                    v-for="o in openTable.orders"
                    :key="o.id"
                    type="button"
                    class="flex items-center justify-between rounded-lg border border-default p-3 text-left hover:bg-inset"
                    @click="busyModal = false; router.visit(`/panel/siparisler/${o.id}`)"
                >
                    <span class="font-medium">Adisyon #{{ o.id }}</span>
                    <span class="text-sm text-muted">{{ o.items_count }} kalem · <span class="whitespace-nowrap tabular-nums">{{ o.total_display }} ₺</span></span>
                </button>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeTableModal">Vazgeç</BaseButton>
                <BaseButton v-if="canCreateOrders" :loading="openBusy" @click="openTable && createOrder(openTable)">
                    <AppIcon name="plus" :size="14" />
                    Yeni adisyon aç
                </BaseButton>
            </template>
        </BaseModal>

        <!-- Rezervasyon ↔ walk-in çakışma onayı (§8): masanın yaklaşan/aktif
             rezervasyonu varsa personel açılışı açıkça onaylar. -->
        <BaseModal
            :open="reservationConflict !== null"
            title="Masa rezerve"
            size="sm"
            @close="cancelReservationConflict"
        >
            <div class="flex flex-col gap-3">
                <div class="flex items-start gap-2 text-sm">
                    <AppIcon name="alert-triangle" :size="18" class="mt-0.5 shrink-0 text-warning" />
                    <p>{{ reservationConflict?.message }}</p>
                </div>
                <div
                    v-if="reservationConflict?.reservation"
                    class="rounded-lg border border-default p-3 text-sm"
                >
                    <p class="font-medium">{{ reservationConflict.reservation.customer_name }}</p>
                    <p class="text-muted">
                        {{ reservationConflict.reservation.reserved_time }}
                        · {{ reservationConflict.reservation.party_size }} kişi
                        <template v-if="reservationConflict.reservation.status_label">
                            · {{ reservationConflict.reservation.status_label }}
                        </template>
                    </p>
                </div>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="cancelReservationConflict">Vazgeç</BaseButton>
                <BaseButton variant="danger" :loading="openBusy" @click="confirmReservationConflict">
                    Yine de aç
                </BaseButton>
            </template>
        </BaseModal>

        <!-- Masasız kanal siparişi -->
        <BaseModal :open="channelModal" title="Paket / Gel-Al / Kiosk siparişi" size="sm" @close="closeChannelModal">
            <div class="flex flex-col gap-3">
                <FormField label="Kanal" required>
                    <BaseSelect v-model="channelForm.channel" :options="channelOptions" />
                </FormField>
                <FormField label="Müşteri adı">
                    <BaseInput v-model="channelForm.customer_name" placeholder="ör. Ayşe Yılmaz" />
                </FormField>
                <FormField label="Telefon">
                    <BaseInput v-model="channelForm.customer_phone" inputmode="tel" placeholder="05xx…" />
                </FormField>
                <FormField label="Not">
                    <BaseInput v-model="channelForm.note" placeholder="ör. Zili çalma" />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeChannelModal">Vazgeç</BaseButton>
                <BaseButton :loading="channelBusy" @click="createChannelOrder">Siparişi aç</BaseButton>
            </template>
        </BaseModal>

        <!-- Mobil filtre çekmecesi: masalar listenin üstünde kalsın diye filtreler
             alttan açılan sayfaya taşınır (yalnız <md). -->
        <BottomSheet v-model="filterOpen" title="Filtrele">
            <div class="flex flex-col gap-4">
                <FormField label="Şube">
                    <BaseSelect v-model="branchId" :options="branchOptions" placeholder="Tümü" @update:model-value="() => load()" />
                </FormField>
                <FormField label="Ara">
                    <SearchInput v-model="q" placeholder="Masa adı veya no…" />
                </FormField>
                <!-- Alan/durum/sıralama: masaüstüyle EŞİT (mobilde eksikti). -->
                <FormField v-if="areaOptions.length > 1" label="Alan">
                    <BaseSelect v-model="areaFilter" :options="areaOptions" placeholder="Tümü" />
                </FormField>
                <FormField label="Masa durumu">
                    <BaseSelect v-model="statusFilter" :options="statusOptions" placeholder="Tümü" />
                </FormField>
                <FormField label="Sıralama">
                    <BaseSelect
                        :model-value="sortKey"
                        :options="sortOptions"
                        @update:model-value="(v: string) => (sortKey = v as SortKey)"
                    />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="ghost" @click="clearFilters">Temizle</BaseButton>
                <BaseButton @click="filterOpen = false">Uygula · {{ filteredTables.length }} masa</BaseButton>
            </template>
        </BottomSheet>

    <!-- §13 Faz B/C: sipariş-giriş terminali PIN modalı (BUG #1 fix) -->
    <StaffPinDialog />

    <!-- ================= Nav çekmecesi (soldan overlay) ================= -->
    <KdsNavDrawer v-if="!isTerminal" :open="showNav" @close="showNav = false" />

    <!-- Terminalde: zorunlu personel giriş gate'i + personel barı (PanelLayout/Kitchen/Runner/Cashier ile aynı) -->
    <TerminalOperatorGate />

    <!-- §13 Faz D: boşta-kalma sonrası ekran kilidi (yalnız aktif operatör varken) -->
    <LockOverlay v-if="idleLocked" @unlocked="unlockIdle" />

    <ToastHost />
</template>

<style scoped>
/*
 * Zemin: Kitchen.vue/Runner.vue/Cashier.vue ile birebir aynı katmanlı yüzey —
 * --ui-surface üstünde çok hafif üstten ışık düşümü (düz/tek tondan
 * "katmanlı yüzey" hissi).
 */
.kds-canvas {
    background-color: var(--ui-surface);
    background-image: radial-gradient(1200px 640px at 50% -12%, rgb(255 255 255 / 0.035), transparent 60%);
}
</style>
