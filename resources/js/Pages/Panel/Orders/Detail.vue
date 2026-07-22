<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Head, router, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
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
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import {
    apiIdempotent,
    channelPrice,
    groupOptionsPrice,
    elapsed,
    fetchBoard,
    fetchOrder,
    fetchOrderCatalog,
    metaFromProps,
    money,
    newIdempotencyKey,
    type BoardTable,
    type CatalogProduct,
    type OrderDetail,
    type OrderItemRow,
    type OrderSummary,
} from './orders';

const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const orderId = Number((page.props as Record<string, unknown>).orderId);
const { success, danger } = useToast();

/* ================= Sipariş + polling ================= */
const order = ref<OrderDetail | null>(null);
const loading = ref(true);
const anyModalOpen = ref(false);

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
const catalog = ref<{ categories: { id: number; name: string }[]; products: CatalogProduct[] }>({ categories: [], products: [] });
const activeCategory = ref<number | 0>(0);
const search = ref('');

const visibleProducts = computed(() => {
    let list = catalog.value.products;
    if (activeCategory.value !== 0) list = list.filter((p) => p.category_id === activeCategory.value);
    if (search.value) {
        const needle = search.value.toLocaleLowerCase('tr-TR');
        list = list.filter((p) => p.name.toLocaleLowerCase('tr-TR').includes(needle));
    }
    return list;
});

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

function productPrice(p: CatalogProduct): number {
    return channelPrice(p, order.value?.channel ?? 'table');
}

