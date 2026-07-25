<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import InventoryNav from './components/InventoryNav.vue';
import InventoryOverview from './components/InventoryOverview.vue';
import {
    fetchCategories, fetchItems, fetchSuppliers, fetchWarehouses,
    itemStatusLabel, itemStatusVariant, metaFromProps, money,
    type ItemRow, type SupplierRow, type WarehouseRow,
} from './inventory';

/**
 * STOK KARTLARI (§17.2): liste (arama/filtre/kritik vurgu) + kart formu +
 * depo yönetimi + depolar arası transfer. Anlık stok yalnız görüntülenir;
 * DEĞİŞTİRİLEMEZ — her değişiklik hareket defterinden geçer (§17.4).
 */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

/**
 * Aynı rota (/panel/stok) iki ekranı barındırır: varsayılan GENEL BAKIŞ,
 * `?gorunum=kartlar` ise STOK KARTLARI. Böylece yeni backend rotası açmadan
 * ayrı sekme gibi davranır (InventoryNav bu parametreyi kullanır).
 */
const view = computed<'overview' | 'items'>(() => {
    const query = page.url.split('?')[1] ?? '';
    return new URLSearchParams(query).get('gorunum') === 'kartlar' ? 'items' : 'overview';
});

const items = ref<ItemRow[]>([]);
const warehouses = ref<WarehouseRow[]>([]);
const categories = ref<{ id: number; name: string }[]>([]);
const suppliers = ref<SupplierRow[]>([]);
const loading = ref(true);

const search = ref('');
const categoryFilter = ref('');
const warehouseFilter = ref('');
const statusFilter = ref('');

