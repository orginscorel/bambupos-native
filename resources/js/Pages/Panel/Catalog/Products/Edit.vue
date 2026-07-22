<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head, router } from '@inertiajs/vue3';
import { api, ApiError, type FieldErrors } from '@/lib/http';
import { formatCurrencyMinor } from '@/lib/format';
import { useToast } from '@/composables/useToast';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseCheckbox from '@/Components/ui/BaseCheckbox.vue';
import BaseTabs from '@/Components/ui/BaseTabs.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import FormField from '@/Components/ui/FormField.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import CatalogShell from '../components/CatalogShell.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import PriceInput from '../components/PriceInput.vue';
import {
    CHANNEL_LABELS,
    STATION_OPTIONS,
    toHm,
    type AllergenRow,
    type CategoryRow,
    type OptionGroupRow,
    type ProductRow,
    type VariantRow,
} from '../types';

const props = defineProps<{ productId: number | null }>();

const { success, danger } = useToast();

const isNew = computed(() => props.productId === null);
const pageTitle = computed(() => (isNew.value ? 'Yeni Ürün' : 'Ürün Düzenle'));

/* ---- Sözlükler ---- */
const categories = ref<CategoryRow[]>([]);
const optionGroups = ref<OptionGroupRow[]>([]);
const allergens = ref<AllergenRow[]>([]);

const categoryOptions = computed(() => [
    { value: '', label: '— Kategorisiz —' },
    ...categories.value.map((c) => ({ value: String(c.id), label: c.parent_id ? `— ${c.name}` : c.name })),
]);

const allergenList = computed(() => allergens.value.filter((a) => a.kind === 'allergen'));
const dietList = computed(() => allergens.value.filter((a) => a.kind === 'diet'));

/* ---- Form durumu ---- */
const loading = ref(true);
const saving = ref(false);
const errors = ref<FieldErrors>({});
const err = (field: string): string => errors.value[field]?.[0] ?? '';

const form = ref({
    name: '',
    description: '',
    category_id: '' as string,
    sku: '',
    barcode: '',
    portion: '',
    unit: '',
    prep_minutes: '' as string | number,

    price_minor: null as number | null,
    discounted_price_minor: null as number | null,
    cost_minor: null as number | null,
    package_price_minor: null as number | null,
    kiosk_price_minor: null as number | null,
    qr_price_minor: null as number | null,
    tax_rate: '10' as string | number,

    calories: '' as string | number,
    protein: '' as string | number,
    carbs: '' as string | number,
    fat: '' as string | number,
    spiciness: '0' as string | number,

    is_new: false,
    is_chef_pick: false,
    is_bestseller: false,
    is_active: true,
    is_available: true,

    channels: ['qr', 'kiosk', 'package', 'pos'] as string[],
    available_from: '',
    available_until: '',
    station: '',
    track_stock: false,
    stock_quantity: '' as string | number,
    min_order_qty: '1' as string | number,
    max_order_qty: '' as string | number,
});

const variants = ref<VariantRow[]>([]);
const selectedGroupIds = ref<number[]>([]);
const selectedAllergenIds = ref<number[]>([]);
const images = ref<NonNullable<ProductRow['images']>>([]);

