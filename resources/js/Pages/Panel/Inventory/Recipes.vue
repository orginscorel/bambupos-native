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
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import InventoryNav from './components/InventoryNav.vue';
import {
    fetchItems, fetchWarehouses, metaFromProps, money,
    type ItemRow, type RecipeData, type RecipeProduct, type WarehouseRow,
} from './inventory';

/**
 * REÇETELER (§17.3): ürün ↔ stok kalemleri. 1 porsiyon başına bileşen,
 * alt birim girişi, satır firesi, şube/varyant özel reçete, sürümleme
 * (her kayıt yeni sürüm) ve yarı mamul üretimi.
 */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

const products = ref<RecipeProduct[]>([]);
const items = ref<ItemRow[]>([]);
const warehouses = ref<WarehouseRow[]>([]);
const loading = ref(true);
const search = ref('');

/* Hedef seçimi */
const mode = ref<'product' | 'semi'>('product');
const selectedProductId = ref<number | null>(null);
const selectedVariantId = ref('');
const selectedBranchId = ref('');
const selectedSemiId = ref('');

const recipe = ref<RecipeData | null>(null);
const versions = ref<{ id: number; version: number; is_active: boolean; created_at: string | null; line_count: number }[]>([]);
const viewingOld = ref<RecipeData | null>(null);

/* Satır düzenleyici */
interface EditLine {
    item_id: string;
    qty: string;
    unit_entry: 'base' | 'sub';
    waste_percent: string;
    warehouse_id: string;
}
const editLines = ref<EditLine[]>([]);
const recipeWaste = ref('');
const recipeNote = ref('');
const yieldQty = ref('1');
const busy = ref(false);

