<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import StaffPinDialog from '@/Components/panel/StaffPinDialog.vue';
import { useTerminalPin } from '@/composables/useTerminalPin';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import {
    apiIdempotent,
    fetchOrderDetail,
    fetchOrderPayments,
    fetchPendingOrders,
    fetchRegisters,
    metaFromProps,
    money,
    newIdempotencyKey,
    parseMoney,
    type OrderDetail,
    type OrderItemRow,
    type PayableOrder,
    type PaymentRow,
    type RegisterRow,
} from './payments';

/**
 * KASİYER EKRANI (prompt §15) — ödeme alan kişi için kapsamlı & ferah:
 * solda ödeme bekleyen adisyonlar, sağda seçili adisyonun KALEM DÖKÜMÜ
 * (ödeme öncesi gözden geçir + düzelt: adet/çıkar/ikram) + tek dokunuşlu
 * tahsilat (hızlı tutar + yöntem + bahşiş + para üstü + kısmi/split).
 * Kalemlerin HAZIRLIK durumu GÖSTERİLMEZ — tutar odaklıdır.
 */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const perms = ((page.props.auth as { permissions?: string[] } | undefined)?.permissions) ?? [];
const canEditItems = perms.includes('orders.update');
const canCompItems = perms.includes('orders.comp');
const canReviewItems = canEditItems || canCompItems || perms.includes('orders.view');
const { success, danger } = useToast();

// §13 Faz B: terminal (kasa) oturumda hassas para eylemleri PIN ister.
const { collectPin } = useTerminalPin();

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

onMounted(async () => {
    await load();
    try {
        registers.value = await fetchRegisters();
    } catch {
        /* cash.view yoksa gösterge gizli kalır */
    }
    timer = setInterval(() => {
        if (!modalOpen && !editMode.value) {
            void load(true);
            if (selected.value) {
                void refreshSelected(true);
                void refreshDetail(true);
            }
        }
    }, 5000);
});

onBeforeUnmount(() => {
    if (timer) clearInterval(timer);
});

/* ================= Sağ: seçili adisyon + tahsilat ================= */
const selected = ref<PayableOrder | null>(null);
const payments = ref<PaymentRow[]>([]);
const detail = ref<OrderDetail | null>(null);
const detailDenied = ref(false);

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
}