function fillFrom(p: ProductRow): void {
    form.value = {
        name: p.name,
        description: p.description ?? '',
        category_id: p.category_id ? String(p.category_id) : '',
        sku: p.sku ?? '',
        barcode: p.barcode ?? '',
        portion: p.portion ?? '',
        unit: p.unit ?? '',
        prep_minutes: p.prep_minutes ?? '',
        price_minor: p.price_minor,
        discounted_price_minor: p.discounted_price_minor,
        cost_minor: p.cost_minor,
        package_price_minor: p.package_price_minor,
        kiosk_price_minor: p.kiosk_price_minor,
        qr_price_minor: p.qr_price_minor,
        tax_rate: String(Number(p.tax_rate)),
        calories: p.calories ?? '',
        protein: p.protein === null ? '' : String(Number(p.protein)),
        carbs: p.carbs === null ? '' : String(Number(p.carbs)),
        fat: p.fat === null ? '' : String(Number(p.fat)),
        spiciness: String(p.spiciness),
        is_new: p.is_new,
        is_chef_pick: p.is_chef_pick,
        is_bestseller: p.is_bestseller,
        is_active: p.is_active,
        is_available: p.is_available,
        channels: p.channels ?? ['qr', 'kiosk', 'package', 'pos'],
        available_from: toHm(p.available_from),
        available_until: toHm(p.available_until),
        station: p.station ?? '',
        track_stock: p.track_stock,
        stock_quantity: p.stock_quantity ?? '',
        min_order_qty: String(p.min_order_qty),
        max_order_qty: p.max_order_qty ?? '',
    };
    variants.value = (p.variants ?? []).map((v) => ({
        id: v.id, name: v.name, price_minor: v.price_minor, is_default: v.is_default, is_active: v.is_active,
    }));
    selectedGroupIds.value = (p.option_groups ?? []).map((g) => g.id);
    selectedAllergenIds.value = (p.allergens ?? []).map((a) => a.id);
    images.value = p.images ?? [];
}

