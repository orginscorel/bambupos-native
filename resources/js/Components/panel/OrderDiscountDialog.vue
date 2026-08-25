<script setup lang="ts">
/**
 * ADİSYON İNDİRİMİ (ortak diyalog) — hazır tanımlar + serbest indirim.
 *
 * İndirim her seferinde elle giriliyordu (tür + değer + gerekçe). "Şehit/gazi
 * yakını", "kamu personeli" gibi TEKRAR EDEN indirimlerde bu hem yavaş hem
 * hataya açıktı: yanlış oran, tutarsız gerekçe metni, raporda gruplanamayan
 * serbest metin. Artık tanımlar bir kez yapılır, burada tek dokunuşla uygulanır.
 *
 * TEK İNDİRİM KURALI: adisyonda indirim varsa yenisi eklenemez — sunucu da
 * reddeder (üzerine yazma yok). Değiştirmek için önce KALDIR.
 */
import { computed, ref, watch } from 'vue';
import { Link } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import FormField from '@/Components/ui/FormField.vue';

export interface DiscountPresetRow {
    id: number;
    name: string;
    type: 'percent' | 'amount';
    value_percent: number | null;
    value_minor: number | null;
    value_label: string;
    note: string | null;
    /** Açıksa her uygulamada yönetici PIN'i sorulur; kapalıysa tanım ön-onaylıdır. */
    requires_approval: boolean;
    is_active: boolean;
    sort_order: number;
    /** Kullanım (genel) — yönetim ekranında gösterilir. */
    used_count?: number;
    used_minor?: number;
    /** Kullanım (içinde bulunulan ay). */
    month_count?: number;
    month_minor?: number;
}

const props = withDefaults(
    defineProps<{
        open: boolean;
        orderId: number;
        /** Uygulanmış indirim (kuruş) — 0 ise ekleme, >0 ise kaldırma gösterilir. */
        discountMinor: number;
        discountReason?: string | null;
        discountPercent?: number | null;
        orderVersion?: number | null;
        /** Serbest (tanımsız) indirim girebilir mi — yoksa yalnız hazır tanımlar. */
        allowCustom?: boolean;
    }>(),
    { discountReason: null, discountPercent: null, orderVersion: null, allowCustom: true },
);

const emit = defineEmits<{ close: []; applied: []; removed: [] }>();
const { success, danger } = useToast();

const presets = ref<DiscountPresetRow[]>([]);
const loading = ref(false);
const busy = ref(false);
const hasDiscount = computed(() => props.discountMinor > 0);

async function loadPresets(): Promise<void> {
    if (presets.value.length > 0 || loading.value) return;
    loading.value = true;
    try {
        const res = await api<{ presets: DiscountPresetRow[] }>('/api/v1/discount-presets');
        presets.value = res.presets;
    } catch {
        /* tanım gelmezse serbest indirim yine kullanılabilir */
    } finally {
        loading.value = false;
    }
}

/* ---- Serbest indirim alanları ---- */
const showCustom = ref(false);
const cType = ref<'percent' | 'amount'>('percent');
const cValue = ref('');
const cReason = ref('');

/** "12,50" → 1250 kuruş; yüzde alanında ondalık nokta/virgül kabul edilir. */
function numericValue(): number | null {
    const raw = cValue.value.replace(/\s/g, '').replace(',', '.');
    const n = Number(raw);
    if (!Number.isFinite(n) || n <= 0) return null;
    return cType.value === 'percent' ? n : Math.round(n * 100);
}

async function applyPreset(p: DiscountPresetRow): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    try {
        await api(`/api/v1/orders/${props.orderId}/discount`, {
            method: 'POST',
            body: { preset_id: p.id, expected_version: props.orderVersion },
        });
        success('İndirim uygulandı', `${p.name} · ${p.value_label}`);
        emit('applied');
    } catch (e) {
        danger('İndirim uygulanamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        busy.value = false;
    }
}