function onProductClick(p: CatalogProduct): void {
    if (!p.is_available) return;
    if (p.variants.length === 0 && p.option_groups.length === 0) {
        void addItem(p, null, [], 1, null);
        return;
    }
    productModal.value = p;
    pmVariant.value = String(p.variants.find((v) => v.is_default)?.id ?? p.variants[0]?.id ?? '');
    pmOptions.value = new Set(p.option_groups.flatMap((g) => g.options.filter((o) => o.is_default).map((o) => o.id)));
    pmQty.value = Math.max(1, p.min_order_qty);
    pmNote.value = '';
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

async function addItem(p: CatalogProduct, variantId: number | null, optionIds: number[], qty: number, note: string | null): Promise<void> {
    if (addBusy.value) return;
    addBusy.value = true;
    try {
        // Idempotency-Key: çift dokunma / ağ tekrarı kalem çoğaltmaz (§12.4)
        const res = await apiIdempotent<{ order: OrderDetail }>(`/api/v1/orders/${orderId}/items`, {
            product_id: p.id,
            variant_id: variantId,
            qty,
            option_ids: optionIds,
            note,
        }, newIdempotencyKey());
        if (res.order) order.value = res.order;
        success(`${p.name} eklendi`, '');
        productModal.value = null;
        anyModalOpen.value = false;
    } catch (e) {
        danger('Eklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        addBusy.value = false;
    }
}

function submitProductModal(): void {
    const p = productModal.value;
    if (!p) return;
    void addItem(p, pmVariant.value ? Number(pmVariant.value) : null, [...pmOptions.value], pmQty.value, pmNote.value || null);
}

/* ================= Kalem işlemleri ================= */
function nextItemStatus(item: OrderItemRow): { value: string; label: string } | null {
    const chain = ['placed', 'sent_to_station', 'accepted', 'preparing', 'ready', 'served'];
    const idx = chain.indexOf(item.status);
    if (idx < 0 || idx >= chain.length - 1) return null;
    const next = chain[idx + 1];
    const label = meta.itemStatuses.find((s) => s.value === next)?.label ?? next;
    return { value: next, label };
}

async function advanceItem(item: OrderItemRow): Promise<void> {
    const next = nextItemStatus(item);
    if (!next) return;
    await runOp(`/api/v1/orders/${orderId}/items/${item.id}/status`, { status: next.value }, '', 'PUT');
}

async function changeQty(item: OrderItemRow, delta: number): Promise<void> {
    const qty = item.qty + delta;
    if (qty < 1) return;
    await runOp(`/api/v1/orders/${orderId}/items/${item.id}`, { qty }, '', 'PUT');
}

async function removeItem(item: OrderItemRow): Promise<void> {
    await runOp(`/api/v1/orders/${orderId}/items/${item.id}`, {}, 'Kalem çıkarıldı', 'DELETE');
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
    if (await runOp(`/api/v1/orders/${orderId}/items/${item.id}`, { note: noteText.value || null }, 'Not kaydedildi', 'PUT')) {
        noteModal.value = null;
        anyModalOpen.value = false;
    }
}

/* Neden isteyen işlemler: kalem iptal / ikram / sipariş iptal / iade */
type ReasonKind = 'item_cancel' | 'item_comp' | 'order_cancel' | 'order_refund';
const reasonModal = ref<{ kind: ReasonKind; item?: OrderItemRow } | null>(null);
const reasonText = ref('');

const reasonTitles: Record<ReasonKind, string> = {
    item_cancel: 'Kalemi iptal et',
    item_comp: 'İkram et',
    order_cancel: 'Adisyonu iptal et',
    order_refund: 'İade et',
};

function openReason(kind: ReasonKind, item?: OrderItemRow): void {
    reasonModal.value = { kind, item };
    reasonText.value = '';
    anyModalOpen.value = true;
}

async function submitReason(): Promise<void> {
    const ctx = reasonModal.value;
    if (!ctx || reasonText.value.trim().length < 3) {
        danger('Neden zorunlu', 'En az 3 karakterlik bir neden girin.');
        return;
    }
    const v = order.value?.version;
    const body = { reason: reasonText.value.trim(), expected_version: v };
    const ok =
        ctx.kind === 'item_cancel' ? await runOp(`/api/v1/orders/${orderId}/items/${ctx.item!.id}/cancel`, body, 'Kalem iptal edildi')
        : ctx.kind === 'item_comp' ? await runOp(`/api/v1/orders/${orderId}/items/${ctx.item!.id}/comp`, body, 'İkram edildi')
        : ctx.kind === 'order_cancel' ? await runOp(`/api/v1/orders/${orderId}/cancel`, body, 'Adisyon iptal edildi')
        : await runOp(`/api/v1/orders/${orderId}/refund`, body, 'İade kaydedildi');
    if (ok) {
        reasonModal.value = null;
        anyModalOpen.value = false;
    }
}

/* ================= Sipariş düzeyi işlemler ================= */
async function requestBill(): Promise<void> {
    await runOp(`/api/v1/orders/${orderId}/request-bill`, {}, 'Hesap istendi');
}

async function approveOrder(): Promise<void> {
    await runOp(`/api/v1/orders/${orderId}/approve`, {}, 'Sipariş onaylandı');
}

/* Ödeme */
const payModal = ref(false);
const payAmount = ref('');
const payMethod = ref('cash');

function openPay(): void {
    payAmount.value = order.value ? money(order.value.remaining_minor).replace(/\./g, '') : '';
    payMethod.value = 'cash';
    payModal.value = true;
    anyModalOpen.value = true;
}

function parseAmountMinor(text: string): number {
    const normalized = text.replace(/\s/g, '').replace(/\./g, '').replace(',', '.');
    const value = Number(normalized);
    return Number.isFinite(value) ? Math.round(value * 100) : 0;
}

async function submitPay(): Promise<void> {
    const amount = parseAmountMinor(payAmount.value);
    if (amount <= 0) {
        danger('Tutar geçersiz', 'Pozitif bir tutar girin.');
        return;
    }
    const ok = await runOp(`/api/v1/orders/${orderId}/pay`, {
        amount_minor: amount,
        method: payMethod.value,
        expected_version: order.value?.version,
    }, 'Ödeme kaydedildi');
    if (ok) {
        payModal.value = false;
        anyModalOpen.value = false;
    }
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
};
</script>

<template>
    <Head :title="order ? `Adisyon #${order.id}` : 'Adisyon'" />
    <PanelShell :title="order ? `Adisyon #${order.id}` : 'Adisyon'">
        <div v-if="order" class="flex flex-col gap-4">
            <!-- Üst şerit: kimlik + durum + ana eylemler -->
            <BaseCard>
                <div class="flex flex-wrap items-center justify-between gap-3">
                    <div class="flex flex-wrap items-center gap-2">
                        <BaseButton size="sm" variant="ghost" icon-only label="Panoya dön" @click="router.visit('/panel/siparisler')">
                            <AppIcon name="arrow-left" :size="18" />
                        </BaseButton>
                        <BaseBadge :variant="order.channel_variant" no-icon>
                            <AppIcon :name="order.channel_icon" :size="12" />
                            {{ order.channel_label }}
                        </BaseBadge>
                        <span class="text-base font-semibold text-body">{{ order.table_name ?? order.customer_name ?? `#${order.id}` }}</span>
                        <BaseBadge :variant="order.status_variant" no-icon>
                            <AppIcon :name="order.status_icon" :size="12" />
                            {{ order.status_label }}
                        </BaseBadge>
                        <span class="text-xs text-muted">{{ elapsed(order.created_at) }} önce · {{ order.opened_by ?? '—' }}</span>
                    </div>
                    <div class="flex flex-wrap gap-2">
                        <BaseButton v-if="order.status === 'pending_approval'" size="sm" :loading="opBusy" @click="approveOrder">
                            <AppIcon name="check" :size="14" />
                            Siparişi onayla
                        </BaseButton>
                        <BaseButton v-if="order.is_open && order.status !== 'bill_requested'" size="sm" variant="secondary" @click="requestBill">
                            <AppIcon name="cart" :size="14" />
                            Hesap iste
                        </BaseButton>
                        <BaseButton v-if="order.is_open && order.remaining_minor > 0" size="sm" @click="openPay">
                            <AppIcon name="check-circle" :size="14" />
                            Ödeme al
                        </BaseButton>
                        <BaseDropdown menu-label="Adisyon işlemleri">
                            <template #trigger="{ toggle, ariaAttrs }">
                                <button
                                    type="button"
                                    v-bind="ariaAttrs"
                                    class="flex h-8 items-center gap-1 rounded-md border border-default px-2 text-sm text-body hover:bg-inset"
                                    @click="toggle"
                                >
                                    İşlemler
                                    <AppIcon name="chevron-down" :size="14" />
                                </button>
                            </template>
                            <DropdownItem v-if="order.is_open" icon="arrow-right" @click="openMove()">Adisyonu taşı</DropdownItem>
                            <DropdownItem v-if="order.is_open" icon="inbox" @click="openMerge">Birleştir</DropdownItem>
                            <DropdownItem v-if="order.is_open" icon="chart" @click="openSplit">Böl</DropdownItem>
                            <DropdownItem v-if="order.is_open" icon="pencil" @click="openDiscount">İndirim uygula</DropdownItem>
                            <DropdownItem v-if="order.is_open && order.paid_minor === 0" icon="x-circle" danger @click="openReason('order_cancel')">
                                Adisyonu iptal et
                            </DropdownItem>
                            <DropdownItem v-if="order.status === 'paid'" icon="arrow-left" danger @click="openReason('order_refund')">
                                İade et
                            </DropdownItem>
                        </BaseDropdown>
                    </div>
                </div>
            </BaseCard>

            <div class="grid gap-4 lg:grid-cols-5">
                <!-- SOL: hızlı ürün ekleme (yoğun saat: az tıklama, büyük hedef, arama) -->
                <BaseCard v-if="order.is_open" class="lg:col-span-3">
                    <div class="flex flex-col gap-3">
                        <SearchInput v-model="search" placeholder="Ürün ara…" />
                        <div class="flex flex-wrap gap-1.5" role="tablist" aria-label="Kategoriler">
                            <button
                                type="button"
                                class="rounded-full border px-3 py-1.5 text-sm font-medium transition-colors"
                                :class="activeCategory === 0 ? 'border-transparent bg-primary text-on-primary' : 'border-default text-muted hover:bg-inset'"
                                @click="activeCategory = 0"
                            >
                                Tümü
                            </button>
                            <button
                                v-for="c in catalog.categories"
                                :key="c.id"
                                type="button"
                                class="rounded-full border px-3 py-1.5 text-sm font-medium transition-colors"
                                :class="activeCategory === c.id ? 'border-transparent bg-primary text-on-primary' : 'border-default text-muted hover:bg-inset'"
                                @click="activeCategory = c.id"
                            >
                                {{ c.name }}
                            </button>
                        </div>
                        <div v-if="visibleProducts.length > 0" class="grid max-h-[60vh] grid-cols-2 gap-2 overflow-y-auto sm:grid-cols-3">
                            <button
                                v-for="p in visibleProducts"
                                :key="p.id"
                                type="button"
                                class="flex min-h-20 flex-col justify-between rounded-lg border border-default p-2.5 text-left transition-colors hover:bg-inset disabled:opacity-45"
                                :disabled="!p.is_available || addBusy"
                                :aria-label="p.is_available ? `${p.name} ekle` : `${p.name} tükendi`"
                                @click="onProductClick(p)"
                            >
                                <span class="text-sm font-medium leading-tight text-body">{{ p.name }}</span>
                                <span class="flex items-center justify-between pt-1">
                                    <span class="text-sm font-semibold text-body">{{ money(productPrice(p)) }} ₺</span>
                                    <BaseBadge v-if="!p.is_available" variant="danger" no-icon>Tükendi</BaseBadge>
                                    <AppIcon v-else-if="p.variants.length > 0 || p.option_groups.length > 0" name="chevron-right" :size="14" class="text-muted" />
                                    <AppIcon v-else name="plus" :size="14" class="text-muted" />
                                </span>
                            </button>
                        </div>
                        <EmptyState v-else title="Ürün bulunamadı" description="Arama ya da kategori filtresini değiştirin." icon="search" />
                    </div>
                </BaseCard>

                <!-- SAĞ: adisyon -->
                <BaseCard :class="order.is_open ? 'lg:col-span-2' : 'lg:col-span-5'">
                    <div class="flex flex-col gap-3">
                        <h2 class="text-sm font-semibold text-body">Adisyon kalemleri</h2>

                        <EmptyState v-if="activeItems.length === 0" title="Adisyon boş" description="Soldan ürün ekleyin." icon="orders" />

                        <div v-for="item in activeItems" :key="item.id" class="rounded-lg border border-default p-3">
                            <div class="flex items-start justify-between gap-2">
                                <div class="min-w-0">
                                    <p class="font-medium text-body">
                                        {{ item.name }}
                                        <span v-if="item.variant_name" class="text-sm text-muted">({{ item.variant_name }})</span>
                                    </p>
                                    <p v-if="item.options.length > 0" class="text-xs text-muted">
                                        {{ item.options.map((o) => o.option_name).join(', ') }}
                                    </p>
                                    <p v-if="item.note" class="text-xs italic text-muted">“{{ item.note }}”</p>
                                    <p v-if="item.is_comp" class="text-xs font-medium text-success">İkram — {{ item.comp_reason }}</p>
                                </div>
                                <div class="text-right">
                                    <p class="font-semibold text-body" :class="{ 'line-through opacity-60': item.is_comp }">
                                        {{ item.line_total_display }} ₺
                                    </p>
                                    <p class="text-xs text-muted">{{ item.qty }} × {{ money(item.unit_price_minor + item.options_price_minor) }}</p>
                                </div>
                            </div>
                            <div class="flex flex-wrap items-center justify-between gap-2 pt-2">
                                <BaseBadge :variant="item.status_variant" no-icon>
                                    <AppIcon :name="item.status_icon" :size="12" />
                                    {{ item.status_label }}
                                </BaseBadge>
                                <div v-if="order.is_open" class="flex items-center gap-1">
                                    <template v-if="item.status === 'placed' && !item.is_comp">
                                        <BaseButton size="sm" variant="ghost" icon-only label="Adet azalt" :disabled="item.qty <= 1" @click="changeQty(item, -1)">
                                            <AppIcon name="chevron-down" :size="14" />
                                        </BaseButton>
                                        <span class="min-w-5 text-center text-sm font-medium">{{ item.qty }}</span>
                                        <BaseButton size="sm" variant="ghost" icon-only label="Adet artır" @click="changeQty(item, 1)">
                                            <AppIcon name="chevron-up" :size="14" />
                                        </BaseButton>
                                    </template>
                                    <BaseButton v-if="nextItemStatus(item)" size="sm" variant="secondary" @click="advanceItem(item)">
                                        → {{ nextItemStatus(item)!.label }}
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
                                        <DropdownItem icon="pencil" @click="openNote(item)">Not ekle / düzenle</DropdownItem>
                                        <DropdownItem icon="arrow-right" @click="openMove(item)">Başka masaya taşı</DropdownItem>
                                        <DropdownItem v-if="!item.is_comp" icon="check-circle" @click="openReason('item_comp', item)">İkram et</DropdownItem>
                                        <DropdownItem v-if="item.status === 'placed'" icon="trash" danger @click="removeItem(item)">Çıkar</DropdownItem>
                                        <DropdownItem v-else icon="x-circle" danger @click="openReason('item_cancel', item)">İptal et (nedenli)</DropdownItem>
                                    </BaseDropdown>
                                </div>
                            </div>
                        </div>

                        <details v-if="inactiveItems.length > 0" class="text-sm">
                            <summary class="cursor-pointer text-muted">İptal edilen kalemler ({{ inactiveItems.length }})</summary>
                            <div v-for="item in inactiveItems" :key="item.id" class="flex items-center justify-between border-b border-default py-1.5 opacity-60">
                                <span class="line-through">{{ item.qty }} × {{ item.name }}</span>
                                <span class="text-xs">{{ item.cancel_reason }}</span>
                            </div>
                        </details>

                        <!-- Toplamlar -->
                        <div class="rounded-lg bg-inset p-3 text-sm">
                            <div class="flex justify-between py-0.5"><span class="text-muted">Ara toplam</span><span>{{ money(order.items_total_minor) }} ₺</span></div>
                            <div v-if="order.discount_minor > 0" class="flex justify-between py-0.5 text-warning">
                                <span>İndirim<template v-if="order.discount_percent"> (%{{ order.discount_percent }})</template> — {{ order.discount_reason }}</span>
                                <span>−{{ money(order.discount_minor) }} ₺</span>
                            </div>
                            <div v-if="order.comp_total_minor > 0" class="flex justify-between py-0.5 text-success">
                                <span>İkramlar</span><span>{{ money(order.comp_total_minor) }} ₺</span>
                            </div>
                            <div class="flex justify-between py-0.5 text-xs text-muted"><span>Dahil KDV</span><span>{{ money(order.vat_total_minor) }} ₺</span></div>
                            <div class="flex justify-between border-t border-default py-1 text-base font-semibold">
                                <span>Toplam</span><span>{{ order.total_display }} ₺</span>
                            </div>
                            <div v-if="order.paid_minor > 0" class="flex justify-between py-0.5"><span class="text-muted">Ödenen</span><span>{{ money(order.paid_minor) }} ₺</span></div>
                            <div v-if="order.paid_minor > 0" class="flex justify-between py-0.5 font-medium"><span>Kalan</span><span>{{ order.remaining_display }} ₺</span></div>
                        </div>

                        <!-- Olay günlüğü -->
                        <details class="text-sm">
                            <summary class="cursor-pointer text-muted">Olay günlüğü ({{ order.events.length }})</summary>
                            <ol class="flex flex-col gap-1 pt-2">
                                <li v-for="e in order.events" :key="e.id" class="flex items-baseline justify-between gap-2 border-b border-default pb-1">
                                    <span>
                                        {{ eventTypeLabels[e.type] ?? e.type }}
                                        <span v-if="e.to_status" class="text-xs text-muted">→ {{ meta.orderStatuses.find((s) => s.value === e.to_status)?.label ?? meta.itemStatuses.find((s) => s.value === e.to_status)?.label ?? e.to_status }}</span>
                                        <span v-if="e.user" class="text-xs text-muted">· {{ e.user }}</span>
                                    </span>
                                    <time class="shrink-0 text-xs text-subtle">{{ e.created_at ? new Date(e.created_at).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' }) : '' }}</time>
                                </li>
                            </ol>
                        </details>
                    </div>
                </BaseCard>
            </div>
        </div>

        <BaseCard v-else-if="!loading">
            <EmptyState title="Adisyon bulunamadı" description="Silinmiş ya da erişiminiz olmayan bir adisyon." icon="alert-circle" />
        </BaseCard>

        <!-- Ürün yapılandırma modalı -->
        <BaseModal :open="productModal !== null" :title="productModal?.name ?? ''" @close="closeModal(() => (productModal = null))">
            <div v-if="productModal" class="flex flex-col gap-4">
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
                            <BaseButton size="sm" variant="secondary" icon-only label="Azalt" :disabled="pmQty <= 1" @click="pmQty--">
                                <AppIcon name="chevron-down" :size="14" />
                            </BaseButton>
                            <span class="min-w-8 text-center text-lg font-semibold">{{ pmQty }}</span>
                            <BaseButton size="sm" variant="secondary" icon-only label="Artır" @click="pmQty++">
                                <AppIcon name="chevron-up" :size="14" />
                            </BaseButton>
                        </div>
                    </FormField>
                    <p class="text-lg font-semibold">{{ money(pmTotal) }} ₺</p>
                </div>

                <FormField label="Not">
                    <BaseInput v-model="pmNote" placeholder="ör. az pişmiş, soğansız" />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeModal(() => (productModal = null))">Vazgeç</BaseButton>
                <BaseButton :loading="addBusy" @click="submitProductModal">
                    <AppIcon name="plus" :size="14" />
                    Adisyona ekle
                </BaseButton>
            </template>
        </BaseModal>

        <!-- Neden modalı (ikram / iptal / iade) -->
        <BaseModal :open="reasonModal !== null" :title="reasonModal ? reasonTitles[reasonModal.kind] : ''" size="sm" @close="closeModal(() => (reasonModal = null))">
            <p v-if="reasonModal?.item" class="pb-2 text-sm text-muted">{{ reasonModal.item.qty }} × {{ reasonModal.item.name }}</p>
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

        <!-- Ödeme -->
        <BaseModal :open="payModal" title="Ödeme al" size="sm" @close="closeModal(() => (payModal = false))">
            <div class="flex flex-col gap-3">
                <p class="text-sm text-muted">Kalan: <strong>{{ order?.remaining_display }} ₺</strong></p>
                <FormField label="Tutar (₺)" required>
                    <BaseInput v-model="payAmount" inputmode="decimal" placeholder="0,00" />
                </FormField>
                <BaseButton size="sm" variant="secondary" @click="payAmount = order ? money(order.remaining_minor) : ''">Tamamı</BaseButton>
                <BaseRadioGroup
                    v-model="payMethod"
                    label="Yöntem"
                    :options="[
                        { value: 'cash', label: 'Nakit' },
                        { value: 'card', label: 'Kart (fiziksel POS)' },
                    ]"
                />
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeModal(() => (payModal = false))">Vazgeç</BaseButton>
                <BaseButton :loading="opBusy" @click="submitPay">Ödemeyi kaydet</BaseButton>
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
                            <span>{{ i + 1 }}. kişi</span><span>{{ money(s) }} ₺</span>
                        </li>
                    </ol>
                </div>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeModal(() => (splitModal = false))">Kapat</BaseButton>
                <BaseButton :loading="opBusy" :disabled="splitMode === 'items' && splitItems.size === 0" @click="submitSplit">Böl</BaseButton>
            </template>
        </BaseModal>
    </PanelShell>
</template>
