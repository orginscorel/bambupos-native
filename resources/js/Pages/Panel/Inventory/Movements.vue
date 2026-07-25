<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { formatDateTime } from '@/lib/format';
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
    fetchItems, fetchWarehouses, metaFromProps, money,
    type ItemRow, type MovementRequestRow, type MovementRow, type WarehouseRow,
} from './inventory';

/**
 * HAREKET DEFTERİ (§17.4): salt görüntüleme + ONAYLI manuel giriş.
 * Defterde düzenleme/silme YOKTUR; yanlış kayıt ters kayıtla düzeltilir.
 * Manuel giriş: stock.adjust yoksa isteğe düşer, yetkili onaylar.
 */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

const movements = ref<MovementRow[]>([]);
const requests = ref<MovementRequestRow[]>([]);
const items = ref<ItemRow[]>([]);
const warehouses = ref<WarehouseRow[]>([]);
const loading = ref(true);
const totalRows = ref(0);
const currentPage = ref(1);
const lastPage = ref(1);

const filterItem = ref('');
const filterWarehouse = ref('');
const filterType = ref('');
const filterFrom = ref('');
const filterTo = ref('');

async function loadMovements(pageNo = 1): Promise<void> {
    loading.value = true;
    try {
        const params = new URLSearchParams();
        if (filterItem.value) params.set('item_id', filterItem.value);
        if (filterWarehouse.value) params.set('warehouse_id', filterWarehouse.value);
        if (filterType.value) params.set('type', filterType.value);
        if (filterFrom.value) params.set('from', filterFrom.value);
        if (filterTo.value) params.set('to', filterTo.value);
        params.set('page', String(pageNo));

        const res = await api<{ movements: MovementRow[]; total: number; current_page: number; last_page: number }>(
            `/api/v1/inventory/movements?${params.toString()}`,
        );
        movements.value = res.movements;
        totalRows.value = res.total;
        currentPage.value = res.current_page;
        lastPage.value = res.last_page;
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

async function loadAll(): Promise<void> {
    try {
        [items.value, warehouses.value] = await Promise.all([fetchItems(), fetchWarehouses()]);
        requests.value = (await api<{ requests: MovementRequestRow[] }>('/api/v1/inventory/movement-requests')).requests;
    } catch {
        /* liste yüklemesi ana akışı bozmasın */
    }
    await loadMovements();
}

onMounted(loadAll);

const itemOptions = computed(() => [{ value: '', label: 'Tüm kalemler' }, ...items.value.map((i) => ({ value: String(i.id), label: i.name }))]);
const warehouseOptions = computed(() => [{ value: '', label: 'Tüm depolar' }, ...warehouses.value.map((w) => ({ value: String(w.id), label: w.name }))]);
const typeOptions = computed(() => [{ value: '', label: 'Tüm türler' }, ...meta.movementTypes]);
const manualTypes = computed(() => meta.movementTypes.filter((t) => t.manual));

/* ---- Manuel hareket girişi ---- */
const formOpen = ref(false);
const busy = ref(false);
const formErrors = ref<Record<string, string[]>>({});
const form = ref({ warehouse_id: '', item_id: '', type: 'manual_adjust', qty: '', unit_cost: '', lot_no: '', expires_at: '', description: '' });

const selectedItem = computed(() => items.value.find((i) => String(i.id) === form.value.item_id));

async function submitManual(): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    formErrors.value = {};
    try {
        const body: Record<string, unknown> = {
            warehouse_id: Number(form.value.warehouse_id),
            item_id: Number(form.value.item_id),
            type: form.value.type,
            qty: form.value.qty,
            description: form.value.description,
            lot_no: form.value.lot_no || null,
            expires_at: form.value.expires_at || null,
        };
        if (form.value.unit_cost) {
            body.unit_cost_minor = Math.round(Number(String(form.value.unit_cost).replace(',', '.')) * 100);
        }
        await api('/api/v1/inventory/movements', { method: 'POST', body });
        success(
            meta.canAdjust ? 'Hareket deftere işlendi' : 'Onaya gönderildi',
            meta.canAdjust ? '' : 'Stok, yetkili onaylayınca güncellenecek.',
        );
        formOpen.value = false;
        form.value = { warehouse_id: '', item_id: '', type: 'manual_adjust', qty: '', unit_cost: '', lot_no: '', expires_at: '', description: '' };
        await loadAll();
    } catch (e) {
        if (e instanceof ApiError) {
            formErrors.value = e.errors;
            danger('Kaydedilemedi', e.displayMessage);
        }
    } finally {
        busy.value = false;
    }
}

async function decide(id: number, action: 'approve' | 'reject'): Promise<void> {
    try {
        await api(`/api/v1/inventory/movement-requests/${id}/${action}`, { method: 'POST' });
        success(action === 'approve' ? 'Onaylandı ve deftere işlendi' : 'Reddedildi', '');
        await loadAll();
    } catch (e) {
        danger('İşlenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    }
}

const err = (f: string): string => formErrors.value[f]?.[0] ?? '';
</script>

<template>
    <Head title="Stok Hareketleri" />
    <PanelShell title="Stok">
        <InventoryNav active="movements" />

        <div class="flex flex-col gap-4">
            <!-- Bekleyen manuel hareket istekleri -->
            <BaseCard v-if="requests.length" title="Onay bekleyen manuel hareketler">
                <ul class="divide-y divide-default">
                    <li v-for="r in requests" :key="r.id" class="flex flex-wrap items-center gap-2 py-2 text-sm">
                        <BaseBadge variant="warning">{{ r.type_label }}</BaseBadge>
                        <span class="font-medium">{{ r.item_name }}</span>
                        <span class="tabular-nums">{{ r.qty }} {{ r.unit }}</span>
                        <span class="text-muted">· {{ r.warehouse_name }} · {{ r.requested_by || '—' }}</span>
                        <span class="text-subtle">{{ r.description }}</span>
                        <span v-if="meta.canAdjust" class="ms-auto flex gap-1.5">
                            <BaseButton size="sm" @click="decide(r.id, 'approve')">Onayla</BaseButton>
                            <BaseButton size="sm" variant="secondary" @click="decide(r.id, 'reject')">Reddet</BaseButton>
                        </span>
                    </li>
                </ul>
            </BaseCard>

            <!-- Filtreler -->
            <div class="flex flex-wrap items-end gap-2">
                <div class="w-44"><BaseSelect v-model="filterItem" :options="itemOptions" size="sm" @update:model-value="loadMovements()" /></div>
                <div class="w-40"><BaseSelect v-model="filterWarehouse" :options="warehouseOptions" size="sm" @update:model-value="loadMovements()" /></div>
                <div class="w-44"><BaseSelect v-model="filterType" :options="typeOptions" size="sm" @update:model-value="loadMovements()" /></div>
                <div class="w-36"><BaseInput v-model="filterFrom" type="date" size="sm" @update:model-value="loadMovements()" /></div>
                <div class="w-36"><BaseInput v-model="filterTo" type="date" size="sm" @update:model-value="loadMovements()" /></div>
                <div class="ms-auto">
                    <BaseButton size="sm" @click="formOpen = true">
                        <AppIcon name="plus" :size="14" /> Manuel hareket
                    </BaseButton>
                </div>
            </div>

            <!-- Defter -->
            <BaseCard flush>
                <div class="w-full overflow-x-auto overscroll-x-contain">
                    <table class="w-full min-w-max border-collapse text-sm" aria-label="Hareket defteri">
                        <thead>
                            <tr class="border-b border-default bg-surface-alt text-xs font-semibold tracking-wide text-muted uppercase">
                                <th class="px-4 py-2.5 text-left">Tarih</th>
                                <th class="px-4 py-2.5 text-left">Tür</th>
                                <th class="px-4 py-2.5 text-left">Kalem</th>
                                <th class="px-4 py-2.5 text-left">Depo</th>
                                <th class="px-4 py-2.5 text-right">Miktar</th>
                                <th class="px-4 py-2.5 text-right">Maliyet</th>
                                <th class="px-4 py-2.5 text-left">Referans / açıklama</th>
                                <th class="px-4 py-2.5 text-left">Kullanıcı</th>
                            </tr>
                        </thead>
                        <tbody v-if="!loading && movements.length">
                            <tr v-for="m in movements" :key="m.id" class="border-b border-default">
                                <td class="px-4 py-2 whitespace-nowrap text-muted">{{ m.occurred_at ? formatDateTime(m.occurred_at) : '—' }}</td>
                                <td class="px-4 py-2"><BaseBadge :variant="(m.type_variant as any)" no-icon>{{ m.type_label }}</BaseBadge></td>
                                <td class="px-4 py-2 font-medium">{{ m.item_name }}</td>
                                <td class="px-4 py-2 text-muted">{{ m.warehouse_name }}</td>
                                <td class="px-4 py-2 text-right tabular-nums" :class="m.qty_milli < 0 ? 'text-danger' : 'text-success'">
                                    {{ m.qty_milli > 0 ? '+' : '' }}{{ m.qty }} {{ m.unit }}
                                </td>
                                <td class="px-4 py-2 text-right tabular-nums text-muted">
                                    {{ m.total_cost_minor != null ? money(m.total_cost_minor) : '—' }}
                                </td>
                                <td class="px-4 py-2 max-w-72 truncate text-muted" :title="m.description ?? ''">
                                    <span v-if="m.lot_no" class="me-1 text-xs">[{{ m.lot_no }}]</span>{{ m.description ?? '—' }}
                                </td>
                                <td class="px-4 py-2 text-muted">{{ m.user_name ?? 'Sistem' }}</td>
                            </tr>
                        </tbody>
                    </table>
                    <div v-if="loading" class="p-6 text-center text-sm text-muted">Yükleniyor…</div>
                    <EmptyState v-else-if="!movements.length" title="Hareket yok" description="Alış, tüketim ve düzeltmeler burada satır satır birikir; satırlar asla değişmez." />
                </div>
                <div v-if="lastPage > 1" class="flex items-center justify-between border-t border-default px-4 py-2 text-sm text-muted">
                    <span>{{ totalRows }} kayıt</span>
                    <span class="flex items-center gap-2">
                        <BaseButton size="sm" variant="ghost" :disabled="currentPage <= 1" @click="loadMovements(currentPage - 1)">Önceki</BaseButton>
                        <span>{{ currentPage }} / {{ lastPage }}</span>
                        <BaseButton size="sm" variant="ghost" :disabled="currentPage >= lastPage" @click="loadMovements(currentPage + 1)">Sonraki</BaseButton>
                    </span>
                </div>
            </BaseCard>

            <p class="text-xs text-subtle">
                Defter değişmezdir: satır silme/düzeltme yoktur. Yanlış kayıt, karşı işaretli yeni bir
                "manuel düzeltme" kaydıyla kapatılır; tüm geçmiş iz bırakır.
            </p>
        </div>

        <!-- Manuel hareket -->
        <BaseModal :open="formOpen" title="Manuel stok hareketi" @close="formOpen = false">
            <form class="flex flex-col gap-3" @submit.prevent="submitManual">
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Depo" required :error="err('warehouse_id')">
                        <BaseSelect v-model="form.warehouse_id" :options="warehouseOptions.slice(1)" placeholder="Seçin…" />
                    </FormField>
                    <FormField label="Stok kalemi" required :error="err('item_id')">
                        <BaseSelect v-model="form.item_id" :options="itemOptions.slice(1)" placeholder="Seçin…" />
                    </FormField>
                </div>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Hareket türü" required :error="err('type')">
                        <BaseSelect v-model="form.type" :options="manualTypes" />
                    </FormField>
                    <FormField :label="`Miktar${selectedItem ? ` (${selectedItem.base_unit})` : ''}`" required :error="err('qty')" hint="Çıkış türlerinde işaret otomatik uygulanır.">
                        <BaseInput v-model="form.qty" inputmode="decimal" placeholder="ör. 1,25" />
                    </FormField>
                </div>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Birim maliyet (₺)" :error="err('unit_cost_minor')" hint="Boşsa ortalama maliyet kullanılır.">
                        <BaseInput v-model="form.unit_cost" inputmode="decimal" />
                    </FormField>
                    <FormField v-if="selectedItem?.track_lot" label="Lot no" :error="err('lot_no')"><BaseInput v-model="form.lot_no" /></FormField>
                    <FormField v-if="selectedItem?.track_expiry" label="SKT" :error="err('expires_at')"><BaseInput v-model="form.expires_at" type="date" /></FormField>
                </div>
                <FormField label="Gerekçe" required :error="err('description')" hint="Gerekçesiz manuel hareket kabul edilmez; denetim kaydına düşer.">
                    <BaseInput v-model="form.description" placeholder="ör. Devrilen tepsi — 6 porsiyon zayi" />
                </FormField>
                <p v-if="!meta.canAdjust" class="rounded-md bg-warning-soft px-3 py-2 text-xs text-body">
                    Stok düzeltme yetkiniz yok: kaydınız onay kuyruğuna düşecek, stok yetkili onaylayınca değişecek.
                </p>
                <div class="flex justify-end gap-2 pt-1">
                    <BaseButton variant="secondary" @click="formOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="busy">{{ meta.canAdjust ? 'Deftere işle' : 'Onaya gönder' }}</BaseButton>
                </div>
            </form>
        </BaseModal>
    </PanelShell>
</template>
