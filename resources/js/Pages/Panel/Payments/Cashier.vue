<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
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
    fetchOrderPayments,
    fetchPendingOrders,
    fetchRegisters,
    metaFromProps,
    money,
    newIdempotencyKey,
    parseMoney,
    type PayableOrder,
    type PaymentRow,
    type RegisterRow,
} from './payments';

/**
 * KASİYER EKRANI (prompt §15) — yoğun saat önceliği:
 * solda ödeme bekleyen adisyonlar (hesap isteyenler önde), sağda tek
 * dokunuşlu tahsilat: hızlı tutar + yöntem + bahşiş + para üstü.
 */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

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
        if (!modalOpen) {
            void load(true);
            if (selected.value) void refreshSelected(true);
        }
    }, 5000);
});

onBeforeUnmount(() => {
    if (timer) clearInterval(timer);
});

/* ================= Sağ: seçili adisyon + tahsilat ================= */
const selected = ref<PayableOrder | null>(null);
const payments = ref<PaymentRow[]>([]);

async function select(order: PayableOrder): Promise<void> {
    selected.value = order;
    await refreshSelected();
    resetForm(order);
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

function resetForm(order: PayableOrder): void {
    amountText.value = money(order.remaining_minor);
    method.value = 'cash';
    tipText.value = '';
    tenderedText.value = '';
    noteText.value = '';
    roundCash.value = false;
}

function setQuickAmount(fraction: number): void {
    if (!selected.value) return;
    const v = fraction === 1
        ? selected.value.remaining_minor
        : Math.ceil(selected.value.remaining_minor * fraction);
    amountText.value = money(v);
}

async function pay(): Promise<void> {
    if (!selected.value || paying.value) return;

    if (amountMinor.value <= 0) {
        danger('Tutar geçersiz', 'Pozitif bir tutar girin.');
        return;
    }

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
        }, newIdempotencyKey());

        if (res.payment.status === 'succeeded') {
            success('Ödeme alındı', `${res.payment.method_label} — ${money(res.payment.amount_minor)} ₺${res.payment.change_minor > 0 ? ` · Para üstü ${money(res.payment.change_minor)} ₺` : ''}`);
        } else if (res.payment.status === 'pending') {
            success('Terminale gönderildi', 'Terminal onayı bekleniyor — gönderim tahsilat DEĞİLDİR; sonucu sorgulayın.');
        } else {
            danger('Ödeme başarısız', res.provider_result?.message ?? 'Sağlayıcı reddetti.');
        }

        await refreshSelected(true);
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
        if (selected.value) amountText.value = money(selected.value.remaining_minor);
    } catch (e) {
        danger('Uygulanamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        actionBusy.value = false;
    }
}
</script>

