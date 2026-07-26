<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { Head, Link } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { formatCurrencyMinor } from '@/lib/format';
import { useToast } from '@/composables/useToast';
import { usePermissions } from '@/composables/usePermissions';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BasePagination from '@/Components/ui/BasePagination.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import CatalogShell from '../components/CatalogShell.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import { useDragSort } from '../components/useDragSort';
import type { CategoryRow, Paginated, ProductRow } from '../types';

const { success, danger } = useToast();

/* ---- Veri ---- */
const loading = ref(true);
const products = ref<ProductRow[]>([]);
const page = ref(1);
const lastPage = ref(1);
const total = ref(0);
const categories = ref<CategoryRow[]>([]);

/* ---- Filtreler ---- */
const q = ref('');
const categoryId = ref('');
const status = ref('');

const categoryOptions = computed(() => [
    { value: '', label: 'Tüm kategoriler' },
    ...categories.value.map((c) => ({ value: String(c.id), label: c.parent_id ? `— ${c.name}` : c.name })),
]);

const statusOptions = [
    { value: '', label: 'Tüm durumlar' },
    { value: 'active', label: 'Satışta' },
    { value: 'passive', label: 'Pasif' },
    { value: 'unavailable', label: 'Mevcut değil (tükendi)' },
];

/** Sıralama modu: kategori seçiliyken ve arama yokken sürükle-bırak açık. */
const dragEnabled = computed(() => categoryId.value !== '' && q.value === '' && status.value === '');

