<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Head, router, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import { useLightbox } from '@/composables/useLightbox';
import { usePermissions } from '@/composables/usePermissions';
import ImageLightbox from '@/Components/ui/ImageLightbox.vue';
import TerminalTopBar from '@/Components/panel/TerminalTopBar.vue';
import KdsNavDrawer from '@/Pages/Panel/Kds/KdsNavDrawer.vue';
import OrderEditItemDialog from '@/Components/panel/OrderEditItemDialog.vue';
import OrderDiscountDialog from '@/Components/panel/OrderDiscountDialog.vue';
import {
    usePaymentReceiptPrint,
    formatReceiptTime,
    type PaymentReceiptLine,
} from '@/Pages/Panel/Payments/usePaymentReceiptPrint';
import { useKdsTheme } from '@/Pages/Panel/Kds/kds';
import StaffPinDialog from '@/Components/panel/StaffPinDialog.vue';
import { useTerminalPin } from '@/composables/useTerminalPin';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseCheckbox from '@/Components/ui/BaseCheckbox.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseRadioGroup from '@/Components/ui/BaseRadioGroup.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import {
    apiIdempotent,
    channelPrice,
    groupOptionsPrice,
    fetchBoard,
    fetchOrder,
    fetchOrderCatalog,
    metaFromProps,
    money,
    newIdempotencyKey,
    orderElapsed,
    type BoardTable,
    type CatalogCategory,
    type CatalogProduct,
    type OrderDetail,
    type OrderItemRow,
    type OrderSummary,
} from './orders';
import { fetchActiveReceivables, type ReceivableRow as ReceivableOption } from '../Receivables/receivables';

const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const orderId = Number((page.props as Record<string, unknown>).orderId);
const { success, danger } = useToast();
const { open: lbOpen } = useLightbox();

// §13 Faz B: terminal (sipariş-giriş/kasa) oturumda hassas eylemler PIN ister.
const { isTerminal, collectPin } = useTerminalPin();

// Arayüz gizleme (izne göre): masa/adisyon birleştirme yalnız Garson + yönetim.
const { can } = usePermissions();

/* ================= Sipariş + polling ================= */
const order = ref<OrderDetail | null>(null);
const loading = ref(true);
const anyModalOpen = ref(false);

/** Ödeme/hesap eylemleri uygun mu: adisyon açık VE onay-bekleyen/taslak değil.
 *  (QR onay bekleyen adisyonda önce "Siparişi onayla" — ödeme/hesap gösterilmez.) */
const payReady = computed(
    () => !!order.value?.is_open && order.value.status !== 'pending_approval' && order.value.status !== 'draft',
);

/* Fiş başlığı: işletme + şube adı — Kasa ekranıyla AYNI kaynak (auth prop). */
const receiptAuth = page.props.auth as {
    branches?: { id: number; name: string }[];
    activeBranchId?: number | null;
    tenant?: { name?: string } | null;
} | null;
const receiptBusiness = receiptAuth?.tenant?.name ?? '';
const receiptBranch = computed(() => {
    const list = receiptAuth?.branches ?? [];
    const active = receiptAuth?.activeBranchId ?? null;
    return (list.find((b) => b.id === active) ?? list[0])?.name ?? '';
});

/* ---- Tam ekran terminal kabuğu (Board/Kitchen/Runner/Kasa ile aynı) ---- */
const showNav = ref(false);
const kdsTheme = useKdsTheme();

/** Sağ panel sekmesi: sepet (kalemler) ↔ geçmiş (olay günlüğü). */
const rightTab = ref<'cart' | 'history'>('cart');

/** Kasaya gidebilir mi — adisyon kasada beklerken kısayol gösterilsin. */
const canGoCashier = computed(() => can('payments.take') || can('cash.view'));

/** "14:32" — mutlak saat (açılış / son sipariş göstergeleri). */
function clockTime(iso: string | null): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
}

let timer: ReturnType<typeof setInterval> | null = null;