async function load(): Promise<void> {
    loading.value = true;
    try {
        [items.value, warehouses.value, categories.value, suppliers.value] = await Promise.all([
            fetchItems(search.value ? `?q=${encodeURIComponent(search.value)}` : ''),
            fetchWarehouses(),
            fetchCategories(),
            fetchSuppliers(),
        ]);
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

onMounted(() => { if (view.value === 'items') void load(); });
watch(view, (v) => { if (v === 'items') void load(); });

const filtered = computed(() => items.value.filter((i) => {
    if (categoryFilter.value && String(i.category_id ?? '') !== categoryFilter.value) return false;
    if (statusFilter.value && i.status !== statusFilter.value) return false;
    if (warehouseFilter.value) {
        const level = i.levels.find((l) => String(l.warehouse_id) === warehouseFilter.value);
        if (!level || level.qty_milli === 0) return false;
    }
    return true;
}));

const categoryOptions = computed(() => [
    { value: '', label: 'Tüm kategoriler' },
    ...categories.value.map((c) => ({ value: String(c.id), label: c.name })),
]);
const warehouseOptions = computed(() => [
    { value: '', label: 'Tüm depolar' },
    ...warehouses.value.map((w) => ({ value: String(w.id), label: w.name })),
]);
const statusOptions = [
    { value: '', label: 'Tüm durumlar' },
    { value: 'negative', label: 'Eksi stok' },
    { value: 'critical', label: 'Kritik' },
    { value: 'low', label: 'Azalıyor' },
    { value: 'ok', label: 'Yeterli' },
];

/* ---- Stok kartı formu (yeni / düzenle) ---- */
const formOpen = ref(false);
const editing = ref<ItemRow | null>(null);
const busy = ref(false);
const formErrors = ref<Record<string, string[]>>({});

const form = ref({
    name: '', code: '', barcode: '', category_id: '',
    base_unit: 'adet', sub_unit: '', sub_unit_factor: '',
    min_qty: '', critical_qty: '', max_qty: '',
    default_supplier_id: '', track_expiry: false, track_lot: false,
    shelf_location: '', tax_rate: '', is_semi_finished: false, is_active: true,
});

function openForm(item: ItemRow | null): void {
    editing.value = item;
    formErrors.value = {};
    form.value = item
        ? {
            name: item.name, code: item.code ?? '', barcode: item.barcode ?? '',
            category_id: item.category_id ? String(item.category_id) : '',
            base_unit: item.base_unit, sub_unit: item.sub_unit ?? '',
            sub_unit_factor: item.sub_unit_factor ? String(item.sub_unit_factor) : '',
            min_qty: item.min_qty, critical_qty: item.critical_qty, max_qty: item.max_qty ?? '',
            default_supplier_id: item.default_supplier_id ? String(item.default_supplier_id) : '',
            track_expiry: item.track_expiry, track_lot: item.track_lot,
            shelf_location: item.shelf_location ?? '', tax_rate: String(item.tax_rate),
            is_semi_finished: item.is_semi_finished, is_active: item.is_active,
        }
        : {
            name: '', code: '', barcode: '', category_id: '', base_unit: 'adet',
            sub_unit: '', sub_unit_factor: '', min_qty: '', critical_qty: '', max_qty: '',
            default_supplier_id: '', track_expiry: false, track_lot: false,
            shelf_location: '', tax_rate: '', is_semi_finished: false, is_active: true,
        };
    formOpen.value = true;
}

async function saveItem(): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    formErrors.value = {};
    try {
        const body = {
            ...form.value,
            category_id: form.value.category_id ? Number(form.value.category_id) : null,
            default_supplier_id: form.value.default_supplier_id ? Number(form.value.default_supplier_id) : null,
            sub_unit: form.value.sub_unit || null,
            sub_unit_factor: form.value.sub_unit_factor ? Number(form.value.sub_unit_factor) : null,
            min_qty: form.value.min_qty || null,
            critical_qty: form.value.critical_qty || null,
            max_qty: form.value.max_qty || null,
            tax_rate: form.value.tax_rate ? Number(String(form.value.tax_rate).replace(',', '.')) : 0,
        };
        if (editing.value) {
            await api(`/api/v1/inventory/items/${editing.value.id}`, { method: 'PUT', body });
            success('Stok kartı güncellendi', form.value.name);
        } else {
            await api('/api/v1/inventory/items', { method: 'POST', body });
            success('Stok kartı oluşturuldu', form.value.name);
        }
        formOpen.value = false;
        await load();
    } catch (e) {
        if (e instanceof ApiError) {
            formErrors.value = e.errors;
            danger('Kaydedilemedi', e.displayMessage);
        } else {
            danger('Kaydedilemedi', 'Beklenmeyen hata.');
        }
    } finally {
        busy.value = false;
    }
}

const err = (f: string): string => formErrors.value[f]?.[0] ?? '';

/* ---- Yeni kategori ---- */
const newCategory = ref('');

async function addCategory(): Promise<void> {
    if (!newCategory.value.trim()) return;
    try {
        await api('/api/v1/inventory/categories', { method: 'POST', body: { name: newCategory.value.trim() } });
        newCategory.value = '';
        categories.value = await fetchCategories();
        success('Kategori eklendi', '');
    } catch (e) {
        danger('Eklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    }
}

/* ---- Detay (depo bazlı stok) ---- */
const detail = ref<ItemRow | null>(null);

const warehouseName = (id: number): string => warehouses.value.find((w) => w.id === id)?.name ?? `Depo #${id}`;

/* ---- Depo yönetimi ---- */
const warehousesOpen = ref(false);
const warehouseForm = ref({ id: 0, name: '', code: '', type: 'main', branch_id: '', is_default: false, is_active: true });
const warehouseEditing = ref(false);
const warehouseErrors = ref<Record<string, string[]>>({});

const branchOptions = computed(() => {
    const auth = (page.props as Record<string, any>).auth;
    return [{ value: '', label: 'Genel (şubesiz)' },
        ...((auth?.branches ?? []) as { id: number; name: string }[]).map((b) => ({ value: String(b.id), label: b.name }))];
});

function editWarehouse(w: WarehouseRow | null): void {
    warehouseErrors.value = {};
    warehouseEditing.value = w !== null;
    warehouseForm.value = w
        ? { id: w.id, name: w.name, code: w.code ?? '', type: w.type, branch_id: w.branch_id ? String(w.branch_id) : '', is_default: w.is_default, is_active: w.is_active }
        : { id: 0, name: '', code: '', type: 'main', branch_id: '', is_default: false, is_active: true };
}

async function saveWarehouse(): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    warehouseErrors.value = {};
    try {
        const body = {
            name: warehouseForm.value.name,
            code: warehouseForm.value.code || null,
            type: warehouseForm.value.type,
            branch_id: warehouseForm.value.branch_id ? Number(warehouseForm.value.branch_id) : null,
            is_default: warehouseForm.value.is_default,
            is_active: warehouseForm.value.is_active,
        };
        if (warehouseEditing.value) {
            await api(`/api/v1/inventory/warehouses/${warehouseForm.value.id}`, { method: 'PUT', body });
        } else {
            await api('/api/v1/inventory/warehouses', { method: 'POST', body });
        }
        success('Depo kaydedildi', warehouseForm.value.name);
        editWarehouse(null);
        warehouses.value = await fetchWarehouses();
    } catch (e) {
        if (e instanceof ApiError) {
            warehouseErrors.value = e.errors;
            danger('Kaydedilemedi', e.displayMessage);
        }
    } finally {
        busy.value = false;
    }
}

/* ---- Transfer ---- */
const transferOpen = ref(false);
const transferForm = ref({ item_id: '', from_warehouse_id: '', to_warehouse_id: '', qty: '', description: '' });
const transferErrors = ref<Record<string, string[]>>({});

function openTransfer(item: ItemRow | null): void {
    transferErrors.value = {};
    transferForm.value = {
        item_id: item ? String(item.id) : '',
        from_warehouse_id: '', to_warehouse_id: '', qty: '', description: '',
    };
    transferOpen.value = true;
}

async function submitTransfer(): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    transferErrors.value = {};
    try {
        await api('/api/v1/inventory/transfers', {
            method: 'POST',
            body: {
                item_id: Number(transferForm.value.item_id),
                from_warehouse_id: Number(transferForm.value.from_warehouse_id),
                to_warehouse_id: Number(transferForm.value.to_warehouse_id),
                qty: transferForm.value.qty,
                description: transferForm.value.description || null,
            },
        });
        success('Transfer tamamlandı', 'Çıkış ve giriş defter kayıtları oluşturuldu.');
        transferOpen.value = false;
        await load();
    } catch (e) {
        if (e instanceof ApiError) {
            transferErrors.value = e.errors;
            danger('Transfer yapılamadı', e.displayMessage);
        }
    } finally {
        busy.value = false;
    }
}

const itemOptions = computed(() => items.value.filter((i) => i.is_active).map((i) => ({ value: String(i.id), label: i.name })));
const warehouseSelect = computed(() => warehouses.value.filter((w) => w.is_active).map((w) => ({ value: String(w.id), label: w.name })));
</script>

<template>
    <Head title="Stok" />
    <PanelShell title="Stok">
        <InventoryNav :active="view" />

        <!-- Genel Bakış (varsayılan açılış) -->
        <InventoryOverview v-if="view === 'overview'" />

        <template v-else>
        <div class="flex flex-col gap-4">
            <!-- Araç çubuğu -->
            <div class="flex flex-wrap items-center gap-2">
                <div class="w-full sm:w-64">
                    <SearchInput v-model="search" placeholder="Ad, kod veya barkod…" @update:model-value="load" />
                </div>
                <div class="w-40"><BaseSelect v-model="categoryFilter" :options="categoryOptions" size="sm" /></div>
                <div class="w-40"><BaseSelect v-model="warehouseFilter" :options="warehouseOptions" size="sm" /></div>
                <div class="w-40"><BaseSelect v-model="statusFilter" :options="statusOptions" size="sm" /></div>
                <div class="ms-auto flex items-center gap-2">
                    <BaseButton variant="secondary" size="sm" @click="warehousesOpen = true; editWarehouse(null)">
                        <AppIcon name="store" :size="14" /> Depolar
                    </BaseButton>
                    <BaseButton v-if="meta.canAdjust" variant="secondary" size="sm" @click="openTransfer(null)">
                        <AppIcon name="arrow-right" :size="14" /> Transfer
                    </BaseButton>
                    <BaseButton v-if="meta.canAdjust" size="sm" @click="openForm(null)">
                        <AppIcon name="plus" :size="14" /> Yeni stok kartı
                    </BaseButton>
                </div>
            </div>

            <!-- Liste -->
            <BaseCard flush>
                <div class="w-full overflow-x-auto overscroll-x-contain">
                    <table class="w-full min-w-max border-collapse text-sm" aria-label="Stok kartları">
                        <thead>
                            <tr class="border-b border-default bg-surface-alt text-xs font-semibold tracking-wide text-muted uppercase">
                                <th class="px-4 py-2.5 text-left">Kalem</th>
                                <th class="px-4 py-2.5 text-left">Kategori</th>
                                <th class="px-4 py-2.5 text-right">Stok</th>
                                <th class="px-4 py-2.5 text-right">Min / Kritik</th>
                                <th class="px-4 py-2.5 text-right">Ort. maliyet</th>
                                <th class="px-4 py-2.5 text-left">Durum</th>
                                <th class="px-4 py-2.5 text-right">İşlem</th>
                            </tr>
                        </thead>
                        <tbody v-if="!loading && filtered.length">
                            <tr
                                v-for="item in filtered"
                                :key="item.id"
                                class="border-b border-default"
                                :class="item.status === 'critical' || item.status === 'negative' ? 'bg-danger-soft/40' : item.status === 'low' ? 'bg-warning-soft/30' : ''"
                            >
                                <td class="px-4 py-2.5">
                                    <button type="button" class="text-left font-medium text-body hover:underline" @click="detail = item">
                                        {{ item.name }}
                                    </button>
                                    <div class="text-xs text-subtle">
                                        {{ item.code || '—' }}
                                        <span v-if="item.is_semi_finished" class="ms-1">· Yarı mamul</span>
                                        <span v-if="!item.is_active" class="ms-1">· Pasif</span>
                                    </div>
                                </td>
                                <td class="px-4 py-2.5 text-muted">{{ item.category_name ?? '—' }}</td>
                                <td class="px-4 py-2.5 text-right font-medium tabular-nums" :class="item.on_hand_milli < 0 ? 'text-danger' : ''">
                                    {{ item.on_hand }} {{ item.base_unit }}
                                </td>
                                <td class="px-4 py-2.5 text-right text-muted tabular-nums">{{ item.min_qty }} / {{ item.critical_qty }}</td>
                                <td class="px-4 py-2.5 text-right tabular-nums">{{ money(item.avg_cost_minor) }}</td>
                                <td class="px-4 py-2.5">
                                    <BaseBadge :variant="itemStatusVariant(item.status)">{{ itemStatusLabel(item.status) }}</BaseBadge>
                                </td>
                                <td class="px-4 py-2.5 text-right">
                                    <div class="flex items-center justify-end gap-1">
                                        <BaseButton v-if="meta.canAdjust" variant="ghost" size="sm" icon-only label="Düzenle" @click="openForm(item)">
                                            <AppIcon name="pencil" :size="14" />
                                        </BaseButton>
                                        <BaseButton v-if="meta.canAdjust" variant="ghost" size="sm" icon-only label="Transfer" @click="openTransfer(item)">
                                            <AppIcon name="arrow-right" :size="14" />
                                        </BaseButton>
                                    </div>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                    <div v-if="loading" class="p-6 text-center text-sm text-muted">Yükleniyor…</div>
                    <EmptyState
                        v-else-if="!filtered.length"
                        title="Stok kartı yok"
                        description="İlk stok kartınızı oluşturun; alımlar ve reçeteler bu kartlara bağlanır."
                    />
                </div>
            </BaseCard>
        </div>

        <!-- Detay: depo bazlı stok -->
        <BaseModal :open="detail !== null" :title="detail?.name ?? ''" @close="detail = null">
            <div v-if="detail" class="flex flex-col gap-3 text-sm">
                <div class="flex flex-wrap gap-2">
                    <BaseBadge :variant="itemStatusVariant(detail.status)">{{ itemStatusLabel(detail.status) }}</BaseBadge>
                    <BaseBadge v-if="detail.track_expiry" variant="info" no-icon>SKT takibi</BaseBadge>
                    <BaseBadge v-if="detail.track_lot" variant="info" no-icon>Lot takibi</BaseBadge>
                </div>
                <dl class="grid grid-cols-2 gap-x-4 gap-y-1.5">
                    <dt class="text-muted">Toplam stok</dt><dd class="text-right font-medium tabular-nums">{{ detail.on_hand }} {{ detail.base_unit }}</dd>
                    <dt class="text-muted">Birim</dt>
                    <dd class="text-right">{{ detail.base_unit }}<span v-if="detail.sub_unit"> · 1 {{ detail.base_unit }} = {{ detail.sub_unit_factor }} {{ detail.sub_unit }}</span></dd>
                    <dt class="text-muted">Ortalama maliyet</dt><dd class="text-right tabular-nums">{{ money(detail.avg_cost_minor) }} / {{ detail.base_unit }}</dd>
                    <dt class="text-muted">Son alış</dt>
                    <dd class="text-right tabular-nums">{{ detail.last_cost_minor != null ? money(detail.last_cost_minor) : '—' }}</dd>
                    <dt class="text-muted">Tedarikçi</dt><dd class="text-right">{{ detail.default_supplier_name ?? '—' }}</dd>
                    <dt class="text-muted">Raf / konum</dt><dd class="text-right">{{ detail.shelf_location ?? '—' }}</dd>
                </dl>
                <div>
                    <h3 class="mb-1.5 text-xs font-semibold tracking-wide text-muted uppercase">Depo bazında</h3>
                    <ul class="divide-y divide-default rounded-md border border-default">
                        <li v-for="level in detail.levels" :key="level.warehouse_id" class="flex items-center justify-between px-3 py-2">
                            <span>{{ warehouseName(level.warehouse_id) }}</span>
                            <span class="font-medium tabular-nums" :class="level.qty_milli < 0 ? 'text-danger' : ''">{{ level.qty }} {{ detail.base_unit }}</span>
                        </li>
                        <li v-if="!detail.levels.length" class="px-3 py-2 text-muted">Henüz hareket yok.</li>
                    </ul>
                </div>
                <p class="text-xs text-subtle">
                    Stok toplamı yalnız hareket defterinden türetilir; elle değiştirilemez. Düzeltme için
                    manuel hareket ya da sayım kullanın.
                </p>
            </div>
        </BaseModal>

        <!-- Stok kartı formu -->
        <BaseDrawer :open="formOpen" :title="editing ? 'Stok kartını düzenle' : 'Yeni stok kartı'" width-class="sm:max-w-lg" @close="formOpen = false">
            <form class="flex flex-col gap-3" @submit.prevent="saveItem">
                <FormField label="Ad" required :error="err('name')"><BaseInput v-model="form.name" /></FormField>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Kod" :error="err('code')"><BaseInput v-model="form.code" /></FormField>
                    <FormField label="Barkod" :error="err('barcode')"><BaseInput v-model="form.barcode" /></FormField>
                </div>
                <FormField label="Kategori" :error="err('category_id')">
                    <BaseSelect v-model="form.category_id" :options="categoryOptions" />
                </FormField>
                <div class="flex items-end gap-2">
                    <FormField label="Yeni kategori" class="grow"><BaseInput v-model="newCategory" placeholder="ör. Et Ürünleri" /></FormField>
                    <BaseButton variant="secondary" size="sm" :disabled="!newCategory.trim()" @click="addCategory">Ekle</BaseButton>
                </div>
                <div class="grid grid-cols-3 gap-3">
                    <FormField label="Ana birim" required :error="err('base_unit')" hint="kg, lt, adet…">
                        <BaseInput v-model="form.base_unit" />
                    </FormField>
                    <FormField label="Alt birim" :error="err('sub_unit')" hint="g, ml…">
                        <BaseInput v-model="form.sub_unit" />
                    </FormField>
                    <FormField label="Dönüşüm" :error="err('sub_unit_factor')" hint="1 ana = N alt">
                        <BaseInput v-model="form.sub_unit_factor" inputmode="numeric" />
                    </FormField>
                </div>
                <div class="grid grid-cols-3 gap-3">
                    <FormField label="Min stok" :error="err('min_qty')"><BaseInput v-model="form.min_qty" inputmode="decimal" /></FormField>
                    <FormField label="Kritik stok" :error="err('critical_qty')"><BaseInput v-model="form.critical_qty" inputmode="decimal" /></FormField>
                    <FormField label="Maks stok" :error="err('max_qty')"><BaseInput v-model="form.max_qty" inputmode="decimal" /></FormField>
                </div>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Varsayılan tedarikçi" :error="err('default_supplier_id')">
                        <BaseSelect v-model="form.default_supplier_id" :options="[{ value: '', label: '—' }, ...suppliers.map((s) => ({ value: String(s.id), label: s.name }))]" />
                    </FormField>
                    <FormField label="KDV oranı (%)" :error="err('tax_rate')"><BaseInput v-model="form.tax_rate" inputmode="decimal" /></FormField>
                </div>
                <FormField label="Raf / depo konumu" :error="err('shelf_location')"><BaseInput v-model="form.shelf_location" /></FormField>
                <div class="flex flex-col gap-2 rounded-md border border-default p-3">
                    <BaseSwitch v-model="form.track_expiry" label="SKT takibi" description="Mal kabulünde son kullanma tarihi istenir." size="sm" />
                    <BaseSwitch v-model="form.track_lot" label="Lot takibi" description="Mal kabulünde lot numarası istenir." size="sm" />
                    <BaseSwitch v-model="form.is_semi_finished" label="Yarı mamul" description="Kendi reçetesiyle üretilir (ör. ev sosu)." size="sm" />
                    <BaseSwitch v-model="form.is_active" label="Aktif" size="sm" />
                </div>
                <div class="flex justify-end gap-2 pt-1">
                    <BaseButton variant="secondary" @click="formOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="busy">Kaydet</BaseButton>
                </div>
            </form>
        </BaseDrawer>

        <!-- Depolar -->
        <BaseDrawer :open="warehousesOpen" title="Depolar" width-class="sm:max-w-lg" @close="warehousesOpen = false">
            <div class="flex flex-col gap-4">
                <ul class="divide-y divide-default rounded-md border border-default">
                    <li v-for="w in warehouses" :key="w.id" class="flex items-center justify-between gap-2 px-3 py-2 text-sm">
                        <div>
                            <span class="font-medium">{{ w.name }}</span>
                            <span v-if="w.is_default" class="ms-1 text-xs text-primary">· varsayılan</span>
                            <div class="text-xs text-subtle">{{ w.type_label }} · {{ w.branch_name ?? 'Genel' }} · {{ w.item_count }} kalem</div>
                        </div>
                        <BaseButton v-if="meta.canAdjust" variant="ghost" size="sm" icon-only label="Düzenle" @click="editWarehouse(w)">
                            <AppIcon name="pencil" :size="14" />
                        </BaseButton>
                    </li>
                    <li v-if="!warehouses.length" class="px-3 py-3 text-sm text-muted">Henüz depo yok.</li>
                </ul>

                <form v-if="meta.canAdjust" class="flex flex-col gap-3 rounded-md border border-default p-3" @submit.prevent="saveWarehouse">
                    <h3 class="text-sm font-semibold">{{ warehouseEditing ? 'Depoyu düzenle' : 'Yeni depo' }}</h3>
                    <FormField label="Ad" required :error="warehouseErrors.name?.[0] ?? ''"><BaseInput v-model="warehouseForm.name" /></FormField>
                    <div class="grid grid-cols-2 gap-3">
                        <FormField label="Tür" :error="warehouseErrors.type?.[0] ?? ''">
                            <BaseSelect v-model="warehouseForm.type" :options="meta.warehouseTypes" />
                        </FormField>
                        <FormField label="Şube" :error="warehouseErrors.branch_id?.[0] ?? ''">
                            <BaseSelect v-model="warehouseForm.branch_id" :options="branchOptions" />
                        </FormField>
                    </div>
                    <BaseSwitch v-model="warehouseForm.is_default" label="Varsayılan tüketim deposu" description="Reçete tüketimi satır deposu yoksa buradan düşer." size="sm" />
                    <BaseSwitch v-model="warehouseForm.is_active" label="Aktif" size="sm" />
                    <div class="flex justify-end gap-2">
                        <BaseButton v-if="warehouseEditing" variant="secondary" size="sm" @click="editWarehouse(null)">Yeni kayda dön</BaseButton>
                        <BaseButton type="submit" size="sm" :loading="busy">Kaydet</BaseButton>
                    </div>
                </form>
            </div>
        </BaseDrawer>

        <!-- Transfer -->
        <BaseModal :open="transferOpen" title="Depolar arası transfer" @close="transferOpen = false">
            <form class="flex flex-col gap-3" @submit.prevent="submitTransfer">
                <FormField label="Stok kalemi" required :error="transferErrors.item_id?.[0] ?? ''">
                    <BaseSelect v-model="transferForm.item_id" :options="itemOptions" placeholder="Seçin…" />
                </FormField>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Kaynak depo" required :error="transferErrors.from_warehouse_id?.[0] ?? ''">
                        <BaseSelect v-model="transferForm.from_warehouse_id" :options="warehouseSelect" placeholder="Seçin…" />
                    </FormField>
                    <FormField label="Hedef depo" required :error="transferErrors.to_warehouse_id?.[0] ?? ''">
                        <BaseSelect v-model="transferForm.to_warehouse_id" :options="warehouseSelect" placeholder="Seçin…" />
                    </FormField>
                </div>
                <FormField label="Miktar (ana birim)" required :error="transferErrors.qty?.[0] ?? ''">
                    <BaseInput v-model="transferForm.qty" inputmode="decimal" placeholder="ör. 2,5" />
                </FormField>
                <FormField label="Açıklama" :error="transferErrors.description?.[0] ?? ''">
                    <BaseInput v-model="transferForm.description" />
                </FormField>
                <div class="flex justify-end gap-2 pt-1">
                    <BaseButton variant="secondary" @click="transferOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="busy">Transfer et</BaseButton>
                </div>
            </form>
        </BaseModal>
        </template>
    </PanelShell>
</template>