function setAmountMinor(v: number): void {
    amountText.value = money(Math.max(0, v));
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

async function pay(): Promise<void> {
    if (!selected.value || paying.value) return;

    if (amountMinor.value <= 0) {
        danger('Tutar geçersiz', 'Pozitif bir tutar girin.');
        return;
    }

    // §13 Faz B: terminal (kasa) oturumda ödeme alma PIN ister; işlem PIN
    // sahibine atfedilir. İptal edilirse tahsilat yapılmaz.
    const pinFields = await collectPin();
    if (pinFields === null) return;

    paying.value = true;
    try {
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
    voidTarget.value = null;
    refundTarget.value = null;
    serviceChargeOpen.value = false;
    compTarget.value = null;
    removeItemTarget.value = null;
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
function orderTitle(o: { table_name: string | null; customer_name: string | null; channel_label: string }): string {
    return o.table_name ?? o.customer_name ?? o.channel_label;
}
</script>

<template>
    <Head title="Kasa" />
    <PanelShell title="Kasa" immersive>
        <div class="flex flex-col gap-4">
            <!-- Kasa oturumu göstergesi -->
            <div v-if="meta.canCashView" class="flex flex-wrap items-center gap-3 rounded-lg border border-default bg-raised p-3">
                <AppIcon name="cart" :size="18" class="text-subtle" />
                <template v-if="activeRegister?.open_session">
                    <BaseBadge variant="success"><AppIcon name="check-circle" :size="12" /> Kasa açık</BaseBadge>
                    <span class="text-sm text-body">
                        {{ activeRegister.name }} · Z#{{ activeRegister.open_session.z_number }} ·
                        {{ activeRegister.open_session.opened_by ?? '—' }}
                    </span>
                </template>
                <template v-else>
                    <BaseBadge variant="warning"><AppIcon name="alert-triangle" :size="12" /> Açık kasa oturumu yok</BaseBadge>
                    <span class="text-sm text-muted">Nakit hareketleri Z raporuna bağlanmaz.</span>
                </template>
                <div class="ms-auto flex items-center gap-2">
                    <BaseSelect
                        v-if="registers.length > 1"
                        :model-value="activeRegisterId ? String(activeRegisterId) : ''"
                        size="sm"
                        placeholder="Kasa seç"
                        :options="registers.map((r) => ({ value: String(r.id), label: r.name }))"
                        @update:model-value="(v: string) => (activeRegisterId = v ? Number(v) : null)"
                    />
                    <BaseButton variant="secondary" size="sm" href="/panel/kasa/yonetim">Kasa yönetimi</BaseButton>
                </div>
            </div>

            <div class="grid gap-4 xl:grid-cols-[minmax(300px,360px)_minmax(0,1fr)]">
                <!-- Sol: ödeme bekleyen adisyonlar -->
                <div class="xl:sticky xl:top-4 xl:self-start">
                    <BaseCard flush>
                        <template #header>
                            <div class="flex w-full items-center justify-between gap-2">
                                <h2 class="text-sm font-semibold text-body">Ödeme bekleyen adisyonlar</h2>
                                <BaseBadge v-if="orders.length" variant="primary" no-icon>{{ orders.length }}</BaseBadge>
                            </div>
                        </template>
                        <div class="flex flex-col gap-2 p-3">
                            <SearchInput v-model="q" placeholder="Masa, müşteri, adisyon no…" />
                            <div v-if="orders.length" class="flex items-center justify-between rounded-md bg-inset px-3 py-2 text-sm">
                                <span class="text-muted">Bekleyen toplam</span>
                                <span class="font-semibold tabular-nums text-body">{{ money(totalPending) }} ₺</span>
                            </div>
                            <p v-if="loading" class="px-1 py-6 text-center text-sm text-muted">Yükleniyor…</p>
                            <EmptyState
                                v-else-if="orders.length === 0"
                                title="Bekleyen adisyon yok"
                                description="Açık ve ödenmemiş adisyonlar burada listelenir."
                                icon="check-circle"
                            />
                            <div v-else class="flex max-h-[calc(100vh-16rem)] flex-col gap-2 overflow-y-auto pe-0.5">
                                <button
                                    v-for="o in orders"
                                    :key="o.id"
                                    type="button"
                                    class="flex flex-col gap-2 rounded-lg border p-3 text-left transition hover:border-strong"
                                    :class="selected?.id === o.id ? 'border-primary bg-primary-soft' : 'border-default'"
                                    @click="select(o)"
                                >
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
                    </BaseCard>
                </div>

                <!-- Sağ: seçili adisyon çalışma alanı -->
                <div class="flex flex-col gap-4">
                    <BaseCard v-if="!selected">
                        <EmptyState
                            title="Adisyon seçin"
                            description="Soldaki listeden ödeme alınacak adisyonu seçin; kalemleri gözden geçirip tahsilatı buradan yapın."
                            icon="cart"
                        />
                    </BaseCard>

                    <template v-else>
                        <!-- Başlık / kalan tutar kahramanı -->
                        <div class="rounded-lg border border-default bg-raised p-4 shadow-card">
                            <div class="flex flex-wrap items-start justify-between gap-4">
                                <div class="min-w-0">
                                    <div class="flex flex-wrap items-center gap-2">
                                        <h2 class="text-lg font-bold text-body">{{ orderTitle(selected) }}</h2>
                                        <span class="text-sm text-subtle">Adisyon #{{ selected.id }}</span>
                                    </div>
                                    <div class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted">
                                        <span v-if="guestCount" class="flex items-center gap-1"><AppIcon name="users" :size="14" /> {{ guestCount }} kişi</span>
                                        <span v-if="selected.items_count">{{ selected.items_count }} kalem</span>
                                        <span v-if="selected.created_at">{{ elapsed(selected.created_at) }} önce açıldı</span>
                                        <BaseBadge v-if="payState(selected) === 'partial'" variant="warning" no-icon>Kısmi ödendi</BaseBadge>
                                    </div>
                                </div>
                                <div class="text-right">
                                    <p class="text-xs font-medium uppercase tracking-wide text-subtle">Kalan tutar</p>
                                    <p class="text-3xl font-bold tabular-nums" :class="selected.remaining_minor > 0 ? 'text-body' : 'text-success'">
                                        {{ money(selected.remaining_minor) }} <span class="text-lg">₺</span>
                                    </p>
                                    <p v-if="selected.paid_minor > 0" class="text-xs text-muted">
                                        {{ money(selected.paid_minor) }} ₺ / {{ money(selected.total_minor) }} ₺ ödendi
                                    </p>
                                </div>
                            </div>
                        </div>

                        <!-- Ödeme tamamlandı bandı -->
                        <div v-if="selected.remaining_minor === 0" class="flex flex-wrap items-center gap-3 rounded-lg border border-success-border bg-success-soft p-4">
                            <AppIcon name="check-circle" :size="22" class="text-success" />
                            <div class="min-w-0">
                                <p class="font-semibold text-success">Adisyon tamamen ödendi</p>
                                <p class="text-sm text-muted">Toplam {{ money(selected.total_minor) }} ₺ tahsil edildi. Fiş verip adisyonu kapatabilirsiniz.</p>
                            </div>
                        </div>

                        <div class="grid gap-4 lg:grid-cols-2 lg:items-start">
                            <!-- Sol iç: kalem dökümü + toplam (kaydırılabilir inceleme) -->
                            <div class="flex flex-col gap-4">
                                <!-- Kalem dökümü (gözden geçir + düzelt) -->
                                <BaseCard flush>
                                    <template #header>
                                        <div class="flex w-full items-center justify-between gap-2">
                                            <h2 class="text-sm font-semibold text-body">Adisyon kalemleri</h2>
                                            <BaseButton
                                                v-if="detail && (canEditItems || canCompItems) && canEditNow"
                                                :variant="editMode ? 'primary' : 'secondary'"
                                                size="sm"
                                                @click="toggleEdit"
                                            >
                                                <AppIcon name="pencil" :size="14" /> {{ editMode ? 'Düzenlemeyi bitir' : 'Düzelt' }}
                                            </BaseButton>
                                        </div>
                                    </template>

                                    <p v-if="detailDenied" class="p-4 text-sm text-muted">
                                        Kalem dökümünü görme yetkiniz yok; aşağıdaki tutar özeti üzerinden tahsilat yapabilirsiniz.
                                    </p>
                                    <p v-else-if="!detail" class="p-4 text-sm text-muted">Kalemler yükleniyor…</p>
                                    <EmptyState v-else-if="visibleItems.length === 0" title="Kalem yok" icon="cart" />
                                    <ul v-else class="divide-y divide-default lg:max-h-[calc(100vh-24rem)] lg:overflow-y-auto">
                                        <li v-for="it in visibleItems" :key="it.id" class="flex items-start gap-3 p-3">
                                            <span class="mt-0.5 min-w-9 shrink-0 rounded-md bg-inset px-2 py-1 text-center text-sm font-semibold tabular-nums text-body">
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

                                                <!-- Düzenleme kontrolleri -->
                                                <div v-if="editMode && canEditNow" class="mt-2 flex flex-wrap items-center gap-2">
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
                                                        <BaseButton variant="ghost" size="sm" :loading="itemBusy === it.id" @click="askRemoveItem(it)">
                                                            <AppIcon name="trash" :size="14" /> Çıkar
                                                        </BaseButton>
                                                    </template>
                                                    <BaseButton
                                                        v-if="canCompItems && !it.is_comp"
                                                        variant="ghost"
                                                        size="sm"
                                                        :loading="itemBusy === it.id"
                                                        @click="askComp(it)"
                                                    >
                                                        İkram yap
                                                    </BaseButton>
                                                    <span v-else-if="it.is_comp" class="text-xs text-muted">İkram · {{ it.comp_reason }}</span>
                                                </div>
                                            </div>
                                            <span class="shrink-0 text-right text-sm font-semibold tabular-nums" :class="it.is_comp ? 'text-subtle line-through' : 'text-body'">
                                                {{ money(it.line_total_minor) }} ₺
                                            </span>
                                        </li>
                                    </ul>
                                    <p v-if="detail && editMode" class="border-t border-default px-4 py-2 text-xs text-muted">
                                        Değişiklikler anında adisyona ve kalan tutara işler. Bittiğinde “Düzenlemeyi bitir”e basın.
                                    </p>
                                </BaseCard>

                                <!-- Tutar dökümü -->
                                <BaseCard title="Tutar özeti">
                                    <template #actions>
                                        <BaseButton variant="ghost" size="sm" @click="openServiceCharge">Servis bedeli</BaseButton>
                                    </template>
                                    <dl class="grid gap-1.5 text-sm">
                                        <div class="flex justify-between"><dt class="text-muted">Kalem toplamı</dt><dd class="tabular-nums">{{ money(selected.items_total_minor) }} ₺</dd></div>
                                        <div v-if="compTotalMinor > 0" class="flex justify-between"><dt class="text-muted">İkram</dt><dd class="tabular-nums text-info">−{{ money(compTotalMinor) }} ₺</dd></div>
                                        <div v-if="selected.discount_minor > 0" class="flex justify-between"><dt class="text-muted">İndirim</dt><dd class="tabular-nums text-danger">−{{ money(selected.discount_minor) }} ₺</dd></div>
                                        <div v-if="selected.service_charge_minor > 0" class="flex justify-between"><dt class="text-muted">Servis bedeli</dt><dd class="tabular-nums">{{ money(selected.service_charge_minor) }} ₺</dd></div>
                                        <div v-if="selected.rounding_minor !== 0" class="flex justify-between"><dt class="text-muted">Yuvarlama</dt><dd class="tabular-nums">{{ selected.rounding_minor > 0 ? '+' : '−' }}{{ money(Math.abs(selected.rounding_minor)) }} ₺</dd></div>
                                        <div class="mt-1 flex justify-between border-t border-default pt-2 text-base font-semibold"><dt>Toplam</dt><dd class="tabular-nums">{{ money(selected.total_minor) }} ₺</dd></div>
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
                                        <div v-if="selected.paid_minor > 0" class="flex justify-between"><dt class="text-muted">Ödenen</dt><dd class="tabular-nums text-success">{{ money(selected.paid_minor) }} ₺</dd></div>
                                        <div v-if="selected.refunded_minor > 0" class="flex justify-between"><dt class="text-muted">İade edilen</dt><dd class="tabular-nums">{{ money(selected.refunded_minor) }} ₺</dd></div>
                                        <div class="flex justify-between text-lg font-bold"><dt>Kalan</dt><dd class="tabular-nums">{{ money(selected.remaining_minor) }} ₺</dd></div>
                                    </dl>
                                </BaseCard>
                            </div>

                            <!-- Sağ iç: yapışkan ödeme paneli (masaüstünde kaydırmadan erişilebilir) -->
                            <div class="flex flex-col gap-4 lg:sticky lg:top-4 lg:self-start">
                                <BaseCard v-if="selected.remaining_minor > 0" title="Ödeme al">
                                    <div class="flex flex-col gap-4">
                                        <!-- Yöntem -->
                                        <div>
                                            <p class="mb-1.5 text-sm font-medium text-body">Ödeme yöntemi</p>
                                            <div class="grid grid-cols-3 gap-2 sm:grid-cols-4">
                                                <button
                                                    v-for="m in meta.paymentMethods"
                                                    :key="m.value"
                                                    type="button"
                                                    class="flex min-h-16 flex-col items-center justify-center gap-1 rounded-lg border p-2 text-xs transition hover:border-strong"
                                                    :class="method === m.value ? 'border-primary bg-primary-soft font-semibold text-primary' : 'border-default text-body'"
                                                    :aria-pressed="method === m.value"
                                                    @click="method = m.value"
                                                >
                                                    <AppIcon :name="m.icon" :size="22" />
                                                    {{ m.label }}
                                                </button>
                                            </div>
                                            <p v-if="methodMeta?.terminal" class="mt-1.5 flex items-center gap-1 text-xs text-muted">
                                                <AppIcon name="info" :size="14" />
                                                Tutar POS terminaline gönderilir; tahsilat yalnız doğrulanmış terminal onayıyla tamamlanır.
                                            </p>
                                        </div>

                                        <!-- Tahsil tutarı -->
                                        <div>
                                            <FormField label="Tahsil edilecek tutar (₺)" required>
                                                <BaseInput v-model="amountText" inputmode="decimal" placeholder="0,00" class="text-lg font-semibold" />
                                            </FormField>
                                            <div class="mt-2 flex flex-wrap gap-2">
                                                <BaseButton variant="secondary" size="sm" @click="setQuickAmount(1)">Tamamı</BaseButton>
                                                <BaseButton variant="secondary" size="sm" @click="setQuickAmount(0.5)">½</BaseButton>
                                                <BaseButton variant="secondary" size="sm" @click="setQuickAmount(1 / 3)">⅓</BaseButton>
                                                <BaseButton v-if="guestCount && guestCount > 1" variant="secondary" size="sm" @click="splitByGuests">
                                                    Kişi başı ({{ guestCount }})
                                                </BaseButton>
                                            </div>
                                            <p v-if="isPartial" class="mt-2 flex items-center gap-1 text-xs text-warning">
                                                <AppIcon name="info" :size="14" />
                                                Kısmi ödeme — bu tahsilat sonrası kalan {{ money(afterPaymentRemaining) }} ₺ olur.
                                            </p>
                                        </div>

                                        <!-- Nakit: verilen para + para üstü -->
                                        <div v-if="method === 'cash'" class="rounded-lg border border-default bg-inset p-3">
                                            <FormField label="Verilen para (₺)">
                                                <BaseInput v-model="tenderedText" inputmode="decimal" placeholder="0,00" />
                                            </FormField>
                                            <div class="mt-2 flex flex-wrap gap-2">
                                                <BaseButton
                                                    v-for="preset in cashPresets"
                                                    :key="preset"
                                                    variant="secondary"
                                                    size="sm"
                                                    @click="tenderedText = money(preset)"
                                                >
                                                    {{ money(preset) }}
                                                </BaseButton>
                                            </div>
                                            <div class="mt-3 flex items-center justify-between border-t border-default pt-2">
                                                <span class="text-sm text-muted">Para üstü</span>
                                                <span class="text-lg font-bold tabular-nums text-body">{{ changeMinor !== null ? money(changeMinor) : '—' }} ₺</span>
                                            </div>
                                            <label class="mt-2 flex items-center gap-2 text-sm text-body">
                                                <input v-model="roundCash" type="checkbox" class="size-4 rounded border-default" />
                                                Kalanı {{ meta.cashRoundingStep }} kuruşa yuvarla
                                            </label>
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

                                        <!-- Masaüstü: yapışkan panelin sonunda erişilebilir; mobilde sabit alt çubuk kullanılır -->
                                        <BaseButton :loading="paying" block size="lg" class="hidden lg:flex" @click="pay">
                                            {{ methodMeta?.terminal ? 'Terminale gönder' : 'Ödemeyi al' }} — {{ money(amountMinor) }} ₺
                                        </BaseButton>
                                    </div>
                                </BaseCard>

                                <!-- Ödeme geçmişi -->
                                <BaseCard title="Ödemeler" flush>
                                    <EmptyState v-if="payments.length === 0" title="Henüz ödeme yok" icon="cart" />
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
                                                    v-if="p.status === 'pending'"
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
                                </BaseCard>
                            </div>
                        </div>

                        <!-- Mobil: her zaman erişilebilir ödeme aksiyonu (alt navigasyonun üstünde, safe-area) -->
                        <div
                            v-if="selected.remaining_minor > 0"
                            class="fixed inset-x-0 z-(--z-sticky) border-t border-default bg-raised px-4 py-3 shadow-lg lg:hidden"
                            style="bottom: calc(3.5rem + env(safe-area-inset-bottom))"
                        >
                            <div class="mb-2 flex items-center justify-between gap-2 text-sm">
                                <span class="text-muted">Kalan <span class="font-semibold text-body">{{ money(selected.remaining_minor) }} ₺</span></span>
                                <span class="flex items-center gap-1 truncate text-xs text-muted">
                                    <AppIcon v-if="methodMeta" :name="methodMeta.icon" :size="14" /> {{ methodMeta?.label }}
                                </span>
                            </div>
                            <BaseButton :loading="paying" block size="lg" @click="pay">
                                {{ methodMeta?.terminal ? 'Terminale gönder' : 'Ödemeyi al' }} — {{ money(amountMinor) }} ₺
                            </BaseButton>
                        </div>
                        <!-- Sabit çubuk son içeriği örtmesin diye mobil boşluk -->
                        <div class="h-32 lg:hidden" aria-hidden="true"></div>
                    </template>
                </div>
            </div>
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

        <!-- §13 Faz B: terminal (kasa) hassas eylem PIN modalı -->
        <StaffPinDialog />
    </PanelShell>
</template>
