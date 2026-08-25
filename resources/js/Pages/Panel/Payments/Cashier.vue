<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import { useVersionWatch } from '@/composables/useVersionWatch';
import StaffPinDialog from '@/Components/panel/StaffPinDialog.vue';
import { useTerminalPin } from '@/composables/useTerminalPin';
import { useTerminalHeartbeat } from '@/composables/useTerminalHeartbeat';
import { useTerminalIdleLock } from '@/composables/useTerminalIdleLock';
import { useTerminalOperator } from '@/composables/useTerminalOperator';
import TerminalOperatorGate from '@/Components/panel/TerminalOperatorGate.vue';
import LockOverlay from '@/Components/panel/LockOverlay.vue';
import TerminalTopBar from '@/Components/panel/TerminalTopBar.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import OrderAddItemDialog from '@/Components/panel/OrderAddItemDialog.vue';
import OrderDiscountDialog from '@/Components/panel/OrderDiscountDialog.vue';
import { fetchActiveReceivables, type ReceivableRow } from '@/Pages/Panel/Receivables/receivables';
import OrderEditItemDialog from '@/Components/panel/OrderEditItemDialog.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import ToastHost from '@/Components/ui/ToastHost.vue';
import KdsIcon from '@/Pages/Panel/Kds/KdsIcon.vue';
import KdsNavDrawer from '@/Pages/Panel/Kds/KdsNavDrawer.vue';
import { useKdsTheme } from '@/Pages/Panel/Kds/kds';
import PaymentReceipt from './PaymentReceipt.vue';
import {
    usePaymentReceiptPrint,
    formatReceiptTime,
    type PaymentReceiptData,
    type PaymentReceiptLine,
} from './usePaymentReceiptPrint';
import {
    apiIdempotent,
    fetchOrderDetail,
    fetchOrderPayments,
    fetchPendingOrders,
    fetchRegisters,
    fetchTerminalStatus,
    metaFromProps,
    money,
    newIdempotencyKey,
    parseMoney,
    type OrderDetail,
    type OrderItemRow,
    type PayableOrder,
    type PaymentRow,
    type RegisterRow,
    type TerminalStatusRow,
} from './payments';

/**
 * KASİYER EKRANI (prompt §15) — ödeme alan kişi için kapsamlı & ferah:
 * solda ödeme bekleyen adisyonlar, sağda seçili adisyonun KALEM DÖKÜMÜ
 * (ödeme öncesi gözden geçir + düzelt: adet/çıkar/ikram) + tek dokunuşlu
 * tahsilat (hızlı tutar + yöntem + bahşiş + para üstü + kısmi/split).
 * Kalemlerin HAZIRLIK durumu GÖSTERİLMEZ — tutar odaklıdır.
 *
 * GÖRSEL DİL (FAZ 3): bu ekran, kasaya atanmış bir terminal cihazının
 * ekranıdır (§13 TerminalStation `kasa`) — Mutfak/Barista/Komi ekranlarıyla
 * (Kitchen.vue/Runner.vue) AYNI premium, bağımsız tam ekran kabuğu kullanır
 * (PanelShell YOK): --ui-* token'ları, aynı üst çubuk deseni (marka + geri +
 * menü + terminal rozeti/çıkış + tema/tam-ekran), aynı `kds-canvas` zemin.
 * Yalnız SUNUM/yerleşim değişti — ödeme akışı, PIN kapısı (useTerminalPin),
 * POS durum rozeti mantığı BİREBİR KORUNDU.
 */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const perms = ((page.props.auth as { permissions?: string[] } | undefined)?.permissions) ?? [];
const canEditItems = perms.includes('orders.update');
const canCompItems = perms.includes('orders.comp');
const canReviewItems = canEditItems || canCompItems || perms.includes('orders.view');
// Sayfa erişimi (viewAny: payments.take VEYA cash.view) tahsilat butonlarından
// DAHA GENİŞ — para alma/sorgulama/geri-gönderme backend'de özel olarak
// payments.take ister (bkz. PaymentPolicy::take/query + OrderController::
// sendBackToService). Sabit rollerde cash.view hep payments.take ile geldiği
// için bugün tetiklenmez, ama özel rol tanımlanabilen bir sistemde
// yalnız cash.view alan bir rol bu butonlarda 403 alabilir.
const canTakePayments = perms.includes('payments.take');
const { success, danger } = useToast();
useVersionWatch();

// §13 Faz B: terminal (kasa) oturumda hassas para eylemleri PIN ister.
// `isTerminal` AYNI kapıdan (useTerminalPin) okunur — Kitchen/Runner/Board ile
// tek kaynaktan tutarlı kalır (terminal rozeti/hesap menüsü artık TerminalTopBar'da).
const { collectPin, isTerminal } = useTerminalPin();

/* ===== FAZ3 entegrasyon (terminal kilit/gate/heartbeat tutarlılığı) =====
 * Kasa, PanelShell'den bağımsız tam-ekran (kds-canvas) olduğu için PanelLayout'un
 * sağladığı terminal altyapısını KENDİSİ kurmalı — aksi halde uzaktan kilit
 * (heartbeat) + operatör-kapısı (TerminalOperatorGate) + boşta-kalma kilidi
 * (idle-lock) bu ekranda çalışmaz (güvenlik regresyonu). PanelLayout/Kitchen.vue/
 * Runner.vue ile BİREBİR AYNI desen; `activeOperator` AYNI kaynaktan
 * (useTerminalOperator) — kopya mantık üretilmedi. */
useTerminalHeartbeat();
const { current: activeOperator } = useTerminalOperator();
const idleLockEnabled = computed(() => isTerminal.value && Boolean(activeOperator.value));
const { locked: idleLocked, unlock: unlockIdle } = useTerminalIdleLock({ enabled: idleLockEnabled });

/* ---- Görsel kabuk: Kitchen.vue/Runner.vue/Board.vue ile birebir aynı desen
 * (ortak <TerminalTopBar> — tam ekran + hesap/operatör menüsü artık orada). ---- */
const showNav = ref(false);
const kdsTheme = useKdsTheme();

/* ================= Sol: bekleyen adisyonlar (5 sn polling) ================= */
const loading = ref(true);
const orders = ref<PayableOrder[]>([]);
const q = ref('');
let timer: ReturnType<typeof setInterval> | null = null;
let modalOpen = false;