async function load(): Promise<void> {
    loading.value = true;
    try {
        const params = new URLSearchParams();
        if (q.value) params.set('q', q.value);
        if (categoryId.value) params.set('category_id', categoryId.value);
        if (status.value) params.set('status', status.value);
        params.set('page', String(page.value));
        params.set('per_page', dragEnabled.value ? '100' : '25');

        const result = await api<{ products: Paginated<ProductRow> }>(`/api/v1/catalog/products?${params}`);
        products.value = result.products.data;
        lastPage.value = result.products.last_page;
        total.value = result.products.total;
        selected.value = new Set();
    } catch (e) {
        danger('Ürünler yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
}

onMounted(async () => {
    try {
        const result = await api<{ categories: CategoryRow[] }>('/api/v1/catalog/categories');
        categories.value = result.categories;
    } catch {
        /* filtre listesi yüklenemedi; arama yine çalışır */
    }
    await load();
});

watch([q, categoryId, status], () => {
    page.value = 1;
    void load();
});
watch(page, () => void load());

/* ---- Seçim + toplu işlem ---- */
const selected = ref<Set<number>>(new Set());
const allChecked = computed(
    () => products.value.length > 0 && products.value.every((p) => selected.value.has(p.id)),
);

function toggleAll(): void {
    selected.value = allChecked.value ? new Set() : new Set(products.value.map((p) => p.id));
}

function toggleOne(id: number): void {
    const next = new Set(selected.value);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    selected.value = next;
}

const bulkBusy = ref(false);
const bulkCategoryId = ref('');
const bulkDeleteOpen = ref(false);

async function bulk(action: string): Promise<void> {
    if (selected.value.size === 0 || bulkBusy.value) return;
    bulkBusy.value = true;
    try {
        const body: Record<string, unknown> = { action, ids: [...selected.value] };
        if (action === 'set_category') body.category_id = Number(bulkCategoryId.value);
        const result = await api<{ affected: number }>('/api/v1/catalog/products/bulk', { method: 'POST', body });
        success('Toplu işlem tamamlandı', `${result.affected} ürün güncellendi.`);
        bulkDeleteOpen.value = false;
        await load();
    } catch (e) {
        danger('Toplu işlem başarısız', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        bulkBusy.value = false;
    }
}

/* ---- Tekil silme ---- */
const deleteTarget = ref<ProductRow | null>(null);
const deleteBusy = ref(false);

async function destroyProduct(): Promise<void> {
    if (!deleteTarget.value || deleteBusy.value) return;
    deleteBusy.value = true;
    try {
        await api(`/api/v1/catalog/products/${deleteTarget.value.id}`, { method: 'DELETE' });
        success('Ürün silindi', `"${deleteTarget.value.name}" menüden kaldırıldı.`);
        deleteTarget.value = null;
        await load();
    } catch (e) {
        danger('Silinemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        deleteBusy.value = false;
    }
}

/* ---- Sürükle-bırak sıralama ---- */
const drag = useDragSort(
    () => products.value,
    (items) => (products.value = items),
    (ids) => {
        void api('/api/v1/catalog/products/reorder', { method: 'POST', body: { ids } })
            .then(() => success('Sıralama kaydedildi'))
            .catch((e) =>
                danger('Sıralama kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Tekrar deneyin.'),
            );
    },
);

const thumb = (p: ProductRow): string | null => p.images?.[0]?.url ?? null;

/* ---- İzinler (arayüz gizleme) ----
 * Garson/mutfak/komi/barista menüyü GÖRÜR (catalog.view) ama ürün
 * ekleyemez/düzenleyemez/silemez. Butonlar izne göre gizlenir; gerçek
 * koruma backend policy/authorize'da. Satır içi aç/kapa switch'i de
 * catalog.update yoksa kilitli çizilir. */
const { can } = usePermissions();
const canCreate = computed<boolean>(() => can('catalog.create'));
const canUpdate = computed<boolean>(() => can('catalog.update'));
const canDelete = computed<boolean>(() => can('catalog.delete'));
// Toplu seçim/işlem yalnız yönetim izni olana anlamlı.
const canBulk = computed<boolean>(() => canUpdate.value || canDelete.value);

const switchBusyId = ref(0);

async function toggleField(p: ProductRow, field: 'is_active' | 'is_available', value: boolean): Promise<void> {
    if (switchBusyId.value) return;
    switchBusyId.value = p.id;
    const previous = p[field];
    (p as unknown as Record<string, boolean>)[field] = value; // iyimser
    try {
        // Dar uç: yalnız ilgili boolean doğrulanır (tam form doğrulaması ÇALIŞMAZ).
        await api(`/api/v1/catalog/products/${p.id}/availability`, { method: 'PATCH', body: { [field]: value } });
        success(
            field === 'is_active' ? (value ? 'Ürün satışta' : 'Ürün satıştan kaldırıldı') : value ? 'Ürün mevcut' : 'Tükendi işaretlendi',
            p.name,
        );
    } catch (e) {
        (p as unknown as Record<string, boolean>)[field] = previous;
        danger('Değiştirilemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        switchBusyId.value = 0;
    }
}
</script>

<template>
    <Head title="Menü — Ürünler" />

    <CatalogShell title="Menü Yönetimi">
        <div class="flex flex-col gap-4">
            <!-- Araç çubuğu -->
            <div class="flex flex-wrap items-center gap-2">
                <div class="w-full sm:w-64">
                    <SearchInput v-model="q" placeholder="Ürün adı, kod veya barkod ara…" label="Ürün ara" />
                </div>
                <div class="w-full sm:w-52">
                    <BaseSelect v-model="categoryId" :options="categoryOptions" />
                </div>
                <div class="w-full sm:w-52">
                    <BaseSelect v-model="status" :options="statusOptions" />
                </div>
                <div class="grow" />
                <BaseButton v-if="canCreate" href="/panel/menu/urunler/yeni">
                    <AppIcon name="plus" :size="16" />
                    Yeni Ürün
                </BaseButton>
            </div>

            <p v-if="dragEnabled" class="flex items-center gap-1.5 text-xs text-muted">
                <AppIcon name="info" :size="14" />
                Bu kategoride satırları sürükleyerek menü sırasını değiştirebilirsiniz.
            </p>

            <p class="flex items-start gap-1.5 text-xs text-muted">
                <AppIcon name="info" :size="14" class="mt-0.5 shrink-0" />
                <span>
                    <strong class="font-semibold text-body">Satışta</strong>: ürün menüde görünsün mü? (kalıcı karar — mevsimlik/kaldırılan ürünü kapatın)
                    &nbsp;·&nbsp;
                    <strong class="font-semibold text-body">Mevcut</strong>: ürün menüde görünür ama bugün stok bitti mi? (geçici — "Tükendi" yazar, gün içinde tekrar açın)
                </span>
            </p>

            <!-- Toplu işlem çubuğu (yalnız yönetim izni olana) -->
            <div
                v-if="canBulk && selected.size > 0"
                class="flex flex-wrap items-center gap-2 rounded-md border border-default bg-surface-alt px-3 py-2"
            >
                <span class="text-sm font-medium text-body">{{ selected.size }} ürün seçili</span>
                <template v-if="canUpdate">
                    <BaseButton size="sm" variant="secondary" :disabled="bulkBusy" @click="bulk('activate')">Satışa al</BaseButton>
                    <BaseButton size="sm" variant="secondary" :disabled="bulkBusy" @click="bulk('deactivate')">Pasifleştir</BaseButton>
                    <BaseButton size="sm" variant="secondary" :disabled="bulkBusy" @click="bulk('set_unavailable')">Tükendi işaretle</BaseButton>
                    <BaseButton size="sm" variant="secondary" :disabled="bulkBusy" @click="bulk('set_available')">Mevcut işaretle</BaseButton>
                    <span class="inline-flex items-center gap-1">
                        <BaseSelect v-model="bulkCategoryId" size="sm" :options="categoryOptions.slice(1)" placeholder="Kategoriye taşı…" />
                        <BaseButton size="sm" variant="secondary" :disabled="bulkBusy || !bulkCategoryId" @click="bulk('set_category')">Taşı</BaseButton>
                    </span>
                </template>
                <div class="grow" />
                <BaseButton v-if="canDelete" size="sm" variant="danger" :disabled="bulkBusy" @click="bulkDeleteOpen = true">Sil</BaseButton>
            </div>

            <!-- Tablo -->
            <div class="w-full overflow-x-auto overscroll-x-contain rounded-md border border-default bg-surface">
                <table class="w-full min-w-max border-collapse text-sm">
                    <caption class="sr-only">Ürün listesi</caption>
                    <thead>
                        <tr class="border-b border-default bg-surface-alt">
                            <th scope="col" class="w-10 px-3 py-2.5">
                                <input
                                    v-if="canBulk"
                                    type="checkbox"
                                    :checked="allChecked"
                                    aria-label="Tümünü seç"
                                    class="size-4 cursor-pointer accent-[var(--color-primary,#4f46e5)]"
                                    @change="toggleAll"
                                />
                            </th>
                            <th v-if="dragEnabled" scope="col" class="w-8 px-1 py-2.5" aria-label="Sırala" />
                            <th scope="col" class="px-3 py-2.5 text-left text-xs font-semibold tracking-wide text-muted uppercase">Ürün</th>
                            <th scope="col" class="px-3 py-2.5 text-left text-xs font-semibold tracking-wide text-muted uppercase">Kategori</th>
                            <th scope="col" class="px-3 py-2.5 text-right text-xs font-semibold tracking-wide text-muted uppercase">Fiyat</th>
                            <th scope="col" class="px-3 py-2.5 text-right text-xs font-semibold tracking-wide text-muted uppercase">KDV</th>
                            <th scope="col" class="px-3 py-2.5 text-left text-xs font-semibold tracking-wide text-muted uppercase">Durum</th>
                            <th scope="col" class="w-24 px-3 py-2.5 text-right text-xs font-semibold tracking-wide text-muted uppercase">İşlem</th>
                        </tr>
                    </thead>
                    <tbody v-if="loading">
                        <tr v-for="i in 6" :key="i" class="border-b border-default">
                            <td v-for="c in 7" :key="c" class="px-3 py-3"><BaseSkeleton size-class="h-3.5 w-3/4" /></td>
                        </tr>
                    </tbody>
                    <tbody v-else-if="products.length">
                        <tr
                            v-for="(p, index) in products"
                            :key="p.id"
                            class="border-b border-default transition-colors duration-(--dur-fast) last:border-b-0 hover:bg-surface-alt"
                            :class="drag.dragIndex.value === index ? 'opacity-60' : ''"
                            :draggable="dragEnabled"
                            @dragstart="dragEnabled && drag.onDragStart(index, $event)"
                            @dragover="dragEnabled && drag.onDragOver(index, $event)"
                            @drop="dragEnabled && drag.onDrop($event)"
                            @dragend="dragEnabled && drag.onDragEnd()"
                        >
                            <td class="px-3 py-2.5">
                                <input
                                    v-if="canBulk"
                                    type="checkbox"
                                    :checked="selected.has(p.id)"
                                    :aria-label="`${p.name} seç`"
                                    class="size-4 cursor-pointer accent-[var(--color-primary,#4f46e5)]"
                                    @change="toggleOne(p.id)"
                                />
                            </td>
                            <td v-if="dragEnabled" class="cursor-grab px-1 py-2.5 text-subtle" aria-hidden="true">
                                <AppIcon name="menu" :size="14" />
                            </td>
                            <td class="px-3 py-2.5">
                                <Link :href="`/panel/menu/urunler/${p.id}`" class="flex items-center gap-3">
                                    <span class="flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-md bg-inset text-subtle">
                                        <img v-if="thumb(p)" :src="thumb(p)!" alt="" class="size-full object-cover" />
                                        <AppIcon v-else name="utensils" :size="16" />
                                    </span>
                                    <span class="flex flex-col">
                                        <span class="font-medium text-body">{{ p.name }}</span>
                                        <span class="flex flex-wrap items-center gap-1 text-xs text-subtle">
                                            <span v-if="p.sku">{{ p.sku }}</span>
                                            <BaseBadge v-if="p.is_new" variant="info" no-icon>Yeni</BaseBadge>
                                            <BaseBadge v-if="p.is_chef_pick" variant="primary" no-icon>Şef önerisi</BaseBadge>
                                            <BaseBadge v-if="p.is_bestseller" variant="warning" no-icon>Çok satan</BaseBadge>
                                        </span>
                                    </span>
                                </Link>
                            </td>
                            <td class="px-3 py-2.5 text-muted">{{ p.category?.name ?? '—' }}</td>
                            <td class="px-3 py-2.5 text-right">
                                <span class="font-medium text-body">{{ formatCurrencyMinor(p.price_minor) }}</span>
                                <span v-if="p.discounted_price_minor" class="block text-xs text-success">
                                    İndirimli: {{ formatCurrencyMinor(p.discounted_price_minor) }}
                                </span>
                                <span v-if="(p.variants_count ?? 0) > 0" class="block text-xs text-subtle">
                                    {{ p.variants_count }} varyant
                                </span>
                            </td>
                            <td class="px-3 py-2.5 text-right text-muted">%{{ Number(p.tax_rate) }}</td>
                            <td class="px-3 py-2.5">
                                <span class="flex flex-col gap-1.5">
                                    <span class="flex items-center gap-2">
                                        <BaseSwitch
                                            size="sm"
                                            :model-value="p.is_active"
                                            :aria-label="`${p.name} satışta/pasif`"
                                            :disabled="!canUpdate"
                                            :busy="switchBusyId === p.id"
                                            @update:model-value="toggleField(p, 'is_active', $event)"
                                        />
                                        <span class="text-xs" :class="p.is_active ? 'text-success' : 'text-subtle'">
                                            {{ p.is_active ? 'Satışta' : 'Pasif' }}
                                        </span>
                                    </span>
                                    <span
                                        class="flex items-center gap-2"
                                        :class="!p.is_active ? 'opacity-45' : ''"
                                        :title="!p.is_active ? 'Ürün satışta değilken stok (Mevcut/Tükendi) durumu uygulanmaz; önce ürünü satışa alın.' : undefined"
                                    >
                                        <BaseSwitch
                                            size="sm"
                                            :model-value="p.is_available"
                                            :aria-label="`${p.name} mevcut/tükendi`"
                                            :disabled="!canUpdate || !p.is_active"
                                            :busy="switchBusyId === p.id"
                                            @update:model-value="toggleField(p, 'is_available', $event)"
                                        />
                                        <span v-if="!p.is_active" class="text-xs text-subtle">Satışta değil</span>
                                        <span v-else class="text-xs" :class="p.is_available ? 'text-muted' : 'text-danger'">
                                            {{ p.is_available ? 'Mevcut' : 'Tükendi' }}
                                        </span>
                                    </span>
                                </span>
                            </td>
                            <td class="px-3 py-2.5">
                                <span class="flex justify-end gap-1">
                                    <BaseButton
                                        v-if="canUpdate"
                                        size="sm"
                                        variant="ghost"
                                        icon-only
                                        :label="`${p.name} düzenle`"
                                        :href="`/panel/menu/urunler/${p.id}`"
                                    >
                                        <AppIcon name="pencil" :size="15" />
                                    </BaseButton>
                                    <BaseButton
                                        v-if="canDelete"
                                        size="sm"
                                        variant="ghost"
                                        icon-only
                                        :label="`${p.name} sil`"
                                        @click="deleteTarget = p"
                                    >
                                        <AppIcon name="trash" :size="15" />
                                    </BaseButton>
                                    <span v-if="!canUpdate && !canDelete" class="text-xs text-subtle">—</span>
                                </span>
                            </td>
                        </tr>
                    </tbody>
                    <tbody v-else>
                        <tr>
                            <td :colspan="dragEnabled ? 8 : 7">
                                <EmptyState
                                    icon="utensils"
                                    title="Ürün bulunamadı"
                                    :description="q || categoryId || status ? 'Filtrelerle eşleşen ürün yok.' : 'Menünüze ilk ürünü ekleyin.'"
                                >
                                    <template v-if="canCreate" #action>
                                        <BaseButton href="/panel/menu/urunler/yeni">
                                            <AppIcon name="plus" :size="16" />
                                            Yeni Ürün
                                        </BaseButton>
                                    </template>
                                </EmptyState>
                            </td>
                        </tr>
                    </tbody>
                </table>
            </div>

            <BasePagination v-if="lastPage > 1 || total > 0" v-model:page="page" :last-page="lastPage" :total="total" />
        </div>

        <ConfirmModal
            :open="deleteTarget !== null"
            title="Ürünü sil"
            :message="`&quot;${deleteTarget?.name ?? ''}&quot; kalıcı olarak silinecek. Bu işlem geri alınamaz.`"
            :busy="deleteBusy"
            @close="deleteTarget = null"
            @confirm="destroyProduct"
        />

        <ConfirmModal
            :open="bulkDeleteOpen"
            title="Seçili ürünleri sil"
            :message="`${selected.size} ürün kalıcı olarak silinecek. Bu işlem geri alınamaz.`"
            :busy="bulkBusy"
            @close="bulkDeleteOpen = false"
            @confirm="bulk('delete')"
        />
    </CatalogShell>
</template>