onMounted(async () => {
    try {
        const dict = await api<{ categories: CategoryRow[]; option_groups: OptionGroupRow[]; allergens: AllergenRow[] }>(
            '/api/v1/catalog/products/form-options',
        );
        categories.value = dict.categories;
        optionGroups.value = dict.option_groups;
        allergens.value = dict.allergens;

        if (props.productId !== null) {
            const result = await api<{ product: ProductRow }>(`/api/v1/catalog/products/${props.productId}`);
            fillFrom(result.product);
        }
    } catch (e) {
        danger('Ürün yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
});

/* ---- Sekmeler ---- */
const tab = ref('basic');
const tabs = computed(() => [
    { key: 'basic', label: 'Temel Bilgi' },
    { key: 'price', label: 'Fiyat & Varyant' },
    { key: 'options', label: 'Seçenekler' },
    { key: 'allergen', label: 'Alerjen & Besin' },
    ...(isNew.value ? [] : [{ key: 'images', label: 'Görseller' }]),
    { key: 'channel', label: 'Kanal & Görünürlük' },
]);

/* ---- Varyantlar ---- */
function addVariant(): void {
    variants.value.push({ name: '', price_minor: form.value.price_minor ?? 0, is_default: variants.value.length === 0, is_active: true });
}

function removeVariant(index: number): void {
    const wasDefault = variants.value[index].is_default;
    variants.value.splice(index, 1);
    if (wasDefault && variants.value.length > 0) variants.value[0].is_default = true;
}

function setDefaultVariant(index: number): void {
    variants.value.forEach((v, i) => (v.is_default = i === index));
}

/* ---- Seçenek grupları / alerjen seçimleri ---- */
function toggleId(list: number[], id: number): number[] {
    return list.includes(id) ? list.filter((x) => x !== id) : [...list, id];
}

/* ---- Kanallar ---- */
function toggleChannel(key: string): void {
    form.value.channels = form.value.channels.includes(key)
        ? form.value.channels.filter((c) => c !== key)
        : [...form.value.channels, key];
}

/* ---- Kaydet / Sil ---- */
function numOrNull(v: string | number): number | null {
    if (v === '' || v === null || v === undefined) return null;
    const n = Number(String(v).replace(',', '.'));
    return Number.isNaN(n) ? null : n;
}

async function save(): Promise<void> {
    if (saving.value) return;
    saving.value = true;
    errors.value = {};

    const body = {
        name: form.value.name,
        description: form.value.description || null,
        category_id: form.value.category_id ? Number(form.value.category_id) : null,
        sku: form.value.sku || null,
        barcode: form.value.barcode || null,
        portion: form.value.portion || null,
        unit: form.value.unit || null,
        prep_minutes: numOrNull(form.value.prep_minutes),

        price_minor: form.value.price_minor ?? 0,
        discounted_price_minor: form.value.discounted_price_minor,
        cost_minor: form.value.cost_minor,
        package_price_minor: form.value.package_price_minor,
        kiosk_price_minor: form.value.kiosk_price_minor,
        qr_price_minor: form.value.qr_price_minor,
        tax_rate: numOrNull(form.value.tax_rate) ?? 10,

        calories: numOrNull(form.value.calories),
        protein: numOrNull(form.value.protein),
        carbs: numOrNull(form.value.carbs),
        fat: numOrNull(form.value.fat),
        spiciness: Number(form.value.spiciness),

        is_new: form.value.is_new,
        is_chef_pick: form.value.is_chef_pick,
        is_bestseller: form.value.is_bestseller,
        is_active: form.value.is_active,
        is_available: form.value.is_available,

        channels: form.value.channels,
        available_from: form.value.available_from || null,
        available_until: form.value.available_until || null,
        station: form.value.station || null,
        track_stock: form.value.track_stock,
        stock_quantity: form.value.track_stock ? numOrNull(form.value.stock_quantity) : null,
        min_order_qty: numOrNull(form.value.min_order_qty) ?? 1,
        max_order_qty: numOrNull(form.value.max_order_qty),

        variants: variants.value.map((v) => ({
            id: v.id ?? null,
            name: v.name,
            price_minor: v.price_minor ?? 0,
            is_default: v.is_default,
            is_active: v.is_active,
        })),
        option_group_ids: selectedGroupIds.value,
        allergen_ids: selectedAllergenIds.value,
    };

    try {
        if (isNew.value) {
            const result = await api<{ product: ProductRow }>('/api/v1/catalog/products', { method: 'POST', body });
            success('Ürün oluşturuldu', 'Şimdi görsel ekleyebilirsiniz.');
            router.visit(`/panel/menu/urunler/${result.product.id}`);
        } else {
            const result = await api<{ product: ProductRow }>(`/api/v1/catalog/products/${props.productId}`, {
                method: 'PUT',
                body,
            });
            fillFrom(result.product);
            success('Ürün kaydedildi');
        }
    } catch (e) {
        if (e instanceof ApiError) {
            errors.value = e.errors;
            danger('Kaydedilemedi', e.displayMessage);
        } else {
            danger('Kaydedilemedi', 'Beklenmeyen bir hata oluştu.');
        }
    } finally {
        saving.value = false;
    }
}

const deleteOpen = ref(false);
const deleteBusy = ref(false);

async function destroyProduct(): Promise<void> {
    if (deleteBusy.value) return;
    deleteBusy.value = true;
    try {
        await api(`/api/v1/catalog/products/${props.productId}`, { method: 'DELETE' });
        success('Ürün silindi');
        router.visit('/panel/menu');
    } catch (e) {
        danger('Silinemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
        deleteBusy.value = false;
    }
}

/* ---- Görseller ---- */
const uploading = ref(false);
const fileInput = ref<HTMLInputElement | null>(null);

async function uploadImage(e: Event): Promise<void> {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file || uploading.value) return;
    uploading.value = true;

    try {
        const data = new FormData();
        data.append('image', file);
        const match = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]+)/);
        const response = await fetch(`/api/v1/catalog/products/${props.productId}/images`, {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
                Accept: 'application/json',
                'X-Requested-With': 'XMLHttpRequest',
                'X-XSRF-TOKEN': match ? decodeURIComponent(match[1]) : '',
            },
            body: data,
        });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) {
            const message =
                (payload as { errors?: FieldErrors; message?: string }).errors?.image?.[0] ??
                (payload as { message?: string }).message ??
                'Görsel yüklenemedi.';
            throw new Error(message);
        }
        images.value = [...images.value, (payload as { image: NonNullable<ProductRow['images']>[number] }).image];
        success('Görsel yüklendi');
    } catch (e2) {
        danger('Görsel yüklenemedi', e2 instanceof Error ? e2.message : 'Lütfen tekrar deneyin.');
    } finally {
        uploading.value = false;
        input.value = '';
    }
}