async function load(silent = false): Promise<void> {
    if (!silent) loading.value = true;
    try {
        orders.value = await fetchPendingOrders(null, q.value);
    } catch (e) {
        if (!silent) danger('Liste yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

/* ---- Kasa kararları: ödeme bekleyen adisyon için (rol ayrımı) ---- */
const flowBusy = ref(false);

/** Yanlışlıkla ya da ek sipariş için adisyonu tekrar servise/siparişe döndür. */
async function sendBackToService(): Promise<void> {
    if (!selected.value || flowBusy.value) return;
    flowBusy.value = true;
    try {
        await api(`/api/v1/orders/${selected.value.id}/send-to-service`, {
            method: 'POST',
            body: { expected_version: selected.value.version },
        });
        success('Siparişe geri gönderildi', 'Adisyon yeniden serviste; garson devam edebilir.');
        selected.value = null;
        await load(true);
    } catch (e) {
        danger('Gönderilemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        flowBusy.value = false;
    }
}

/** Borca yaz: cari (müşteri) seçimi gerektiğinden adisyon detayındaki tam
 *  "Borca taşı" akışına götürür (kasiyerin artık receivables.transfer izni var). */
function goToDebtTransfer(): void {
    if (!selected.value) return;
    router.visit(`/panel/siparisler/${selected.value.id}`);
}

watch(q, () => void load(true));

const totalPending = computed(() => orders.value.reduce((s, o) => s + o.remaining_minor, 0));

/* ================= Kasa oturumu göstergesi ================= */
const registers = ref<RegisterRow[]>([]);
const activeRegisterId = ref<number | null>(
    Number(localStorage.getItem('bhx-cash-register') || '') || null,
);

const activeRegister = computed(
    () => registers.value.find((r) => r.id === activeRegisterId.value) ?? registers.value.find((r) => r.open_session) ?? null,
);

watch(activeRegisterId, (v) => {
    if (v) localStorage.setItem('bhx-cash-register', String(v));
});

/**
 * FAZ2 — kasiyer ekranı POS/banka durumu (audit #4): SandboxPosProvider gerçek
 * bir ECR/bankaya bağlı DEĞİL; kart yöntemi seçilince personel "gerçek kart
 * okutma" bekleyebilir. Aktif sağlayıcının GERÇEK durumunu sunucudan okuyup
 * (uydurma yok) rozetle gösteriyoruz — para akışına/ödeme mantığına dokunulmaz.
 */
const terminalStatus = ref<TerminalStatusRow | null>(null);
/** Yüklenene kadar VE hata durumunda güvenli taraf: "simüle/bağlı değil" varsay. */
const posSimulated = computed(() => terminalStatus.value?.simulated ?? true);
const posOnline = computed(() => terminalStatus.value?.online ?? false);
/** Kart ödemesi şu an gerçek/doğrulanmış bir terminale ULAŞMIYOR — manuel onay gerekir. */
const posNeedsManual = computed(() => posSimulated.value || !posOnline.value);

async function refreshTerminalStatus(silent = false): Promise<void> {
    try {
        terminalStatus.value = await fetchTerminalStatus();
    } catch {
        // Yetkisiz/başarısız → rozet "bağlı değil" varsayımında kalır (fail-safe);
        // ödeme akışını bloklamaz, yalnız iyimser bir mesaj GÖSTERMEZ.
        if (!silent) terminalStatus.value = null;
    }
}

onMounted(async () => {
    await load();
    void refreshTerminalStatus();
    try {
        registers.value = await fetchRegisters();
    } catch {
        /* cash.view yoksa gösterge gizli kalır */
    }
    timer = setInterval(() => {
        if (!modalOpen && !editMode.value) {
            void load(true);
            void refreshTerminalStatus(true);
            if (selected.value) {
                void refreshSelected(true);
                void refreshDetail(true);
            }
        }
    }, 5000);
    window.addEventListener('keydown', onKeydown);
    if (leftTab.value === 'debts') void loadDebtors();
});

onBeforeUnmount(() => {
    if (timer) clearInterval(timer);
    window.removeEventListener('keydown', onKeydown);
    kdsTheme.release();
});

/* ================= Sağ: seçili adisyon + tahsilat ================= */
const selected = ref<PayableOrder | null>(null);
const payments = ref<PaymentRow[]>([]);
const detail = ref<OrderDetail | null>(null);
const detailDenied = ref(false);

/** Sağ panel sekmesi: adisyon kalemleri (sepet) ↔ alınan ödemeler (geçmiş). */
const rightTab = ref<'items' | 'payments'>('items');

/** Ödeme durumu (kısmi/ödendi) — liste ve başlık rozetleri için. */
function payState(o: { paid_minor: number; remaining_minor: number }): 'unpaid' | 'partial' | 'paid' {
    if (o.remaining_minor <= 0) return 'paid';
    if (o.paid_minor > 0) return 'partial';
    return 'unpaid';
}

async function select(order: PayableOrder): Promise<void> {
    selected.value = order;
    detail.value = null;
    editMode.value = false;
    rightTab.value = 'items';
    clearItemSelection();
    await Promise.all([refreshSelected(), refreshDetail()]);
    if (selected.value) resetForm(selected.value);
}

async function refreshSelected(silent = false): Promise<void> {
    if (!selected.value) return;
    try {
        const res = await fetchOrderPayments(selected.value.id);
        selected.value = res.order;
        payments.value = res.payments;
    } catch (e) {
        if (!silent) danger('Adisyon yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    }
}

/** Kalem dökümünü çeker; orders.view yoksa sessizce gizlenir. */
async function refreshDetail(silent = false): Promise<void> {
    if (!selected.value || !canReviewItems) return;
    try {
        detail.value = await fetchOrderDetail(selected.value.id);
        detailDenied.value = false;
    } catch (e) {
        detail.value = null;
        if (e instanceof ApiError && (e.status === 403 || e.status === 401)) detailDenied.value = true;
        else if (!silent) detailDenied.value = false;
    }
}

/** Görünen (iptal edilmemiş) kalemler. Hazırlık durumu gösterilmez. */
const visibleItems = computed<OrderItemRow[]>(() => (detail.value?.items ?? []).filter((i) => i.is_active));
const compTotalMinor = computed(() => detail.value?.comp_total_minor ?? 0);

/**
 * Toplam KDV (kuruş). KDV Türkiye'de fiyata DAHİLDİR (OrderService.computeLine
 * → Money::vatPortionOfGross); yani `total_minor` içinde zaten yer alır. Bu
 * yüzden ayrı EKLENMEZ — yalnız bilgi olarak "KDV (dahil)" gösterilir.
 */
const vatTotalMinor = computed(() => selected.value?.vat_total_minor ?? 0);

/**
 * Kalem-bazlı KDV oranı kırılımı (matrah + KDV). Backend ile birebir tutarlı:
 * KDV DAHİL satır toplamından net = round(gross/(1+oran)), KDV = gross − net
 * (aktif, ikramsız kalemler; oran 0 = KDV'siz hariç). Oranlar azalan sıralı.
 */
const vatByRate = computed<Array<{ rate: number; base_minor: number; vat_minor: number }>>(() => {
    const groups = new Map<number, { base_minor: number; vat_minor: number }>();
    for (const it of visibleItems.value) {
        if (it.is_comp || !it.tax_rate || it.tax_rate <= 0) continue;
        const gross = it.line_total_minor;
        const net = Math.round(gross / (1 + it.tax_rate / 100));
        const vat = gross - net;
        const g = groups.get(it.tax_rate) ?? { base_minor: 0, vat_minor: 0 };
        g.base_minor += net;
        g.vat_minor += vat;
        groups.set(it.tax_rate, g);
    }
    return [...groups.entries()]
        .map(([rate, v]) => ({ rate, ...v }))
        .sort((a, b) => b.rate - a.rate);
});
/** Kırılım güvenilir mi (döküm görülebiliyorsa ve toplamı KDV toplamına eşitse). */
const vatBreakdownReliable = computed(
    () => vatByRate.value.length > 0
        && vatByRate.value.reduce((s, r) => s + r.vat_minor, 0) === vatTotalMinor.value,
);
/** Oran-tabanlı KDV formatı (ör. "%10"). */
function ratePct(rate: number): string {
    return `%${Number.isInteger(rate) ? rate : rate.toFixed(1)}`;
}

/* ================= §13 Faz C-2: Kasa/müşteri fişi ================= */
/**
 * Hesap Fişi (ön-hesap, ödeme öncesi) + Ödeme/Adisyon Fişi (kapanış). Faz C-1
 * KDS fişiyle AYNI yazdırma deseni (yalıtılmış iframe + window.print, tüm
 * cihaz uyumu) ama PARALI — kasa PARA görür. Fiş kaynağı adisyon detay
 * payload'ı (detail/selected/payments); backend'e dokunulmaz.
 */
const receiptPrint = usePaymentReceiptPrint();
const previewReceipt = ref<PaymentReceiptData | null>(null);

/** İşletme/şube adı — paylaşılan auth prop'undan (KDS ile aynı kaynak). */
const receiptAuth = page.props.auth as {
    branches?: { id: number; name: string }[];
    activeBranchId?: number | null;
    tenant?: { name?: string } | null;
} | null;
const businessName = receiptAuth?.tenant?.name ?? '';
const branchName = computed(() => {
    const list = receiptAuth?.branches ?? [];
    const active = receiptAuth?.activeBranchId ?? null;
    return (list.find((b) => b.id === active) ?? list[0])?.name ?? '';
});

/** Başarılı ödemelerin fişe uygun özeti (yöntem + tutar + para üstü). */
const succeededPayments = computed(() =>
    payments.value.filter((p) => p.kind === 'payment' && p.status === 'succeeded'),
);
const changeTotalMinor = computed(() => succeededPayments.value.reduce((s, p) => s + (p.change_minor ?? 0), 0));

/** Adisyon detay/özet payload'ından fiş verisi kurar (fiyatlı). */
function buildReceipt(kind: 'bill' | 'payment'): PaymentReceiptData | null {
    if (!selected.value) return null;
    const o = selected.value;

    const lines: PaymentReceiptLine[] = visibleItems.value.map((it) => {
        const opts = it.options.map((op) => op.option_name);
        return {
            qty: it.qty,
            name: it.name,
            variant: it.variant_name,
            options: opts,
            note: it.note,
            isComp: it.is_comp,
            lineTotalMinor: it.is_comp ? 0 : it.line_total_minor,
            unitPriceMinor: it.unit_price_minor + it.options_price_minor,
        };
    });

    return {
        business: businessName,
        branch: branchName.value,
        kind,
        orderNo: o.id,
        destination: orderTitle(o),
        serviceType: o.channel_label,
        guestCount: guestCount.value,
        time: formatReceiptTime(o.created_at),
        lines,
        itemsTotalMinor: o.items_total_minor,
        compTotalMinor: compTotalMinor.value,
        discountMinor: o.discount_minor,
        serviceChargeMinor: o.service_charge_minor,
        roundingMinor: o.rounding_minor,
        totalMinor: o.total_minor,
        vatTotalMinor: vatTotalMinor.value,
        vatByRate: vatBreakdownReliable.value ? vatByRate.value : undefined,
        paidMinor: o.paid_minor,
        remainingMinor: o.remaining_minor,
        changeTotalMinor: changeTotalMinor.value,
        payments: succeededPayments.value.map((p) => ({
            methodLabel: p.method_label,
            amountMinor: p.amount_minor,
            changeMinor: p.change_minor ?? 0,
        })),
    };
}

/** Önizleme modalını aç (hesap veya ödeme fişi). */
function openReceiptPreview(kind: 'bill' | 'payment'): void {
    const data = buildReceipt(kind);
    if (!data) return;
    previewReceipt.value = data;
    modalOpen = true;
}
function closeReceiptPreview(): void {
    previewReceipt.value = null;
    modalOpen = false;
}
/** Doğrudan yazdır (önizlemesiz kısa yol). */
function printReceipt(kind: 'bill' | 'payment'): void {
    const data = buildReceipt(kind);
    if (data) receiptPrint.print(data);
}
/** Önizlemedeki fişi yazdır. */
function printPreview(): void {
    if (previewReceipt.value) receiptPrint.print(previewReceipt.value);
}

/* ---- Kalem düzenleme (ödeme öncesi hata düzeltme) ---- */
const editMode = ref(false);
const itemBusy = ref<number | null>(null);
const canEditNow = computed(() => !!detail.value?.is_open && (selected.value?.remaining_minor ?? 0) > 0);

function toggleEdit(): void {
    editMode.value = !editMode.value;
}

/** Kalem işlemi sonrası hem döküm hem tahsilat verisini tazele. */
async function afterItemChange(): Promise<void> {
    await Promise.all([refreshDetail(true), refreshSelected(true)]);
    await load(true);
    if (selected.value) amountText.value = money(selected.value.remaining_minor);
}

async function adjustQty(item: OrderItemRow, delta: number): Promise<void> {
    if (itemBusy.value !== null || !detail.value) return;
    const next = item.qty + delta;
    if (next < 1 || next > 100) return;
    itemBusy.value = item.id;
    try {
        await api(`/api/v1/orders/${detail.value.id}/items/${item.id}`, {
            method: 'PUT',
            body: { qty: next, expected_version: detail.value.version },
        });
        success('Adet güncellendi', `${item.name} — ${next} adet`);
        await afterItemChange();
    } catch (e) {
        danger('Güncellenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
        await refreshDetail(true);
    } finally {
        itemBusy.value = null;
    }
}

/* ---- Adisyona ürün ekle (eksik/unutulmuş kalem → doğru tutar) ----
 * Sipariş detayındaki ekleme akışının AYNISI, ortak bileşenden
 * (OrderAddItemDialog). Kasiyer düzenleme yetkisi varken ve adisyon
 * açıkken görünür. */
const addItemOpen = ref(false);
function openAddItem(): void {
    if (!canEditNow.value) return;
    addItemOpen.value = true;
    modalOpen = true;
}
function closeAddItem(): void {
    addItemOpen.value = false;
    modalOpen = false;
}
async function onItemAdded(): Promise<void> {
    closeAddItem();
    await afterItemChange();
}

/* ---- Kalemi değiştir (adet + seçenek + not, yerinde) ----
 * Önceden kasada kalem üzerinde yalnız "çıkar" ve "ikram" vardı; müşteri
 * "şekersiz olacaktı" dediğinde kalem silinip yeniden ekleniyordu. */
const editItemTarget = ref<OrderItemRow | null>(null);
function openEditItem(item: OrderItemRow): void {
    if (!canEditNow.value) return;
    editItemTarget.value = item;
    modalOpen = true;
}
function closeEditItem(): void {
    editItemTarget.value = null;
    modalOpen = false;
}
async function onItemSaved(): Promise<void> {
    closeEditItem();
    await afterItemChange();
}
/** Varyant değişimi sunucuda desteklenmiyor → çıkar + yeniden ekle akışına geç. */
function replaceItemFlow(item: { id: number }): void {
    const row = visibleItems.value.find((i) => i.id === item.id);
    closeEditItem();
    if (row) askRemoveItem(row);
}

/* ================= MASASIZ TAHSİLAT: cari borçlar =================
 * Borç tahsilatı yalnız Borçlar sayfasındaki küçük modaldan alınabiliyordu:
 * kasiyer para alırken kasadan çıkıp başka ekrana gidiyor, nakit çekmecesi
 * ve Z raporu bağlamından kopuyordu. Artık kasa ekranında ADİSYONSUZ tahsilat
 * yapılabilir — aynı numpad, aynı yöntem kutuları, aynı kasa oturumu.
 * Sunucu ucu (POST /receivables/{id}/collect) DEĞİŞMEDİ; nakit tahsilat
 * zaten kasa defterine düşüyordu. */
type LeftTab = 'orders' | 'debts';
const leftTab = ref<LeftTab>(
    // Borçlar sayfasından "Kasada tahsil et" ile gelindiğinde doğrudan borç
    // sekmesi açılsın (?sekme=borclar).
    typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('sekme') === 'borclar'
        ? 'debts'
        : 'orders',
);

const debtors = ref<ReceivableRow[]>([]);
const debtorsLoading = ref(false);
const selectedDebtor = ref<ReceivableRow | null>(null);
const debtAmountText = ref('');
const debtMethod = ref('cash');
const debtNote = ref('');
const debtBusy = ref(false);

const debtorQuery = ref('');
const visibleDebtors = computed(() => {
    const needle = debtorQuery.value.trim().toLocaleLowerCase('tr-TR');
    return debtors.value
        .filter((d) => d.balance_minor > 0)
        .filter((d) => needle === '' || `${d.name} ${d.phone ?? ''}`.toLocaleLowerCase('tr-TR').includes(needle));
});
const debtTotal = computed(() => visibleDebtors.value.reduce((n, d) => n + d.balance_minor, 0));
const debtAmountMinor = computed(() => parseMoney(debtAmountText.value) ?? 0);

async function loadDebtors(silent = false): Promise<void> {
    if (debtorsLoading.value) return;
    debtorsLoading.value = true;
    try {
        debtors.value = await fetchActiveReceivables();
    } catch (e) {
        if (!silent) danger('Cariler yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        debtorsLoading.value = false;
    }
}

function selectDebtor(d: ReceivableRow): void {
    selectedDebtor.value = d;
    // Varsayılan: borcun TAMAMI (kasiyer çoğunlukla tamamını tahsil eder).
    debtAmountText.value = money(d.balance_minor);
    debtMethod.value = 'cash';
    debtNote.value = '';
}

async function collectDebt(): Promise<void> {
    const d = selectedDebtor.value;
    if (!d || debtBusy.value) return;
    if (debtAmountMinor.value <= 0) {
        danger('Tutar geçersiz', 'Pozitif bir tutar girin.');
        return;
    }
    if (debtAmountMinor.value > d.balance_minor) {
        danger('Tutar borcu aşıyor', `Güncel borç ${money(d.balance_minor)} ₺.`);
        return;
    }
    debtBusy.value = true;
    try {
        const res = await api<{ receivable: ReceivableRow }>(`/api/v1/receivables/${d.id}/collect`, {
            method: 'POST',
            body: { amount_minor: debtAmountMinor.value, method: debtMethod.value, note: debtNote.value || null },
        });
        success('Borç tahsil edildi', `${d.name} — ${money(debtAmountMinor.value)} ₺`);
        selectedDebtor.value = res.receivable.balance_minor > 0 ? res.receivable : null;
        if (selectedDebtor.value) debtAmountText.value = money(selectedDebtor.value.balance_minor);
        await loadDebtors(true);
    } catch (e) {
        danger('Tahsil edilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        debtBusy.value = false;
    }
}

watch(leftTab, (t) => {
    if (t === 'debts') void loadDebtors();
});

/* ---- İndirim (hazır tanımlar + serbest) ----
 * Kasada indirim uygulanacak yer yoktu; kasiyer indirim için adisyon
 * ekranına gitmek zorundaydı. Tek indirim kuralı sunucuda. */
const discountOpen = ref(false);
function openDiscount(): void {
    discountOpen.value = true;
    modalOpen = true;
}
function closeDiscount(): void {
    discountOpen.value = false;
    modalOpen = false;
}
async function onDiscountChanged(): Promise<void> {
    closeDiscount();
    await Promise.all([refreshSelected(true), refreshDetail(true)]);
    await load(true);
    if (selected.value) amountText.value = money(selected.value.remaining_minor);
}

/* Kalem çıkarma (onaylı) */
const removeItemTarget = ref<OrderItemRow | null>(null);
function askRemoveItem(item: OrderItemRow): void {
    removeItemTarget.value = item;
    modalOpen = true;
}
async function doRemoveItem(): Promise<void> {
    if (!removeItemTarget.value || !detail.value || itemBusy.value !== null) return;
    const item = removeItemTarget.value;
    itemBusy.value = item.id;
    try {
        await api(`/api/v1/orders/${detail.value.id}/items/${item.id}`, {
            method: 'DELETE',
            body: { expected_version: detail.value.version },
        });
        success('Kalem çıkarıldı', item.name);
        removeItemTarget.value = null;
        modalOpen = false;
        await afterItemChange();
    } catch (e) {
        danger('Çıkarılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
        await refreshDetail(true);
    } finally {
        itemBusy.value = null;
    }
}

/* İkram / comp (ücretsiz) */
const compTarget = ref<OrderItemRow | null>(null);
const compReason = ref('');
function askComp(item: OrderItemRow): void {
    compTarget.value = item;
    compReason.value = '';
    modalOpen = true;
}
async function doComp(): Promise<void> {
    if (!compTarget.value || !detail.value || itemBusy.value !== null) return;
    const item = compTarget.value;
    const reason = compReason.value;
    const orderId = detail.value.id;
    const version = detail.value.version;

    // İkram modalını kapat → terminal PIN modalı üst üste binmesin.
    compTarget.value = null;
    modalOpen = false;

    // Terminal (kasa) oturumda PIN gerekir; iptal edilirse eylem yapılmaz.
    const pinFields = await collectPin();
    if (pinFields === null) return;

    itemBusy.value = item.id;
    try {
        await api(`/api/v1/orders/${orderId}/items/${item.id}/comp`, {
            method: 'POST',
            body: { reason, expected_version: version, ...pinFields },
        });
        success('İkram işlendi', `${item.name} ücretsiz`);
        await afterItemChange();
    } catch (e) {
        danger('İşlenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
        await refreshDetail(true);
    } finally {
        itemBusy.value = null;
    }
}

/** Kalemin opsiyon/not özeti (tek satır). */
function itemMeta(item: OrderItemRow): string {
    const parts: string[] = [];
    if (item.variant_name) parts.push(item.variant_name);
    for (const o of item.options) parts.push(o.option_name);
    if (item.note) parts.push(`“${item.note}”`);
    return parts.join(' · ');
}

/* ---- Ödeme formu ---- */
const amountText = ref('');
const method = ref('cash');
const tipText = ref('');
const tenderedText = ref('');
const noteText = ref('');
const roundCash = ref(false);
const paying = ref(false);

const methodMeta = computed(() => meta.paymentMethods.find((m) => m.value === method.value));
/* Ödeme yöntemleri: "Açık hesap" (on_account) GERÇEK tahsilat DEĞİL — nakit
   almadan kapatıp kafa karıştırıyordu. Cari'ye yazma artık NET yol: "Borca yaz"
   (cari seçimi + bakiye takibi). Bu yüzden pay seçeneklerinden çıkarıldı. */
const payMethods = computed(() => meta.paymentMethods.filter((m) => m.value !== 'on_account'));
/**
 * Ödeme yöntemi renk tonu — kasiyer yöntemi OKUMADAN, renkten tanısın
 * (nakit yeşil, kart mor/marka, yemek kartı turuncu, dijital mavi). Sınıf
 * dizeleri TAM yazılır; Tailwind kaynak taraması parçalı dizeyi göremez.
 * Renkler yalnız --ui-* token'larından türer → koyu tema otomatik uyar.
 */
const METHOD_TONES: Record<string, { idle: string; on: string }> = {
    cash: { idle: 'text-success', on: 'border-success-border bg-success-soft text-success' },
    credit_card: { idle: 'text-primary', on: 'border-primary bg-primary-soft text-primary' },
    debit_card: { idle: 'text-primary', on: 'border-primary bg-primary-soft text-primary' },
    meal_card: { idle: 'text-warning', on: 'border-warning-border bg-warning-soft text-warning' },
    gift_card: { idle: 'text-warning', on: 'border-warning-border bg-warning-soft text-warning' },
    transfer: { idle: 'text-info', on: 'border-info-border bg-info-soft text-info' },
    qr: { idle: 'text-info', on: 'border-info-border bg-info-soft text-info' },
    online: { idle: 'text-info', on: 'border-info-border bg-info-soft text-info' },
};
const FALLBACK_TONE = { idle: 'text-muted', on: 'border-primary bg-primary-soft text-primary' };

function methodTone(value: string, active: boolean): string {
    const t = METHOD_TONES[value] ?? FALLBACK_TONE;
    return active ? t.on : 'border-default text-body';
}
function methodIconTone(value: string, active: boolean): string {
    if (active) return '';
    return (METHOD_TONES[value] ?? FALLBACK_TONE).idle;
}

/**
 * Adisyon satırının sol renk şeridi: hesap istenen (kasada bekleyen) yeşil,
 * kısmi ödenmiş turuncu, yeni gelen nötr. Listeyi okumadan önceliklendirir.
 */
function orderStripe(o: PayableOrder): string {
    if (payState(o) === 'partial') return 'bg-warning';
    if (o.status === 'bill_requested') return 'bg-success';
    return 'bg-strong';
}

const amountMinor = computed(() => parseMoney(amountText.value) ?? 0);
const tipMinor = computed(() => parseMoney(tipText.value) ?? 0);
const tenderedMinor = computed(() => parseMoney(tenderedText.value));
const changeMinor = computed(() => {
    if (method.value !== 'cash' || tenderedMinor.value === null) return null;
    return Math.max(0, tenderedMinor.value - amountMinor.value - tipMinor.value);
});
const isPartial = computed(() => !!selected.value && amountMinor.value > 0 && amountMinor.value < selected.value.remaining_minor);
const afterPaymentRemaining = computed(() =>
    selected.value ? Math.max(0, selected.value.remaining_minor - amountMinor.value) : 0,
);
const guestCount = computed(() => detail.value?.guest_count ?? null);

function resetForm(order: PayableOrder): void {
    amountText.value = money(order.remaining_minor);
    method.value = 'cash';
    tipText.value = '';
    tenderedText.value = '';
    noteText.value = '';
    roundCash.value = false;
    padTarget.value = 'amount';
    padFresh.value = true;
}

function setAmountMinor(v: number): void {
    amountText.value = money(Math.max(0, v));
    // Hazır tutar (Tamamı/½/⅓/kişi başı) sonrası ilk rakam basışı sıfırdan yazar.
    padFresh.value = true;
}
function setQuickAmount(fraction: number): void {
    if (!selected.value) return;
    const v = fraction === 1
        ? selected.value.remaining_minor
        : Math.ceil(selected.value.remaining_minor * fraction);
    setAmountMinor(v);
}
/** Kişi başı eşit bölüm (adisyon misafir sayısına göre). */
function splitByGuests(): void {
    if (!selected.value || !guestCount.value || guestCount.value < 1) return;
    setAmountMinor(Math.ceil(selected.value.remaining_minor / guestCount.value));
}

/* ---- 1/n: serbest bölme (kaç kişiye bölünecek) ----
 * Sabit ½/⅓ yetmiyor; 5 kişilik masa hesabı 5'e bölünebilmeli. Kalanı n'e
 * böler ve yukarı yuvarlar (eksik tahsilat olmasın; son ödeyene kuruş farkı
 * kalır — kalan tutar zaten her tahsilatta yeniden hesaplanır). */
const splitOpen = ref(false);
const splitCount = ref('');
const splitPreviewMinor = computed(() => {
    const n = Number(splitCount.value);
    if (!selected.value || !Number.isFinite(n) || n < 2) return 0;
    return Math.ceil(selected.value.remaining_minor / n);
});
function openSplit(): void {
    splitCount.value = guestCount.value && guestCount.value > 1 ? String(guestCount.value) : '';
    splitOpen.value = true;
    modalOpen = true;
}
function applySplit(): void {
    if (splitPreviewMinor.value <= 0) return;
    setAmountMinor(splitPreviewMinor.value);
    splitOpen.value = false;
    modalOpen = false;
}

/* ---- Kalem seçerek tahsilat (Kardo'daki "Seçilen" akışı) ----
 * Masadan biri "ben sadece kendi yediğimi ödeyeyim" dediğinde kasiyerin
 * hesap makinesiyle uğraşmaması için: kalemlere dokunup seçer, seçili
 * kalemlerin toplamı tahsil tutarına yazılır.
 *
 * ÖNEMLİ (dürüstlük): bu seçim tutarı HESAPLAR; sunucuda "şu kalemler
 * ödendi" diye işaretlenmez — ödeme adisyon bazında tutar olarak düşer.
 * Kalan tutar her tahsilattan sonra sunucudan yeniden okunur. */
const selectedItemIds = ref<Set<number>>(new Set());
const selectedItemsMinor = computed(() =>
    visibleItems.value
        .filter((i) => selectedItemIds.value.has(i.id) && !i.is_comp)
        .reduce((s, i) => s + i.line_total_minor, 0),
);
const hasItemSelection = computed(() => selectedItemsMinor.value > 0);

function toggleItemSelect(item: OrderItemRow): void {
    // Düzenleme modunda satırlar adet/çıkar/ikram kontrolü barındırır —
    // dokunuş seçim sanılmasın diye seçim kapalıdır.
    if (editMode.value || item.is_comp) return;
    const next = new Set(selectedItemIds.value);
    if (next.has(item.id)) next.delete(item.id);
    else next.add(item.id);
    selectedItemIds.value = next;
}
function clearItemSelection(): void {
    selectedItemIds.value = new Set();
}
/** Seçili kalemlerin toplamını tahsil tutarına yaz (kalanı aşamaz). */
function applyItemSelection(): void {
    if (!selected.value || !hasItemSelection.value) return;
    setAmountMinor(Math.min(selectedItemsMinor.value, selected.value.remaining_minor));
    padTarget.value = 'amount';
}
/** Nakit için üste yuvarlanmış hazır tutarlar (verilen para hızlı seçimi). */
const cashPresets = computed<number[]>(() => {
    const rem = selected.value?.remaining_minor ?? 0;
    const steps = [5000, 10000, 20000, 50000];
    const out = [rem];
    for (const s of steps) {
        const up = Math.ceil(rem / s) * s;
        if (up > rem && !out.includes(up)) out.push(up);
    }
    return out.slice(0, 4);
});

/* ---- Numpad (büyük ekran dokunmatik giriş; Kardo tarzı) ----
 * Klavye girişini DEĞİŞTİRMEZ — input'lar aynen çalışır; pad yalnız aktif
 * hedefin (tutar/verilen para) metnini düzenler. parseMoney aynı kalır. */
const padTarget = ref<'amount' | 'tendered'>('amount');
/** Tutar otomatik dolduruldu (kalan/hazır seçim): ilk rakam basışı sıfırdan yazar. */
const padFresh = ref(true);

function padPress(k: string): void {
    if (!selected.value) return;
    const model = padTarget.value === 'amount' ? amountText : tenderedText;
    const fresh = padTarget.value === 'amount' && padFresh.value;
    if (k === 'del') {
        model.value = fresh ? '' : model.value.slice(0, -1);
        if (fresh) padFresh.value = false;
        return;
    }
    if (fresh) {
        model.value = '';
        padFresh.value = false;
    }
    if (k === ',') {
        if (!model.value.includes(',')) model.value = (model.value || '0') + ',';
        return;
    }
    // Rakam: virgülden sonra en fazla 2 hane (kuruş).
    const dec = model.value.split(',')[1];
    if (dec !== undefined && dec.length >= 2) return;
    model.value += k;
}

/**
 * Fiziksel klavye: kasada çoğu cihazda numpad'li klavye var. Rakam/virgül/
 * geri-sil aktif hedefe yazar, Enter tahsilatı başlatır. Bir metin alanına ya
 * da modal'a odaklanılmışsa DEVRE DIŞI — arama kutusuna yazarken tutar
 * bozulmasın (ödeme mantığı aynı; yalnız giriş kısayolu).
 */
function onKeydown(e: KeyboardEvent): void {
    if (e.ctrlKey || e.altKey || e.metaKey) return;
    if (!selected.value || selected.value.remaining_minor <= 0) return;
    if (modalOpen || idleLocked.value) return;
    const el = e.target as HTMLElement | null;
    if (el && (el.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName))) return;

    if (e.key >= '0' && e.key <= '9') {
        padPress(e.key);
    } else if (e.key === ',' || e.key === '.') {
        padPress(',');
    } else if (e.key === 'Backspace') {
        padPress('del');
    } else if (e.key === 'Enter') {
        if (canTakePayments && !paying.value) void pay();
    } else {
        return;
    }
    e.preventDefault();
}

async function pay(): Promise<void> {
    if (!selected.value || paying.value) return;
    // Çift-tıklama kilidi: await'lerden (collectPin/PIN modalı) ÖNCE senkron kur →
    // ikinci tıklama PIN resolver'ını ezip ilk ödemeyi askıda bırakamaz.
    paying.value = true;
    try {
        if (amountMinor.value <= 0) {
            danger('Tutar geçersiz', 'Pozitif bir tutar girin.');
            return;
        }

        // §13 Faz B: terminal (kasa) oturumda ödeme alma PIN ister; işlem PIN
        // sahibine atfedilir. İptal edilirse tahsilat yapılmaz.
        const pinFields = await collectPin();
        if (pinFields === null) return;

        const res = await apiIdempotent<{
            payment: PaymentRow;
            provider_result: { status: string; message: string | null } | null;
            order: PayableOrder;
        }>(`/api/v1/orders/${selected.value.id}/payments`, {
            method: method.value,
            amount_minor: amountMinor.value,
            tip_minor: tipMinor.value || 0,
            tendered_minor: method.value === 'cash' ? tenderedMinor.value : null,
            note: noteText.value || null,
            round: roundCash.value,
            cash_register_id: activeRegister.value?.id ?? null,
            expected_version: selected.value.version,
            ...pinFields,
        }, newIdempotencyKey());

        if (res.payment.status === 'succeeded') {
            success('Ödeme alındı', `${res.payment.method_label} — ${money(res.payment.amount_minor)} ₺${res.payment.change_minor > 0 ? ` · Para üstü ${money(res.payment.change_minor)} ₺` : ''}`);
        } else if (res.payment.status === 'pending') {
            success('Terminale gönderildi', 'Terminal onayı bekleniyor — gönderim tahsilat DEĞİLDİR; sonucu sorgulayın.');
        } else {
            danger('Ödeme başarısız', res.provider_result?.message ?? 'Sağlayıcı reddetti.');
        }

        await refreshSelected(true);
        await refreshDetail(true);
        await load(true);
        // Tahsilat bitti → kalem seçimi kalıcı olmasın; tutar kalana göre yeniden dolar.
        clearItemSelection();
        if (selected.value) resetForm(selected.value);
    } catch (e) {
        danger('Ödeme alınamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
        await refreshSelected(true);
    } finally {
        paying.value = false;
    }
}

/* ---- Bekleyen terminal ödemesini sorgula ---- */
const querying = ref<number | null>(null);

async function queryPayment(p: PaymentRow): Promise<void> {
    if (querying.value !== null) return;
    querying.value = p.id;
    try {
        const res = await api<{ payment: PaymentRow; provider_result: { status: string; message: string | null } | null }>(
            `/api/v1/payments/${p.id}/query`,
            { method: 'POST' },
        );
        if (res.payment.status === 'succeeded') success('Ödeme doğrulandı', 'Sağlayıcı işlemi onayladı.');
        else if (res.payment.status === 'failed') danger('Ödeme reddedilmiş', res.provider_result?.message ?? '');
        else success('Hâlâ bekliyor', res.provider_result?.message ?? 'Sağlayıcı işliyor; tekrar deneyin.');
        await refreshSelected(true);
    } catch (e) {
        danger('Sorgulanamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        querying.value = null;
    }
}

/* ---- Void / iade ---- */
const voidTarget = ref<PaymentRow | null>(null);
const voidReason = ref('');
const refundTarget = ref<PaymentRow | null>(null);
const refundAmountText = ref('');
const refundReason = ref('');
const actionBusy = ref(false);

function openVoid(p: PaymentRow): void {
    voidTarget.value = p;
    voidReason.value = '';
    modalOpen = true;
}

function openRefund(p: PaymentRow): void {
    refundTarget.value = p;
    refundAmountText.value = money(p.amount_minor - p.refunded_total_minor);
    refundReason.value = '';
    modalOpen = true;
}

function closeModals(): void {
    discountOpen.value = false;
    editItemTarget.value = null;
    splitOpen.value = false;
    addItemOpen.value = false;
    voidTarget.value = null;
    refundTarget.value = null;
    serviceChargeOpen.value = false;
    compTarget.value = null;
    removeItemTarget.value = null;
    previewReceipt.value = null;
    modalOpen = false;
}

async function doVoid(): Promise<void> {
    if (!voidTarget.value || actionBusy.value) return;
    actionBusy.value = true;
    try {
        await api(`/api/v1/payments/${voidTarget.value.id}/void`, {
            method: 'POST',
            body: { reason: voidReason.value },
        });
        success('Ödeme iptal edildi', 'Tahsilat geri alındı; adisyon yeniden açıldı.');
        closeModals();
        await refreshSelected(true);
        await load(true);
    } catch (e) {
        danger('İptal edilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        actionBusy.value = false;
    }
}

async function doRefund(): Promise<void> {
    if (!refundTarget.value || actionBusy.value) return;
    const amount = parseMoney(refundAmountText.value);
    if (!amount || amount <= 0) {
        danger('Tutar geçersiz', 'Pozitif bir iade tutarı girin.');
        return;
    }
    actionBusy.value = true;
    try {
        await api(`/api/v1/payments/${refundTarget.value.id}/refund`, {
            method: 'POST',
            body: { amount_minor: amount, reason: refundReason.value },
        });
        success('İade yapıldı', `${money(amount)} ₺ iade edildi.`);
        closeModals();
        await refreshSelected(true);
        await load(true);
    } catch (e) {
        danger('İade edilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        actionBusy.value = false;
    }
}

/* ---- Servis bedeli ---- */
const serviceChargeOpen = ref(false);
const scType = ref<'percent' | 'amount'>('percent');
const scValue = ref('');

function openServiceCharge(): void {
    serviceChargeOpen.value = true;
    scType.value = 'percent';
    scValue.value = '';
    modalOpen = true;
}

async function applyServiceCharge(remove = false): Promise<void> {
    if (!selected.value || actionBusy.value) return;
    actionBusy.value = true;
    try {
        if (remove) {
            await api(`/api/v1/orders/${selected.value.id}/service-charge`, { method: 'DELETE' });
            success('Servis bedeli kaldırıldı', '');
        } else {
            const value = scType.value === 'percent' ? Number(scValue.value.replace(',', '.')) : parseMoney(scValue.value);
            await api(`/api/v1/orders/${selected.value.id}/service-charge`, {
                method: 'POST',
                body: { type: scType.value, value, reason: 'Servis bedeli' },
            });
            success('Servis bedeli eklendi', '');
        }
        closeModals();
        await refreshSelected(true);
        await refreshDetail(true);
        if (selected.value) amountText.value = money(selected.value.remaining_minor);
    } catch (e) {
        danger('Uygulanamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        actionBusy.value = false;
    }
}

/* ---- Yardımcılar ---- */
function elapsed(iso: string | null): string {
    if (!iso) return '';
    const mins = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 60000));
    if (mins < 60) return `${mins} dk`;
    return `${Math.floor(mins / 60)} sa ${mins % 60} dk`;
}
function orderTitle(o: {
    table_name: string | null;
    customer_name: string | null;
    channel_label: string;
    linked_table_names?: string[];
}): string {
    const base = o.table_name ?? o.customer_name ?? o.channel_label;
    // BİRLEŞİK MASA: kalabalık grup birden çok masaya oturduysa hesap tek
    // adisyondadır; kasiyer hangi masaları kapsadığını görmeli.
    const linked = o.linked_table_names ?? [];
    return linked.length > 0 ? `${base} + ${linked.join(' + ')}` : base;
}
</script>

<template>
    <Head title="Kasa" />

    <div class="kds-canvas fixed inset-0 flex flex-col overflow-hidden text-body">
        <!-- ================= Üst çubuk (Kitchen.vue/Runner.vue ile aynı dil) ================= -->
        <TerminalTopBar
            screen-label="Kasa Ekranı"
            :theme="kdsTheme.theme.value"
            @toggle-theme="kdsTheme.toggle()"
            @open-nav="showNav = true"
        >
            <template #status>
                <!-- Bekleyen adisyon + tutar: kompakt pill (Kitchen'daki "bekleyen" rozetiyle aynı dil) -->
                <span
                    v-if="orders.length > 0"
                    class="ml-1 inline-flex shrink-0 items-center gap-1.5 rounded-full border border-default bg-inset px-2.5 py-1 text-xs font-semibold text-muted tabular-nums"
                >
                    {{ orders.length }} bekleyen · {{ money(totalPending) }} ₺
                </span>
            </template>

            <template #actions>
                <!-- Kasa oturumu artık KASİYERİN İŞİ DEĞİL: ilk tahsilatta sunucu
                     şubenin kasasını (yoksa oluşturup) otomatik açar. Bu yüzden
                     "kasa kapalı" uyarısı / kasa seçici / bağlama adımı kaldırıldı.
                     Kalan tek bağlantı: sayım ve Z raporu için kasa yönetimi. -->
                <Link
                    v-if="meta.canCashView"
                    href="/panel/kasa/yonetim"
                    class="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-default bg-inset px-2.5 py-1 text-xs font-semibold text-muted transition hover:border-strong hover:text-body"
                    title="Kasa yönetimi — sayım, Z raporu ve nakit hareketleri"
                >
                    <AppIcon name="cart" :size="13" />
                    <span class="hidden sm:inline">Kasa yönetimi</span>
                </Link>
            </template>
        </TerminalTopBar>

        <!-- ================= İçerik =================
             Büyük ekran (xl+): tam yükseklik 3 kolon POS düzeni — sol adisyon
             listesi · orta dev numpad + ödeme yöntemleri · sağ adisyon paneli
             (sekmeli kalem/ödeme + alt toplam şeridi). Sayfa KAYMAZ; her kolon
             kendi içinde kayar. Küçük ekranlar eski dikey akışta kalır. -->
        <main class="min-h-0 flex-1 overflow-y-auto p-3 xl:overflow-hidden xl:p-0">
            <div class="flex flex-col gap-3 xl:grid xl:h-full xl:grid-cols-[minmax(280px,330px)_minmax(0,1fr)_minmax(370px,430px)] xl:gap-0">

                <!-- ============ SOL: ödeme bekleyen adisyonlar ============ -->
                <section class="flex min-h-0 flex-col rounded-lg border border-default bg-raised xl:rounded-none xl:border-0 xl:border-e xl:border-default">
                    <!-- SEKME: masalı tahsilat (adisyon) ↔ MASASIZ tahsilat (cari borç) -->
                    <div class="grid grid-cols-2 border-b border-default text-sm font-semibold">
                        <button
                            type="button"
                            class="flex items-center justify-center gap-1.5 border-b-2 px-2 py-2.5 transition"
                            :class="leftTab === 'orders' ? 'border-primary text-primary' : 'border-transparent text-muted hover:text-body'"
                            @click="leftTab = 'orders'"
                        >
                            <AppIcon name="orders" :size="15" /> Adisyonlar
                            <span class="rounded-full bg-inset px-1.5 text-xs tabular-nums">{{ orders.length }}</span>
                        </button>
                        <button
                            type="button"
                            class="flex items-center justify-center gap-1.5 border-b-2 px-2 py-2.5 transition"
                            :class="leftTab === 'debts' ? 'border-primary text-primary' : 'border-transparent text-muted hover:text-body'"
                            @click="leftTab = 'debts'"
                        >
                            <AppIcon name="inbox" :size="15" /> Borçlar
                            <span v-if="debtors.length" class="rounded-full bg-inset px-1.5 text-xs tabular-nums">{{ visibleDebtors.length }}</span>
                        </button>
                    </div>

                    <template v-if="leftTab === 'orders'">
                    <div class="flex flex-col gap-2 px-3 pt-3">
                        <SearchInput v-model="q" placeholder="Masa, müşteri, adisyon no…" />
                        <div v-if="orders.length" class="flex items-center justify-between rounded-md bg-inset px-3 py-2 text-sm">
                            <span class="text-muted">Bekleyen toplam</span>
                            <span class="font-semibold tabular-nums text-body">{{ money(totalPending) }} ₺</span>
                        </div>
                    </div>

                    <div class="min-h-0 p-3 xl:flex-1 xl:overflow-y-auto">
                        <p v-if="loading" class="px-1 py-6 text-center text-sm text-muted">Yükleniyor…</p>
                        <EmptyState
                            v-else-if="orders.length === 0"
                            title="Bekleyen adisyon yok"
                            description="Açık ve ödenmemiş adisyonlar burada listelenir."
                            icon="check-circle"
                        />
                        <div v-else class="flex max-h-[40vh] flex-col gap-2 overflow-y-auto pe-0.5 xl:max-h-none xl:overflow-visible">
                            <button
                                v-for="o in orders"
                                :key="o.id"
                                type="button"
                                class="relative flex flex-col gap-2 overflow-hidden rounded-lg border p-3 ps-4 text-left transition hover:border-strong"
                                :class="selected?.id === o.id ? 'border-primary bg-primary-soft' : 'border-default'"
                                @click="select(o)"
                            >
                                <!-- Sol renk şeridi: yeşil = hesap istendi (kasada bekliyor),
                                     turuncu = kısmi ödendi, gri = henüz sırada. -->
                                <span class="absolute inset-y-0 start-0 w-1" :class="orderStripe(o)" aria-hidden="true"></span>
                                <div class="flex items-center justify-between gap-2">
                                    <span class="flex min-w-0 items-center gap-2">
                                        <AppIcon :name="o.channel_icon" :size="16" class="shrink-0 text-subtle" />
                                        <span class="truncate font-semibold text-body">{{ orderTitle(o) }}</span>
                                        <span class="shrink-0 text-xs text-subtle">#{{ o.id }}</span>
                                    </span>
                                    <span class="shrink-0 text-base font-bold tabular-nums text-body">{{ money(o.remaining_minor) }} ₺</span>
                                </div>
                                <div class="flex items-center justify-between gap-2">
                                    <span class="flex items-center gap-2 text-xs text-muted">
                                        <span v-if="o.items_count">{{ o.items_count }} kalem</span>
                                        <span v-if="o.created_at">· {{ elapsed(o.created_at) }}</span>
                                    </span>
                                    <BaseBadge v-if="payState(o) === 'partial'" variant="warning" no-icon>Kısmi ödendi</BaseBadge>
                                    <BaseBadge v-else :variant="o.status_variant" no-icon>
                                        <AppIcon :name="o.status_icon" :size="12" /> {{ o.status_label }}
                                    </BaseBadge>
                                </div>
                            </button>
                        </div>
                    </div>
                    </template>

                    <!-- ===== MASASIZ TAHSİLAT: cari borç listesi ===== -->
                    <template v-else>
                        <div class="flex flex-col gap-2 px-3 pt-3">
                            <SearchInput v-model="debtorQuery" placeholder="Cari adı veya telefon…" />
                            <div v-if="visibleDebtors.length" class="flex items-center justify-between rounded-md bg-inset px-3 py-2 text-sm">
                                <span class="text-muted">Toplam borç</span>
                                <span class="font-semibold tabular-nums text-danger">{{ money(debtTotal) }} ₺</span>
                            </div>
                        </div>

                        <div class="min-h-0 p-3 xl:flex-1 xl:overflow-y-auto">
                            <p v-if="debtorsLoading" class="px-1 py-6 text-center text-sm text-muted">Cariler yükleniyor…</p>
                            <EmptyState
                                v-else-if="visibleDebtors.length === 0"
                                title="Borçlu cari yok"
                                description="Adisyon borca taşındığında ya da elle cari eklendiğinde burada listelenir."
                                icon="check-circle"
                            />
                            <div v-else class="flex max-h-[40vh] flex-col gap-2 overflow-y-auto pe-0.5 xl:max-h-none xl:overflow-visible">
                                <button
                                    v-for="d in visibleDebtors"
                                    :key="d.id"
                                    type="button"
                                    class="relative flex flex-col gap-1 overflow-hidden rounded-lg border p-3 ps-4 text-left transition hover:border-strong"
                                    :class="selectedDebtor?.id === d.id ? 'border-primary bg-primary-soft' : 'border-default'"
                                    @click="selectDebtor(d)"
                                >
                                    <span class="absolute inset-y-0 start-0 w-1 bg-danger" aria-hidden="true"></span>
                                    <span class="flex items-center justify-between gap-2">
                                        <span class="truncate font-semibold text-body">{{ d.name }}</span>
                                        <span class="shrink-0 text-base font-bold tabular-nums text-danger">{{ money(d.balance_minor) }} ₺</span>
                                    </span>
                                    <span class="flex items-center gap-2 text-xs text-muted">
                                        <AppIcon name="user" :size="12" class="text-subtle" />
                                        {{ d.phone ?? '—' }}
                                        <template v-if="d.open_debt_orders_count">· {{ d.open_debt_orders_count }} adisyon</template>
                                    </span>
                                </button>
                            </div>
                        </div>
                    </template>
                </section>

                <!-- ============ SAĞ: seçili adisyon paneli (mobilde 2. sırada) ============ -->
                <section
                    class="min-h-0 flex-col rounded-lg border border-default bg-raised xl:order-3 xl:flex xl:rounded-none xl:border-0"
                    :class="selected ? 'flex' : 'hidden'"
                >
                    <EmptyState
                        v-if="!selected"
                        class="my-auto"
                        title="Adisyon seçin"
                        description="Soldaki listeden ödeme alınacak adisyonu seçin; kalemler ve ödemeler burada görünür."
                        icon="cart"
                    />

                    <template v-else>
                        <!-- Başlık: masa/kanal + süre + hızlı eylemler -->
                        <div class="border-b border-default px-4 py-3">
                            <div class="flex flex-wrap items-start justify-between gap-2">
                                <div class="flex min-w-0 flex-wrap items-center gap-2">
                                    <h2 class="truncate text-lg font-bold text-body">{{ orderTitle(selected) }}</h2>
                                    <span class="text-sm text-subtle">#{{ selected.id }}</span>
                                    <BaseBadge v-if="(selected.linked_table_names?.length ?? 0) > 0" variant="primary" no-icon>
                                        <AppIcon name="merge" :size="12" />
                                        {{ (selected.linked_table_names?.length ?? 0) + 1 }} masa birleşik
                                    </BaseBadge>
                                    <BaseBadge v-if="payState(selected) === 'partial'" variant="warning" no-icon>Kısmi ödendi</BaseBadge>
                                </div>
                                <span v-if="selected.created_at" class="inline-flex shrink-0 items-center gap-1 rounded-full bg-inset px-2.5 py-1 text-xs font-medium text-muted tabular-nums">
                                    <AppIcon name="clock" :size="13" /> {{ elapsed(selected.created_at) }}
                                </span>
                            </div>
                            <div class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted">
                                <span v-if="guestCount" class="flex items-center gap-1"><AppIcon name="users" :size="14" /> {{ guestCount }} kişi</span>
                                <span v-if="selected.items_count">{{ selected.items_count }} kalem</span>
                                <span v-if="selected.paid_minor > 0" class="tabular-nums">{{ money(selected.paid_minor) }} ₺ ödendi</span>
                            </div>
                            <!-- Hızlı eylemler: sık kullanılan İKİSİ görünür (Düzelt · Hesap
                                 yazdır), gerisi tek "⋮" menüsünde — başlık altı altı ayrı
                                 butonla dolmasın. Eylemlerin hiçbiri kaldırılmadı. -->
                            <div class="mt-2 flex flex-wrap items-center gap-1.5">
                                <BaseButton
                                    v-if="detail && (canEditItems || canCompItems) && canEditNow"
                                    :variant="editMode ? 'primary' : 'secondary'"
                                    size="sm"
                                    @click="toggleEdit"
                                >
                                    <AppIcon name="pencil" :size="14" /> {{ editMode ? 'Düzenlemeyi bitir' : 'Düzelt' }}
                                </BaseButton>

                                <BaseButton variant="secondary" size="sm" @click="printReceipt('bill')">
                                    <AppIcon name="printer" :size="15" /> Hesap yazdır
                                </BaseButton>

                                <BaseButton
                                    v-if="selected.paid_minor > 0"
                                    variant="secondary"
                                    size="sm"
                                    class="!text-success"
                                    @click="printReceipt('payment')"
                                >
                                    <AppIcon name="receipt" :size="15" /> Fiş
                                </BaseButton>

                                <BaseDropdown align="right" menu-label="Adisyon işlemleri" class="ms-auto">
                                    <template #trigger="{ toggle, ariaAttrs }">
                                        <BaseButton variant="ghost" size="sm" icon-only label="Diğer işlemler" v-bind="ariaAttrs" @click="toggle">
                                            <AppIcon name="dots-vertical" :size="16" />
                                        </BaseButton>
                                    </template>

                                    <DropdownItem icon="receipt" @select="openReceiptPreview('bill')">Hesap fişini önizle</DropdownItem>
                                    <DropdownItem v-if="selected.paid_minor > 0" icon="receipt" @select="openReceiptPreview('payment')">
                                        Ödeme fişini önizle
                                    </DropdownItem>
                                    <DropdownItem v-if="meta.canDiscount" icon="tag" @select="openDiscount">
                                        {{ selected.discount_minor > 0 ? 'İndirimi kaldır' : 'İndirim uygula' }}
                                    </DropdownItem>
                                    <DropdownItem v-if="canEditItems" icon="plus" @select="openServiceCharge">Servis bedeli ekle/kaldır</DropdownItem>
                                    <DropdownItem
                                        v-if="selected.remaining_minor > 0 && selected.status === 'bill_requested' && canTakePayments"
                                        icon="arrow-left"
                                        :disabled="flowBusy"
                                        @select="sendBackToService"
                                    >
                                        Tekrar siparişe gönder
                                    </DropdownItem>
                                    <DropdownItem v-if="selected.remaining_minor > 0" icon="inbox" @select="goToDebtTransfer">
                                        Borca yaz (cari)
                                    </DropdownItem>
                                </BaseDropdown>
                            </div>
                        </div>

                        <!-- Sekmeler: Kalemler (sepet) ↔ Ödemeler (geçmiş) -->
                        <div class="grid grid-cols-2 border-b border-default text-sm font-semibold">
                            <button
                                type="button"
                                class="flex items-center justify-center gap-1.5 border-b-2 px-3 py-2.5 transition"
                                :class="rightTab === 'items' ? 'border-primary text-primary' : 'border-transparent text-muted hover:text-body'"
                                @click="rightTab = 'items'"
                            >
                                <AppIcon name="cart" :size="15" /> Kalemler
                                <span class="rounded-full bg-inset px-1.5 text-xs tabular-nums">{{ visibleItems.length }}</span>
                            </button>
                            <button
                                type="button"
                                class="flex items-center justify-center gap-1.5 border-b-2 px-3 py-2.5 transition"
                                :class="rightTab === 'payments' ? 'border-primary text-primary' : 'border-transparent text-muted hover:text-body'"
                                @click="rightTab = 'payments'"
                            >
                                <AppIcon name="wallet" :size="15" /> Ödemeler
                                <span class="rounded-full bg-inset px-1.5 text-xs tabular-nums">{{ payments.length }}</span>
                            </button>
                        </div>

                        <!-- Sekme içeriği (kendi içinde kayar) -->
                        <div class="max-h-[45vh] min-h-0 overflow-y-auto xl:max-h-none xl:flex-1">
                            <!-- KALEMLER -->
                            <template v-if="rightTab === 'items'">
                                <p v-if="detailDenied" class="p-4 text-sm text-muted">
                                    Kalem dökümünü görme yetkiniz yok; alttaki tutar özeti üzerinden tahsilat yapabilirsiniz.
                                </p>
                                <p v-else-if="!detail" class="p-4 text-sm text-muted">Kalemler yükleniyor…</p>
                                <template v-else>
                                <!-- Kalem seçim çubuğu: dokunulan kalemlerin toplamı tahsil
                                     tutarına yazılır ("ben sadece kendi yediğimi ödeyeyim"). -->
                                <div
                                    v-if="!editMode && visibleItems.length > 0 && selected.remaining_minor > 0"
                                    class="flex flex-wrap items-center gap-2 border-b border-default px-3 py-2 text-xs"
                                    :class="hasItemSelection ? 'bg-primary-soft' : 'bg-inset'"
                                >
                                    <template v-if="hasItemSelection">
                                        <span class="font-semibold text-primary">
                                            {{ selectedItemIds.size }} kalem seçili · {{ money(selectedItemsMinor) }} ₺
                                        </span>
                                        <div class="ms-auto flex items-center gap-1.5">
                                            <BaseButton variant="ghost" size="sm" @click="clearItemSelection">Temizle</BaseButton>
                                            <BaseButton size="sm" @click="applyItemSelection">Tutara yaz</BaseButton>
                                        </div>
                                    </template>
                                    <template v-else>
                                        <AppIcon name="info" :size="14" class="text-subtle" />
                                        <span class="text-muted">Kişi kendi kalemlerini ödeyecekse kalemlere dokunup seçin.</span>
                                    </template>
                                </div>

                                <EmptyState v-if="visibleItems.length === 0" title="Kalem yok" icon="cart" />
                                <ul v-else class="divide-y divide-default">
                                    <li
                                        v-for="it in visibleItems"
                                        :key="it.id"
                                        class="p-3 transition"
                                        :class="[
                                            !editMode && !it.is_comp ? 'cursor-pointer hover:bg-inset' : '',
                                            selectedItemIds.has(it.id) ? 'bg-primary-soft' : '',
                                        ]"
                                        @click="toggleItemSelect(it)"
                                    >
                                        <!-- Üst satır: adet · ad/açıklama · satır tutarı -->
                                        <div class="flex items-start gap-3">
                                            <span
                                                class="mt-0.5 min-w-9 shrink-0 rounded-md px-2 py-1 text-center text-sm font-semibold tabular-nums"
                                                :class="selectedItemIds.has(it.id) ? 'bg-primary text-on-primary' : 'bg-inset text-body'"
                                            >
                                                {{ it.qty }}×
                                            </span>
                                            <div class="min-w-0 grow">
                                                <p class="flex flex-wrap items-center gap-2 font-medium text-body">
                                                    <span class="truncate">{{ it.name }}</span>
                                                    <BaseBadge v-if="it.is_comp" variant="info" no-icon>İkram</BaseBadge>
                                                </p>
                                                <p v-if="itemMeta(it)" class="truncate text-xs text-muted">{{ itemMeta(it) }}</p>
                                                <p class="text-xs text-subtle">
                                                    {{ money(it.unit_price_minor + it.options_price_minor) }} ₺ / adet
                                                    <span v-if="!it.is_comp && it.tax_rate > 0" class="text-muted">· KDV {{ ratePct(it.tax_rate) }} dahil</span>
                                                </p>
                                            </div>
                                            <span class="shrink-0 text-right text-sm font-semibold tabular-nums" :class="it.is_comp ? 'text-subtle line-through' : 'text-body'">
                                                {{ money(it.line_total_minor) }} ₺
                                            </span>
                                        </div>

                                        <!-- Düzenleme kontrolleri: kalemin TAM GENİŞLİĞİNDE kendi
                                             satırı — daha önce metin sütununa sıkışıp "İkram yap"
                                             alt satıra düşüyordu. Adet solda, eylemler sağda. -->
                                        <div
                                            v-if="editMode && canEditNow"
                                            class="mt-2.5 flex flex-wrap items-center gap-1.5 border-t border-default pt-2.5"
                                        >
                                            <template v-if="canEditItems && !it.is_comp">
                                                <div class="flex items-center overflow-hidden rounded-md border border-strong">
                                                    <button
                                                        type="button"
                                                        class="flex h-9 w-9 items-center justify-center text-lg font-semibold text-body transition hover:bg-inset disabled:opacity-40"
                                                        :disabled="itemBusy !== null || it.qty <= 1"
                                                        aria-label="Adet azalt"
                                                        @click="adjustQty(it, -1)"
                                                    >−</button>
                                                    <span class="min-w-10 px-2 text-center text-sm font-semibold tabular-nums text-body">{{ it.qty }}</span>
                                                    <button
                                                        type="button"
                                                        class="flex h-9 w-9 items-center justify-center text-body transition hover:bg-inset disabled:opacity-40"
                                                        :disabled="itemBusy !== null || it.qty >= 100"
                                                        aria-label="Adet artır"
                                                        @click="adjustQty(it, 1)"
                                                    >
                                                        <AppIcon name="plus" :size="16" />
                                                    </button>
                                                </div>
                                                <!-- Değiştir: seçenek/not/adet yerinde düzenlenir
                                                     (önceden yalnız çıkar+ikram vardı). -->
                                                <BaseButton variant="secondary" size="sm" :disabled="itemBusy !== null" @click="openEditItem(it)">
                                                    <AppIcon name="pencil" :size="14" /> Değiştir
                                                </BaseButton>
                                            </template>

                                            <div class="ms-auto flex items-center gap-1.5">
                                                <BaseButton
                                                    v-if="canCompItems && !it.is_comp"
                                                    variant="ghost"
                                                    size="sm"
                                                    class="!text-info"
                                                    :loading="itemBusy === it.id"
                                                    @click="askComp(it)"
                                                >
                                                    <AppIcon name="tag" :size="14" /> İkram yap
                                                </BaseButton>
                                                <BaseButton
                                                    v-if="canEditItems && !it.is_comp"
                                                    variant="ghost"
                                                    size="sm"
                                                    class="!text-danger"
                                                    :loading="itemBusy === it.id"
                                                    @click="askRemoveItem(it)"
                                                >
                                                    <AppIcon name="trash" :size="14" /> Çıkar
                                                </BaseButton>
                                                <span v-if="it.is_comp" class="text-xs text-muted">İkram · {{ it.comp_reason }}</span>
                                            </div>
                                        </div>
                                    </li>
                                </ul>
                                <p v-if="detail && editMode" class="border-t border-default px-4 py-2 text-xs text-muted">
                                    Değişiklikler anında adisyona ve kalan tutara işler. Bittiğinde “Düzenlemeyi bitir”e basın.
                                </p>

                                <!-- Eksik ürün: adisyona ekle (doğru tutara ulaşmak için) -->
                                <div v-if="canEditItems && canEditNow" class="border-t border-default p-3">
                                    <BaseButton variant="secondary" block @click="openAddItem">
                                        <AppIcon name="plus" :size="16" /> Adisyona ürün ekle
                                    </BaseButton>
                                    <p class="mt-1.5 text-center text-xs text-muted">
                                        Adisyonda eksik/unutulmuş ürün varsa buradan ekleyin; tutar anında güncellenir.
                                    </p>
                                </div>
                                </template>

                                <!-- Tutar dökümü -->
                                <dl class="grid gap-1.5 border-t border-default p-4 text-sm">
                                    <div class="flex justify-between"><dt class="text-muted">Kalem toplamı</dt><dd class="tabular-nums">{{ money(selected.items_total_minor) }} ₺</dd></div>
                                    <div v-if="compTotalMinor > 0" class="flex justify-between"><dt class="text-muted">İkram</dt><dd class="tabular-nums text-info">−{{ money(compTotalMinor) }} ₺</dd></div>
                                    <div v-if="selected.discount_minor > 0" class="flex justify-between"><dt class="text-muted">İndirim</dt><dd class="tabular-nums text-danger">−{{ money(selected.discount_minor) }} ₺</dd></div>
                                    <div v-if="selected.service_charge_minor > 0" class="flex justify-between"><dt class="text-muted">Servis bedeli</dt><dd class="tabular-nums">{{ money(selected.service_charge_minor) }} ₺</dd></div>
                                    <div v-if="selected.rounding_minor !== 0" class="flex justify-between"><dt class="text-muted">Yuvarlama</dt><dd class="tabular-nums">{{ selected.rounding_minor > 0 ? '+' : '−' }}{{ money(Math.abs(selected.rounding_minor)) }} ₺</dd></div>
                                    <!-- KDV fiyata DAHİL: toplama eklenmez, bilgi amaçlı gösterilir. -->
                                    <div v-if="vatTotalMinor > 0" class="flex justify-between text-xs text-subtle">
                                        <dt>KDV (dahil)</dt>
                                        <dd class="tabular-nums">{{ money(vatTotalMinor) }} ₺</dd>
                                    </div>
                                    <template v-if="vatBreakdownReliable && (vatByRate.length > 1 || vatTotalMinor > 0)">
                                        <div
                                            v-for="r in vatByRate"
                                            :key="r.rate"
                                            class="flex justify-between text-xs text-subtle"
                                        >
                                            <dt class="ps-3">KDV {{ ratePct(r.rate) }} <span class="text-muted">(matrah {{ money(r.base_minor) }} ₺)</span></dt>
                                            <dd class="tabular-nums">{{ money(r.vat_minor) }} ₺</dd>
                                        </div>
                                    </template>
                                    <div v-if="selected.refunded_minor > 0" class="flex justify-between"><dt class="text-muted">İade edilen</dt><dd class="tabular-nums">{{ money(selected.refunded_minor) }} ₺</dd></div>
                                </dl>
                            </template>

                            <!-- ÖDEMELER -->
                            <template v-else>
                                <EmptyState v-if="payments.length === 0" title="Henüz ödeme yok" icon="wallet" />
                                <ul v-else class="divide-y divide-default">
                                    <li v-for="p in payments" :key="p.id" class="flex flex-wrap items-center justify-between gap-2 p-3">
                                        <div class="flex min-w-0 flex-col gap-0.5">
                                            <span class="flex items-center gap-2 text-sm font-medium text-body">
                                                <AppIcon :name="p.method_icon" :size="14" class="shrink-0 text-subtle" />
                                                {{ p.kind === 'refund' ? 'İade — ' : '' }}{{ p.method_label }}
                                                <span class="tabular-nums">{{ p.kind === 'refund' ? '−' : '' }}{{ money(p.amount_minor) }} ₺</span>
                                                <span v-if="p.tip_minor > 0" class="text-xs text-muted">(+{{ money(p.tip_minor) }} bahşiş)</span>
                                            </span>
                                            <span class="text-xs text-muted">
                                                {{ p.cashier ?? '—' }} · {{ p.created_at ? new Date(p.created_at).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' }) : '' }}
                                                <template v-if="p.reason"> · {{ p.reason }}</template>
                                            </span>
                                            <span v-if="p.suspect" class="flex items-center gap-1 text-xs text-danger">
                                                <AppIcon name="alert-triangle" :size="12" /> {{ p.suspect_reason }}
                                            </span>
                                        </div>
                                        <div class="flex items-center gap-2">
                                            <BaseBadge :variant="p.status_variant" no-icon>
                                                <AppIcon :name="p.status_icon" :size="12" /> {{ p.status_label }}
                                            </BaseBadge>
                                            <BaseButton
                                                v-if="p.status === 'pending' && canTakePayments"
                                                variant="secondary"
                                                size="sm"
                                                :loading="querying === p.id"
                                                @click="queryPayment(p)"
                                            >
                                                Sorgula
                                            </BaseButton>
                                            <template v-if="meta.canRefund && p.kind === 'payment'">
                                                <BaseButton
                                                    v-if="p.status === 'succeeded' && p.refunded_total_minor === 0"
                                                    variant="ghost"
                                                    size="sm"
                                                    @click="openVoid(p)"
                                                >
                                                    İptal (void)
                                                </BaseButton>
                                                <BaseButton
                                                    v-if="(p.status === 'succeeded' || p.status === 'partially_refunded') && p.refunded_total_minor < p.amount_minor"
                                                    variant="ghost"
                                                    size="sm"
                                                    @click="openRefund(p)"
                                                >
                                                    İade
                                                </BaseButton>
                                            </template>
                                        </div>
                                    </li>
                                </ul>
                            </template>
                        </div>

                        <!-- Ödeme tamamlandı bandı -->
                        <div v-if="selected.remaining_minor === 0" class="flex items-center gap-2 border-t border-success-border bg-success-soft px-4 py-2.5">
                            <AppIcon name="check-circle" :size="18" class="shrink-0 text-success" />
                            <p class="text-sm font-semibold text-success">Adisyon tamamen ödendi — fiş verip kapatabilirsiniz.</p>
                        </div>

                        <!-- Alt toplam şeridi (Kardo tarzı) -->
                        <div class="grid grid-cols-4 divide-x divide-default border-t border-default bg-inset text-center">
                            <!-- Seçilen: seçili KALEMLERİN toplamı (kalem seçimi yoksa
                                 tahsil edilecek tutar) — Kardo'daki "Seçilen" ile aynı anlam. -->
                            <div class="px-2 py-2.5">
                                <p class="text-[11px] font-medium uppercase tracking-wide text-subtle">Seçilen</p>
                                <p class="text-sm font-bold tabular-nums text-primary sm:text-base">
                                    {{ money(hasItemSelection ? selectedItemsMinor : amountMinor) }} ₺
                                </p>
                            </div>
                            <div class="px-2 py-2.5">
                                <p class="text-[11px] font-medium uppercase tracking-wide text-subtle">Ödenen</p>
                                <p class="text-sm font-bold tabular-nums text-success sm:text-base">{{ money(selected.paid_minor) }} ₺</p>
                            </div>
                            <div class="px-2 py-2.5">
                                <p class="text-[11px] font-medium uppercase tracking-wide text-subtle">Kalan</p>
                                <p class="text-sm font-bold tabular-nums sm:text-base" :class="selected.remaining_minor > 0 ? 'text-body' : 'text-success'">{{ money(selected.remaining_minor) }} ₺</p>
                            </div>
                            <div class="px-2 py-2.5">
                                <p class="text-[11px] font-medium uppercase tracking-wide text-subtle">Toplam</p>
                                <p class="text-sm font-bold tabular-nums text-body sm:text-base">{{ money(selected.total_minor) }} ₺</p>
                            </div>
                        </div>
                    </template>
                </section>

                <!-- ============ ORTA (borç modu): masasız tahsilat ============ -->
                <section
                    v-if="leftTab === 'debts'"
                    class="flex min-h-0 flex-col rounded-lg border border-default bg-raised xl:order-2 xl:rounded-none xl:border-0 xl:border-e xl:border-default"
                >
                    <EmptyState
                        v-if="!selectedDebtor"
                        class="my-auto"
                        title="Borç tahsilatı"
                        description="Soldan bir cari seçin; tahsilat adisyonsuz alınır ve nakitse kasa defterine düşer."
                        icon="inbox"
                    />

                    <template v-else>
                        <div class="flex flex-wrap items-center justify-between gap-2 border-b border-default px-4 py-2.5">
                            <div class="min-w-0">
                                <h2 class="truncate text-sm font-semibold text-body">{{ selectedDebtor.name }}</h2>
                                <p class="truncate text-xs text-muted">{{ selectedDebtor.phone ?? 'Telefon yok' }}</p>
                            </div>
                            <p class="flex items-baseline gap-1.5">
                                <span class="text-xs font-medium uppercase tracking-wide text-subtle">Borç</span>
                                <span class="text-xl font-bold tabular-nums text-danger">{{ money(selectedDebtor.balance_minor) }} ₺</span>
                            </p>
                        </div>

                        <div class="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto p-3 xl:p-4">
                            <div class="rounded-xl border-2 border-primary bg-primary-soft p-3">
                                <p class="text-xs font-semibold uppercase tracking-wide text-subtle">Tahsil edilecek (₺)</p>
                                <BaseInput
                                    v-model="debtAmountText"
                                    inputmode="decimal"
                                    placeholder="0,00"
                                    class="mt-1 h-12 text-2xl font-bold tabular-nums"
                                />
                            </div>

                            <div class="flex flex-wrap gap-2">
                                <BaseButton variant="secondary" size="sm" @click="debtAmountText = money(selectedDebtor.balance_minor)">
                                    Tamamı
                                </BaseButton>
                                <BaseButton variant="secondary" size="sm" @click="debtAmountText = money(Math.ceil(selectedDebtor.balance_minor / 2))">
                                    ½
                                </BaseButton>
                            </div>

                            <FormField label="Not" hint="İsteğe bağlı — cari hareket geçmişinde görünür">
                                <BaseInput v-model="debtNote" placeholder="ör. elden ödeme" />
                            </FormField>

                            <p class="rounded-md border border-info-border bg-info-soft px-2.5 py-2 text-xs text-muted">
                                <AppIcon name="info" :size="13" class="me-1 inline text-info" />
                                Bu tahsilat bir adisyona bağlı değildir. <strong>Nakit</strong> seçilirse kasa
                                çekmecesine ve Z raporuna düşer; kart/havale POS akışına girmez.
                            </p>
                        </div>

                        <div class="flex flex-col gap-3 border-t border-default p-3 xl:p-4">
                            <div class="grid grid-cols-2 gap-2 md:grid-cols-4">
                                <button
                                    v-for="m in ([
                                        { value: 'cash', label: 'Nakit', icon: 'wallet' },
                                        { value: 'card', label: 'Kart', icon: 'package' },
                                        { value: 'transfer', label: 'Havale', icon: 'arrow-right' },
                                        { value: 'other', label: 'Diğer', icon: 'dots-vertical' },
                                    ] as const)"
                                    :key="m.value"
                                    type="button"
                                    class="flex min-h-16 flex-col items-center justify-center gap-1.5 rounded-xl border-2 p-2 text-sm font-semibold transition hover:border-strong xl:min-h-20"
                                    :class="debtMethod === m.value ? 'border-primary bg-primary-soft text-primary' : 'border-default text-body'"
                                    :aria-pressed="debtMethod === m.value"
                                    @click="debtMethod = m.value"
                                >
                                    <AppIcon :name="m.icon" :size="24" />
                                    {{ m.label }}
                                </button>
                            </div>

                            <BaseButton :loading="debtBusy" block size="lg" class="!h-14 !text-lg" @click="collectDebt">
                                <AppIcon name="check-circle" :size="18" />
                                Borç tahsil et — {{ money(debtAmountMinor) }} ₺
                            </BaseButton>
                        </div>
                    </template>
                </section>

                <!-- ============ ORTA: ödeme işlemleri (numpad + yöntemler) ============ -->
                <section
                    v-else
                    class="min-h-0 flex-col rounded-lg border border-default bg-raised xl:order-2 xl:flex xl:rounded-none xl:border-0 xl:border-e xl:border-default"
                    :class="selected ? 'flex' : 'hidden'"
                >
                    <EmptyState
                        v-if="!selected"
                        class="my-auto"
                        title="Ödeme işlemleri"
                        description="Adisyon seçtiğinizde tahsilat burada yapılır: tutar, ödeme yöntemi ve para üstü."
                        icon="wallet"
                    />

                    <template v-else>
                        <!-- Kalan 0: tahsilat kapandı -->
                        <div v-if="selected.remaining_minor === 0" class="flex flex-1 flex-col items-center justify-center gap-4 p-8 text-center">
                            <AppIcon name="check-circle" :size="56" class="text-success" />
                            <div>
                                <p class="text-xl font-bold text-success">Adisyon tamamen ödendi</p>
                                <p class="mt-1 text-sm text-muted">Toplam {{ money(selected.total_minor) }} ₺ tahsil edildi.</p>
                            </div>
                            <BaseButton size="lg" variant="secondary" @click="printReceipt('payment')">
                                <AppIcon name="printer" :size="17" /> Ödeme fişi yazdır
                            </BaseButton>
                        </div>

                        <template v-else>
                            <div class="flex flex-wrap items-center justify-between gap-2 border-b border-default px-4 py-2.5">
                                <div class="flex min-w-0 items-baseline gap-2">
                                    <h2 class="text-sm font-semibold text-body">Ödeme İşlemleri</h2>
                                    <span class="truncate text-xs text-subtle">{{ orderTitle(selected) }} · #{{ selected.id }}</span>
                                </div>
                                <div class="flex items-center gap-3">
                                    <p v-if="isPartial" class="flex items-center gap-1 text-xs font-medium text-warning">
                                        <AppIcon name="info" :size="13" /> Sonrası kalan {{ money(afterPaymentRemaining) }} ₺
                                    </p>
                                    <p class="flex items-baseline gap-1.5">
                                        <span class="text-xs font-medium uppercase tracking-wide text-subtle">Kalan</span>
                                        <span class="text-xl font-bold tabular-nums text-body">{{ money(selected.remaining_minor) }} ₺</span>
                                    </p>
                                </div>
                            </div>

                            <div class="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto p-3 xl:p-4">
                                <!-- Tutar göstergeleri: tıklanan alan numpad hedefi olur -->
                                <div class="grid gap-2" :class="method === 'cash' ? 'sm:grid-cols-2' : ''">
                                    <div
                                        class="cursor-pointer rounded-xl border-2 p-3 transition"
                                        :class="padTarget === 'amount' ? 'border-primary bg-primary-soft' : 'border-default bg-inset hover:border-strong'"
                                        @click="padTarget = 'amount'"
                                    >
                                        <p class="text-xs font-semibold uppercase tracking-wide text-subtle">Tahsil edilecek (₺)</p>
                                        <BaseInput
                                            v-model="amountText"
                                            inputmode="decimal"
                                            placeholder="0,00"
                                            class="mt-1 h-12 text-2xl font-bold tabular-nums"
                                        />
                                    </div>
                                    <div
                                        v-if="method === 'cash'"
                                        class="cursor-pointer rounded-xl border-2 p-3 transition"
                                        :class="padTarget === 'tendered' ? 'border-primary bg-primary-soft' : 'border-default bg-inset hover:border-strong'"
                                        @click="padTarget = 'tendered'"
                                    >
                                        <div class="flex items-center justify-between gap-2">
                                            <p class="text-xs font-semibold uppercase tracking-wide text-subtle">Verilen para (₺)</p>
                                            <p class="text-xs font-semibold text-muted">
                                                Para üstü:
                                                <span
                                                    class="tabular-nums"
                                                    :class="changeMinor !== null && changeMinor > 0 ? 'text-base font-bold text-success' : 'text-body'"
                                                >{{ changeMinor !== null ? money(changeMinor) : '—' }} ₺</span>
                                            </p>
                                        </div>
                                        <BaseInput
                                            v-model="tenderedText"
                                            inputmode="decimal"
                                            placeholder="0,00"
                                            class="mt-1 h-12 text-2xl font-bold tabular-nums"
                                        />
                                    </div>
                                </div>

                                <!-- Nakit hazır tutarlar + yuvarlama -->
                                <div v-if="method === 'cash'" class="flex flex-wrap items-center gap-2">
                                    <BaseButton
                                        v-for="preset in cashPresets"
                                        :key="preset"
                                        variant="secondary"
                                        size="sm"
                                        @click="tenderedText = money(preset); padTarget = 'tendered'"
                                    >
                                        {{ money(preset) }}
                                    </BaseButton>
                                    <label class="ms-auto flex items-center gap-2 text-sm text-body">
                                        <input v-model="roundCash" type="checkbox" class="size-4 rounded border-default" />
                                        Kalanı {{ meta.cashRoundingStep }} kuruşa yuvarla
                                    </label>
                                </div>

                                <!-- Numpad + hızlı bölme (Kardo tarzı büyük tuşlar) -->
                                <div class="hidden flex-1 grid-cols-4 gap-2 md:grid" style="grid-auto-rows: minmax(3.25rem, 1fr)">
                                    <button type="button" class="pad-key" @click="padPress('1')">1</button>
                                    <button type="button" class="pad-key" @click="padPress('2')">2</button>
                                    <button type="button" class="pad-key" @click="padPress('3')">3</button>
                                    <button type="button" class="pad-quick" @click="setQuickAmount(1)">Tamamı</button>
                                    <button type="button" class="pad-key" @click="padPress('4')">4</button>
                                    <button type="button" class="pad-key" @click="padPress('5')">5</button>
                                    <button type="button" class="pad-key" @click="padPress('6')">6</button>
                                    <button type="button" class="pad-quick" @click="setQuickAmount(0.5)">1/2</button>
                                    <button type="button" class="pad-key" @click="padPress('7')">7</button>
                                    <button type="button" class="pad-key" @click="padPress('8')">8</button>
                                    <button type="button" class="pad-key" @click="padPress('9')">9</button>
                                    <button type="button" class="pad-quick" @click="setQuickAmount(1 / 3)">1/3</button>
                                    <button type="button" class="pad-key pad-del" @click="padPress('del')">Sil</button>
                                    <button type="button" class="pad-key" @click="padPress('0')">0</button>
                                    <button type="button" class="pad-key" @click="padPress(',')">,</button>
                                    <button type="button" class="pad-quick" title="Kalanı n kişiye böl" @click="openSplit">1/n</button>
                                </div>
                                <p class="hidden text-center text-[11px] text-subtle md:block">
                                    Klavye de çalışır: rakamlar
                                    <span class="font-semibold text-muted">{{ padTarget === 'amount' ? 'tahsil tutarına' : 'verilen paraya' }}</span>
                                    yazar · Backspace siler · Enter tahsil eder.
                                </p>
                                <!-- Küçük ekran: hızlı bölme butonları (numpad gizli, klavye kullanılır) -->
                                <div class="flex flex-wrap gap-2 md:hidden">
                                    <BaseButton variant="secondary" size="sm" @click="setQuickAmount(1)">Tamamı</BaseButton>
                                    <BaseButton variant="secondary" size="sm" @click="setQuickAmount(0.5)">½</BaseButton>
                                    <BaseButton variant="secondary" size="sm" @click="setQuickAmount(1 / 3)">⅓</BaseButton>
                                    <BaseButton v-if="guestCount && guestCount > 1" variant="secondary" size="sm" @click="splitByGuests">
                                        Kişi başı ({{ guestCount }})
                                    </BaseButton>
                                </div>

                                <!-- Bahşiş + not -->
                                <div class="grid gap-3 sm:grid-cols-2">
                                    <FormField label="Bahşiş (₺)" hint="Adisyona işlemez; Z raporunda ayrı izlenir">
                                        <BaseInput v-model="tipText" inputmode="decimal" placeholder="0,00" />
                                    </FormField>
                                    <FormField label="Not">
                                        <BaseInput v-model="noteText" placeholder="İsteğe bağlı" />
                                    </FormField>
                                </div>
                            </div>

                            <!-- Alt: ödeme yöntemi + büyük tahsilat butonu -->
                            <div class="flex flex-col gap-3 border-t border-default p-3 xl:p-4">
                                <div class="grid grid-cols-2 gap-2 md:grid-cols-4">
                                    <button
                                        v-for="m in payMethods"
                                        :key="m.value"
                                        type="button"
                                        class="flex min-h-16 flex-col items-center justify-center gap-1.5 rounded-xl border-2 p-2 text-sm font-semibold transition hover:border-strong xl:min-h-20"
                                        :class="methodTone(m.value, method === m.value)"
                                        :aria-pressed="method === m.value"
                                        @click="method = m.value"
                                    >
                                        <AppIcon :name="m.icon" :size="26" :class="methodIconTone(m.value, method === m.value)" />
                                        {{ m.label }}
                                    </button>
                                </div>
                                <!-- FAZ2: POS/terminal gerçek-durum rozeti (audit #4) — sandbox/mock'ta
                                     "gerçek kart okutma bekleme" yanılgısını önler; uydurma yok, sunucudan okunur. -->
                                <div
                                    v-if="methodMeta?.terminal"
                                    class="flex flex-col gap-1 rounded-md border p-2 text-xs"
                                    :class="posNeedsManual ? 'border-warning-border bg-warning-soft' : 'border-success-border bg-success-soft'"
                                >
                                    <span class="flex items-center gap-1.5 font-medium" :class="posNeedsManual ? 'text-warning' : 'text-success'">
                                        <AppIcon :name="posNeedsManual ? 'alert-triangle' : 'check-circle'" :size="14" />
                                        Kart POS: {{ terminalStatus?.provider_label ?? 'Durum okunuyor…' }}
                                    </span>
                                    <span v-if="posSimulated" class="text-muted">
                                        Fiziksel kart okuyucu <strong>bağlı değil</strong> — bu sağlayıcı test/simülasyon amaçlıdır, GERÇEK tahsilat yapmaz.
                                        Kartı harici POS cihazınızdan siz okutup tutarı burada <strong>manuel onaylayın</strong>.
                                    </span>
                                    <span v-else-if="!posOnline" class="text-muted">
                                        Terminal şu an çevrimdışı görünüyor{{ terminalStatus?.message ? ` (${terminalStatus.message})` : '' }} — gönderim beklemede kalabilir, tutarı manuel doğrulayın.
                                    </span>
                                    <span v-else class="text-muted">
                                        Tutar POS terminaline gönderilir; tahsilat yalnız doğrulanmış terminal onayıyla tamamlanır{{ terminalStatus?.terminal_id ? ` (terminal ${terminalStatus.terminal_id})` : '' }}.
                                    </span>
                                </div>

                                <!-- Masaüstünde büyük tahsilat butonu; mobilde sabit alt çubuk kullanılır -->
                                <BaseButton v-if="canTakePayments" :loading="paying" block size="lg" class="hidden !h-14 !text-lg lg:flex" @click="pay">
                                    {{ methodMeta?.terminal ? (posNeedsManual ? 'Manuel onayla (POS bağlı değil)' : 'Terminale gönder') : 'Ödemeyi al' }} — {{ money(amountMinor) }} ₺
                                </BaseButton>
                            </div>
                        </template>
                    </template>
                </section>
            </div>

            <!-- Mobil: her zaman erişilebilir ödeme aksiyonu (safe-area) -->
            <template v-if="selected && selected.remaining_minor > 0">
                <div
                    class="fixed inset-x-0 z-(--z-sticky) border-t border-default bg-raised px-4 py-3 shadow-lg lg:hidden"
                    style="bottom: calc(3.5rem + env(safe-area-inset-bottom))"
                >
                    <div class="mb-2 flex items-center justify-between gap-2 text-sm">
                        <span class="text-muted">Kalan <span class="font-semibold text-body">{{ money(selected.remaining_minor) }} ₺</span></span>
                        <span class="flex items-center gap-1 truncate text-xs text-muted">
                            <AppIcon v-if="methodMeta" :name="methodMeta.icon" :size="14" /> {{ methodMeta?.label }}
                        </span>
                    </div>
                    <BaseButton v-if="canTakePayments" :loading="paying" block size="lg" @click="pay">
                        {{ methodMeta?.terminal ? (posNeedsManual ? 'Manuel onayla (POS bağlı değil)' : 'Terminale gönder') : 'Ödemeyi al' }} — {{ money(amountMinor) }} ₺
                    </BaseButton>
                </div>
                <!-- Sabit çubuk son içeriği örtmesin diye mobil boşluk -->
                <div class="h-32 lg:hidden" aria-hidden="true"></div>
            </template>
        </main>
    </div>

    <!-- Kalem çıkarma onayı -->
        <BaseModal :open="removeItemTarget !== null" title="Kalemi çıkar" @close="closeModals">
            <div class="flex flex-col gap-3">
                <p class="text-sm text-muted">
                    <span class="font-medium text-body">{{ removeItemTarget?.name }}</span> adisyondan çıkarılacak. Tutar buna göre güncellenir.
                </p>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="closeModals">Vazgeç</BaseButton>
                    <BaseButton variant="danger" :loading="itemBusy !== null" @click="doRemoveItem">Kalemi çıkar</BaseButton>
                </div>
            </div>
        </BaseModal>

        <!-- İkram (comp) modalı -->
        <BaseModal :open="compTarget !== null" title="İkram (ücretsiz yap)" @close="closeModals">
            <div class="flex flex-col gap-3">
                <p class="text-sm text-muted">
                    <span class="font-medium text-body">{{ compTarget?.name }}</span> ikram edilecek; tutarı sıfırlanır ve Z raporunda ikram olarak izlenir.
                </p>
                <FormField label="Neden" required>
                    <BaseInput v-model="compReason" placeholder="ör. müşteri memnuniyeti" />
                </FormField>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="closeModals">Vazgeç</BaseButton>
                    <BaseButton :loading="itemBusy !== null" :disabled="compReason.trim().length < 3" @click="doComp">İkram et</BaseButton>
                </div>
            </div>
        </BaseModal>

        <!-- Void modalı -->
        <BaseModal :open="voidTarget !== null" title="Ödemeyi iptal et (void)" @close="closeModals">
            <div class="flex flex-col gap-3">
                <p class="text-sm text-muted">
                    Tahsilat hiç olmamış sayılır; adisyon yeniden açılır. Nakitse çekmece defterine ters kayıt düşer.
                </p>
                <FormField label="Neden" required>
                    <BaseInput v-model="voidReason" placeholder="ör. yanlış adisyona alındı" />
                </FormField>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="closeModals">Vazgeç</BaseButton>
                    <BaseButton variant="danger" :loading="actionBusy" :disabled="voidReason.trim().length < 3" @click="doVoid">
                        Ödemeyi iptal et
                    </BaseButton>
                </div>
            </div>
        </BaseModal>

        <!-- İade modalı -->
        <BaseModal :open="refundTarget !== null" title="İade" @close="closeModals">
            <div class="flex flex-col gap-3">
                <p v-if="refundTarget" class="text-sm text-muted">
                    {{ refundTarget.method_label }} — ödeme {{ money(refundTarget.amount_minor) }} ₺;
                    iade edilebilir kalan {{ money(refundTarget.amount_minor - refundTarget.refunded_total_minor) }} ₺.
                </p>
                <FormField label="İade tutarı (₺)" required>
                    <BaseInput v-model="refundAmountText" inputmode="decimal" />
                </FormField>
                <FormField label="Neden" required>
                    <BaseInput v-model="refundReason" placeholder="ör. ürün iade edildi" />
                </FormField>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="closeModals">Vazgeç</BaseButton>
                    <BaseButton variant="danger" :loading="actionBusy" :disabled="refundReason.trim().length < 3" @click="doRefund">
                        İade et
                    </BaseButton>
                </div>
            </div>
        </BaseModal>

        <!-- Servis bedeli modalı -->
        <BaseModal :open="serviceChargeOpen" title="Servis bedeli" @close="closeModals">
            <div class="flex flex-col gap-3">
                <FormField label="Tür">
                    <BaseSelect
                        :model-value="scType"
                        :options="[
                            { value: 'percent', label: 'Yüzde (%)' },
                            { value: 'amount', label: 'Sabit tutar (₺)' },
                        ]"
                        @update:model-value="(v: string) => (scType = v as 'percent' | 'amount')"
                    />
                </FormField>
                <FormField :label="scType === 'percent' ? 'Yüzde' : 'Tutar (₺)'" required>
                    <BaseInput v-model="scValue" inputmode="decimal" :placeholder="scType === 'percent' ? 'ör. 10' : 'ör. 25,00'" />
                </FormField>
                <div class="flex justify-between gap-2">
                    <BaseButton
                        v-if="selected && selected.service_charge_minor > 0"
                        variant="ghost"
                        :loading="actionBusy"
                        @click="applyServiceCharge(true)"
                    >
                        Bedeli kaldır
                    </BaseButton>
                    <div class="ms-auto flex gap-2">
                        <BaseButton variant="secondary" @click="closeModals">Vazgeç</BaseButton>
                        <BaseButton :loading="actionBusy" :disabled="!scValue" @click="applyServiceCharge(false)">Uygula</BaseButton>
                    </div>
                </div>
            </div>
        </BaseModal>

        <!-- §13 Faz C-2: fiş önizleme (hesap/ödeme) — yazdırmayla tek kaynak -->
        <BaseModal
            :open="previewReceipt !== null"
            :title="previewReceipt?.kind === 'bill' ? 'Hesap fişi önizleme' : 'Ödeme fişi önizleme'"
            @close="closeReceiptPreview"
        >
            <div class="flex flex-col gap-4">
                <div class="max-h-[60vh] overflow-y-auto rounded-lg bg-inset p-4">
                    <PaymentReceipt v-if="previewReceipt" :data="previewReceipt" />
                </div>
                <p class="text-xs text-muted">
                    Yazdır'a basınca fiş cihazınızın varsayılan yazıcısına (termal 58/80mm, A4 veya “PDF'e kaydet”) gönderilir.
                </p>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="closeReceiptPreview">Kapat</BaseButton>
                    <BaseButton @click="printPreview">
                        <AppIcon name="printer" :size="16" /> Yazdır
                    </BaseButton>
                </div>
            </div>
        </BaseModal>

    <!-- 1/n: kalanı serbest sayıda kişiye böl -->
    <BaseModal :open="splitOpen" title="Hesabı böl" size="sm" @close="closeModals">
        <div class="flex flex-col gap-3">
            <p class="text-sm text-muted">
                Kalan <span class="font-semibold tabular-nums text-body">{{ selected ? money(selected.remaining_minor) : '0,00' }} ₺</span>
                kaç kişiye bölünecek?
            </p>
            <div class="flex flex-wrap gap-2">
                <BaseButton
                    v-for="n in [2, 3, 4, 5, 6, 8]"
                    :key="n"
                    :variant="splitCount === String(n) ? 'primary' : 'secondary'"
                    size="sm"
                    @click="splitCount = String(n)"
                >
                    {{ n }}
                </BaseButton>
            </div>
            <FormField label="Kişi sayısı" required>
                <BaseInput v-model="splitCount" inputmode="numeric" placeholder="ör. 5" />
            </FormField>
            <div v-if="splitPreviewMinor > 0" class="flex items-center justify-between rounded-lg bg-inset px-3 py-2">
                <span class="text-sm text-muted">Kişi başı</span>
                <span class="text-xl font-bold tabular-nums text-body">{{ money(splitPreviewMinor) }} ₺</span>
            </div>
            <p class="text-xs text-muted">
                Yukarı yuvarlanır (eksik tahsilat olmaz); kalan tutar her ödemeden sonra yeniden hesaplanır.
            </p>
            <div class="flex justify-end gap-2">
                <BaseButton variant="secondary" @click="closeModals">Vazgeç</BaseButton>
                <BaseButton :disabled="splitPreviewMinor <= 0" @click="applySplit">Tutara yaz</BaseButton>
            </div>
        </div>
    </BaseModal>

    <!-- Kalemi değiştir (adet/seçenek/not) -->
    <OrderEditItemDialog
        v-if="selected && detail"
        :open="editItemTarget !== null"
        :order-id="selected.id"
        :item="editItemTarget"
        :order-version="detail.version"
        :channel="detail.channel ?? 'table'"
        :branch-id="detail.branch_id ?? null"
        @close="closeEditItem"
        @saved="onItemSaved"
        @replace="replaceItemFlow"
    />

    <!-- İndirim (hazır tanımlar) -->
    <OrderDiscountDialog
        v-if="selected"
        :open="discountOpen"
        :order-id="selected.id"
        :discount-minor="selected.discount_minor"
        :discount-reason="selected.discount_reason ?? null"
        :discount-percent="selected.discount_percent ?? null"
        :order-version="selected.version"
        @close="closeDiscount"
        @applied="onDiscountChanged"
        @removed="onDiscountChanged"
    />

    <!-- Adisyona ürün ekle (kasa + sipariş ekranıyla ortak bileşen) -->
    <OrderAddItemDialog
        v-if="selected && detail"
        :open="addItemOpen"
        :order-id="selected.id"
        :order-version="detail.version"
        :channel="detail.channel ?? 'table'"
        :branch-id="detail.branch_id ?? null"
        @close="closeAddItem"
        @added="onItemAdded"
    />

    <!-- §13 Faz B: terminal (kasa) hassas eylem PIN modalı -->
    <StaffPinDialog />

    <!-- ================= Nav çekmecesi (soldan overlay) ================= -->
    <KdsNavDrawer v-if="!isTerminal" :open="showNav" @close="showNav = false" />

    <!-- Terminalde: zorunlu personel giriş gate'i + personel barı (PanelLayout/Kitchen/Runner ile aynı) -->
    <TerminalOperatorGate />

    <!-- §13 Faz D: boşta-kalma sonrası ekran kilidi (yalnız aktif operatör varken) -->
    <LockOverlay v-if="idleLocked" @unlocked="unlockIdle" />

    <ToastHost />
</template>

<style scoped>
/*
 * Zemin: Kitchen.vue/Runner.vue ile birebir aynı katmanlı yüzey — --ui-surface
 * üstünde çok hafif üstten ışık düşümü (düz/tek tondan "katmanlı yüzey" hissi).
 */
.kds-canvas {
    background-color: var(--ui-surface);
    background-image: radial-gradient(1200px 640px at 50% -12%, rgb(255 255 255 / 0.035), transparent 60%);
}

/*
 * Dokunmatik numpad tuşları (büyük ekran kasa): parmakla vurulacak kadar geniş,
 * düşük kontrastlı yüzey — tutar/para üstü alanları başrolde kalsın. Renkler
 * yalnız --ui-* token'larından; koyu tema otomatik uyar.
 */
.pad-key,
.pad-quick {
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 0.75rem;
    border: 1px solid var(--ui-border);
    font-size: 1.5rem;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    color: var(--ui-text);
    transition: background-color 0.12s ease, border-color 0.12s ease, transform 0.06s ease;
    user-select: none;
}
.pad-key {
    background-color: var(--ui-surface-inset);
}
.pad-quick {
    background-color: var(--ui-primary-soft);
    border-color: var(--ui-primary-soft-border);
    color: var(--ui-primary);
    font-size: 1.0625rem;
}
.pad-del {
    font-size: 1.125rem;
    color: var(--ui-danger);
}
.pad-key:hover,
.pad-quick:hover {
    border-color: var(--ui-border-strong);
}
.pad-key:active,
.pad-quick:active {
    transform: scale(0.97);
}
</style>
