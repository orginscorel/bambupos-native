<script setup lang="ts">
/**
 * ADİSYONA ÜRÜN EKLE (ortak diyalog).
 *
 * Kasada ve sipariş detayında AYNI ihtiyaç var: adisyonda eksik/unutulmuş bir
 * ürün varsa toplam YANLIŞ kalıyor; kasiyerin ürünü ekleyip DOĞRU tutara
 * ulaşabilmesi gerekir. Sipariş detayı (Orders/Detail.vue) bunu kendi içinde
 * yapıyordu, kasa ekranında hiç yoktu — bu bileşen aynı akışı kasaya da
 * taşır ve tek yerde tutar.
 *
 * Fiyat kuralları sunucuyla BİREBİR aynı yardımcılardan okunur
 * (channelPrice + groupOptionsPrice) — burada ikinci bir fiyat mantığı
 * TÜRETİLMEZ; gösterilen tutar önizlemedir, kaydı sunucu hesaplar.
 *
 * Idempotency: "Ekle" niyeti başına tek anahtar (ürün seçilince üretilir) →
 * yanıt kaybolup tekrar denendiğinde AYNI kalem ikinci kez düşmez.
 */
import { computed, ref, watch } from 'vue';
import { ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import {
    apiIdempotent,
    channelPrice,
    fetchOrderCatalog,
    groupOptionsPrice,
    money,
    newIdempotencyKey,
    type CatalogProduct,
    type OrderCatalog,
} from '@/Pages/Panel/Orders/orders';

const props = withDefaults(
    defineProps<{
        open: boolean;
        orderId: number;
        /** İyimser kilit — adisyon arada değiştiyse sunucu 409 döner. */
        orderVersion?: number | null;
        /** Kanal anahtarı (table/qr/package/kiosk…) — doğru fiyat sütunu için. */
        channel?: string;
        branchId?: number | null;
    }>(),
    { orderVersion: null, channel: 'table', branchId: null },
);

const emit = defineEmits<{ close: []; added: [name: string] }>();
const { success, danger } = useToast();

/* ---- Katalog (ilk açılışta bir kez) ---- */
const catalog = ref<OrderCatalog | null>(null);
const catalogLoading = ref(false);
const catalogError = ref(false);

async function loadCatalog(): Promise<void> {
    if (catalog.value || catalogLoading.value) return;
    catalogLoading.value = true;
    catalogError.value = false;
    try {
        catalog.value = await fetchOrderCatalog(props.branchId);
    } catch {
        catalogError.value = true;
    } finally {
        catalogLoading.value = false;
    }
}

/* ---- Arama / kategori süzgeci (iki seviyeli) ----
 * Sipariş ekranıyla AYNI kural: üst satır ana kategoriler, alt satır seçili
 * ananın altları. Alt kategori tanımlı değilse ikinci satır çizilmez. */
const q = ref('');
const activeCategory = ref<number | null>(null);
const activeSub = ref<number | null>(null);

const rootCategories = computed(() => (catalog.value?.categories ?? []).filter((c) => !c.parent_id));
const isFlatCatalog = computed(() => rootCategories.value.length === (catalog.value?.categories.length ?? 0));
const mainCategories = computed(() => (isFlatCatalog.value ? catalog.value?.categories ?? [] : rootCategories.value));
const subCategories = computed(() =>
    activeCategory.value === null || isFlatCatalog.value
        ? []
        : (catalog.value?.categories ?? []).filter((c) => c.parent_id === activeCategory.value),
);

/** Kategori + alt kategorilerinin id kümesi. */
function categoryTreeIds(categoryId: number): Set<number> {
    const ids = new Set<number>([categoryId]);
    for (const c of catalog.value?.categories ?? []) {
        if (c.parent_id === categoryId) ids.add(c.id);
    }
    return ids;
}

function selectCategory(id: number | null): void {
    activeCategory.value = id;
    activeSub.value = null;
}

const products = computed<CatalogProduct[]>(() => {
    const list = catalog.value?.products ?? [];
    const needle = q.value.trim().toLocaleLowerCase('tr-TR');
    return list.filter((p) => {
        if (activeSub.value !== null) {
            if (p.category_id !== activeSub.value) return false;
        } else if (activeCategory.value !== null) {
            const ids = categoryTreeIds(activeCategory.value);
            if (p.category_id === null || !ids.has(p.category_id)) return false;
        }
        if (needle === '') return true;
        return p.name.toLocaleLowerCase('tr-TR').includes(needle);
    });
});

/* ---- Seçili ürün adımı (varyant + seçenek + adet + not) ---- */
const picked = ref<CatalogProduct | null>(null);
const variantId = ref('');
const optionIds = ref<Set<number>>(new Set());
const qty = ref(1);
const note = ref('');
const idemKey = ref('');
const busy = ref(false);

function unitPrice(p: CatalogProduct): number {
    return channelPrice(p, props.channel);
}

function pick(p: CatalogProduct): void {
    if (!p.is_available) return;
    picked.value = p;
    variantId.value = String(p.variants.find((v) => v.is_default)?.id ?? p.variants[0]?.id ?? '');
    optionIds.value = new Set(p.option_groups.flatMap((g) => g.options.filter((o) => o.is_default).map((o) => o.id)));
    qty.value = Math.max(1, p.min_order_qty);
    note.value = '';
    idemKey.value = newIdempotencyKey();
}

function backToList(): void {
    picked.value = null;
}

function toggleOption(groupId: number, optId: number, single: boolean): void {
    const next = new Set(optionIds.value);
    const group = picked.value?.option_groups.find((g) => g.id === groupId);
    if (single && group) {
        group.options.forEach((o) => next.delete(o.id));
        next.add(optId);
    } else if (next.has(optId)) {
        next.delete(optId);
    } else {
        // Çoklu seçimde grup sınırı dolduysa yeni seçim eklenmez.
        const inGroup = group ? group.options.filter((o) => next.has(o.id)).length : 0;
        if (group?.max_select && inGroup >= group.max_select) return;
        next.add(optId);
    }
    optionIds.value = next;
}

const minQty = computed(() => Math.max(1, picked.value?.min_order_qty ?? 1));
const maxQty = computed(() => picked.value?.max_order_qty ?? 99);

/** Önizleme tutarı — sunucudaki hesapla aynı kurallar (free_limit dahil). */
const previewTotal = computed(() => {
    const p = picked.value;
    if (!p) return 0;
    const variant = p.variants.find((v) => String(v.id) === variantId.value);
    const unit = variant ? variant.price_minor : unitPrice(p);
    const opts = p.option_groups.reduce((n, g) => n + groupOptionsPrice(g, optionIds.value), 0);
    return qty.value * (unit + opts);
});

/** Zorunlu seçenek grupları dolduruldu mu (gereksiz 422 turu olmasın). */
const requiredOk = computed(() => {
    const p = picked.value;
    if (!p) return true;
    return p.option_groups.every((g) => !g.is_required || g.options.some((o) => optionIds.value.has(o.id)));
});
const canSubmit = computed(() => requiredOk.value && qty.value >= minQty.value && qty.value <= maxQty.value);

async function submit(): Promise<void> {
    const p = picked.value;
    if (!p || busy.value || !canSubmit.value) return;
    busy.value = true;
    try {
        await apiIdempotent(
            `/api/v1/orders/${props.orderId}/items`,
            {
                product_id: p.id,
                variant_id: variantId.value ? Number(variantId.value) : null,
                qty: qty.value,
                option_ids: [...optionIds.value],
                note: note.value || null,
                expected_version: props.orderVersion,
            },
            idemKey.value || newIdempotencyKey(),
        );
        success(`${p.name} eklendi`, `${qty.value} adet · ${money(previewTotal.value)} ₺`);
        emit('added', p.name);
        picked.value = null;
    } catch (e) {
        danger('Eklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        busy.value = false;
    }
}

watch(
    () => props.open,
    (isOpen) => {
        if (isOpen) {
            void loadCatalog();
        } else {
            picked.value = null;
            q.value = '';
            activeSub.value = null;
        }
    },
);
</script>

<template>
    <BaseModal
        :open="open"
        :title="picked ? picked.name : 'Adisyona ürün ekle'"
        size="lg"
        @close="emit('close')"
    >
        <!-- ================= 1. adım: ürün seç ================= -->
        <div v-if="!picked" class="flex flex-col gap-3">
            <SearchInput v-model="q" placeholder="Ürün adı ara…" />

            <div v-if="catalog && catalog.categories.length" class="flex flex-col gap-1.5">
                <div class="flex flex-wrap gap-1.5">
                    <button
                        type="button"
                        class="rounded-full border px-3 py-1 text-xs font-semibold transition"
                        :class="activeCategory === null ? 'border-primary bg-primary-soft text-primary' : 'border-default text-muted hover:border-strong'"
                        @click="selectCategory(null)"
                    >
                        Tümü
                    </button>
                    <button
                        v-for="c in mainCategories"
                        :key="c.id"
                        type="button"
                        class="rounded-full border px-3 py-1 text-xs font-semibold transition"
                        :class="activeCategory === c.id ? 'border-primary bg-primary-soft text-primary' : 'border-default text-muted hover:border-strong'"
                        @click="selectCategory(c.id)"
                    >
                        {{ c.name }}
                    </button>
                </div>
                <div v-if="subCategories.length > 0" class="flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-default pt-1.5">
                    <button
                        type="button"
                        class="border-b-2 px-1 py-0.5 text-xs font-medium transition"
                        :class="activeSub === null ? 'border-primary text-primary' : 'border-transparent text-muted hover:text-body'"
                        @click="activeSub = null"
                    >
                        Tümü
                    </button>
                    <button
                        v-for="sc in subCategories"
                        :key="sc.id"
                        type="button"
                        class="border-b-2 px-1 py-0.5 text-xs font-medium transition"
                        :class="activeSub === sc.id ? 'border-primary text-primary' : 'border-transparent text-muted hover:text-body'"
                        @click="activeSub = sc.id"
                    >
                        {{ sc.name }}
                    </button>
                </div>
            </div>

            <p v-if="catalogLoading" class="py-8 text-center text-sm text-muted">Katalog yükleniyor…</p>
            <EmptyState
                v-else-if="catalogError"
                title="Katalog getirilemedi"
                description="Bağlantıyı kontrol edip tekrar deneyin."
                icon="alert-triangle"
            />
            <EmptyState
                v-else-if="products.length === 0"
                title="Ürün bulunamadı"
                :description="q ? `“${q}” için eşleşme yok.` : 'Bu kategoride ürün yok.'"
                icon="search"
            />
            <div v-else class="grid max-h-[52vh] grid-cols-2 gap-2 overflow-y-auto pe-0.5 sm:grid-cols-3">
                <button
                    v-for="p in products"
                    :key="p.id"
                    type="button"
                    class="flex flex-col gap-1 rounded-lg border border-default p-2.5 text-left transition hover:border-primary hover:bg-primary-soft disabled:cursor-not-allowed disabled:opacity-45"
                    :disabled="!p.is_available"
                    @click="pick(p)"
                >
                    <span class="line-clamp-2 text-sm font-semibold text-body">{{ p.name }}</span>
                    <span class="mt-auto flex items-center justify-between gap-1">
                        <span class="text-sm font-bold tabular-nums text-primary">{{ money(unitPrice(p)) }} ₺</span>
                        <BaseBadge v-if="!p.is_available" variant="warning" no-icon>Tükendi</BaseBadge>
                        <span v-else-if="p.variants.length > 1 || p.option_groups.length" class="text-[11px] text-subtle">seçenekli</span>
                    </span>
                </button>
            </div>
        </div>

        <!-- ================= 2. adım: varyant / seçenek / adet ================= -->
        <div v-else class="flex flex-col gap-4">
            <button type="button" class="flex items-center gap-1 self-start text-sm font-medium text-muted transition hover:text-body" @click="backToList">
                <AppIcon name="arrow-left" :size="15" /> Başka ürün seç
            </button>

            <div v-if="picked.variants.length > 1">
                <p class="mb-1.5 text-sm font-semibold text-body">Seçenek</p>
                <div class="flex flex-wrap gap-2">
                    <button
                        v-for="v in picked.variants"
                        :key="v.id"
                        type="button"
                        class="rounded-lg border px-3 py-2 text-sm font-medium transition"
                        :class="variantId === String(v.id) ? 'border-primary bg-primary-soft text-primary' : 'border-default text-body hover:border-strong'"
                        @click="variantId = String(v.id)"
                    >
                        {{ v.name }} · <span class="tabular-nums">{{ money(v.price_minor) }} ₺</span>
                    </button>
                </div>
            </div>

            <div v-for="g in picked.option_groups" :key="g.id">
                <p class="mb-1.5 flex items-center gap-2 text-sm font-semibold text-body">
                    {{ g.name }}
                    <BaseBadge v-if="g.is_required" variant="danger" no-icon>Zorunlu</BaseBadge>
                    <span v-if="g.free_limit > 0" class="text-xs font-normal text-muted">ilk {{ g.free_limit }} ücretsiz</span>
                </p>
                <div class="flex flex-wrap gap-2">
                    <button
                        v-for="o in g.options"
                        :key="o.id"
                        type="button"
                        class="rounded-lg border px-3 py-1.5 text-sm transition"
                        :class="optionIds.has(o.id) ? 'border-primary bg-primary-soft font-semibold text-primary' : 'border-default text-body hover:border-strong'"
                        @click="toggleOption(g.id, o.id, g.selection_type === 'single')"
                    >
                        {{ o.name }}
                        <span v-if="o.price_minor > 0" class="tabular-nums text-muted">+{{ money(o.price_minor) }} ₺</span>
                    </button>
                </div>
            </div>

            <div class="flex flex-wrap items-end gap-4">
                <div>
                    <p class="mb-1.5 text-sm font-semibold text-body">Adet</p>
                    <div class="flex items-center overflow-hidden rounded-md border border-strong">
                        <button
                            type="button"
                            class="flex h-10 w-10 items-center justify-center text-lg font-semibold text-body transition hover:bg-inset disabled:opacity-40"
                            :disabled="qty <= minQty"
                            aria-label="Adet azalt"
                            @click="qty--"
                        >−</button>
                        <span class="min-w-12 px-2 text-center text-base font-bold tabular-nums text-body">{{ qty }}</span>
                        <button
                            type="button"
                            class="flex h-10 w-10 items-center justify-center text-body transition hover:bg-inset disabled:opacity-40"
                            :disabled="qty >= maxQty"
                            aria-label="Adet artır"
                            @click="qty++"
                        >
                            <AppIcon name="plus" :size="17" />
                        </button>
                    </div>
                </div>
                <div class="min-w-40 grow">
                    <p class="mb-1.5 text-sm font-semibold text-body">Not</p>
                    <BaseInput v-model="note" placeholder="ör. az şekerli" />
                </div>
            </div>

            <p v-if="!requiredOk" class="flex items-center gap-1.5 text-sm text-danger">
                <AppIcon name="alert-triangle" :size="15" /> Zorunlu seçenek gruplarından seçim yapın.
            </p>

            <div class="flex items-center justify-between gap-3 border-t border-default pt-3">
                <div>
                    <p class="text-xs font-medium uppercase tracking-wide text-subtle">Satır tutarı</p>
                    <p class="text-2xl font-bold tabular-nums text-body">{{ money(previewTotal) }} ₺</p>
                </div>
                <div class="flex gap-2">
                    <BaseButton variant="secondary" @click="emit('close')">Vazgeç</BaseButton>
                    <BaseButton :loading="busy" :disabled="!canSubmit" @click="submit">
                        <AppIcon name="plus" :size="16" /> Adisyona ekle
                    </BaseButton>
                </div>
            </div>
        </div>
    </BaseModal>
</template>