async function makePrimary(imageId: number): Promise<void> {
    try {
        await api(`/api/v1/catalog/products/${props.productId}/images/${imageId}/primary`, { method: 'POST' });
        images.value = images.value.map((img) => ({ ...img, is_primary: img.id === imageId }));
        success('Kapak görseli güncellendi');
    } catch (e) {
        danger('Güncellenemedi', e instanceof ApiError ? e.displayMessage : 'Tekrar deneyin.');
    }
}

async function removeImage(imageId: number): Promise<void> {
    try {
        await api(`/api/v1/catalog/products/${props.productId}/images/${imageId}`, { method: 'DELETE' });
        images.value = images.value.filter((img) => img.id !== imageId);
        success('Görsel silindi');
    } catch (e) {
        danger('Silinemedi', e instanceof ApiError ? e.displayMessage : 'Tekrar deneyin.');
    }
}

const spicinessOptions = [
    { value: '0', label: 'Acısız' },
    { value: '1', label: 'Hafif acı 🌶' },
    { value: '2', label: 'Acı 🌶🌶' },
    { value: '3', label: 'Çok acı 🌶🌶🌶' },
];
</script>

<template>
    <Head :title="`Menü — ${pageTitle}`" />

    <CatalogShell :title="pageTitle">
        <div class="flex flex-col gap-4">
            <!-- Üst şerit -->
            <div class="flex flex-wrap items-center gap-2">
                <BaseButton variant="ghost" href="/panel/menu" size="sm">
                    <AppIcon name="arrow-left" :size="15" />
                    Ürün listesi
                </BaseButton>
                <h1 class="text-lg font-semibold text-body">{{ isNew ? 'Yeni Ürün' : form.name || 'Ürün' }}</h1>
                <BaseBadge v-if="!isNew && !form.is_active" variant="neutral">Pasif</BaseBadge>
                <BaseBadge v-if="!isNew && !form.is_available" variant="danger">Tükendi</BaseBadge>
                <div class="grow" />
                <BaseButton v-if="!isNew" variant="danger" size="sm" @click="deleteOpen = true">
                    <AppIcon name="trash" :size="15" />
                    Sil
                </BaseButton>
                <BaseButton :loading="saving" @click="save">Kaydet</BaseButton>
            </div>

            <div v-if="loading" class="flex flex-col gap-3 rounded-md border border-default bg-surface p-5">
                <BaseSkeleton size-class="h-5 w-1/3" />
                <BaseSkeleton size-class="h-10 w-full" />
                <BaseSkeleton size-class="h-10 w-2/3" />
                <BaseSkeleton size-class="h-10 w-1/2" />
            </div>

            <div v-else class="rounded-md border border-default bg-surface p-4 sm:p-5">
                <BaseTabs v-model="tab" :tabs="tabs">
                    <!-- ============ Temel Bilgi ============ -->
                    <template #basic>
                        <div class="grid gap-4 sm:grid-cols-2">
                            <FormField label="Ürün adı" required :error="err('name')" class="sm:col-span-2">
                                <BaseInput v-model="form.name" placeholder="Ör. Izgara Köfte" />
                            </FormField>
                            <FormField label="Açıklama" :error="err('description')" class="sm:col-span-2">
                                <textarea
                                    v-model="form.description"
                                    rows="3"
                                    placeholder="Menüde görünecek kısa açıklama"
                                    class="w-full rounded-md border border-strong bg-raised px-3 py-2 text-sm text-body placeholder:text-subtle focus:ring-ring-brand focus:ring-2 focus:outline-none"
                                />
                            </FormField>
                            <FormField label="Kategori" :error="err('category_id')">
                                <BaseSelect v-model="form.category_id" :options="categoryOptions" />
                            </FormField>
                            <FormField label="Hazırlama süresi (dk)" :error="err('prep_minutes')">
                                <BaseInput v-model="form.prep_minutes" inputmode="numeric" placeholder="15" />
                            </FormField>
                            <FormField label="Ürün kodu (SKU)" :error="err('sku')">
                                <BaseInput v-model="form.sku" placeholder="Ör. KFT-01" />
                            </FormField>
                            <FormField label="Barkod" :error="err('barcode')">
                                <BaseInput v-model="form.barcode" placeholder="Barkod numarası" />
                            </FormField>
                            <FormField label="Porsiyon" hint="Ör. 250 gr, 2 kişilik" :error="err('portion')">
                                <BaseInput v-model="form.portion" />
                            </FormField>
                            <FormField label="Birim" hint="adet / porsiyon / gram / ml" :error="err('unit')">
                                <BaseInput v-model="form.unit" />
                            </FormField>
                            <div class="sm:col-span-2">
                                <p class="mb-1 text-sm font-medium text-body">Etiketler</p>
                                <div class="flex flex-wrap gap-x-6">
                                    <BaseCheckbox v-model="form.is_new" label="Yeni" />
                                    <BaseCheckbox v-model="form.is_chef_pick" label="Şef önerisi" />
                                    <BaseCheckbox v-model="form.is_bestseller" label="Çok satan" />
                                </div>
                            </div>
                        </div>
                    </template>

                    <!-- ============ Fiyat & Varyant ============ -->
                    <template #price>
                        <div class="flex flex-col gap-5">
                            <div class="grid gap-4 sm:grid-cols-3">
                                <FormField label="Satış fiyatı" required :error="err('price_minor')">
                                    <PriceInput v-model="form.price_minor" />
                                </FormField>
                                <FormField label="İndirimli fiyat" hint="Boşsa indirim yok" :error="err('discounted_price_minor')">
                                    <PriceInput v-model="form.discounted_price_minor" />
                                </FormField>
                                <FormField label="KDV oranı (%)" :error="err('tax_rate')">
                                    <BaseInput v-model="form.tax_rate" inputmode="decimal" placeholder="10" />
                                </FormField>
                                <FormField label="Maliyet" hint="Kâr raporları için" :error="err('cost_minor')">
                                    <PriceInput v-model="form.cost_minor" />
                                </FormField>
                                <FormField label="Paket servis fiyatı" hint="Boşsa satış fiyatı geçerli" :error="err('package_price_minor')">
                                    <PriceInput v-model="form.package_price_minor" />
                                </FormField>
                                <FormField label="Kiosk fiyatı" hint="Boşsa satış fiyatı geçerli" :error="err('kiosk_price_minor')">
                                    <PriceInput v-model="form.kiosk_price_minor" />
                                </FormField>
                                <FormField label="QR menü fiyatı" hint="Boşsa satış fiyatı geçerli" :error="err('qr_price_minor')">
                                    <PriceInput v-model="form.qr_price_minor" />
                                </FormField>
                            </div>

                            <div class="border-t border-default pt-4">
                                <div class="mb-2 flex items-center justify-between">
                                    <div>
                                        <h3 class="text-sm font-semibold text-body">Varyantlar (boyut / porsiyon)</h3>
                                        <p class="text-xs text-muted">Ör. Küçük / Orta / Büyük — her varyantın kendi fiyatı olur.</p>
                                    </div>
                                    <BaseButton size="sm" variant="secondary" @click="addVariant">
                                        <AppIcon name="plus" :size="14" />
                                        Varyant ekle
                                    </BaseButton>
                                </div>
                                <p v-if="variants.length === 0" class="text-sm text-subtle">Varyant yok; ürün tek fiyatla satılır.</p>
                                <div v-else class="flex flex-col gap-2">
                                    <div
                                        v-for="(variant, index) in variants"
                                        :key="variant.id ?? `new-${index}`"
                                        class="flex flex-wrap items-center gap-2 rounded-md border border-default bg-surface-alt p-2"
                                    >
                                        <input
                                            v-model="variant.name"
                                            type="text"
                                            placeholder="Varyant adı (ör. Büyük)"
                                            :aria-label="`Varyant ${index + 1} adı`"
                                            class="h-9 w-44 rounded-md border border-strong bg-raised px-2.5 text-sm text-body placeholder:text-subtle focus:ring-ring-brand focus:ring-2 focus:outline-none"
                                        />
                                        <div class="w-36">
                                            <PriceInput v-model="variant.price_minor" />
                                        </div>
                                        <label class="flex cursor-pointer items-center gap-1.5 text-sm text-body">
                                            <input
                                                type="radio"
                                                name="default-variant"
                                                :checked="variant.is_default"
                                                class="size-4 accent-[var(--color-primary,#4f46e5)]"
                                                @change="setDefaultVariant(index)"
                                            />
                                            Varsayılan
                                        </label>
                                        <BaseCheckbox v-model="variant.is_active" label="Aktif" />
                                        <div class="grow" />
                                        <BaseButton size="sm" variant="ghost" icon-only :label="`Varyant ${index + 1} sil`" @click="removeVariant(index)">
                                            <AppIcon name="trash" :size="15" />
                                        </BaseButton>
                                    </div>
                                </div>
                                <p v-if="err('variants')" class="mt-1 text-xs font-medium text-danger">{{ err('variants') }}</p>
                            </div>
                        </div>
                    </template>

                    <!-- ============ Seçenekler ============ -->
                    <template #options>
                        <div class="flex flex-col gap-3">
                            <p class="text-sm text-muted">
                                Bu ürüne bağlanacak seçenek gruplarını işaretleyin. Grupları
                                <a href="/panel/menu/secenekler" class="font-medium text-primary hover:underline">Seçenek Grupları</a>
                                sayfasından yönetebilirsiniz.
                            </p>
                            <p v-if="optionGroups.length === 0" class="text-sm text-subtle">Henüz seçenek grubu tanımlanmamış.</p>
                            <label
                                v-for="group in optionGroups"
                                :key="group.id"
                                class="flex cursor-pointer items-start gap-3 rounded-md border p-3 transition-colors duration-(--dur-fast)"
                                :class="selectedGroupIds.includes(group.id) ? 'border-primary bg-primary-soft' : 'border-default bg-surface-alt hover:border-strong'"
                            >
                                <input
                                    type="checkbox"
                                    :checked="selectedGroupIds.includes(group.id)"
                                    class="mt-1 size-4 cursor-pointer accent-[var(--color-primary,#4f46e5)]"
                                    @change="selectedGroupIds = toggleId(selectedGroupIds, group.id)"
                                />
                                <span class="flex flex-col gap-0.5">
                                    <span class="flex flex-wrap items-center gap-1.5 text-sm font-medium text-body">
                                        {{ group.name }}
                                        <BaseBadge :variant="group.is_required ? 'warning' : 'neutral'" no-icon>
                                            {{ group.is_required ? 'Zorunlu' : 'Opsiyonel' }}
                                        </BaseBadge>
                                        <BaseBadge variant="neutral" no-icon>
                                            {{ group.selection_type === 'single' ? 'Tek seçim' : 'Çoklu seçim' }}
                                        </BaseBadge>
                                        <BaseBadge v-if="group.free_limit > 0" variant="success" no-icon>
                                            {{ group.free_limit }} adet ücretsiz
                                        </BaseBadge>
                                    </span>
                                    <span class="text-xs text-muted">
                                        {{ group.options.map((o) => o.name + (o.price_minor ? ` (+${formatCurrencyMinor(o.price_minor)})` : '')).join(', ') }}
                                    </span>
                                </span>
                            </label>
                        </div>
                    </template>

                    <!-- ============ Alerjen & Besin ============ -->
                    <template #allergen>
                        <div class="flex flex-col gap-6">
                            <div>
                                <h3 class="mb-2 text-sm font-semibold text-body">Alerjenler</h3>
                                <div class="flex flex-wrap gap-2">
                                    <button
                                        v-for="a in allergenList"
                                        :key="a.id"
                                        type="button"
                                        class="inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm transition-colors duration-(--dur-fast)"
                                        :class="selectedAllergenIds.includes(a.id)
                                            ? 'border-primary bg-primary-soft font-medium text-primary'
                                            : 'border-default bg-surface-alt text-body hover:border-strong'"
                                        :aria-pressed="selectedAllergenIds.includes(a.id)"
                                        :title="a.description ?? undefined"
                                        @click="selectedAllergenIds = toggleId(selectedAllergenIds, a.id)"
                                    >
                                        <span class="size-2 rounded-full" :style="{ backgroundColor: a.color ?? '#9ca3af' }" aria-hidden="true" />
                                        {{ a.name }}
                                        <AppIcon v-if="selectedAllergenIds.includes(a.id)" name="check" :size="13" />
                                    </button>
                                </div>
                            </div>
                            <div>
                                <h3 class="mb-2 text-sm font-semibold text-body">Diyet etiketleri</h3>
                                <div class="flex flex-wrap gap-2">
                                    <button
                                        v-for="a in dietList"
                                        :key="a.id"
                                        type="button"
                                        class="inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm transition-colors duration-(--dur-fast)"
                                        :class="selectedAllergenIds.includes(a.id)
                                            ? 'border-primary bg-primary-soft font-medium text-primary'
                                            : 'border-default bg-surface-alt text-body hover:border-strong'"
                                        :aria-pressed="selectedAllergenIds.includes(a.id)"
                                        :title="a.description ?? undefined"
                                        @click="selectedAllergenIds = toggleId(selectedAllergenIds, a.id)"
                                    >
                                        {{ a.name }}
                                        <AppIcon v-if="selectedAllergenIds.includes(a.id)" name="check" :size="13" />
                                    </button>
                                </div>
                            </div>
                            <div class="border-t border-default pt-4">
                                <h3 class="mb-3 text-sm font-semibold text-body">Besin değerleri <span class="font-normal text-muted">(porsiyon başına, isteğe bağlı)</span></h3>
                                <div class="grid gap-4 sm:grid-cols-4">
                                    <FormField label="Kalori (kcal)" :error="err('calories')">
                                        <BaseInput v-model="form.calories" inputmode="numeric" />
                                    </FormField>
                                    <FormField label="Protein (g)" :error="err('protein')">
                                        <BaseInput v-model="form.protein" inputmode="decimal" />
                                    </FormField>
                                    <FormField label="Karbonhidrat (g)" :error="err('carbs')">
                                        <BaseInput v-model="form.carbs" inputmode="decimal" />
                                    </FormField>
                                    <FormField label="Yağ (g)" :error="err('fat')">
                                        <BaseInput v-model="form.fat" inputmode="decimal" />
                                    </FormField>
                                </div>
                            </div>
                            <FormField label="Acılık" :error="err('spiciness')" class="sm:max-w-56">
                                <BaseSelect v-model="form.spiciness" :options="spicinessOptions" />
                            </FormField>
                        </div>
                    </template>

                    <!-- ============ Görseller (yalnız kayıtlı ürün) ============ -->
                    <template #images>
                        <div class="flex flex-col gap-4">
                            <div class="flex flex-wrap items-center gap-3">
                                <input
                                    ref="fileInput"
                                    type="file"
                                    accept=".jpg,.jpeg,.png,.webp"
                                    class="hidden"
                                    @change="uploadImage"
                                />
                                <BaseButton variant="secondary" :loading="uploading" @click="fileInput?.click()">
                                    <AppIcon name="plus" :size="16" />
                                    Görsel yükle
                                </BaseButton>
                                <p class="text-xs text-muted">JPG, PNG veya WebP · en fazla 4 MB · en fazla 8 görsel</p>
                            </div>
                            <p v-if="images.length === 0" class="text-sm text-subtle">Henüz görsel yok.</p>
                            <div v-else class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                                <figure
                                    v-for="img in images"
                                    :key="img.id"
                                    class="group relative overflow-hidden rounded-md border border-default"
                                >
                                    <img :src="img.url" :alt="img.original_name ?? 'Ürün görseli'" class="aspect-square w-full object-cover" />
                                    <BaseBadge v-if="img.is_primary" variant="primary" no-icon class="absolute top-2 left-2">Kapak</BaseBadge>
                                    <figcaption class="flex items-center justify-between gap-1 border-t border-default bg-surface-alt px-2 py-1.5">
                                        <button
                                            v-if="!img.is_primary"
                                            type="button"
                                            class="text-xs font-medium text-primary hover:underline"
                                            @click="makePrimary(img.id)"
                                        >
                                            Kapak yap
                                        </button>
                                        <span v-else class="text-xs text-subtle">Kapak görseli</span>
                                        <BaseButton size="sm" variant="ghost" icon-only label="Görseli sil" @click="removeImage(img.id)">
                                            <AppIcon name="trash" :size="14" />
                                        </BaseButton>
                                    </figcaption>
                                </figure>
                            </div>
                        </div>
                    </template>

                    <!-- ============ Kanal & Görünürlük ============ -->
                    <template #channel>
                        <div class="flex flex-col gap-6">
                            <div>
                                <h3 class="mb-2 text-sm font-semibold text-body">Satış kanalları</h3>
                                <div class="flex flex-wrap gap-x-6">
                                    <BaseCheckbox
                                        v-for="(label, key) in CHANNEL_LABELS"
                                        :key="key"
                                        :model-value="form.channels.includes(key)"
                                        :label="label"
                                        @update:model-value="toggleChannel(key)"
                                    />
                                </div>
                                <p v-if="err('channels')" class="mt-1 text-xs font-medium text-danger">{{ err('channels') }}</p>
                            </div>

                            <div class="grid gap-4 sm:grid-cols-2">
                                <BaseCheckbox v-model="form.is_active" label="Satışta" description="Kapalıysa ürün hiçbir kanalda görünmez." />
                                <BaseCheckbox v-model="form.is_available" label="Mevcut" description="Kapatınca menüde 'tükendi' görünür." />
                            </div>

                            <div class="grid gap-4 sm:grid-cols-3">
                                <FormField label="Servis başlangıcı" hint="Boşsa gün boyu" :error="err('available_from')">
                                    <BaseInput v-model="form.available_from" type="time" />
                                </FormField>
                                <FormField label="Servis bitişi" :error="err('available_until')">
                                    <BaseInput v-model="form.available_until" type="time" />
                                </FormField>
                                <FormField label="Hazırlama istasyonu" :error="err('station')">
                                    <BaseSelect v-model="form.station" :options="STATION_OPTIONS" />
                                </FormField>
                            </div>

                            <div class="border-t border-default pt-4">
                                <h3 class="mb-2 text-sm font-semibold text-body">Stok & sipariş sınırları</h3>
                                <div class="grid items-end gap-4 sm:grid-cols-4">
                                    <BaseCheckbox
                                        v-model="form.track_stock"
                                        label="Stok takibi"
                                        description="Stok modülü açıldığında bu alan bağlanır."
                                    />
                                    <FormField label="Stok adedi" :error="err('stock_quantity')">
                                        <BaseInput v-model="form.stock_quantity" inputmode="numeric" :disabled="!form.track_stock" />
                                    </FormField>
                                    <FormField label="En az sipariş adedi" :error="err('min_order_qty')">
                                        <BaseInput v-model="form.min_order_qty" inputmode="numeric" />
                                    </FormField>
                                    <FormField label="En fazla sipariş adedi" hint="Boşsa sınırsız" :error="err('max_order_qty')">
                                        <BaseInput v-model="form.max_order_qty" inputmode="numeric" />
                                    </FormField>
                                </div>
                            </div>
                        </div>
                    </template>
                </BaseTabs>

                <div class="mt-5 flex justify-end gap-2 border-t border-default pt-4">
                    <BaseButton variant="secondary" href="/panel/menu">Vazgeç</BaseButton>
                    <BaseButton :loading="saving" @click="save">Kaydet</BaseButton>
                </div>
            </div>
        </div>

        <ConfirmModal
            :open="deleteOpen"
            title="Ürünü sil"
            :message="`&quot;${form.name}&quot; kalıcı olarak silinecek. Bu işlem geri alınamaz.`"
            :busy="deleteBusy"
            @close="deleteOpen = false"
            @confirm="destroyProduct"
        />
    </CatalogShell>
</template>