<template>
    <Head title="Kasa" />
    <PanelShell title="Kasa">
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

            <div class="grid gap-4 lg:grid-cols-[minmax(280px,1fr)_minmax(0,1.6fr)]">
                <!-- Sol: ödeme bekleyen adisyonlar -->
                <BaseCard title="Ödeme bekleyen adisyonlar" flush>
                    <div class="flex flex-col gap-2 p-3">
                        <SearchInput v-model="q" placeholder="Masa, müşteri, adisyon no…" />
                        <p v-if="loading" class="px-1 py-6 text-center text-sm text-muted">Yükleniyor…</p>
                        <EmptyState
                            v-else-if="orders.length === 0"
                            title="Bekleyen adisyon yok"
                            description="Açık ve ödenmemiş adisyonlar burada listelenir."
                            icon="check-circle"
                        />
                        <button
                            v-for="o in orders"
                            :key="o.id"
                            type="button"
                            class="flex flex-wrap items-center justify-between gap-2 rounded-lg border p-3 text-left transition hover:border-strong"
                            :class="selected?.id === o.id ? 'border-strong bg-inset' : 'border-default'"
                            @click="select(o)"
                        >
                            <span class="flex min-w-0 items-center gap-2">
                                <AppIcon :name="o.channel_icon" :size="16" class="shrink-0 text-subtle" />
                                <span class="truncate font-medium text-body">
                                    {{ o.table_name ?? o.customer_name ?? o.channel_label }} · #{{ o.id }}
                                </span>
                            </span>
                            <span class="flex items-center gap-2">
                                <BaseBadge :variant="o.status_variant" no-icon>
                                    <AppIcon :name="o.status_icon" :size="12" /> {{ o.status_label }}
                                </BaseBadge>
                                <span class="text-sm font-semibold tabular-nums text-body">{{ money(o.remaining_minor) }} ₺</span>
                            </span>
                        </button>
                    </div>
                </BaseCard>

                <!-- Sağ: tahsilat paneli -->
                <div class="flex flex-col gap-4">
                    <BaseCard v-if="!selected">
                        <EmptyState
                            title="Adisyon seçin"
                            description="Soldaki listeden ödeme alınacak adisyonu seçin."
                            icon="cart"
                        />
                    </BaseCard>

                    <template v-else>
                        <!-- Tutar dökümü -->
                        <BaseCard :title="`Adisyon #${selected.id} — ${selected.table_name ?? selected.customer_name ?? selected.channel_label}`">
                            <template #actions>
                                <BaseButton variant="ghost" size="sm" @click="openServiceCharge">Servis bedeli</BaseButton>
                            </template>
                            <dl class="grid gap-1 text-sm">
                                <div class="flex justify-between"><dt class="text-muted">Kalem toplamı</dt><dd class="tabular-nums">{{ money(selected.items_total_minor) }} ₺</dd></div>
                                <div v-if="selected.discount_minor > 0" class="flex justify-between"><dt class="text-muted">İndirim</dt><dd class="tabular-nums text-danger">−{{ money(selected.discount_minor) }} ₺</dd></div>
                                <div v-if="selected.service_charge_minor > 0" class="flex justify-between"><dt class="text-muted">Servis bedeli</dt><dd class="tabular-nums">{{ money(selected.service_charge_minor) }} ₺</dd></div>
                                <div v-if="selected.rounding_minor !== 0" class="flex justify-between"><dt class="text-muted">Yuvarlama</dt><dd class="tabular-nums">{{ selected.rounding_minor > 0 ? '+' : '−' }}{{ money(Math.abs(selected.rounding_minor)) }} ₺</dd></div>
                                <div class="flex justify-between border-t border-default pt-1 font-semibold"><dt>Toplam</dt><dd class="tabular-nums">{{ money(selected.total_minor) }} ₺</dd></div>
                                <div class="flex justify-between"><dt class="text-muted">Ödenen</dt><dd class="tabular-nums text-success">{{ money(selected.paid_minor) }} ₺</dd></div>
                                <div v-if="selected.refunded_minor > 0" class="flex justify-between"><dt class="text-muted">İade edilen</dt><dd class="tabular-nums">{{ money(selected.refunded_minor) }} ₺</dd></div>
                                <div class="flex justify-between text-base font-bold"><dt>Kalan</dt><dd class="tabular-nums">{{ money(selected.remaining_minor) }} ₺</dd></div>
                            </dl>
                        </BaseCard>

                        <!-- Ödeme alma -->
                        <BaseCard v-if="selected.remaining_minor > 0" title="Ödeme al">
                            <div class="flex flex-col gap-3">
                                <!-- Hızlı tutar -->
                                <div class="flex flex-wrap items-end gap-2">
                                    <FormField label="Tutar (₺)" required class="grow">
                                        <BaseInput v-model="amountText" inputmode="decimal" placeholder="0,00" />
                                    </FormField>
                                    <BaseButton variant="secondary" size="sm" @click="setQuickAmount(1)">Kalan</BaseButton>
                                    <BaseButton variant="secondary" size="sm" @click="setQuickAmount(0.5)">1/2</BaseButton>
                                    <BaseButton variant="secondary" size="sm" @click="setQuickAmount(1 / 3)">1/3</BaseButton>
                                </div>

                                <!-- Yöntem -->
                                <div>
                                    <p class="mb-1 text-sm font-medium text-body">Yöntem</p>
                                    <div class="grid grid-cols-3 gap-2 sm:grid-cols-5">
                                        <button
                                            v-for="m in meta.paymentMethods"
                                            :key="m.value"
                                            type="button"
                                            class="flex flex-col items-center gap-1 rounded-lg border p-2 text-xs transition hover:border-strong"
                                            :class="method === m.value ? 'border-strong bg-inset font-semibold' : 'border-default'"
                                            :aria-pressed="method === m.value"
                                            @click="method = m.value"
                                        >
                                            <AppIcon :name="m.icon" :size="18" />
                                            {{ m.label }}
                                        </button>
                                    </div>
                                    <p v-if="methodMeta?.terminal" class="mt-1 flex items-center gap-1 text-xs text-muted">
                                        <AppIcon name="info" :size="14" />
                                        Tutar POS terminaline gönderilir; tahsilat yalnız doğrulanmış terminal onayıyla tamamlanır.
                                    </p>
                                </div>

                                <!-- Bahşiş + nakit alanları -->
                                <div class="grid gap-3 sm:grid-cols-3">
                                    <FormField label="Bahşiş (₺)" hint="Adisyona işlemez; Z raporunda ayrı izlenir">
                                        <BaseInput v-model="tipText" inputmode="decimal" placeholder="0,00" />
                                    </FormField>
                                    <FormField v-if="method === 'cash'" label="Verilen para (₺)">
                                        <BaseInput v-model="tenderedText" inputmode="decimal" placeholder="0,00" />
                                    </FormField>
                                    <div v-if="method === 'cash'" class="flex flex-col justify-end gap-2 pb-1">
                                        <p v-if="changeMinor !== null" class="text-sm font-semibold text-body">
                                            Para üstü: <span class="tabular-nums">{{ money(changeMinor) }} ₺</span>
                                        </p>
                                        <label class="flex items-center gap-2 text-sm text-body">
                                            <input v-model="roundCash" type="checkbox" class="size-4 rounded border-default" />
                                            Kalanı {{ meta.cashRoundingStep }} kuruşa yuvarla
                                        </label>
                                    </div>
                                </div>

                                <FormField label="Not">
                                    <BaseInput v-model="noteText" placeholder="İsteğe bağlı" />
                                </FormField>

                                <BaseButton :loading="paying" block size="lg" @click="pay">
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
                    </template>
                </div>
            </div>
        </div>

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
    </PanelShell>
</template>
