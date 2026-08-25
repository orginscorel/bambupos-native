<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { formatDate } from '@/lib/format';
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
import InventoryNav from './components/InventoryNav.vue';
import {
    fetchItems, fetchSuppliers, fetchWarehouses, metaFromProps, money,
    paymentStatusLabel, paymentStatusVariant,
    type ItemRow, type PurchaseRow, type SuggestionGroup, type SupplierRow, type WarehouseRow,
} from './inventory';

/**
 * MAL KABUL / SATIN ALMA (§17.6). Akış: talep(draft) → sipariş(ordered) →
 * mal kabul (stok GİRER, defter+ortalama maliyet güncellenir). Miktar
 * milli-int, para kuruş-int; hepsi sunucuda çözülür.
 */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

const orders = ref<PurchaseRow[]>([]);
const suppliers = ref<SupplierRow[]>([]);
const warehouses = ref<WarehouseRow[]>([]);
const items = ref<ItemRow[]>([]);
const suggestions = ref<SuggestionGroup[]>([]);
const loading = ref(true);

async function loadOrders(): Promise<void> {
    orders.value = (await api<{ orders: PurchaseRow[] }>('/api/v1/inventory/purchases')).orders;
}

async function loadAll(): Promise<void> {
    loading.value = true;
    try {
        [suppliers.value, warehouses.value, items.value] = await Promise.all([fetchSuppliers(), fetchWarehouses(), fetchItems()]);
        await loadOrders();
        suggestions.value = (await api<{ suggestions: SuggestionGroup[] }>('/api/v1/inventory/purchases/suggested')).suggestions;
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

onMounted(loadAll);

const supplierOptions = computed(() => suppliers.value.filter((s) => s.is_active).map((s) => ({ value: String(s.id), label: s.name })));
const warehouseOptions = computed(() => warehouses.value.map((w) => ({ value: String(w.id), label: w.name })));
const itemOptions = computed(() => items.value.map((i) => ({ value: String(i.id), label: i.name })));

/* ---- Yeni sipariş ---- */
const createOpen = ref(false);
const busy = ref(false);
const createErr = ref<Record<string, string[]>>({});
const draft = ref<{ supplier_id: string; warehouse_id: string; expected_at: string; note: string; lines: { item_id: string; qty: string; unit_price: string }[] }>({
    supplier_id: '', warehouse_id: '', expected_at: '', note: '', lines: [{ item_id: '', qty: '', unit_price: '' }],
});

function openCreate(): void {
    draft.value = { supplier_id: '', warehouse_id: '', expected_at: '', note: '', lines: [{ item_id: '', qty: '', unit_price: '' }] };
    createErr.value = {};
    createOpen.value = true;
}

const addLine = (): void => { draft.value.lines.push({ item_id: '', qty: '', unit_price: '' }); };
const removeLine = (i: number): void => { draft.value.lines.splice(i, 1); };

async function submitCreate(): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    createErr.value = {};
    try {
        const lines = draft.value.lines.filter((l) => l.item_id && l.qty && l.unit_price)
            .map((l) => ({ item_id: Number(l.item_id), qty: l.qty, unit_price: l.unit_price }));
        await api('/api/v1/inventory/purchases', {
            method: 'POST',
            body: {
                supplier_id: Number(draft.value.supplier_id),
                warehouse_id: draft.value.warehouse_id ? Number(draft.value.warehouse_id) : null,
                expected_at: draft.value.expected_at || null,
                note: draft.value.note || null,
                lines,
            },
        });
        success('Sipariş oluşturuldu', 'Taslak olarak kaydedildi.');
        createOpen.value = false;
        await loadAll();
    } catch (e) {
        if (e instanceof ApiError) { createErr.value = e.errors; danger('Kaydedilemedi', e.displayMessage); }
    } finally {
        busy.value = false;
    }
}

/* ---- Detay + mal kabul ---- */
const detailOpen = ref(false);
const detail = ref<PurchaseRow | null>(null);
const receive = ref<Record<number, { qty: string; lot_no: string; expires_at: string }>>({});

async function openDetail(id: number): Promise<void> {
    detail.value = null;
    detailOpen.value = true;
    try {
        detail.value = (await api<{ order: PurchaseRow }>(`/api/v1/inventory/purchases/${id}`)).order;
        receive.value = {};
        for (const l of detail.value.lines ?? []) {
            const remaining = (l.qty_milli - l.received_qty_milli) / 1000;
            receive.value[l.id] = { qty: remaining > 0 ? String(remaining).replace('.', ',') : '', lot_no: '', expires_at: '' };
        }
    } catch (e) {
        danger('Açılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    }
}

async function transition(status: string): Promise<void> {
    if (!detail.value) return;
    try {
        detail.value = (await api<{ order: PurchaseRow }>(`/api/v1/inventory/purchases/${detail.value.id}/transition`, { method: 'POST', body: { status } })).order;
        success('Durum güncellendi', '');
        await loadOrders();
    } catch (e) {
        danger('Güncellenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    }
}

async function submitReceive(): Promise<void> {
    if (!detail.value || busy.value) return;
    busy.value = true;
    try {
        const lines = Object.entries(receive.value)
            .filter(([, v]) => v.qty && Number(String(v.qty).replace(',', '.')) > 0)
            .map(([lineId, v]) => ({ line_id: Number(lineId), qty: v.qty, lot_no: v.lot_no || null, expires_at: v.expires_at || null }));
        if (lines.length === 0) { danger('Miktar girin', 'En az bir satır için kabul miktarı girin.'); return; }
        detail.value = (await api<{ order: PurchaseRow }>(`/api/v1/inventory/purchases/${detail.value.id}/receive`, { method: 'POST', body: { lines } })).order;
        success('Mal kabul edildi', 'Stok girişi deftere işlendi, ortalama maliyet güncellendi.');
        await loadAll();
        await openDetail(detail.value.id);
    } catch (e) {
        danger('Kabul edilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}

const cErr = (f: string): string => createErr.value[f]?.[0] ?? '';
const canReceive = computed(() => detail.value && ['ordered', 'partially_received'].includes(detail.value.status));
</script>

<template>
    <Head title="Mal Kabul / Satın Alma" />
    <PanelShell title="Stok" flush canvas>
        <div class="shrink-0 border-b border-default bg-raised px-4 py-2.5 sm:px-6">
            <InventoryNav active="purchasing" />
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">
        <div class="mb-3 flex items-center justify-between">
            <p class="text-sm text-muted">Sipariş oluştur, mal kabulünde stok otomatik girer ve ortalama maliyet güncellenir.</p>
            <BaseButton v-if="meta.canAdjust" size="sm" @click="openCreate">
                <AppIcon name="plus" :size="14" /> Yeni sipariş
            </BaseButton>
        </div>

        <!-- Önerilen sipariş -->
        <BaseCard v-if="suggestions.length" title="Önerilen sipariş (min. altındakiler)" class="mb-4">
            <div v-for="(g, gi) in suggestions" :key="gi" class="mb-2 last:mb-0">
                <p class="text-xs font-semibold text-muted">{{ g.supplier.name }}</p>
                <ul class="flex flex-wrap gap-1.5 pt-1">
                    <li v-for="s in g.items" :key="s.item_id">
                        <BaseBadge variant="warning" no-icon>
                            {{ s.name }} · {{ (s.suggested_qty_milli / 1000).toLocaleString('tr-TR') }} {{ s.base_unit }}
                        </BaseBadge>
                    </li>
                </ul>
            </div>
        </BaseCard>

        <BaseCard flush>
            <div class="w-full overflow-x-auto overscroll-x-contain">
                <table class="w-full min-w-max border-collapse text-sm" aria-label="Satın alma siparişleri">
                    <thead>
                        <tr class="border-b border-default bg-surface-alt text-xs font-semibold tracking-wide text-muted uppercase">
                            <th class="px-4 py-2.5 text-left">#</th>
                            <th class="px-4 py-2.5 text-left">Tedarikçi</th>
                            <th class="px-4 py-2.5 text-left">Durum</th>
                            <th class="px-4 py-2.5 text-left">Ödeme</th>
                            <th class="px-4 py-2.5 text-right">Fatura</th>
                            <th class="px-4 py-2.5 text-right">Satır</th>
                            <th class="px-4 py-2.5 text-left">Beklenen</th>
                            <th class="px-4 py-2.5"></th>
                        </tr>
                    </thead>
                    <tbody v-if="!loading && orders.length">
                        <tr v-for="o in orders" :key="o.id" class="cursor-pointer border-b border-default hover:bg-inset" @click="openDetail(o.id)">
                            <td class="px-4 py-2 tabular-nums text-muted">#{{ o.id }}</td>
                            <td class="px-4 py-2 font-medium">{{ o.supplier_name }}</td>
                            <td class="px-4 py-2"><BaseBadge :variant="(o.status_variant as any)" no-icon>{{ o.status_label }}</BaseBadge></td>
                            <td class="px-4 py-2"><BaseBadge :variant="paymentStatusVariant(o.payment_status)" no-icon>{{ paymentStatusLabel(o.payment_status) }}</BaseBadge></td>
                            <td class="px-4 py-2 text-right tabular-nums text-muted">{{ o.invoice_total_minor != null ? money(o.invoice_total_minor) : '—' }}</td>
                            <td class="px-4 py-2 text-right tabular-nums text-muted">{{ o.line_count }}</td>
                            <td class="px-4 py-2 text-muted">{{ o.expected_at ? formatDate(o.expected_at) : '—' }}</td>
                            <td class="px-4 py-2 text-right"><AppIcon name="chevron-right" :size="16" class="text-subtle" /></td>
                        </tr>
                    </tbody>
                </table>
                <div v-if="loading" class="p-6 text-center text-sm text-muted">Yükleniyor…</div>
                <EmptyState v-else-if="!orders.length" title="Sipariş yok" description="İlk satın alma siparişini oluşturun; mal kabulünde stok girişi otomatik işlenir." />
            </div>
        </BaseCard>

        <!-- Yeni sipariş -->
        <BaseModal :open="createOpen" title="Yeni satın alma siparişi" size="lg" @close="createOpen = false">
            <form class="flex flex-col gap-3" @submit.prevent="submitCreate">
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Tedarikçi" required :error="cErr('supplier_id')">
                        <BaseSelect v-model="draft.supplier_id" :options="supplierOptions" placeholder="Seçin…" />
                    </FormField>
                    <FormField label="Depo (mal kabul)" :error="cErr('warehouse_id')">
                        <BaseSelect v-model="draft.warehouse_id" :options="warehouseOptions" placeholder="Varsayılan depo" />
                    </FormField>
                </div>
                <FormField label="Beklenen teslim" :error="cErr('expected_at')"><BaseInput v-model="draft.expected_at" type="date" /></FormField>

                <div class="rounded-md border border-default p-2">
                    <div class="mb-1 flex items-center justify-between">
                        <span class="text-xs font-semibold text-muted uppercase">Kalemler</span>
                        <BaseButton size="sm" variant="ghost" @click="addLine"><AppIcon name="plus" :size="14" /> Satır</BaseButton>
                    </div>
                    <div v-for="(l, i) in draft.lines" :key="i" class="mb-2 grid grid-cols-[1fr_5rem_6rem_auto] items-center gap-2">
                        <BaseSelect v-model="l.item_id" :options="itemOptions" size="sm" placeholder="Kalem" />
                        <BaseInput v-model="l.qty" size="sm" inputmode="decimal" placeholder="Miktar" />
                        <BaseInput v-model="l.unit_price" size="sm" inputmode="decimal" placeholder="Birim ₺" />
                        <BaseButton size="sm" variant="ghost" :disabled="draft.lines.length <= 1" @click="removeLine(i)"><AppIcon name="trash" :size="14" /></BaseButton>
                    </div>
                    <p v-if="cErr('lines')" class="text-xs text-danger">{{ cErr('lines') }}</p>
                </div>

                <FormField label="Not" :error="cErr('note')"><BaseInput v-model="draft.note" /></FormField>
                <div class="flex justify-end gap-2 pt-1">
                    <BaseButton variant="secondary" @click="createOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="busy">Taslak oluştur</BaseButton>
                </div>
            </form>
        </BaseModal>

        <!-- Detay + mal kabul -->
        <BaseModal :open="detailOpen" :title="detail ? `Sipariş #${detail.id} — ${detail.supplier_name}` : 'Yükleniyor…'" size="lg" @close="detailOpen = false">
            <div v-if="detail" class="flex flex-col gap-3">
                <div class="flex flex-wrap items-center gap-2">
                    <BaseBadge :variant="(detail.status_variant as any)" no-icon>{{ detail.status_label }}</BaseBadge>
                    <span class="text-sm text-muted">{{ detail.warehouse_name ?? 'Varsayılan depo' }}</span>
                    <span v-if="meta.canAdjust" class="ms-auto flex gap-1.5">
                        <BaseButton v-if="detail.status === 'draft'" size="sm" variant="secondary" @click="transition('ordered')">Sipariş ver</BaseButton>
                        <BaseButton v-if="['draft','quoted','ordered'].includes(detail.status)" size="sm" variant="ghost" @click="transition('cancelled')">İptal</BaseButton>
                    </span>
                </div>

                <div class="w-full overflow-x-auto">
                    <table class="w-full text-sm">
                        <thead>
                            <tr class="border-b border-default text-xs text-muted uppercase">
                                <th class="py-2 text-left">Kalem</th>
                                <th class="py-2 text-right">Sipariş</th>
                                <th class="py-2 text-right">Kabul</th>
                                <th class="py-2 text-right">Birim ₺</th>
                                <th v-if="canReceive && meta.canAdjust" class="py-2 text-right">Bu kabul</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="l in detail.lines" :key="l.id" class="border-b border-default">
                                <td class="py-2 font-medium">{{ l.item_name }} <span class="text-subtle">/ {{ l.unit }}</span></td>
                                <td class="py-2 text-right tabular-nums">{{ l.qty }}</td>
                                <td class="py-2 text-right tabular-nums text-muted">{{ l.received_qty }}</td>
                                <td class="py-2 text-right tabular-nums">{{ money(l.unit_price_minor) }}</td>
                                <td v-if="canReceive && meta.canAdjust && receive[l.id]" class="py-2 text-right">
                                    <BaseInput v-model="receive[l.id].qty" size="sm" inputmode="decimal" class="w-24" />
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>

                <div v-if="canReceive && meta.canAdjust" class="flex justify-end">
                    <BaseButton :loading="busy" @click="submitReceive">Mal kabul et (stok gir)</BaseButton>
                </div>
                <p v-else-if="detail.status === 'received'" class="text-sm text-success">Bu sipariş tamamen teslim alındı.</p>
                <p v-else-if="detail.status === 'draft'" class="text-xs text-subtle">Mal kabulü için önce "Sipariş ver" ile durumu ilerletin.</p>
            </div>
            <div v-else class="p-6 text-center text-sm text-muted">Yükleniyor…</div>
        </BaseModal>
        </div>
        </div>
    </PanelShell>
</template>
