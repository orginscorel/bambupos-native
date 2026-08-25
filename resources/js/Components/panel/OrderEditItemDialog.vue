<script setup lang="ts">
/**
 * ADİSYON KALEMİNİ DEĞİŞTİR (ortak diyalog).
 *
 * Kasada kalem üzerinde yalnız "adet / çıkar / ikram" vardı; müşteri
 * "ben bunu şekersiz istemiştim" ya da "büyük boy olacaktı" dediğinde
 * kasiyer kalemi silip yeniden eklemek zorunda kalıyordu. Bu diyalog
 * kalemin ADET, SEÇENEK ve NOT alanlarını yerinde düzenler.
 *
 * SINIR (dürüstlük): sunucunun kalem güncelleme ucu qty/note/option_ids
 * kabul eder — VARYANT değişimi desteklemez. Varyant değişecekse kalem
 * çıkarılıp yeniden eklenmelidir; diyalog bunu açıkça söyler ve tek
 * dokunuşla o akışa yönlendirir.
 */
import { computed, ref, watch } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import {
    channelPrice,
    fetchOrderCatalog,
    groupOptionsPrice,
    money,
    type CatalogProduct,
} from '@/Pages/Panel/Orders/orders';

/** Diyaloğun ihtiyaç duyduğu kalem alanları (kasa ve sipariş tipleriyle uyumlu). */
export interface EditableItem {
    id: number;
    product_id?: number | null;
    qty: number;
    name: string;
    variant_name: string | null;
    unit_price_minor: number;
    options_price_minor: number;
    note: string | null;
    options: Array<{ option_id?: number | null; group_name: string; option_name: string; price_minor: number }>;
}

const props = withDefaults(
    defineProps<{
        open: boolean;
        orderId: number;
        item: EditableItem | null;
        orderVersion?: number | null;
        channel?: string;
        branchId?: number | null;
    }>(),
    { orderVersion: null, channel: 'table', branchId: null },
);

const emit = defineEmits<{ close: []; saved: []; replace: [item: EditableItem] }>();
const { success, danger } = useToast();

/* ---- Katalog: seçenek gruplarını göstermek için ürünü bulmalıyız ---- */
const product = ref<CatalogProduct | null>(null);
const catalogLoading = ref(false);
/** Katalogda ürün bulunamadı (silinmiş/başka şube) → yalnız adet+not düzenlenir. */
const productMissing = ref(false);

async function loadProduct(): Promise<void> {
    const pid = props.item?.product_id ?? null;
    product.value = null;
    productMissing.value = false;
    if (!pid) {
        productMissing.value = true;
        return;
    }
    catalogLoading.value = true;
    try {
        const catalog = await fetchOrderCatalog(props.branchId);
        product.value = catalog.products.find((p) => p.id === pid) ?? null;
        productMissing.value = product.value === null;
    } catch {
        productMissing.value = true;
    } finally {
        catalogLoading.value = false;
    }
}

/* ---- Düzenlenen alanlar ---- */
const qty = ref(1);
const note = ref('');
const optionIds = ref<Set<number>>(new Set());

function reset(): void {
    const it = props.item;
    qty.value = it?.qty ?? 1;
    note.value = it?.note ?? '';
    // Mevcut seçimler katalog option_id'siyle işaretlenir (ada göre eşleştirme yok).
    optionIds.value = new Set(
        (it?.options ?? []).map((o) => o.option_id).filter((id): id is number => typeof id === 'number'),
    );
}

const minQty = computed(() => Math.max(1, product.value?.min_order_qty ?? 1));
const maxQty = computed(() => product.value?.max_order_qty ?? 100);

function toggleOption(groupId: number, optId: number, single: boolean): void {
    const next = new Set(optionIds.value);
    const group = product.value?.option_groups.find((g) => g.id === groupId);
    if (single && group) {
        group.options.forEach((o) => next.delete(o.id));
        next.add(optId);
    } else if (next.has(optId)) {
        next.delete(optId);
    } else {
        const inGroup = group ? group.options.filter((o) => next.has(o.id)).length : 0;
        if (group?.max_select && inGroup >= group.max_select) return;
        next.add(optId);
    }
    optionIds.value = next;
}