async function load(silent = false): Promise<void> {
    try {
        order.value = await fetchOrder(orderId);
    } catch (e) {
        if (!silent) danger('Adisyon yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

/* ================= Hızlı ürün ekleme ================= */
const catalog = ref<{ categories: CatalogCategory[]; products: CatalogProduct[] }>({ categories: [], products: [] });
/** Seçili ANA kategori (0 = tümü). */
const activeCategory = ref<number | 0>(0);
/** Seçili ALT kategori (0 = ana kategorinin tamamı). */
const activeSubCategory = ref<number | 0>(0);
const search = ref('');

/* ---- İki seviyeli kategori gezinmesi ----
 * Katalogda üst-kategori (parent_id) zaten vardı ama sipariş ekranı tek
 * seviye gösteriyordu: "Yemekler" altındaki "Tava Yemekler / Izgaralar"
 * ayrımı kayboluyor, uzun menülerde ürün aranarak bulunuyordu. Artık üst
 * satır ana kategoriler, alt satır seçili ananın alt kategorileri.
 * Hiç alt kategori tanımlanmamış işletmede alt satır GÖRÜNMEZ — düz
 * kategori listesi bugünküyle birebir aynı çalışır. */
const rootCategories = computed(() => catalog.value.categories.filter((c) => !c.parent_id));
/** Hiç ana/alt ilişkisi yoksa düz liste (eski davranış). */
const isFlatCatalog = computed(() => rootCategories.value.length === catalog.value.categories.length);
const mainCategories = computed(() => (isFlatCatalog.value ? catalog.value.categories : rootCategories.value));
const subCategories = computed(() =>
    activeCategory.value === 0 || isFlatCatalog.value
        ? []
        : catalog.value.categories.filter((c) => c.parent_id === activeCategory.value),
);

/** Kategori ve (varsa) tüm alt kategorilerinin id kümesi. */
function categoryTreeIds(categoryId: number): Set<number> {
    const ids = new Set<number>([categoryId]);
    for (const c of catalog.value.categories) {
        if (c.parent_id === categoryId) ids.add(c.id);
    }
    return ids;
}

function selectCategory(id: number | 0): void {
    activeCategory.value = id;
    activeSubCategory.value = 0;
}

const visibleProducts = computed(() => {
    let list = catalog.value.products;
    if (activeSubCategory.value !== 0) {
        list = list.filter((p) => p.category_id === activeSubCategory.value);
    } else if (activeCategory.value !== 0) {
        // Ana kategori seçiliyken alt kategorilerdeki ürünler de görünür.
        const ids = categoryTreeIds(activeCategory.value);
        list = list.filter((p) => p.category_id !== null && ids.has(p.category_id));
    }
    if (search.value) {
        const needle = search.value.toLocaleLowerCase('tr-TR');
        list = list.filter((p) => p.name.toLocaleLowerCase('tr-TR').includes(needle));
    }
    return list;
});

/** Kırık/yüklenemeyen ürün görseli → zarif ikon yer tutucuya düş (kırık görsel simgesi yok). */
const brokenImages = ref<Set<number>>(new Set());
function onProductImageError(productId: number): void {
    brokenImages.value = new Set(brokenImages.value).add(productId);
}

onMounted(async () => {
    await load();
    try {
        catalog.value = await fetchOrderCatalog(order.value?.branch_id ?? null);
    } catch {
        /* katalog gelmezse arama boş kalır; sipariş yine görünür */
    }
    timer = setInterval(() => {
        if (!anyModalOpen.value) void load(true);
    }, 5000);
});

onBeforeUnmount(() => {
    if (timer) clearInterval(timer);
    kdsTheme.release();
});

/* ================= Ortak işlem yardımcıları ================= */
const opBusy = ref(false);

async function runOp(path: string, body: Record<string, unknown>, okTitle: string, method = 'POST'): Promise<boolean> {
    if (opBusy.value) return false;
    opBusy.value = true;
    try {
        const res = await api<{ order: OrderDetail }>(path, { method, body });
        if (res.order) order.value = res.order;
        if (okTitle) success(okTitle, '');
        return true;
    } catch (e) {
        if (e instanceof ApiError && e.status === 409) {
            danger('Eşzamanlı değişiklik', e.displayMessage);
            await load(true);
        } else {
            danger('İşlem tamamlanamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
        }
        return false;
    } finally {
        opBusy.value = false;
    }
}

/* ================= Ürün ekleme (varyant/seçenek modalı) ================= */
const productModal = ref<CatalogProduct | null>(null);
const pmVariant = ref('');
const pmOptions = ref<Set<number>>(new Set());
const pmQty = ref(1);
const pmNote = ref('');
const addBusy = ref(false);
/** Idempotency-Key NİYET başına (modal açılışında) üretilir; başarıya kadar sabit
 *  → yanıt kaybında tekrar "Ekle" AYNI kalemi ikinci kez mutfağa DÜŞÜRMEZ. */
const pmIdemKey = ref('');

function productPrice(p: CatalogProduct): number {
    return channelPrice(p, order.value?.channel ?? 'table');
}

function onProductClick(p: CatalogProduct): void {
    if (!p.is_available) return;
    // HER üründe onay + adet adımı: basit ürün de artık DOĞRUDAN eklenmez —
    // modal açılır (yanlış/kazara dokunma mutfağa düşmesin). Varyant/opsiyon
    // yoksa modal yalnız adet + not + "Ekle / Vazgeç" gösterir. Vazgeç = başka
    // ürün seç (değiştir).
    productModal.value = p;
    pmVariant.value = String(p.variants.find((v) => v.is_default)?.id ?? p.variants[0]?.id ?? '');
    pmOptions.value = new Set(p.option_groups.flatMap((g) => g.options.filter((o) => o.is_default).map((o) => o.id)));
    pmQty.value = Math.max(1, p.min_order_qty);
    pmNote.value = '';
    pmIdemKey.value = newIdempotencyKey();
    anyModalOpen.value = true;
}

function toggleOption(groupId: number, optionId: number, single: boolean): void {
    const next = new Set(pmOptions.value);
    const group = productModal.value?.option_groups.find((g) => g.id === groupId);
    if (single && group) {
        group.options.forEach((o) => next.delete(o.id));
        next.add(optionId);
    } else if (next.has(optionId)) {
        next.delete(optionId);
    } else {
        // #12 Çoklu seçim: max_select dolduysa yeni seçimi engelle.
        const selectedInGroup = group ? group.options.filter((o) => next.has(o.id)).length : 0;
        if (group?.max_select && selectedInGroup >= group.max_select) return;
        next.add(optionId);
    }
    pmOptions.value = next;
}

const pmTotal = computed(() => {
    const p = productModal.value;
    if (!p) return 0;
    const variant = p.variants.find((v) => String(v.id) === pmVariant.value);
    const unit = variant ? variant.price_minor : productPrice(p);
    // free_limit kuralı sunucuyla birebir (groupOptionsPrice)
    const opts = p.option_groups.reduce((n, g) => n + groupOptionsPrice(g, pmOptions.value), 0);
    return pmQty.value * (unit + opts);
});

/* #12 Adet sınırları + zorunlu seçim doğrulaması (istemcide → gereksiz 422 turu yok). */
const pmMinQty = computed(() => Math.max(1, productModal.value?.min_order_qty ?? 1));
const pmMaxQty = computed(() => productModal.value?.max_order_qty ?? 99);
const pmRequiredOk = computed(() => {
    const p = productModal.value;
    if (!p) return true;
    return p.option_groups.every(
        (g) => !g.is_required || g.options.some((o) => pmOptions.value.has(o.id)),
    );
});
const pmValid = computed(
    () => pmRequiredOk.value && pmQty.value >= pmMinQty.value && pmQty.value <= pmMaxQty.value,
);
function pmInc(): void {
    if (pmQty.value < pmMaxQty.value) pmQty.value++;
}
function pmDec(): void {
    if (pmQty.value > pmMinQty.value) pmQty.value--;
}

async function addItem(p: CatalogProduct, variantId: number | null, optionIds: number[], qty: number, note: string | null): Promise<void> {
    if (addBusy.value) return;
    addBusy.value = true;
    try {
        // Idempotency-Key NİYET başına (modal açılışında üretildi) → yanıt kaybında
        // tekrar "Ekle" kalemi ikinci kez düşürmez (§12.4).
        const res = await apiIdempotent<{ order: OrderDetail }>(`/api/v1/orders/${orderId}/items`, {
            product_id: p.id,
            variant_id: variantId,
            qty,
            option_ids: optionIds,
            note,
        }, pmIdemKey.value || newIdempotencyKey());
        if (res.order) order.value = res.order;
        success(`${p.name} eklendi`, '');
        productModal.value = null;
        anyModalOpen.value = false;
        // Ekler eklemez SOR: "mutfağa iletilsin mi?" — gönderme unutulup adisyon
        // açık kalmasın. Hatalıysa "Şimdi değil" deyip düzeltir/siler.
        openSendPrompt(p.name);
    } catch (e) {
        danger('Eklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        addBusy.value = false;
    }
}

/* Ekleme-anı "mutfağa gönder" sorusu (unutma önleyici). */
const sendPromptOpen = ref(false);
const sendPromptName = ref('');
function openSendPrompt(name: string): void {
    sendPromptName.value = name;
    sendPromptOpen.value = true;
    anyModalOpen.value = true;
}
async function confirmSendPrompt(): Promise<void> {
    sendPromptOpen.value = false;
    anyModalOpen.value = false;
    await sendToKitchen();
}
function dismissSendPrompt(): void {
    sendPromptOpen.value = false;
    anyModalOpen.value = false;
}

function submitProductModal(): void {
    const p = productModal.value;
    if (!p) return;
    void addItem(p, pmVariant.value ? Number(pmVariant.value) : null, [...pmOptions.value], pmQty.value, pmNote.value || null);
}

/* ================= Kalem işlemleri =================
   NOT: Durum İLERLETME genelde burada YOK — sipariş yaşam döngüsü (Hazırlanıyor
   → Garson & Komi bekliyor → Servis edildi) İSTASYONDA ilerler: Mutfak/Barista
   (KDS) "bitir", Komi "teslim et". Siparişler panosu görüntüler; adet/not/
   taşı/ikram/iptal (kasa/yetki işleri) kalır.
   TEK İSTİSNA (denetim 2026-08-06, BULGU #3): komi rolü yoksa (küçük işletme)
   'hazır' bir kalemi HİÇBİR yerden servis edilmiş işaretleyemiyordu — garson
   artık kendi ekranından "Servis Edildi" diyebilir (kds.deliver iznine bağlı,
   bkz. config/authz.php + can('kds.deliver')). Yalnız BU TEK durum geçişi
   (ready→served); ara adımlar (accepted/preparing/ready) hâlâ KDS'in işi. */
async function serveItem(item: OrderItemRow): Promise<void> {
    await runOp(`/api/v1/orders/${orderId}/items/${item.id}/status`, { status: 'served', expected_version: order.value?.version }, 'Servis edildi', 'PUT');
}

async function changeQty(item: OrderItemRow, delta: number): Promise<void> {
    const qty = item.qty + delta;
    if (qty < 1) return;
    // expected_version: eşzamanlı düzenlemede sessiz clobber yerine 409 → runOp tazeler.
    await runOp(`/api/v1/orders/${orderId}/items/${item.id}`, { qty, expected_version: order.value?.version }, '', 'PUT');
}

async function removeItem(item: OrderItemRow): Promise<void> {
    await runOp(`/api/v1/orders/${orderId}/items/${item.id}`, { expected_version: order.value?.version }, 'Kalem çıkarıldı', 'DELETE');
}

/* Not düzenleme */
const noteModal = ref<OrderItemRow | null>(null);
const noteText = ref('');

function openNote(item: OrderItemRow): void {
    noteModal.value = item;
    noteText.value = item.note ?? '';
    anyModalOpen.value = true;
}

async function saveNote(): Promise<void> {
    const item = noteModal.value;
    if (!item) return;
    if (await runOp(`/api/v1/orders/${orderId}/items/${item.id}`, { note: noteText.value || null, expected_version: order.value?.version }, 'Not kaydedildi', 'PUT')) {
        noteModal.value = null;
        anyModalOpen.value = false;
    }
}

/* Neden isteyen işlemler: kalem iptal / ikram / sipariş iptal / iade */
type ReasonKind = 'item_cancel' | 'item_comp' | 'order_cancel' | 'order_refund';
const reasonModal = ref<{ kind: ReasonKind; item?: OrderItemRow } | null>(null);
const reasonText = ref('');
/* İkram adedi (kısmi ikram): varsayılan tüm adet; 1..item.qty arası girilebilir. */
const compQty = ref(1);

const reasonTitles: Record<ReasonKind, string> = {
    item_cancel: 'Kalemi iptal et',
    item_comp: 'İkram et',
    order_cancel: 'Adisyonu iptal et',
    order_refund: 'İade et',
};

function openReason(kind: ReasonKind, item?: OrderItemRow): void {
    reasonModal.value = { kind, item };
    reasonText.value = '';
    compQty.value = item?.qty ?? 1; // varsayılan: tüm adedi ikram
    anyModalOpen.value = true;
}

async function submitReason(): Promise<void> {
    const ctx = reasonModal.value;
    if (!ctx || reasonText.value.trim().length < 3) {
        danger('Neden zorunlu', 'En az 3 karakterlik bir neden girin.');
        return;
    }
    const reason = reasonText.value.trim();
    const v = order.value?.version;

    // §13 Faz B: terminal oturumda PIN gerekir (iptal/ikram/iade → personele
    // atfedilir). Neden modalı üstüne PIN modalı binmesin diye geçici kapat;
    // iptal/başarısızlıkta geri aç (neden kaybolmasın).
    let pinFields: Record<string, unknown> = {};
    if (isTerminal.value) {
        reasonModal.value = null;
        anyModalOpen.value = false;
        const collected = await collectPin();
        if (collected === null) {
            reasonModal.value = ctx;
            reasonText.value = reason;
            anyModalOpen.value = true;
            return;
        }
        pinFields = collected;
    }

    // Kısmi ikram: adet, kalem adedinden azsa gövdeye eklenir (tam adette gerek yok).
    const compFields =
        ctx.kind === 'item_comp' && ctx.item && compQty.value > 0 && compQty.value < ctx.item.qty
            ? { qty: compQty.value }
            : {};
    const body = { reason, expected_version: v, ...compFields, ...pinFields };
    const ok =
        ctx.kind === 'item_cancel' ? await runOp(`/api/v1/orders/${orderId}/items/${ctx.item!.id}/cancel`, body, 'Kalem iptal edildi')
        : ctx.kind === 'item_comp' ? await runOp(`/api/v1/orders/${orderId}/items/${ctx.item!.id}/comp`, body, 'İkram edildi')
        : ctx.kind === 'order_cancel' ? await runOp(`/api/v1/orders/${orderId}/cancel`, body, 'Adisyon iptal edildi')
        : await runOp(`/api/v1/orders/${orderId}/refund`, body, 'İade kaydedildi');
    if (ok) {
        reasonModal.value = null;
        anyModalOpen.value = false;
    } else if (isTerminal.value) {
        // PIN reddi vb. → neden modalını geri aç, tekrar denensin.
        reasonModal.value = ctx;
        reasonText.value = reason;
        anyModalOpen.value = true;
    }
}

/* ================= Sipariş düzeyi işlemler ================= */
async function requestBill(): Promise<void> {
    await runOp(`/api/v1/orders/${orderId}/request-bill`, {}, 'Kasaya gönderildi');
}

async function approveOrder(): Promise<void> {
    await runOp(`/api/v1/orders/${orderId}/approve`, {}, 'Sipariş onaylandı');
}

/* Mutfağa gönder: gönderilmemiş (placed) kalemler sent_to_station olur → KDS'e düşer.
   Bu ana kadar kalemler serbestçe düzeltilebilir/silinebilir (kazara ekleme mutfağa
   gitmez). Gönderilmemiş kalem sayısı butonu ve "Gönderilmedi" rozetini besler. */
const unsentCount = computed(
    () => order.value?.items.filter((i) => i.is_active && i.status === 'placed').reduce((n, i) => n + i.qty, 0) ?? 0,
);

async function sendToKitchen(): Promise<void> {
    await runOp(`/api/v1/orders/${orderId}/send-to-kitchen`, {}, 'Kalemler hazırlığa gönderildi');
}

/* Ödeme — bu ekranda PARA ALINMAZ (kasa ekranının işi). Eski "Ödeme al"
 * modalı ve openPay/submitPay şablondan HİÇ çağrılmıyordu (erişilemez ölü
 * kod) → kaldırıldı; adisyon "Ödemeye gönder" ile kasaya düşer.
 * parseAmountMinor indirim alanında hâlâ kullanılıyor. */
function parseAmountMinor(text: string): number {
    // Türkçe: nokta binlik, virgül ondalık. "1.234"→123400, "12,50"→1250, "12.5"→1250.
    let s = text.replace(/\s/g, '');
    if (s.includes(',')) {
        s = s.replace(/\./g, '').replace(',', '.');
    } else if (s.includes('.')) {
        const parts = s.split('.');
        const isThousands = parts.length > 1 && parts.slice(1).every((p) => /^\d{3}$/.test(p));
        if (isThousands) s = parts.join('');
    }
    const value = Number(s);
    return Number.isFinite(value) ? Math.round(value * 100) : 0;
}

/* ---- Kişi sayısı + adisyon notu (sonradan düzeltilebilir) ----
 * Bu iki alan yalnız adisyon açılırken giriliyordu; masaya biri katıldığında
 * ya da mutfağa iletilecek bir not çıktığında düzeltmek mümkün değildi. */
const infoModal = ref(false);
const infoGuests = ref('');
const infoNote = ref('');

function openGuestCount(): void {
    infoGuests.value = order.value?.guest_count ? String(order.value.guest_count) : '';
    infoNote.value = order.value?.note ?? '';
    infoModal.value = true;
    anyModalOpen.value = true;
}

async function submitInfo(): Promise<void> {
    const raw = infoGuests.value.trim();
    const guests = raw === '' ? null : Number(raw);
    if (guests !== null && (!Number.isInteger(guests) || guests < 1 || guests > 200)) {
        danger('Kişi sayısı geçersiz', '1–200 arası bir sayı girin ya da boş bırakın.');
        return;
    }
    const ok = await runOp(`/api/v1/orders/${orderId}/info`, {
        guest_count: guests,
        note: infoNote.value.trim() || null,
        expected_version: order.value?.version,
    }, 'Adisyon bilgisi güncellendi', 'PUT');
    if (ok) {
        infoModal.value = false;
        anyModalOpen.value = false;
    }
}

/* ---- İndirim: hazır tanımlar + serbest (ortak diyalog) ----
 * Eski "İndirim uygula" modalı yalnız serbest giriş sunuyordu; hazır
 * tanımlar (şehit/gazi yakını, kamu personeli…) ve kaldırma yoktu. */
const discountDialogOpen = ref(false);
function openDiscountDialog(): void {
    discountDialogOpen.value = true;
    anyModalOpen.value = true;
}
function closeDiscountDialog(): void {
    discountDialogOpen.value = false;
    anyModalOpen.value = false;
}
async function onDiscountChanged(): Promise<void> {
    closeDiscountDialog();
    await load(true);
}

/* ---- Kalemi değiştir (kasa ekranıyla ORTAK bileşen) ---- */
const editItemTarget = ref<OrderItemRow | null>(null);
function openEditItem(item: OrderItemRow): void {
    editItemTarget.value = item;
    anyModalOpen.value = true;
}
function closeEditItem(): void {
    editItemTarget.value = null;
    anyModalOpen.value = false;
}
async function onItemSaved(): Promise<void> {
    closeEditItem();
    await load(true);
}
/** Varyant değişimi sunucuda desteklenmiyor → çıkar + yeniden ekle akışı. */
function onItemReplace(item: { id: number }): void {
    const row = activeItems.value.find((i) => i.id === item.id);
    closeEditItem();
    if (row) void removeItem(row);
}

/* ---- Hesap fişi (ön-hesap) — kasa ekranındaki fişle AYNI bileşen ---- */
const billPrint = usePaymentReceiptPrint();

function printBill(): void {
    const o = order.value;
    if (!o) return;

    const lines: PaymentReceiptLine[] = activeItems.value.map((it) => ({
        qty: it.qty,
        name: it.name,
        variant: it.variant_name,
        options: it.options.map((op) => op.option_name),
        note: it.note,
        isComp: it.is_comp,
        lineTotalMinor: it.is_comp ? 0 : it.line_total_minor,
        unitPriceMinor: it.unit_price_minor + it.options_price_minor,
    }));

    billPrint.print({
        business: receiptBusiness,
        branch: receiptBranch.value,
        kind: 'bill',
        orderNo: o.id,
        destination: o.table_name ?? o.customer_name ?? o.channel_label,
        serviceType: o.service_type_label,
        guestCount: o.guest_count,
        time: formatReceiptTime(o.created_at),
        lines,
        itemsTotalMinor: o.items_total_minor,
        compTotalMinor: o.comp_total_minor,
        discountMinor: o.discount_minor,
        serviceChargeMinor: 0,
        roundingMinor: 0,
        totalMinor: o.total_minor,
        vatTotalMinor: o.vat_total_minor,
        paidMinor: o.paid_minor,
        remainingMinor: o.remaining_minor,
        changeTotalMinor: 0,
        payments: [],
    });
}

/* İndirim */
const discountModal = ref(false);
const dType = ref<string>('percent');
const dValue = ref('');
const dReason = ref('');
const dApproverEmail = ref('');
const dApproverPin = ref('');

const discountNeedsApproval = computed(() => {
    if (!order.value) return false;
    const itemsTotal = order.value.items_total_minor;
    if (itemsTotal <= 0) return false;
    if (dType.value === 'percent') return Number(dValue.value.replace(',', '.')) > meta.discountApprovalPercent;
    return (parseAmountMinor(dValue.value) * 100) / itemsTotal > meta.discountApprovalPercent;
});

function openDiscount(): void {
    dType.value = 'percent';
    dValue.value = '';
    dReason.value = '';
    dApproverEmail.value = '';
    dApproverPin.value = '';
    discountModal.value = true;
    anyModalOpen.value = true;
}

async function submitDiscount(): Promise<void> {
    const value = dType.value === 'percent' ? Number(dValue.value.replace(',', '.')) : parseAmountMinor(dValue.value);
    const ok = await runOp(`/api/v1/orders/${orderId}/discount`, {
        type: dType.value,
        value,
        reason: dReason.value,
        approver_email: dApproverEmail.value || null,
        approver_pin: dApproverPin.value || null,
        expected_version: order.value?.version,
    }, 'İndirim uygulandı');
    if (ok) {
        discountModal.value = false;
        anyModalOpen.value = false;
    }
}

/* Taşı (adisyon ya da kalem) */
const moveModal = ref<{ item?: OrderItemRow } | null>(null);
const moveTables = ref<BoardTable[]>([]);
const moveTarget = ref('');

async function openMove(item?: OrderItemRow): Promise<void> {
    moveModal.value = { item };
    moveTarget.value = '';
    anyModalOpen.value = true;
    try {
        const board = await fetchBoard(order.value?.branch_id ?? null);
        moveTables.value = board.tables.filter((t) => t.id !== order.value?.table_id);
    } catch {
        moveTables.value = [];
    }
}

const moveOptions = computed(() =>
    moveTables.value.map((t) => ({
        value: String(t.id),
        label: `${t.name}${t.orders.length > 0 ? ` (açık adisyon: ${t.orders.length})` : ''} — ${t.status_label}`,
    })),
);

async function submitMove(): Promise<void> {
    const ctx = moveModal.value;
    if (!ctx || !moveTarget.value) return;
    const body = { table_id: Number(moveTarget.value), expected_version: order.value?.version };
    const ok = ctx.item
        ? await runOp(`/api/v1/orders/${orderId}/items/${ctx.item.id}/move`, body, 'Kalem taşındı')
        : await runOp(`/api/v1/orders/${orderId}/move`, body, 'Adisyon taşındı');
    if (ok) {
        moveModal.value = null;
        anyModalOpen.value = false;
    }
}

/* Birleştir */
const mergeModal = ref(false);
const mergeOrders = ref<OrderSummary[]>([]);
const mergeSource = ref('');

async function openMerge(): Promise<void> {
    mergeModal.value = true;
    anyModalOpen.value = true;
    mergeSource.value = '';
    try {
        const res = await api<{ orders: { data: OrderSummary[] } }>(`/api/v1/orders?open=1&branch_id=${order.value?.branch_id ?? ''}&per_page=200`);
        mergeOrders.value = res.orders.data.filter((o) => o.id !== orderId);
    } catch {
        mergeOrders.value = [];
    }
}

const mergeOptions = computed(() =>
    mergeOrders.value.map((o) => ({
        value: String(o.id),
        label: `#${o.id} — ${o.table_name ?? o.channel_label} · ${o.items_count} kalem · ${o.total_display} ₺`,
    })),
);

async function submitMerge(): Promise<void> {
    if (!mergeSource.value) return;
    const ok = await runOp(`/api/v1/orders/${orderId}/merge`, {
        source_order_id: Number(mergeSource.value),
        expected_version: order.value?.version,
    }, 'Adisyonlar birleştirildi');
    if (ok) {
        mergeModal.value = false;
        anyModalOpen.value = false;
    }
}

/* Borca taşı (Borçlar/Cari) — açık ama ödenmemiş adisyonu bir cariye
   atar: adisyon 'debt_transferred' terminal durumuna geçer (paid DEĞİL),
   masa boşalır. Bkz. resources/js/Pages/Panel/Receivables. */
const debtModal = ref(false);
const debtReceivables = ref<ReceivableOption[]>([]);
const debtReceivableId = ref('');
const debtReason = ref('');
const debtNewName = ref('');
const debtNewPhone = ref('');
const debtCreatingNew = ref(false);
const debtBusy = ref(false);

async function openDebtTransfer(): Promise<void> {
    debtModal.value = true;
    anyModalOpen.value = true;
    debtReceivableId.value = '';
    debtReason.value = '';
    debtNewName.value = '';
    debtNewPhone.value = '';
    debtCreatingNew.value = false;
    try {
        debtReceivables.value = await fetchActiveReceivables();
    } catch {
        debtReceivables.value = [];
    }
}

const debtOptions = computed(() =>
    debtReceivables.value.map((r) => ({ value: String(r.id), label: `${r.name}${r.phone ? ' · ' + r.phone : ''} — bakiye ${money(r.balance_minor)} ₺` })),
);

async function submitDebtTransfer(): Promise<void> {
    if (debtBusy.value || !debtReason.value.trim()) return;
    debtBusy.value = true;
    try {
        let receivableId = debtReceivableId.value;

        if (debtCreatingNew.value) {
            if (!debtNewName.value.trim()) {
                danger('Cari adı gerekli', '');
                debtBusy.value = false;
                return;
            }
            const created = await api<{ receivable: { id: number } }>('/api/v1/receivables', {
                method: 'POST',
                body: { name: debtNewName.value.trim(), phone: debtNewPhone.value || null },
            });
            receivableId = String(created.receivable.id);
        }

        if (!receivableId) {
            danger('Cari seçilmedi', 'Var olan bir cari seçin ya da yeni cari oluşturun.');
            debtBusy.value = false;
            return;
        }

        const ok = await runOp(`/api/v1/orders/${orderId}/transfer-to-debt`, {
            receivable_id: Number(receivableId),
            reason: debtReason.value.trim(),
            expected_version: order.value?.version,
        }, 'Adisyon borca taşındı');

        if (ok) {
            debtModal.value = false;
            anyModalOpen.value = false;
        }
    } catch (e) {
        danger('Borca taşınamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        debtBusy.value = false;
    }
}

/* Böl */
const splitModal = ref(false);
const splitMode = ref<string>('items');
const splitItems = ref<Set<number>>(new Set());
const splitWays = ref('2');
const splitAmounts = ref('');
const splitShares = ref<number[] | null>(null);

function openSplit(): void {
    splitMode.value = 'items';
    splitItems.value = new Set();
    splitWays.value = '2';
    splitAmounts.value = '';
    splitShares.value = null;
    splitModal.value = true;
    anyModalOpen.value = true;
}

function toggleSplitItem(id: number, value: boolean): void {
    const next = new Set(splitItems.value);
    if (value) next.add(id);
    else next.delete(id);
    splitItems.value = next;
}

async function submitSplit(): Promise<void> {
    if (opBusy.value) return;
    opBusy.value = true;
    try {
        const body: Record<string, unknown> = { mode: splitMode.value, expected_version: order.value?.version };
        if (splitMode.value === 'items') body.item_ids = [...splitItems.value];
        if (splitMode.value === 'equal') body.ways = Number(splitWays.value);
        if (splitMode.value === 'persons') {
            body.amounts = splitAmounts.value.split(/[,;\n]+/).map((s) => parseAmountMinor(s.trim())).filter((n) => n > 0);
        }
        const res = await api<{ order: OrderDetail; new_order?: OrderSummary; shares_minor?: number[] }>(
            `/api/v1/orders/${orderId}/split`,
            { method: 'POST', body },
        );
        order.value = res.order;
        if (res.new_order) {
            success('Adisyon bölündü', `Seçilen kalemler yeni adisyona (#${res.new_order.id}) ayrıldı.`);
            splitModal.value = false;
            anyModalOpen.value = false;
        } else if (res.shares_minor) {
            splitShares.value = res.shares_minor;
            success('Paylar hesaplandı', 'Kuruş kaybı olmadan bölündü.');
        }
    } catch (e) {
        danger('Bölünemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        opBusy.value = false;
    }
}

function closeModal(refFn: () => void): void {
    refFn();
    anyModalOpen.value = false;
}

/* ================= Görünüm yardımcıları ================= */
const activeItems = computed(() => order.value?.items.filter((i) => i.is_active) ?? []);
const inactiveItems = computed(() => order.value?.items.filter((i) => !i.is_active) ?? []);

/**
 * Kalem satırının sol renk şeridi — hazırlık zincirindeki yeri renkten okunur:
 * turuncu = henüz mutfağa gönderilmedi, mavi = hazırlanıyor, yeşil = hazır,
 * gri = servis edildi, mor-mavi = ikram. Sınıf dizeleri TAM yazılır
 * (Tailwind kaynak taraması parçalı dizeyi göremez).
 */
function itemStripe(item: OrderItemRow): string {
    if (item.is_comp) return 'bg-info';
    if (item.status === 'placed') return 'bg-warning';
    if (item.status === 'ready') return 'bg-success';
    if (item.status === 'served') return 'bg-strong';
    return 'bg-info';
}

/** Adisyondaki toplam ürün adedi (kalem sayısı değil, adetlerin toplamı). */
const totalQty = computed(() => activeItems.value.reduce((n, i) => n + i.qty, 0));

/**
 * Son sipariş hareketi: en yeni "kalem eklendi" olayı; yoksa adisyonun
 * `placed_at`/`created_at`'i. Masaya en son ne zaman bir şey girildiğini
 * gösterir (unutulmuş masa yakalanır).
 */
const lastItemIso = computed<string | null>(() => {
    const evs = order.value?.events ?? [];
    let best: string | null = null;
    for (const e of evs) {
        if (e.type !== 'item_added') continue;
        if (e.created_at && (best === null || e.created_at > best)) best = e.created_at;
    }
    return best ?? order.value?.placed_at ?? order.value?.created_at ?? null;
});

/** Son siparişin üzerinden 30 dk+ geçtiyse "son sipariş" turuncuya döner. */
const staleOrder = computed(() => {
    const iso = lastItemIso.value;
    if (!iso || !order.value?.is_open) return false;
    return Date.now() - new Date(iso).getTime() > 30 * 60 * 1000;
});

/**
 * Görseli olmayan ürün için monogram: adın ilk harfi + kategori rengiyle
 * tonlanmış zemin. Boş gri bir kutu yerine kart hem dolu görünür hem de
 * kategoriye göre renkten tanınır. Renk yalnız güvenli hex kabul edilir
 * (katalogdan gelen serbest metin doğrudan stile yazılmaz).
 */
function monogram(p: CatalogProduct): string {
    return (p.name.trim()[0] ?? '•').toLocaleUpperCase('tr-TR');
}

const HEX_RE = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i;

function monogramStyle(p: CatalogProduct): Record<string, string> {
    const color = catalog.value.categories.find((c) => c.id === p.category_id)?.color ?? '';
    if (!HEX_RE.test(color)) {
        return { backgroundColor: 'var(--ui-surface-inset)', color: 'var(--ui-text-subtle)' };
    }
    // Aynı renk hem zemin (düşük opaklık) hem yazı → her temada okunur kalır.
    return { backgroundColor: `color-mix(in srgb, ${color} 18%, transparent)`, color };
}

/** Kategori (ve alt kategorileri) başına ürün adedi — sekme sayacı. */
function categoryCount(categoryId: number): number {
    const ids = categoryTreeIds(categoryId);
    return catalog.value.products.filter((p) => p.category_id !== null && ids.has(p.category_id)).length;
}

/**
 * Ürün kartındaki fiyat etiketi: varyantlı üründe TEK fiyat yanıltıcıdır
 * (referans ekranda "₺210,00 - ₺370,00" gibi aralık gösteriliyor), bu yüzden
 * birden çok varyant varsa en düşük–en yüksek aralık yazılır.
 */
function priceLabel(p: CatalogProduct): string {
    if (p.variants.length > 1) {
        const prices = p.variants.map((v) => v.price_minor);
        const lo = Math.min(...prices);
        const hi = Math.max(...prices);
        if (lo !== hi) return `${money(lo)} – ${money(hi)}`;
        return money(lo);
    }
    return money(productPrice(p));
}


const eventTypeLabels: Record<string, string> = {
    opened: 'Adisyon açıldı',
    item_added: 'Kalem eklendi',
    item_updated: 'Kalem güncellendi',
    item_removed: 'Kalem çıkarıldı',
    item_cancelled: 'Kalem iptal',
    item_comped: 'İkram',
    item_status_changed: 'Kalem durumu',
    item_moved_in: 'Kalem geldi',
    item_moved_out: 'Kalem taşındı',
    status_changed: 'Durum değişti',
    status_derived: 'Durum güncellendi',
    discount_applied: 'İndirim',
    payment_recorded: 'Ödeme',
    cancelled: 'İptal',
    refunded: 'İade',
    order_moved: 'Adisyon taşındı',
    merged_from: 'Birleştirildi (alındı)',
    merged_into: 'Birleştirildi',
    split_out: 'Bölündü',
    split_from: 'Bölünerek açıldı',
    split_shares: 'Hesap payları',
    // Payments modülü (Faz-5) olayları
    payment_reversed: 'Ödeme iptal (void)',
    refund_applied: 'İade işlendi',
    service_charge_applied: 'Servis bedeli',
    rounding_applied: 'Yuvarlama',
};
</script>

<template>
    <Head :title="order ? `Adisyon #${order.id}` : 'Adisyon'" />

    <!-- ================= SATIŞ / SİPARİŞ EKRANI =================
         Artık PanelShell DEĞİL: Masa panosu (Board.vue), Mutfak, Komi ve Kasa
         ile AYNI tam ekran terminal kabuğu (kds-canvas + TerminalTopBar).
         Panodan adisyona geçerken kabuk değişmiyor — sipariş almak tek
         bir POS yüzeyi.

         Yerleşim (xl+): SOL ürün seçme alanı (arama + kategoriler + ızgara),
         SAĞ sabit adisyon paneli (başlık · sepet/geçmiş · toplamlar · eylem).
         Sayfa kaymaz; her kolon kendi içinde kayar. -->
    <div class="kds-canvas fixed inset-0 flex flex-col overflow-hidden text-body">
        <TerminalTopBar
            screen-label="Sipariş Ekranı"
            :theme="kdsTheme.theme.value"
            @toggle-theme="kdsTheme.toggle()"
            @open-nav="showNav = true"
        >
            <template #status>
                <span
                    v-if="order"
                    class="ml-1 inline-flex min-w-0 shrink items-center gap-1.5 rounded-full border border-default bg-inset px-2.5 py-1 text-xs font-semibold text-muted"
                >
                    <AppIcon :name="order.channel_icon" :size="13" class="shrink-0" />
                    <span class="truncate">{{ order.table_name ?? order.customer_name ?? `#${order.id}` }}</span>
                    <span class="shrink-0 text-subtle">#{{ order.id }}</span>
                </span>
            </template>

            <template #actions>
                <template v-if="order">
                    <BaseButton v-if="order.status === 'pending_approval' && can('orders.update')" size="sm" :loading="opBusy" @click="approveOrder">
                        <AppIcon name="check" :size="14" /> Siparişi onayla
                    </BaseButton>

                    <!-- Hazırlığa gönder: gönderilmemiş (placed) kalemleri KDS'e yollar. -->
                    <BaseButton
                        v-if="order.status !== 'pending_approval' && order.is_open && unsentCount > 0 && can('orders.update')"
                        size="sm"
                        :loading="opBusy"
                        @click="sendToKitchen"
                    >
                        <AppIcon name="utensils" :size="14" /> Hazırlığa gönder ({{ unsentCount }})
                    </BaseButton>

                    <span
                        v-if="order.status === 'bill_requested'"
                        class="inline-flex items-center gap-1.5 rounded-full border border-warning-border bg-warning-soft px-2.5 py-1 text-xs font-semibold text-warning"
                    >
                        <AppIcon name="clock" :size="13" /> Kasada bekliyor
                    </span>

                    <!-- İşlemler menüsü ARTIK sağ panelin araç çubuğunda (adisyonun
                         hemen üstünde) — üst çubukta yalnız akışı ilerleten ana
                         eylemler kalır; aynı menü iki yerde tekrar etmez. -->
                </template>
            </template>
        </TerminalTopBar>

        <main class="min-h-0 flex-1 overflow-y-auto p-3 xl:overflow-hidden xl:p-0">
            <div
                v-if="order"
                class="flex flex-col gap-3 xl:grid xl:h-full xl:grid-cols-[minmax(0,1fr)_minmax(380px,440px)] xl:gap-0"
            >
                <!-- ============ SOL: ürün seçme (arama + kategori + ızgara) ============ -->
                <section
                    v-if="order.is_open"
                    class="flex min-h-0 flex-col rounded-lg border border-default bg-raised xl:rounded-none xl:border-0 xl:border-e xl:border-default"
                >
                    <!-- Arama şeridi (referans ekrandaki üst "Ürün Ara" ile aynı yer)
                         + anlık sonuç sayısı: aramanın bir şey bulup bulmadığı
                         ızgaraya bakmadan görünür. -->
                    <div class="flex items-center gap-3 border-b border-default p-3">
                        <div class="min-w-0 grow">
                            <SearchInput v-model="search" placeholder="Ürün ara…" />
                        </div>
                        <span class="hidden shrink-0 items-center gap-1.5 rounded-full border border-default bg-inset px-2.5 py-1 text-xs font-semibold text-muted sm:inline-flex">
                            <AppIcon name="utensils" :size="12" class="text-subtle" />
                            <span class="tabular-nums">{{ visibleProducts.length }}</span> ürün
                        </span>
                    </div>

                    <!-- Kategoriler: ana satır + (varsa) alt kategori satırı.
                         Alt kategori tanımlanmamış işletmede ikinci satır hiç
                         çizilmez — düz liste bugünküyle birebir aynı. -->
                    <div class="flex flex-col gap-1.5 border-b border-default px-3 py-2">
                        <div class="flex flex-wrap gap-1.5" role="tablist" aria-label="Kategoriler">
                            <button
                                type="button"
                                class="rounded-full border px-3 py-1.5 text-sm font-semibold transition-colors"
                                :class="activeCategory === 0 ? 'border-transparent bg-primary text-on-primary' : 'border-default text-muted hover:bg-inset'"
                                @click="selectCategory(0)"
                            >
                                Tümü
                                <span class="ms-1 text-xs opacity-80 tabular-nums">{{ catalog.products.length }}</span>
                            </button>
                            <button
                                v-for="c in mainCategories"
                                :key="c.id"
                                type="button"
                                class="rounded-full border px-3 py-1.5 text-sm font-semibold transition-colors"
                                :class="activeCategory === c.id ? 'border-transparent bg-primary text-on-primary' : 'border-default text-muted hover:bg-inset'"
                                @click="selectCategory(c.id)"
                            >
                                {{ c.name }}
                                <span class="ms-1 text-xs opacity-80 tabular-nums">{{ categoryCount(c.id) }}</span>
                            </button>
                        </div>

                        <!-- Alt kategoriler: alt çizgili sade sekmeler (referans ekrandaki
                             ikinci satır); ana kategoriden görsel olarak ayrışır. -->
                        <div v-if="subCategories.length > 0" class="flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-default pt-1.5">
                            <button
                                type="button"
                                class="border-b-2 px-1 py-1 text-sm font-medium transition"
                                :class="activeSubCategory === 0 ? 'border-primary text-primary' : 'border-transparent text-muted hover:text-body'"
                                @click="activeSubCategory = 0"
                            >
                                Tümü
                            </button>
                            <button
                                v-for="sc in subCategories"
                                :key="sc.id"
                                type="button"
                                class="border-b-2 px-1 py-1 text-sm font-medium transition"
                                :class="activeSubCategory === sc.id ? 'border-primary text-primary' : 'border-transparent text-muted hover:text-body'"
                                @click="activeSubCategory = sc.id"
                            >
                                {{ sc.name }}
                                <span class="ms-0.5 text-xs text-subtle tabular-nums">{{ categoryCount(sc.id) }}</span>
                            </button>
                        </div>
                    </div>

                    <!-- Ürün ızgarası: GÖRSEL ÖNDE kartlar. Önceki düzende kart
                         geniş, görsel 36px'lik bir küçük kutuydu — ürün göze
                         çarpmıyordu. Artık üstte 4:3 görsel bandı, altında ad ve
                         fiyat; kartlar daralıp sütun sayısı arttı (aynı alanda
                         daha çok ürün, daha az kaydırma).
                         Görseli olmayan üründe band boş gri kalmaz: kategori
                         rengiyle tonlanmış bir monogram gösterilir. -->
                    <div class="min-h-0 p-3 xl:flex-1 xl:overflow-y-auto">
                        <div
                            v-if="visibleProducts.length > 0"
                            class="grid max-h-[46vh] grid-cols-3 gap-2.5 overflow-y-auto sm:grid-cols-4 xl:max-h-none xl:overflow-visible xl:grid-cols-4 2xl:grid-cols-5"
                        >
                            <button
                                v-for="p in visibleProducts"
                                :key="p.id"
                                type="button"
                                class="group flex flex-col overflow-hidden rounded-xl border border-default bg-raised text-left shadow-sm transition hover:-translate-y-0.5 hover:border-primary hover:shadow-card disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:translate-y-0"
                                :disabled="!p.is_available || addBusy"
                                :aria-label="p.is_available ? `${p.name} ekle` : `${p.name} tükendi`"
                                @click="onProductClick(p)"
                            >
                                <!-- Görsel bandı -->
                                <div class="relative aspect-[4/3] w-full overflow-hidden bg-inset">
                                    <img
                                        v-if="p.image_url && !brokenImages.has(p.id)"
                                        :src="p.image_url"
                                        :alt="p.name"
                                        loading="lazy"
                                        class="size-full object-cover transition duration-(--dur-normal) group-hover:scale-105"
                                        @error="onProductImageError(p.id)"
                                    />
                                    <span
                                        v-else
                                        class="flex size-full items-center justify-center text-xl font-black uppercase"
                                        :style="monogramStyle(p)"
                                    >
                                        {{ monogram(p) }}
                                    </span>

                                    <!-- Seçenekli ürün göstergesi (sağ üst) -->
                                    <span
                                        v-if="p.is_available && (p.option_groups.length > 0 || p.variants.length > 1)"
                                        class="absolute end-1.5 top-1.5 flex size-6 items-center justify-center rounded-full bg-warning text-on-status shadow-sm"
                                        title="Seçenekli ürün — varyant/ek seçim sorulur"
                                    >
                                        <AppIcon name="dashboard" :size="13" />
                                    </span>

                                    <!-- Tükendi perdesi -->
                                    <span
                                        v-if="!p.is_available"
                                        class="absolute inset-0 flex items-center justify-center bg-overlay/60 text-xs font-bold uppercase tracking-wide text-invert"
                                    >
                                        Tükendi
                                    </span>
                                </div>

                                <!-- Ad + fiyat -->
                                <div class="flex flex-1 flex-col gap-1 px-2.5 py-2">
                                    <span class="line-clamp-2 text-[13px] font-semibold leading-snug text-body">{{ p.name }}</span>
                                    <span class="mt-auto whitespace-nowrap text-sm font-bold tabular-nums text-primary">{{ priceLabel(p) }} ₺</span>
                                </div>
                            </button>
                        </div>
                        <EmptyState v-else title="Ürün bulunamadı" description="Arama ya da kategori filtresini değiştirin." icon="search" />
                    </div>
                </section>

                <!-- ============ SAĞ: adisyon paneli ============ -->
                <section
                    class="flex min-h-0 flex-col rounded-lg border border-default bg-raised xl:rounded-none xl:border-0"
                    :class="order.is_open ? '' : 'xl:col-span-2'"
                >
                    <!-- Başlık: masa/müşteri + açılış saati · masa süresi · son sipariş.
                         Panel baştan sona tek renkti ve bölümler birbirine karışıyordu;
                         başlık artık hafif markalı bir zeminde durur, altındaki liste
                         beyaz/yüzey renginde kalır → göz bölümleri ayırır. -->
                    <div class="border-b border-default bg-primary-soft/40 px-4 py-3">
                        <div class="flex flex-wrap items-start justify-between gap-2">
                            <!-- "Panoya dön" oku KALDIRILDI: gezinme menü çekmecesinde
                                 ve hesap menüsünde zaten var, başlıkta yer harcıyordu. -->
                            <div class="flex min-w-0 items-center gap-2">
                                <div class="min-w-0">
                                    <p class="truncate text-lg font-bold text-primary">
                                        {{ order.table_name ?? order.customer_name ?? `#${order.id}` }}
                                        <span class="text-sm font-semibold text-subtle">({{ String(order.id).padStart(3, '0') }})</span>
                                    </p>
                                    <p class="flex flex-wrap items-center gap-x-2 text-xs text-muted">
                                        <span>{{ order.source_label }}</span>
                                        <span aria-hidden="true">·</span>
                                        <span>{{ order.service_type_label }}</span>
                                        <template v-if="order.opened_by">
                                            <span aria-hidden="true">·</span>
                                            <span class="truncate">{{ order.opened_by }}</span>
                                        </template>
                                    </p>
                                </div>
                            </div>
                            <div class="flex shrink-0 flex-col items-center rounded-lg border border-primary-soft-border bg-raised px-2.5 py-1">
                                <span class="text-[10.5px] font-medium uppercase tracking-wide text-subtle">Ürün</span>
                                <span class="text-lg font-bold leading-none tabular-nums text-primary">{{ totalQty }}</span>
                            </div>
                        </div>

                        <!-- Açılış / masa süresi / son sipariş: üç ayrı kutu, her biri
                             kendi ikonu ve rengiyle (düz gri şeritte üçü birbirine
                             karışıyordu). -->
                        <div class="mt-2.5 grid grid-cols-3 gap-1.5">
                            <div class="rounded-lg border border-default bg-raised px-2 py-1.5 text-center">
                                <p class="flex items-center justify-center gap-1 text-[10.5px] font-medium uppercase tracking-wide text-subtle">
                                    <AppIcon name="clock" :size="11" /> Açılış
                                </p>
                                <p class="text-sm font-bold tabular-nums text-body">{{ clockTime(order.created_at) }}</p>
                            </div>
                            <div class="rounded-lg border border-info-border bg-info-soft px-2 py-1.5 text-center">
                                <p class="flex items-center justify-center gap-1 text-[10.5px] font-medium uppercase tracking-wide text-info">
                                    <AppIcon name="gauge" :size="11" /> Süre
                                </p>
                                <p class="text-sm font-bold tabular-nums text-info">{{ orderElapsed(order) }}</p>
                            </div>
                            <div
                                class="rounded-lg border px-2 py-1.5 text-center"
                                :class="staleOrder ? 'border-warning-border bg-warning-soft' : 'border-default bg-raised'"
                                :title="staleOrder ? 'Son siparişin üzerinden 30 dakikadan fazla geçti' : 'Son sipariş saati'"
                            >
                                <p
                                    class="flex items-center justify-center gap-1 text-[10.5px] font-medium uppercase tracking-wide"
                                    :class="staleOrder ? 'text-warning' : 'text-subtle'"
                                >
                                    <AppIcon name="refresh-cw" :size="11" /> Son
                                </p>
                                <p class="text-sm font-bold tabular-nums" :class="staleOrder ? 'text-warning' : 'text-body'">
                                    {{ clockTime(lastItemIso) }}
                                </p>
                            </div>
                        </div>

                        <div class="mt-2 flex flex-wrap items-center gap-1.5">
                            <BaseBadge :variant="order.status_variant" no-icon>
                                <AppIcon :name="order.status_icon" :size="12" /> {{ order.status_label }}
                            </BaseBadge>
                            <BaseBadge v-if="order.items_count > 0 && order.served_count < order.items_count" variant="neutral" no-icon>
                                <AppIcon name="utensils" :size="12" /> {{ order.served_count }}/{{ order.items_count }} servis
                            </BaseBadge>
                            <BaseBadge v-if="order.guest_count" variant="neutral" no-icon>
                                <AppIcon name="users" :size="12" /> {{ order.guest_count }} kişi
                            </BaseBadge>
                            <BaseBadge
                                :variant="order.payment_state === 'paid' ? 'success' : order.payment_state === 'partial' ? 'warning' : 'neutral'"
                                no-icon
                            >
                                <AppIcon :name="order.payment_state === 'paid' ? 'check-circle' : 'cart'" :size="12" />
                                {{ order.payment_label }}
                            </BaseBadge>
                        </div>
                        <p v-if="order.note" class="mt-2 flex items-start gap-1.5 rounded-md bg-warning-soft px-2.5 py-1.5 text-xs text-warning">
                            <AppIcon name="info" :size="13" class="mt-0.5 shrink-0" />
                            <span class="min-w-0">{{ order.note }}</span>
                        </p>
                    </div>

                    <!-- Araç çubuğu: sekmeler + sık eylemler İKON olarak (referans
                         ekrandaki gibi). Yazdır/not/işlemler artık üst çubuğun
                         menüsünde gömülü değil, adisyonun hemen üstünde. -->
                    <div class="flex items-stretch border-b border-default">
                        <button
                            type="button"
                            class="flex flex-1 items-center justify-center gap-1.5 border-b-2 px-3 py-2.5 text-sm font-semibold transition"
                            :class="rightTab === 'cart' ? 'border-primary text-primary' : 'border-transparent text-muted hover:text-body'"
                            :title="`Sepet — ${activeItems.length} kalem`"
                            @click="rightTab = 'cart'"
                        >
                            <AppIcon name="cart" :size="16" />
                            <span class="hidden sm:inline">Sepet</span>
                            <span class="rounded-full bg-inset px-1.5 text-xs tabular-nums">{{ activeItems.length }}</span>
                        </button>
                        <button
                            type="button"
                            class="flex flex-1 items-center justify-center gap-1.5 border-b-2 px-3 py-2.5 text-sm font-semibold transition"
                            :class="rightTab === 'history' ? 'border-primary text-primary' : 'border-transparent text-muted hover:text-body'"
                            :title="`Geçmiş — ${order.events.length} kayıt`"
                            @click="rightTab = 'history'"
                        >
                            <AppIcon name="refresh-cw" :size="16" />
                            <span class="hidden sm:inline">Geçmiş</span>
                            <span class="rounded-full bg-inset px-1.5 text-xs tabular-nums">{{ order.events.length }}</span>
                        </button>

                        <!-- İkon eylemler: yazdır · adisyon notu/kişi · diğer -->
                        <div class="flex items-center gap-0.5 border-s border-default px-1.5">
                            <button
                                type="button"
                                class="flex size-9 items-center justify-center rounded-md text-muted transition hover:bg-inset hover:text-body"
                                title="Hesap fişi yazdır"
                                aria-label="Hesap fişi yazdır"
                                @click="printBill"
                            >
                                <AppIcon name="printer" :size="17" />
                            </button>
                            <button
                                v-if="order.is_open && can('orders.update')"
                                type="button"
                                class="flex size-9 items-center justify-center rounded-md transition hover:bg-inset"
                                :class="order.note ? 'text-warning' : 'text-muted hover:text-body'"
                                :title="order.note ? `Adisyon notu: ${order.note}` : 'Kişi sayısı / adisyon notu'"
                                aria-label="Kişi sayısı / adisyon notu"
                                @click="openGuestCount"
                            >
                                <AppIcon name="note" :size="17" />
                            </button>
                            <BaseDropdown menu-label="Adisyon işlemleri">
                                <template #trigger="{ toggle, ariaAttrs }">
                                    <button
                                        type="button"
                                        v-bind="ariaAttrs"
                                        class="flex size-9 items-center justify-center rounded-md text-muted transition hover:bg-inset hover:text-body"
                                        title="Diğer işlemler"
                                        aria-label="Diğer işlemler"
                                        @click="toggle"
                                    >
                                        <AppIcon name="dots-vertical" :size="17" />
                                    </button>
                                </template>
                                <DropdownItem v-if="order.is_open && can('orders.update')" icon="arrow-right" @click="openMove()">Adisyonu taşı</DropdownItem>
                                <DropdownItem v-if="order.is_open && can('orders.merge_tables')" icon="merge" @click="openMerge">Birleştir</DropdownItem>
                                <DropdownItem v-if="order.is_open && can('orders.update')" icon="split" @click="openSplit">Böl</DropdownItem>
                                <DropdownItem v-if="order.is_open && can('orders.discount')" icon="tag" @click="openDiscountDialog">
                                    {{ order.discount_minor > 0 ? 'İndirimi kaldır' : 'İndirim uygula' }}
                                </DropdownItem>
                                <!-- Borca taşı: YALNIZ borç yetkisi (receivables.transfer =
                                     backend ile birebir; kasiyerde var, garsonda yok). -->
                                <DropdownItem v-if="order.is_open && order.remaining_minor > 0 && can('receivables.transfer')" icon="inbox" @click="openDebtTransfer">
                                    Borca taşı
                                </DropdownItem>
                                <DropdownItem v-if="order.status === 'paid' && can('orders.refund')" icon="arrow-left" danger @click="openReason('order_refund')">
                                    İade et
                                </DropdownItem>
                            </BaseDropdown>
                            <button
                                v-if="order.is_open && order.paid_minor === 0 && can('orders.cancel')"
                                type="button"
                                class="flex size-9 items-center justify-center rounded-md text-muted transition hover:bg-danger-soft hover:text-danger"
                                title="Adisyonu iptal et"
                                aria-label="Adisyonu iptal et"
                                @click="openReason('order_cancel')"
                            >
                                <AppIcon name="trash" :size="17" />
                            </button>
                        </div>
                    </div>

                    <!-- Sekme içeriği -->
                    <div class="max-h-[45vh] min-h-0 overflow-y-auto xl:max-h-none xl:flex-1">
                        <!-- SEPET -->
                        <template v-if="rightTab === 'cart'">
                            <EmptyState v-if="activeItems.length === 0" title="Adisyon boş" description="Soldan ürün seçerek adisyonu açın." icon="orders" />

                            <!-- Kalem satırı: solda DURUM RENGİ şeridi (gönderilmedi turuncu,
                                 hazırlanıyor mavi, hazır yeşil, ikram mor-mavi). Liste tek
                                 renkken hangi kalemin nerede olduğu okunmadan anlaşılmıyordu. -->
                            <div
                                v-for="item in activeItems"
                                :key="item.id"
                                class="relative border-b border-default p-3 ps-4"
                            >
                                <span class="absolute inset-y-0 start-0 w-1" :class="itemStripe(item)" aria-hidden="true"></span>
                                <div class="flex items-start justify-between gap-2">
                                    <div class="min-w-0">
                                        <p class="font-medium text-body">
                                            <span class="font-bold tabular-nums">{{ item.qty }} x</span>
                                            {{ item.name }}
                                            <span v-if="item.variant_name" class="text-sm text-muted">({{ item.variant_name }})</span>
                                        </p>
                                        <p v-if="item.options.length > 0" class="text-xs text-muted">
                                            {{ item.options.map((o) => o.option_name).join(', ') }}
                                        </p>
                                        <p v-if="item.note" class="text-xs italic text-muted">“{{ item.note }}”</p>
                                        <p v-if="item.is_comp" class="text-xs font-medium text-success">İkram — {{ item.comp_reason }}</p>
                                    </div>
                                    <div class="shrink-0 text-right">
                                        <p class="whitespace-nowrap font-semibold tabular-nums text-body" :class="{ 'line-through opacity-60': item.is_comp }">
                                            {{ item.line_total_display }} ₺
                                        </p>
                                        <p class="text-xs text-muted tabular-nums">{{ money(item.unit_price_minor + item.options_price_minor) }} / adet</p>
                                    </div>
                                </div>
                                <div class="flex flex-wrap items-center justify-between gap-2 pt-2">
                                    <div class="flex items-center gap-1.5">
                                        <BaseBadge :variant="item.status_variant" no-icon>
                                            <AppIcon :name="item.status_icon" :size="12" /> {{ item.status_label }}
                                        </BaseBadge>
                                        <!-- Gönderilmemiş (placed) kalem: mutfağa DÜŞMEDİ; net görünsün. -->
                                        <span
                                            v-if="item.status === 'placed'"
                                            class="inline-flex items-center gap-1 rounded-full border border-warning bg-warning-soft px-2 py-0.5 text-[11px] font-semibold text-warning"
                                        >
                                            <AppIcon name="clock" :size="11" /> Gönderilmedi
                                        </span>
                                    </div>
                                    <div v-if="order.is_open" class="flex items-center gap-1">
                                        <template v-if="item.status === 'placed' && !item.is_comp">
                                            <!-- Adet: yön okları yerine −/+ (dokunmatikte anlamı net) -->
                                            <div class="flex items-center overflow-hidden rounded-md border border-strong">
                                                <button
                                                    type="button"
                                                    class="flex size-8 items-center justify-center text-body transition hover:bg-inset disabled:opacity-40"
                                                    :disabled="item.qty <= 1"
                                                    aria-label="Adet azalt"
                                                    @click="changeQty(item, -1)"
                                                >
                                                    <AppIcon name="minus" :size="15" />
                                                </button>
                                                <span class="min-w-8 px-1 text-center text-sm font-semibold tabular-nums text-body">{{ item.qty }}</span>
                                                <button
                                                    type="button"
                                                    class="flex size-8 items-center justify-center text-body transition hover:bg-inset"
                                                    aria-label="Adet artır"
                                                    @click="changeQty(item, 1)"
                                                >
                                                    <AppIcon name="plus" :size="15" />
                                                </button>
                                            </div>
                                        </template>
                                        <!-- Komi rolü yoksa garson buradan servis edebilsin —
                                             yalnız 'hazır' kalem, yalnız kds.deliver izniyle. -->
                                        <BaseButton
                                            v-if="item.status === 'ready' && can('kds.deliver')"
                                            size="sm"
                                            variant="secondary"
                                            :loading="opBusy"
                                            @click="serveItem(item)"
                                        >
                                            <AppIcon name="utensils" :size="14" /> Servis edildi
                                        </BaseButton>
                                        <BaseDropdown menu-label="Kalem işlemleri">
                                            <template #trigger="{ toggle, ariaAttrs }">
                                                <button
                                                    type="button"
                                                    v-bind="ariaAttrs"
                                                    class="flex size-8 items-center justify-center rounded-md text-muted hover:bg-inset hover:text-body"
                                                    aria-label="Kalem işlemleri"
                                                    @click="toggle"
                                                >
                                                    <AppIcon name="dots-vertical" :size="16" />
                                                </button>
                                            </template>
                                            <DropdownItem v-if="item.status === 'placed' && can('orders.update')" icon="pencil" @click="openEditItem(item)">
                                                Değiştir (seçenek/adet/not)
                                            </DropdownItem>
                                            <DropdownItem icon="pencil" @click="openNote(item)">Not ekle / düzenle</DropdownItem>
                                            <DropdownItem v-if="can('orders.update')" icon="arrow-right" @click="openMove(item)">Başka masaya taşı</DropdownItem>
                                            <DropdownItem v-if="!item.is_comp && can('orders.comp')" icon="check-circle" @click="openReason('item_comp', item)">İkram et</DropdownItem>
                                            <DropdownItem v-if="item.status === 'placed'" icon="trash" danger @click="removeItem(item)">Çıkar</DropdownItem>
                                            <DropdownItem v-else-if="can('orders.cancel')" icon="x-circle" danger @click="openReason('item_cancel', item)">İptal et (nedenli)</DropdownItem>
                                        </BaseDropdown>
                                    </div>
                                </div>
                            </div>

                            <details v-if="inactiveItems.length > 0" class="border-b border-default p-3 text-sm">
                                <summary class="cursor-pointer text-muted">İptal edilen kalemler ({{ inactiveItems.length }})</summary>
                                <div v-for="item in inactiveItems" :key="item.id" class="flex items-center justify-between gap-2 border-b border-default py-1.5 opacity-70">
                                    <span class="line-through">{{ item.qty }} × {{ item.name }}</span>
                                    <span v-if="item.cancel_reason" class="shrink-0 rounded-md bg-danger-soft px-2 py-0.5 text-xs font-medium text-danger">{{ item.cancel_reason }}</span>
                                </div>
                            </details>

                            <!-- Tutar dökümü -->
                            <div class="p-3 text-sm">
                                <div class="flex justify-between gap-2 py-0.5"><span class="text-muted">Ara toplam</span><span class="whitespace-nowrap tabular-nums">{{ money(order.items_total_minor) }} ₺</span></div>
                                <div v-if="order.discount_minor > 0" class="flex justify-between py-0.5 text-warning">
                                    <span class="min-w-0 truncate">İndirim<template v-if="order.discount_percent"> (%{{ order.discount_percent }})</template></span>
                                    <span class="shrink-0 whitespace-nowrap tabular-nums">−{{ money(order.discount_minor) }} ₺</span>
                                </div>
                                <div v-if="order.comp_total_minor > 0" class="flex justify-between py-0.5 text-success">
                                    <span>İkramlar</span><span class="whitespace-nowrap tabular-nums">{{ money(order.comp_total_minor) }} ₺</span>
                                </div>
                                <div class="flex justify-between gap-2 py-0.5 text-xs text-muted"><span>Dahil KDV</span><span class="whitespace-nowrap tabular-nums">{{ money(order.vat_total_minor) }} ₺</span></div>
                            </div>
                        </template>

                        <!-- GEÇMİŞ (olay günlüğü) -->
                        <template v-else>
                            <EmptyState v-if="order.events.length === 0" title="Kayıt yok" icon="clock" />
                            <ol v-else class="divide-y divide-default text-sm">
                                <li v-for="e in order.events" :key="e.id" class="flex items-baseline justify-between gap-2 px-3 py-2">
                                    <span class="min-w-0">
                                        {{ eventTypeLabels[e.type] ?? e.type }}
                                        <span v-if="e.to_status" class="text-xs text-muted">→ {{ meta.orderStatuses.find((s) => s.value === e.to_status)?.label ?? meta.itemStatuses.find((s) => s.value === e.to_status)?.label ?? e.to_status }}</span>
                                        <span v-if="e.user" class="text-xs text-muted">· {{ e.user }}</span>
                                    </span>
                                    <time class="shrink-0 text-xs text-subtle tabular-nums">{{ e.created_at ? new Date(e.created_at).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' }) : '' }}</time>
                                </li>
                            </ol>
                        </template>
                    </div>

                    <!-- Alt toplam şeridi (kasa ekranıyla aynı dil) -->
                    <div class="grid grid-cols-3 divide-x divide-default border-t border-default text-center">
                        <div class="bg-success-soft/50 px-2 py-2.5">
                            <p class="flex items-center justify-center gap-1 text-[11px] font-medium uppercase tracking-wide text-subtle">
                                <AppIcon name="check-circle" :size="11" /> Ödenen
                            </p>
                            <p class="text-sm font-bold tabular-nums text-success sm:text-base">{{ money(order.paid_minor) }} ₺</p>
                        </div>
                        <div class="px-2 py-2.5" :class="order.remaining_minor > 0 ? 'bg-warning-soft/50' : 'bg-success-soft/50'">
                            <p class="flex items-center justify-center gap-1 text-[11px] font-medium uppercase tracking-wide text-subtle">
                                <AppIcon name="wallet" :size="11" /> Kalan
                            </p>
                            <p class="text-sm font-bold tabular-nums sm:text-base" :class="order.remaining_minor > 0 ? 'text-warning' : 'text-success'">
                                {{ order.remaining_display }} ₺
                            </p>
                        </div>
                        <div class="bg-primary-soft/50 px-2 py-2.5">
                            <p class="flex items-center justify-center gap-1 text-[11px] font-medium uppercase tracking-wide text-subtle">
                                <AppIcon name="receipt" :size="11" /> Toplam
                            </p>
                            <p class="text-sm font-bold tabular-nums text-primary sm:text-base">{{ order.total_display }} ₺</p>
                        </div>
                    </div>

                    <!-- Ana eylem: para KASADA tahsil edilir; buradan adisyon kasaya düşer.
                         (Bilinçli: sipariş ekranı sipariş ALIR, para almaz.) -->
                    <div class="border-t border-default bg-raised p-3 shadow-[0_-6px_16px_-14px_rgba(0,0,0,0.6)]">
                        <!-- Gönderilmemiş kalem varsa ÖNCE o uyarılır: adisyon kasaya
                             gidince mutfağa düşmemiş kalem arada kaynayabilir. -->
                        <p
                            v-if="order.is_open && unsentCount > 0"
                            class="mb-2 flex items-center gap-1.5 rounded-md border border-warning-border bg-warning-soft px-2.5 py-1.5 text-xs font-semibold text-warning"
                        >
                            <AppIcon name="alert-triangle" :size="14" class="shrink-0" />
                            {{ unsentCount }} kalem henüz hazırlığa gönderilmedi.
                        </p>
                        <BaseButton
                            v-if="payReady && order.remaining_minor > 0 && order.status !== 'bill_requested' && can('orders.update')"
                            block
                            size="lg"
                            class="!h-12"
                            :loading="opBusy"
                            @click="requestBill"
                        >
                            <AppIcon name="check-circle" :size="17" /> Ödemeye gönder — {{ order.remaining_display }} ₺
                        </BaseButton>
                        <BaseButton
                            v-else-if="order.status === 'bill_requested' && canGoCashier"
                            block
                            size="lg"
                            variant="secondary"
                            class="!h-12"
                            @click="router.visit('/panel/kasa')"
                        >
                            <AppIcon name="wallet" :size="17" /> Kasada bekliyor — Kasaya git
                        </BaseButton>
                        <p v-else-if="!order.is_open" class="text-center text-sm text-muted">Bu adisyon kapalı.</p>
                        <p v-else class="text-center text-xs text-muted">
                            Kalemler hazırlığa gönderildikten sonra adisyon kasaya iletilebilir.
                        </p>
                    </div>
                </section>
            </div>

            <BaseCard v-else-if="!loading">
                <EmptyState title="Adisyon bulunamadı" description="Silinmiş ya da erişiminiz olmayan bir adisyon." icon="alert-circle" />
            </BaseCard>
        </main>
    </div>

    <!-- Nav çekmecesi (terminal dışı) -->
    <KdsNavDrawer v-if="!isTerminal" :open="showNav" @close="showNav = false" />

        <!-- Ürün yapılandırma modalı -->
        <BaseModal :open="productModal !== null" :title="productModal?.name ?? ''" @close="closeModal(() => (productModal = null))">
            <div v-if="productModal" class="flex flex-col gap-4">
                <!-- Onay başlığı + ürün görseli (garson "ne eklediğini" görür; dokununca büyür) -->
                <div class="flex items-start gap-3">
                    <button
                        v-if="productModal.image_url && !brokenImages.has(productModal.id)"
                        type="button"
                        class="block size-16 shrink-0 cursor-zoom-in appearance-none overflow-hidden rounded-lg border border-default bg-inset p-0 leading-none"
                        aria-label="Ürün görselini büyüt"
                        @click="lbOpen(productModal.image_url, productModal.name)"
                    >
                        <img :src="productModal.image_url" :alt="productModal.name" loading="lazy" class="size-full object-cover" @error="onProductImageError(productModal.id)" />
                    </button>
                    <p class="flex flex-1 items-start gap-2 rounded-lg bg-info-soft px-3 py-2 text-[13px] text-info">
                        <AppIcon name="alert-circle" :size="15" class="mt-0.5 shrink-0" />
                        <span><span class="font-semibold">{{ productModal.name }}</span> adisyona eklenecek. Adedi seçip onaylayın; yanlışsa <span class="font-semibold">Vazgeç</span> ile başka ürün seçin.</span>
                    </p>
                </div>
                <BaseRadioGroup
                    v-if="productModal.variants.length > 0"
                    v-model="pmVariant"
                    label="Boyut / Porsiyon"
                    :options="productModal.variants.map((v) => ({ value: String(v.id), label: `${v.name} — ${money(v.price_minor)} ₺` }))"
                />

                <div v-for="g in productModal.option_groups" :key="g.id" class="flex flex-col gap-1.5">
                    <p class="text-sm font-medium text-body">
                        {{ g.name }}
                        <span v-if="g.is_required" class="text-danger">*</span>
                        <span class="text-xs font-normal text-muted">
                            ({{ g.selection_type === 'single' ? 'tek seçim' : g.max_select ? `en çok ${g.max_select}` : 'çoklu seçim' }})
                        </span>
                    </p>
                    <div class="flex flex-wrap gap-1.5">
                        <button
                            v-for="o in g.options"
                            :key="o.id"
                            type="button"
                            class="rounded-full border px-3 py-1.5 text-sm transition-colors"
                            :class="pmOptions.has(o.id) ? 'border-transparent bg-primary text-on-primary' : 'border-default text-muted hover:bg-inset'"
                            :aria-pressed="pmOptions.has(o.id)"
                            @click="toggleOption(g.id, o.id, g.selection_type === 'single')"
                        >
                            {{ o.name }}<template v-if="o.price_minor > 0"> +{{ money(o.price_minor) }} ₺</template>
                        </button>
                    </div>
                </div>

                <div class="flex items-center justify-between">
                    <FormField label="Adet">
                        <div class="flex items-center gap-2">
                            <BaseButton size="sm" variant="secondary" icon-only label="Azalt" :disabled="pmQty <= pmMinQty" @click="pmDec">
                                <AppIcon name="chevron-down" :size="14" />
                            </BaseButton>
                            <span class="min-w-8 text-center text-lg font-semibold">{{ pmQty }}</span>
                            <BaseButton size="sm" variant="secondary" icon-only label="Artır" :disabled="pmQty >= pmMaxQty" @click="pmInc">
                                <AppIcon name="chevron-up" :size="14" />
                            </BaseButton>
                        </div>
                    </FormField>
                    <p class="whitespace-nowrap text-lg font-semibold tabular-nums">{{ money(pmTotal) }} ₺</p>
                </div>

                <FormField label="Not">
                    <BaseInput v-model="pmNote" placeholder="ör. az pişmiş, soğansız" />
                </FormField>
            </div>
            <template #footer>
                <span v-if="!pmRequiredOk" class="mr-auto self-center text-xs text-danger">Zorunlu (*) seçimleri tamamlayın.</span>
                <BaseButton variant="secondary" @click="closeModal(() => (productModal = null))">Vazgeç</BaseButton>
                <BaseButton :loading="addBusy" :disabled="!pmValid" @click="submitProductModal">
                    <AppIcon name="plus" :size="14" />
                    Adisyona ekle
                </BaseButton>
            </template>
        </BaseModal>

        <!-- Ekleme-anı "hazırlığa gönder" sorusu: eklenen ürün unutulmasın. -->
        <BaseModal :open="sendPromptOpen" title="Hazırlığa iletilsin mi?" size="sm" @close="dismissSendPrompt">
            <div class="flex flex-col gap-3">
                <p class="flex items-start gap-2 rounded-lg bg-info-soft px-3 py-2 text-[13px] text-info">
                    <AppIcon name="utensils" :size="16" class="mt-0.5 shrink-0" />
                    <span><span class="font-semibold">{{ sendPromptName }}</span> adisyona eklendi. İlgili istasyona (mutfak/barista/nargile) şimdi iletilsin mi?
                        Hatalıysa <span class="font-semibold">Şimdi değil</span> deyip kalemi düzeltin/silin.</span>
                </p>
                <p class="text-xs text-muted">
                    İpucu: Birkaç ürünü birlikte göndermek isterseniz “Şimdi değil” deyip hepsini ekledikten sonra
                    <span class="font-medium">Hazırlığa gönder</span> ile tek seferde iletebilirsiniz.
                </p>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="dismissSendPrompt">Şimdi değil</BaseButton>
                <BaseButton :loading="opBusy" @click="confirmSendPrompt">
                    <AppIcon name="utensils" :size="14" />
                    Hazırlığa gönder
                </BaseButton>
            </template>
        </BaseModal>

        <!-- Neden modalı (ikram / iptal / iade) -->
        <BaseModal :open="reasonModal !== null" :title="reasonModal ? reasonTitles[reasonModal.kind] : ''" size="sm" @close="closeModal(() => (reasonModal = null))">
            <p v-if="reasonModal?.item" class="pb-2 text-sm text-muted">{{ reasonModal.item.qty }} × {{ reasonModal.item.name }}</p>
            <!-- Kısmi ikram: kaç adet ikram edilecek (varsayılan tümü) -->
            <FormField
                v-if="reasonModal?.kind === 'item_comp' && (reasonModal.item?.qty ?? 1) > 1"
                label="İkram adedi"
                :hint="`Toplam ${reasonModal.item?.qty} adet — kaçı ikram edilsin?`"
            >
                <div class="flex items-center gap-2">
                    <BaseButton size="sm" variant="secondary" icon-only :disabled="compQty <= 1" @click="compQty = Math.max(1, compQty - 1)">
                        <AppIcon name="minus" :size="16" />
                    </BaseButton>
                    <span class="w-10 text-center text-base font-bold tabular-nums text-body">{{ compQty }}</span>
                    <BaseButton size="sm" variant="secondary" icon-only :disabled="compQty >= (reasonModal.item?.qty ?? 1)" @click="compQty = Math.min(reasonModal.item?.qty ?? 1, compQty + 1)">
                        <AppIcon name="plus" :size="16" />
                    </BaseButton>
                    <button type="button" class="ms-1 text-xs font-medium text-primary hover:underline" @click="compQty = reasonModal.item?.qty ?? 1">Tümü</button>
                </div>
            </FormField>
            <FormField label="Neden" required hint="Denetim kaydına yazılır; zorunludur.">
                <BaseInput v-model="reasonText" placeholder="ör. müşteri memnuniyeti, yanlış sipariş…" />
            </FormField>
            <template #footer>
                <BaseButton variant="secondary" @click="closeModal(() => (reasonModal = null))">Vazgeç</BaseButton>
                <BaseButton :variant="reasonModal?.kind === 'item_comp' ? 'primary' : 'danger'" :loading="opBusy" @click="submitReason">Onayla</BaseButton>
            </template>
        </BaseModal>

        <!-- Kalem notu -->
        <BaseModal :open="noteModal !== null" title="Kalem notu" size="sm" @close="closeModal(() => (noteModal = null))">
            <FormField label="Not">
                <BaseInput v-model="noteText" placeholder="ör. az pişmiş, soğansız" />
            </FormField>
            <template #footer>
                <BaseButton variant="secondary" @click="closeModal(() => (noteModal = null))">Vazgeç</BaseButton>
                <BaseButton :loading="opBusy" @click="saveNote">Kaydet</BaseButton>
            </template>
        </BaseModal>


        <!-- Kişi sayısı + adisyon notu -->
        <BaseModal :open="infoModal" title="Kişi sayısı / adisyon notu" size="sm" @close="closeModal(() => (infoModal = false))">
            <div class="flex flex-col gap-3">
                <FormField label="Kişi sayısı" hint="Boş bırakılabilir; hesap bölerken kişi başı tutarda kullanılır">
                    <BaseInput v-model="infoGuests" inputmode="numeric" placeholder="ör. 4" />
                </FormField>
                <div class="flex flex-wrap gap-1.5">
                    <BaseButton
                        v-for="n in [1, 2, 3, 4, 5, 6, 8, 10]"
                        :key="n"
                        size="sm"
                        :variant="infoGuests === String(n) ? 'primary' : 'secondary'"
                        @click="infoGuests = String(n)"
                    >
                        {{ n }}
                    </BaseButton>
                </div>
                <FormField label="Adisyon notu" hint="Adisyonun tamamı için (ör. “doğum günü, pasta sonda gelsin”)">
                    <BaseInput v-model="infoNote" placeholder="İsteğe bağlı" />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeModal(() => (infoModal = false))">Vazgeç</BaseButton>
                <BaseButton :loading="opBusy" @click="submitInfo">Kaydet</BaseButton>
            </template>
        </BaseModal>

        <!-- İndirim -->
        <BaseModal :open="discountModal" title="İndirim uygula" size="sm" @close="closeModal(() => (discountModal = false))">
            <div class="flex flex-col gap-3">
                <BaseRadioGroup
                    v-model="dType"
                    label="Tür"
                    :options="[
                        { value: 'percent', label: 'Yüzde (%)' },
                        { value: 'amount', label: 'Tutar (₺)' },
                    ]"
                />
                <FormField :label="dType === 'percent' ? 'Yüzde' : 'Tutar (₺)'" required>
                    <BaseInput v-model="dValue" inputmode="decimal" :placeholder="dType === 'percent' ? 'ör. 10' : 'ör. 50,00'" />
                </FormField>
                <FormField label="Neden" required hint="Denetim kaydına yazılır.">
                    <BaseInput v-model="dReason" placeholder="ör. sadakat, şikâyet telafisi" />
                </FormField>
                <div v-if="discountNeedsApproval" class="rounded-lg border border-warning/40 bg-inset p-3">
                    <p class="pb-2 text-xs font-medium text-warning">
                        %{{ meta.discountApprovalPercent }} üzeri indirim yönetici onayı gerektirir.
                    </p>
                    <FormField label="Yönetici e-posta" required>
                        <BaseInput v-model="dApproverEmail" type="email" placeholder="yonetici@ornek.com" />
                    </FormField>
                    <FormField label="Yönetici PIN" required>
                        <BaseInput v-model="dApproverPin" type="password" inputmode="numeric" placeholder="••••••" />
                    </FormField>
                </div>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeModal(() => (discountModal = false))">Vazgeç</BaseButton>
                <BaseButton :loading="opBusy" @click="submitDiscount">Uygula</BaseButton>
            </template>
        </BaseModal>

        <!-- Taşı -->
        <BaseModal :open="moveModal !== null" :title="moveModal?.item ? 'Kalemi başka masaya taşı' : 'Adisyonu taşı'" size="sm" @close="closeModal(() => (moveModal = null))">
            <p v-if="moveModal?.item" class="pb-2 text-sm text-muted">{{ moveModal.item.qty }} × {{ moveModal.item.name }}</p>
            <FormField label="Hedef masa" required hint="Hedef masada açık adisyon varsa kalemler ona eklenir.">
                <BaseSelect v-model="moveTarget" :options="moveOptions" placeholder="Masa seçin" />
            </FormField>
            <template #footer>
                <BaseButton variant="secondary" @click="closeModal(() => (moveModal = null))">Vazgeç</BaseButton>
                <BaseButton :disabled="!moveTarget" :loading="opBusy" @click="submitMove">Taşı</BaseButton>
            </template>
        </BaseModal>

        <!-- Birleştir -->
        <BaseModal :open="mergeModal" title="Adisyon birleştir" size="sm" @close="closeModal(() => (mergeModal = false))">
            <FormField label="Kaynak adisyon" required hint="Seçilen adisyonun kalemleri bu adisyona aktarılır ve kaynak kapanır.">
                <BaseSelect v-model="mergeSource" :options="mergeOptions" placeholder="Adisyon seçin" />
            </FormField>
            <template #footer>
                <BaseButton variant="secondary" @click="closeModal(() => (mergeModal = false))">Vazgeç</BaseButton>
                <BaseButton :disabled="!mergeSource" :loading="opBusy" @click="submitMerge">Birleştir</BaseButton>
            </template>
        </BaseModal>

        <!-- Borca taşı -->
        <BaseModal :open="debtModal" title="Adisyonu borca taşı" size="sm" @close="closeModal(() => (debtModal = false))">
            <div class="flex flex-col gap-3">
                <p class="text-sm text-muted">
                    Kalan tutar (<strong class="whitespace-nowrap tabular-nums">{{ order?.remaining_display }} ₺</strong>) seçilen cariye borç olarak yazılır; adisyon
                    <strong>ödendi SAYILMAZ</strong>, ama masa boşalır — başka müşteri sipariş verebilir.
                </p>

                <BaseSwitch v-if="can('receivables.create')" v-model="debtCreatingNew" label="Yeni cari oluştur" />

                <FormField v-if="!debtCreatingNew" label="Cari" required hint="Bakiyesi olan cariler de listelenir; borç üstüne eklenir.">
                    <BaseSelect v-model="debtReceivableId" :options="debtOptions" placeholder="Cari seçin" />
                </FormField>
                <template v-else>
                    <FormField label="Cari adı" required>
                        <BaseInput v-model="debtNewName" placeholder="ör. Ahmet Bey" />
                    </FormField>
                    <FormField label="Telefon">
                        <BaseInput v-model="debtNewPhone" inputmode="tel" />
                    </FormField>
                </template>

                <FormField label="Açıklama" required hint="Denetim kaydına düşer (kim, ne zaman, neden).">
                    <BaseInput v-model="debtReason" placeholder="ör. Müşteri sonra ödeyecek" />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeModal(() => (debtModal = false))">Vazgeç</BaseButton>
                <BaseButton
                    :loading="debtBusy"
                    :disabled="debtReason.trim().length < 3 || (!debtCreatingNew && !debtReceivableId) || (debtCreatingNew && !debtNewName.trim())"
                    @click="submitDebtTransfer"
                >
                    Borca taşı
                </BaseButton>
            </template>
        </BaseModal>

        <!-- Böl -->
        <BaseModal :open="splitModal" title="Adisyonu böl" @close="closeModal(() => (splitModal = false))">
            <div class="flex flex-col gap-3">
                <BaseRadioGroup
                    v-model="splitMode"
                    label="Bölme türü"
                    :options="[
                        { value: 'items', label: 'Ürün bazlı (kalemler yeni adisyona ayrılır)' },
                        { value: 'equal', label: 'Eşit böl (kişi sayısına)' },
                        { value: 'persons', label: 'Kişi bazlı (tutarları elle gir)' },
                    ]"
                />

                <div v-if="splitMode === 'items'" class="flex max-h-64 flex-col gap-1.5 overflow-y-auto">
                    <BaseCheckbox
                        v-for="item in activeItems"
                        :key="item.id"
                        :model-value="splitItems.has(item.id)"
                        :label="`${item.qty} × ${item.name} — ${item.line_total_display} ₺`"
                        @update:model-value="(v: boolean) => toggleSplitItem(item.id, v)"
                    />
                </div>

                <FormField v-if="splitMode === 'equal'" label="Kişi sayısı" required>
                    <BaseInput v-model="splitWays" inputmode="numeric" placeholder="ör. 3" />
                </FormField>

                <FormField v-if="splitMode === 'persons'" label="Tutarlar (₺, virgülle ayırın)" required :hint="`Toplamı kalan tutara (${order?.remaining_display} ₺) eşit olmalı.`">
                    <BaseInput v-model="splitAmounts" placeholder="ör. 150; 200,50; 99,50" />
                </FormField>

                <div v-if="splitShares" class="rounded-lg bg-inset p-3 text-sm">
                    <p class="pb-1 font-medium">Paylar (kuruş kaybı yok):</p>
                    <ol class="flex flex-col gap-0.5">
                        <li v-for="(s, i) in splitShares" :key="i" class="flex justify-between">
                            <span>{{ i + 1 }}. kişi</span><span class="whitespace-nowrap tabular-nums">{{ money(s) }} ₺</span>
                        </li>
                    </ol>
                </div>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeModal(() => (splitModal = false))">Kapat</BaseButton>
                <BaseButton :loading="opBusy" :disabled="splitMode === 'items' && splitItems.size === 0" @click="submitSplit">Böl</BaseButton>
            </template>
        </BaseModal>

        <!-- §13 Faz B: terminal (sipariş-giriş/kasa) hassas eylem PIN modalı -->
        <StaffPinDialog />

        <!-- Ürün görseli büyüteci (onay modalındaki görsel → tam ekran) -->
        <ImageLightbox />
    <OrderDiscountDialog
        v-if="order"
        :open="discountDialogOpen"
        :order-id="order.id"
        :discount-minor="order.discount_minor"
        :discount-reason="order.discount_reason"
        :discount-percent="order.discount_percent"
        :order-version="order.version"
        @close="closeDiscountDialog"
        @applied="onDiscountChanged"
        @removed="onDiscountChanged"
    />

    <OrderEditItemDialog
        v-if="order"
        :open="editItemTarget !== null"
        :order-id="order.id"
        :item="editItemTarget"
        :order-version="order.version"
        :channel="order.channel"
        :branch-id="order.branch_id"
        @close="closeEditItem"
        @saved="onItemSaved"
        @replace="onItemReplace"
    />
</template>

<style scoped>
/*
 * Zemin: Board.vue/Kitchen.vue/Cashier.vue ile birebir aynı katmanlı yüzey —
 * --ui-surface üstünde çok hafif üstten ışık düşümü.
 */
.kds-canvas {
    background-color: var(--ui-surface);
    background-image: radial-gradient(1200px 640px at 50% -12%, rgb(255 255 255 / 0.035), transparent 60%);
}
</style>