async function applyCustom(): Promise<void> {
    if (busy.value) return;
    const value = numericValue();
    if (value === null) {
        danger('Değer geçersiz', 'Sıfırdan büyük bir değer girin.');
        return;
    }
    if (cReason.value.trim().length < 3) {
        danger('Gerekçe gerekli', 'En az 3 karakterlik bir gerekçe yazın.');
        return;
    }
    busy.value = true;
    try {
        await api(`/api/v1/orders/${props.orderId}/discount`, {
            method: 'POST',
            body: { type: cType.value, value, reason: cReason.value.trim(), expected_version: props.orderVersion },
        });
        success('İndirim uygulandı', cReason.value.trim());
        emit('applied');
    } catch (e) {
        danger('İndirim uygulanamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        busy.value = false;
    }
}

async function removeDiscount(): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    try {
        await api(`/api/v1/orders/${props.orderId}/discount`, {
            method: 'DELETE',
            body: { expected_version: props.orderVersion },
        });
        success('İndirim kaldırıldı', 'Tutar yeniden hesaplandı.');
        emit('removed');
    } catch (e) {
        danger('Kaldırılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        busy.value = false;
    }
}

watch(
    () => props.open,
    (isOpen) => {
        if (isOpen) {
            void loadPresets();
            showCustom.value = false;
            cType.value = 'percent';
            cValue.value = '';
            cReason.value = '';
        }
    },
);
</script>

<template>
    <BaseModal :open="open" title="İndirim" size="md" @close="emit('close')">
        <div class="flex flex-col gap-4">
            <!-- Uygulanmış indirim: yalnız KALDIRILABİLİR (üzerine yazma yok) -->
            <div
                v-if="hasDiscount"
                class="flex flex-wrap items-center gap-3 rounded-lg border border-warning-border bg-warning-soft p-3"
            >
                <AppIcon name="tag" :size="20" class="shrink-0 text-warning" />
                <div class="min-w-0 grow">
                    <p class="truncate font-semibold text-warning">
                        {{ discountReason || 'İndirim' }}
                        <span v-if="discountPercent" class="font-normal">(%{{ discountPercent }})</span>
                    </p>
                    <p class="text-xs text-muted">
                        Bu adisyonda zaten bir indirim var. Başka indirim uygulamak için önce bunu kaldırın.
                    </p>
                </div>
                <BaseButton variant="danger" size="sm" :loading="busy" @click="removeDiscount">
                    <AppIcon name="trash" :size="14" /> Kaldır
                </BaseButton>
            </div>

            <template v-else>
                <!-- Hazır tanımlar -->
                <div>
                    <p class="mb-1.5 text-sm font-semibold text-body">Hazır indirimler</p>
                    <p v-if="loading" class="py-3 text-sm text-muted">Tanımlar yükleniyor…</p>
                    <p v-else-if="presets.length === 0" class="rounded-lg bg-inset p-3 text-sm text-muted">
                        Tanımlı hazır indirim yok. Sol menüdeki
                        <Link href="/panel/ayarlar/indirimler" class="font-semibold text-primary underline">İndirim Tanımları</Link>
                        ekranından ekleyebilirsiniz (ör. “Şehit/Gazi yakını”, “Kamu personeli”).
                    </p>
                    <div v-else class="grid gap-2 sm:grid-cols-2">
                        <button
                            v-for="p in presets"
                            :key="p.id"
                            type="button"
                            class="flex items-center justify-between gap-2 rounded-lg border border-default p-3 text-left transition hover:border-primary hover:bg-primary-soft disabled:opacity-50"
                            :disabled="busy"
                            @click="applyPreset(p)"
                        >
                            <span class="min-w-0">
                                <span class="block truncate text-sm font-semibold text-body">{{ p.name }}</span>
                                <span v-if="p.note" class="block truncate text-xs text-muted">{{ p.note }}</span>
                            </span>
                            <span class="shrink-0 rounded-full bg-primary-soft px-2.5 py-1 text-sm font-bold text-primary">
                                {{ p.value_label }}
                            </span>
                        </button>
                    </div>
                </div>

                <!-- Serbest indirim (yetkiliye açık kaçış kapısı) -->
                <div v-if="allowCustom" class="border-t border-default pt-3">
                    <button
                        v-if="!showCustom"
                        type="button"
                        class="flex items-center gap-1.5 text-sm font-medium text-muted transition hover:text-body"
                        @click="showCustom = true"
                    >
                        <AppIcon name="plus" :size="15" /> Tanımsız (serbest) indirim gir
                    </button>
                    <div v-else class="flex flex-col gap-3">
                        <FormField label="Tür">
                            <BaseSelect
                                :model-value="cType"
                                :options="[
                                    { value: 'percent', label: 'Yüzde (%)' },
                                    { value: 'amount', label: 'Sabit tutar (₺)' },
                                ]"
                                @update:model-value="(v: string) => (cType = v as 'percent' | 'amount')"
                            />
                        </FormField>
                        <FormField :label="cType === 'percent' ? 'Yüzde' : 'Tutar (₺)'" required>
                            <BaseInput v-model="cValue" inputmode="decimal" :placeholder="cType === 'percent' ? 'ör. 10' : 'ör. 25,00'" />
                        </FormField>
                        <FormField label="Gerekçe" required>
                            <BaseInput v-model="cReason" placeholder="ör. yönetici onaylı özel indirim" />
                        </FormField>
                        <div class="flex justify-end gap-2">
                            <BaseButton variant="secondary" @click="showCustom = false">Vazgeç</BaseButton>
                            <BaseButton :loading="busy" @click="applyCustom">Uygula</BaseButton>
                        </div>
                    </div>
                </div>
            </template>

            <div class="flex justify-end">
                <BaseButton variant="secondary" @click="emit('close')">Kapat</BaseButton>
            </div>
        </div>
    </BaseModal>
</template>