/** Önizleme: sunucudaki kuralların aynısı (birim + seçenek, free_limit dahil). */
const previewTotal = computed(() => {
    const it = props.item;
    if (!it) return 0;
    const p = product.value;
    // Varyantlı kalemde birim fiyat kalemin KENDİ kaydından okunur (varyant
    // değişmiyor); katalog fiyatı yalnız ürün bulunamadığında yedektir.
    const unit = it.unit_price_minor || (p ? channelPrice(p, props.channel) : 0);
    const opts = p
        ? p.option_groups.reduce((n, g) => n + groupOptionsPrice(g, optionIds.value), 0)
        : it.options_price_minor;
    return qty.value * (unit + opts);
});

const requiredOk = computed(() => {
    const p = product.value;
    if (!p) return true;
    return p.option_groups.every((g) => !g.is_required || g.options.some((o) => optionIds.value.has(o.id)));
});

const busy = ref(false);

async function save(): Promise<void> {
    const it = props.item;
    if (!it || busy.value || !requiredOk.value) return;
    busy.value = true;
    try {
        const body: Record<string, unknown> = {
            qty: qty.value,
            note: note.value || null,
            expected_version: props.orderVersion,
        };
        // option_ids yalnız katalog bilinirken gönderilir — ürün bulunamadıysa
        // mevcut seçenekleri YANLIŞLIKLA silmeyelim.
        if (product.value) body.option_ids = [...optionIds.value];

        await api(`/api/v1/orders/${props.orderId}/items/${it.id}`, { method: 'PUT', body });
        success('Kalem güncellendi', `${it.name} — ${qty.value} adet · ${money(previewTotal.value)} ₺`);
        emit('saved');
    } catch (e) {
        danger('Güncellenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        busy.value = false;
    }
}

watch(
    () => [props.open, props.item?.id],
    ([isOpen]) => {
        if (isOpen) {
            reset();
            void loadProduct();
        }
    },
    { immediate: true },
);
</script>

<template>
    <BaseModal :open="open" :title="item ? `Kalemi değiştir — ${item.name}` : 'Kalemi değiştir'" size="lg" @close="emit('close')">
        <div v-if="item" class="flex flex-col gap-4">
            <p v-if="item.variant_name" class="flex flex-wrap items-center gap-2 text-sm text-muted">
                Seçili varyant: <BaseBadge variant="neutral" no-icon>{{ item.variant_name }}</BaseBadge>
                <span class="text-xs">Varyant burada değiştirilemez —</span>
                <button type="button" class="text-xs font-semibold text-primary underline" @click="emit('replace', item)">
                    kalemi çıkarıp yeniden ekleyin
                </button>
            </p>

            <!-- Adet -->
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
                    <BaseInput v-model="note" placeholder="ör. az şekerli, soğansız" />
                </div>
            </div>

            <!-- Seçenekler -->
            <p v-if="catalogLoading" class="text-sm text-muted">Seçenekler yükleniyor…</p>
            <div
                v-else-if="productMissing"
                class="flex items-start gap-2 rounded-lg border border-warning-border bg-warning-soft p-3 text-xs text-muted"
            >
                <AppIcon name="alert-triangle" :size="15" class="mt-0.5 shrink-0 text-warning" />
                <span>
                    Bu ürün güncel katalogda bulunamadı (kaldırılmış olabilir); seçenekler düzenlenemiyor.
                    Adet ve not değiştirilebilir, mevcut seçenekler olduğu gibi kalır.
                </span>
            </div>
            <template v-else-if="product">
                <div v-for="g in product.option_groups" :key="g.id">
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
                <p v-if="product.option_groups.length === 0" class="text-sm text-muted">Bu üründe seçenek yok.</p>
            </template>

            <p v-if="!requiredOk" class="flex items-center gap-1.5 text-sm text-danger">
                <AppIcon name="alert-triangle" :size="15" /> Zorunlu seçenek gruplarından seçim yapın.
            </p>

            <div class="flex items-center justify-between gap-3 border-t border-default pt-3">
                <div>
                    <p class="text-xs font-medium uppercase tracking-wide text-subtle">Yeni satır tutarı</p>
                    <p class="text-2xl font-bold tabular-nums text-body">{{ money(previewTotal) }} ₺</p>
                </div>
                <div class="flex gap-2">
                    <BaseButton variant="secondary" @click="emit('close')">Vazgeç</BaseButton>
                    <BaseButton :loading="busy" :disabled="!requiredOk" @click="save">Kaydet</BaseButton>
                </div>
            </div>
        </div>
    </BaseModal>
</template>