async function load(): Promise<void> {
    loading.value = true;
    try {
        [items.value, warehouses.value] = await Promise.all([fetchItems(), fetchWarehouses()]);
        products.value = (await api<{ products: RecipeProduct[] }>('/api/v1/inventory/recipes/products')).products;
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

const filteredProducts = computed(() =>
    products.value.filter((p) => p.name.toLocaleLowerCase('tr').includes(search.value.toLocaleLowerCase('tr'))));

const selectedProduct = computed(() => products.value.find((p) => p.id === selectedProductId.value) ?? null);
const semiItems = computed(() => items.value.filter((i) => i.is_semi_finished && i.is_active));

const branchOptions = computed(() => {
    const auth = (page.props as Record<string, any>).auth;
    return [{ value: '', label: 'Genel (tüm şubeler)' },
        ...((auth?.branches ?? []) as { id: number; name: string }[]).map((b) => ({ value: String(b.id), label: `${b.name} (şubeye özel)` }))];
});

const variantOptions = computed(() => [
    { value: '', label: 'Ürün geneli' },
    ...(selectedProduct.value?.variants ?? []).map((v) => ({ value: String(v.id), label: `${v.name} (varyanta özel)` })),
]);

async function loadRecipe(): Promise<void> {
    viewingOld.value = null;
    const params = new URLSearchParams();
    if (mode.value === 'product') {
        if (!selectedProductId.value) { recipe.value = null; versions.value = []; return; }
        params.set('product_id', String(selectedProductId.value));
        if (selectedVariantId.value) params.set('variant_id', selectedVariantId.value);
        if (selectedBranchId.value) params.set('branch_id', selectedBranchId.value);
    } else {
        if (!selectedSemiId.value) { recipe.value = null; versions.value = []; return; }
        params.set('item_id', selectedSemiId.value);
    }
    try {
        const res = await api<{ recipe: RecipeData | null; versions: typeof versions.value }>(`/api/v1/inventory/recipes?${params.toString()}`);
        recipe.value = res.recipe;
        versions.value = res.versions;
        editLines.value = (res.recipe?.lines ?? []).map((l) => ({
            item_id: String(l.item_id),
            qty: l.qty,
            unit_entry: l.unit_entry,
            waste_percent: l.waste_percent ? String(l.waste_percent) : '',
            warehouse_id: l.warehouse_id ? String(l.warehouse_id) : '',
        }));
        recipeWaste.value = res.recipe?.waste_percent ? String(res.recipe.waste_percent) : '';
        recipeNote.value = res.recipe?.note ?? '';
        yieldQty.value = res.recipe?.yield_qty ?? '1';
    } catch (e) {
        danger('Reçete yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    }
}

watch([mode, selectedProductId, selectedVariantId, selectedBranchId, selectedSemiId], loadRecipe);

function selectProduct(p: RecipeProduct): void {
    mode.value = 'product';
    selectedProductId.value = p.id;
    selectedVariantId.value = '';
    selectedBranchId.value = '';
}

function addLine(): void {
    editLines.value.push({ item_id: '', qty: '', unit_entry: 'base', waste_percent: '', warehouse_id: '' });
}

const itemById = (id: string): ItemRow | undefined => items.value.find((i) => String(i.id) === id);

function unitOptions(line: EditLine): { value: string; label: string }[] {
    const item = itemById(line.item_id);
    const opts = [{ value: 'base', label: item?.base_unit ?? 'ana birim' }];
    if (item?.sub_unit) opts.push({ value: 'sub', label: item.sub_unit });
    return opts;
}

/** Satır maliyeti (öngörü): girilen miktar × ortalama maliyet. */
function lineCost(line: EditLine): number | null {
    const item = itemById(line.item_id);
    if (!item) return null;
    const parsed = Number(String(line.qty).replace(/\./g, '').replace(',', '.'));
    if (!Number.isFinite(parsed) || parsed <= 0) return null;
    const baseQty = line.unit_entry === 'sub' && item.sub_unit_factor ? parsed / item.sub_unit_factor : parsed;
    const waste = 1 + (Number(line.waste_percent.replace(',', '.')) || 0) / 100;
    return Math.round(baseQty * waste * item.avg_cost_minor);
}

const totalCost = computed(() => editLines.value.reduce((sum, l) => sum + (lineCost(l) ?? 0), 0));

async function saveRecipe(): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    try {
        const body: Record<string, unknown> = {
            waste_percent: recipeWaste.value ? Number(recipeWaste.value.replace(',', '.')) : 0,
            note: recipeNote.value || null,
            lines: editLines.value
                .filter((l) => l.item_id && l.qty)
                .map((l) => ({
                    item_id: Number(l.item_id),
                    qty: l.qty,
                    unit_entry: l.unit_entry,
                    waste_percent: l.waste_percent ? Number(l.waste_percent.replace(',', '.')) : 0,
                    warehouse_id: l.warehouse_id ? Number(l.warehouse_id) : null,
                })),
        };
        if (mode.value === 'product') {
            body.product_id = selectedProductId.value;
            body.variant_id = selectedVariantId.value ? Number(selectedVariantId.value) : null;
            body.branch_id = selectedBranchId.value ? Number(selectedBranchId.value) : null;
        } else {
            body.item_id = Number(selectedSemiId.value);
            body.yield_qty = yieldQty.value;
        }
        await api('/api/v1/inventory/recipes', { method: 'POST', body });
        success('Reçete kaydedildi', 'Yeni sürüm oluşturuldu; eski sürüm tarihçede.');
        await Promise.all([load(), loadRecipe()]);
    } catch (e) {
        danger('Kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}

async function openVersion(id: number): Promise<void> {
    try {
        viewingOld.value = (await api<{ recipe: RecipeData }>(`/api/v1/inventory/recipes/versions/${id}`)).recipe;
    } catch (e) {
        danger('Sürüm açılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    }
}

/* ---- Yarı mamul üretimi ---- */
const produceOpen = ref(false);
const produceForm = ref({ qty: '', warehouse_id: '' });

async function produce(): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    try {
        await api('/api/v1/inventory/production', {
            method: 'POST',
            body: { item_id: Number(selectedSemiId.value), qty: produceForm.value.qty, warehouse_id: Number(produceForm.value.warehouse_id) },
        });
        success('Üretim deftere işlendi', 'Bileşenler düştü, yarı mamul stoğa girdi.');
        produceOpen.value = false;
    } catch (e) {
        danger('Üretilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}

const componentOptions = computed(() =>
    items.value
        .filter((i) => i.is_active && String(i.id) !== selectedSemiId.value)
        .map((i) => ({ value: String(i.id), label: i.name })));

const warehouseOptions = computed(() => warehouses.value.filter((w) => w.is_active).map((w) => ({ value: String(w.id), label: w.name })));

const hasBranchOverride = (p: RecipeProduct): boolean => p.recipes.some((r) => r.branch_id !== null);
const hasVariantOverride = (p: RecipeProduct): boolean => p.recipes.some((r) => r.variant_id !== null);
</script>

<template>
    <Head title="Reçeteler" />
    <PanelShell title="Stok" flush canvas>
        <div class="shrink-0 border-b border-default bg-raised px-4 py-2.5 sm:px-6">
            <InventoryNav active="recipes" />
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">
        <div class="grid gap-4 lg:grid-cols-[320px_1fr]">
            <!-- Sol: hedef listesi -->
            <BaseCard flush>
                <div class="flex flex-col gap-2 p-3">
                    <div class="flex gap-1.5">
                        <BaseButton :variant="mode === 'product' ? 'primary' : 'secondary'" size="sm" block @click="mode = 'product'">Ürünler</BaseButton>
                        <BaseButton :variant="mode === 'semi' ? 'primary' : 'secondary'" size="sm" block @click="mode = 'semi'">Yarı mamuller</BaseButton>
                    </div>
                    <SearchInput v-if="mode === 'product'" v-model="search" placeholder="Ürün ara…" :debounce="150" />
                </div>
                <div class="max-h-[60vh] overflow-y-auto border-t border-default">
                    <template v-if="mode === 'product'">
                        <button
                            v-for="p in filteredProducts"
                            :key="p.id"
                            type="button"
                            class="flex w-full items-center justify-between gap-2 border-b border-default px-3 py-2 text-left text-sm hover:bg-surface-alt"
                            :class="p.id === selectedProductId ? 'bg-surface-alt font-medium' : ''"
                            @click="selectProduct(p)"
                        >
                            <span class="truncate">{{ p.name }}</span>
                            <span class="flex shrink-0 items-center gap-1">
                                <BaseBadge v-if="p.recipes.length" variant="success" no-icon>v{{ Math.max(...p.recipes.map((r) => r.version)) }}</BaseBadge>
                                <BaseBadge v-else variant="warning" no-icon>Reçetesiz</BaseBadge>
                                <span v-if="hasVariantOverride(p)" class="text-xs text-subtle" title="Varyanta özel reçete var">V</span>
                                <span v-if="hasBranchOverride(p)" class="text-xs text-subtle" title="Şubeye özel reçete var">Ş</span>
                            </span>
                        </button>
                        <EmptyState v-if="!filteredProducts.length && !loading" title="Ürün yok" />
                    </template>
                    <template v-else>
                        <button
                            v-for="i in semiItems"
                            :key="i.id"
                            type="button"
                            class="flex w-full items-center justify-between border-b border-default px-3 py-2 text-left text-sm hover:bg-surface-alt"
                            :class="String(i.id) === selectedSemiId ? 'bg-surface-alt font-medium' : ''"
                            @click="selectedSemiId = String(i.id)"
                        >
                            <span class="truncate">{{ i.name }}</span>
                            <span class="text-xs text-muted tabular-nums">{{ i.on_hand }} {{ i.base_unit }}</span>
                        </button>
                        <EmptyState
                            v-if="!semiItems.length && !loading"
                            title="Yarı mamul yok"
                            description="Stok kartında 'Yarı mamul' işaretli kalemler burada listelenir."
                        />
                    </template>
                </div>
            </BaseCard>

            <!-- Sağ: reçete düzenleyici -->
            <div class="flex flex-col gap-4">
                <BaseCard v-if="mode === 'product' && !selectedProductId" flush>
                    <EmptyState icon="utensils" title="Ürün seçin" description="Soldan bir ürün seçin; 1 porsiyonun hangi stok kalemlerinden oluştuğunu tanımlayın. Satış servis edildiğinde stok bu reçeteye göre düşer." />
                </BaseCard>
                <BaseCard v-else-if="mode === 'semi' && !selectedSemiId" flush>
                    <EmptyState icon="chef-hat" title="Yarı mamul seçin" description="Yarı mamulün 1 verim birimi için bileşenleri tanımlayın; üretimle stoğa girer." />
                </BaseCard>

                <template v-else>
                    <BaseCard :title="mode === 'product' ? (selectedProduct?.name ?? '') : (itemById(selectedSemiId)?.name ?? '')">
                        <div class="flex flex-col gap-3">
                            <div v-if="mode === 'product'" class="grid gap-3 sm:grid-cols-2">
                                <FormField label="Varyant" hint="Varyanta özel reçete, ürün genelini ezer.">
                                    <BaseSelect v-model="selectedVariantId" :options="variantOptions" />
                                </FormField>
                                <FormField label="Kapsam" hint="Şubeye özel reçete o şubede genel reçeteyi ezer.">
                                    <BaseSelect v-model="selectedBranchId" :options="branchOptions" />
                                </FormField>
                            </div>
                            <div v-else class="grid gap-3 sm:grid-cols-2">
                                <FormField label="Verim" :hint="`Bu reçete kaç ${itemById(selectedSemiId)?.base_unit ?? 'birim'} üretir?`">
                                    <BaseInput v-model="yieldQty" inputmode="decimal" />
                                </FormField>
                                <div class="flex items-end">
                                    <BaseButton v-if="meta.canAdjust && recipe" variant="secondary" @click="produceOpen = true; produceForm = { qty: '', warehouse_id: '' }">
                                        <AppIcon name="chef-hat" :size="14" /> Üretim yap
                                    </BaseButton>
                                </div>
                            </div>

                            <div class="flex items-center justify-between">
                                <h3 class="text-sm font-semibold">
                                    Bileşenler <span class="font-normal text-muted">({{ mode === 'product' ? '1 porsiyon için' : `${yieldQty || '1'} ${itemById(selectedSemiId)?.base_unit ?? ''} verim için` }})</span>
                                </h3>
                                <BaseBadge v-if="recipe" variant="info" no-icon>Aktif sürüm v{{ recipe.version }}</BaseBadge>
                                <BaseBadge v-else variant="warning">Reçete tanımsız — satışta stok düşmez</BaseBadge>
                            </div>

                            <div class="flex flex-col gap-2">
                                <div
                                    v-for="(line, idx) in editLines"
                                    :key="idx"
                                    class="grid grid-cols-[1fr_90px_90px_80px_1fr_auto] items-center gap-2 rounded-md border border-default p-2"
                                >
                                    <BaseSelect v-model="line.item_id" :options="componentOptions" size="sm" placeholder="Bileşen…" />
                                    <BaseInput v-model="line.qty" size="sm" inputmode="decimal" placeholder="Miktar" />
                                    <BaseSelect v-model="line.unit_entry" :options="unitOptions(line)" size="sm" />
                                    <BaseInput v-model="line.waste_percent" size="sm" inputmode="decimal" placeholder="Fire %" />
                                    <BaseSelect v-model="line.warehouse_id" :options="[{ value: '', label: 'Varsayılan depo' }, ...warehouseOptions]" size="sm" />
                                    <div class="flex items-center gap-1">
                                        <span class="w-20 text-right text-xs text-muted tabular-nums">{{ lineCost(line) != null ? money(lineCost(line)!) : '' }}</span>
                                        <BaseButton variant="ghost" size="sm" icon-only label="Satırı kaldır" @click="editLines.splice(idx, 1)">
                                            <AppIcon name="trash" :size="14" />
                                        </BaseButton>
                                    </div>
                                </div>
                                <BaseButton variant="secondary" size="sm" @click="addLine"><AppIcon name="plus" :size="14" /> Bileşen ekle</BaseButton>
                            </div>

                            <div class="grid gap-3 sm:grid-cols-2">
                                <FormField label="Genel fire (%)" hint="Tüm bileşenlere ek olarak uygulanır.">
                                    <BaseInput v-model="recipeWaste" inputmode="decimal" />
                                </FormField>
                                <FormField label="Not"><BaseInput v-model="recipeNote" /></FormField>
                            </div>

                            <div class="flex items-center justify-between border-t border-default pt-3">
                                <span class="text-sm text-muted">
                                    Tahmini {{ mode === 'product' ? 'porsiyon' : 'parti' }} maliyeti:
                                    <strong class="text-body tabular-nums">{{ money(totalCost) }}</strong>
                                </span>
                                <BaseButton v-if="meta.canAdjust" :loading="busy" :disabled="!editLines.some((l) => l.item_id && l.qty)" @click="saveRecipe">
                                    Yeni sürüm olarak kaydet
                                </BaseButton>
                                <span v-else class="text-xs text-subtle">Reçete kaydetmek stok düzeltme yetkisi ister.</span>
                            </div>
                        </div>
                    </BaseCard>

                    <BaseCard v-if="versions.length" title="Sürüm tarihçesi">
                        <ul class="divide-y divide-default text-sm">
                            <li v-for="v in versions" :key="v.id" class="flex items-center gap-2 py-2">
                                <BaseBadge :variant="v.is_active ? 'success' : 'neutral'" no-icon>v{{ v.version }}</BaseBadge>
                                <span class="text-muted">{{ v.line_count }} bileşen</span>
                                <span class="text-subtle">{{ v.created_at ? new Date(v.created_at).toLocaleString('tr-TR') : '' }}</span>
                                <BaseButton class="ms-auto" variant="ghost" size="sm" @click="openVersion(v.id)">Görüntüle</BaseButton>
                            </li>
                        </ul>
                    </BaseCard>
                </template>
            </div>
        </div>

        <!-- Eski sürüm görüntüleme -->
        <BaseModal :open="viewingOld !== null" :title="viewingOld ? `Reçete v${viewingOld.version}` : ''" @close="viewingOld = null">
            <ul v-if="viewingOld" class="divide-y divide-default text-sm">
                <li v-for="(l, i) in viewingOld.lines" :key="i" class="flex items-center justify-between py-2">
                    <span>{{ l.item_name }} <span v-if="l.waste_percent" class="text-xs text-subtle">(fire %{{ l.waste_percent }})</span></span>
                    <span class="tabular-nums">{{ l.qty }} {{ l.base_unit }}</span>
                </li>
            </ul>
        </BaseModal>

        <!-- Üretim -->
        <BaseModal :open="produceOpen" title="Yarı mamul üretimi" @close="produceOpen = false">
            <form class="flex flex-col gap-3" @submit.prevent="produce">
                <FormField :label="`Üretim miktarı (${itemById(selectedSemiId)?.base_unit ?? ''})`" required>
                    <BaseInput v-model="produceForm.qty" inputmode="decimal" />
                </FormField>
                <FormField label="Depo" required hint="Bileşenler bu depodan düşer, üretilen buraya girer.">
                    <BaseSelect v-model="produceForm.warehouse_id" :options="warehouseOptions" placeholder="Seçin…" />
                </FormField>
                <div class="flex justify-end gap-2 pt-1">
                    <BaseButton variant="secondary" @click="produceOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="busy" :disabled="!produceForm.qty || !produceForm.warehouse_id">Üret</BaseButton>
                </div>
            </form>
        </BaseModal>
        </div>
        </div>
    </PanelShell>
</template>
