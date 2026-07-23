<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import FormField from '@/Components/ui/FormField.vue';
import {
    fetchAvailability,
    type AvailabilityTable,
    type ReservationRow,
    type ReservationsMeta,
} from './reservations';

/**
 * Rezervasyon oluşturma/düzenleme çekmecesi.
 * Tarih/saat/süre girilince masa uygunluk haritası çekilir; dolu masalar
 * işaretli gelir. Alerji notu alanı yalnız reservations.view_sensitive
 * izniyle gösterilir (sunucu zaten izinsize içerik sızdırmaz).
 */
const props = defineProps<{
    open: boolean;
    meta: ReservationsMeta;
    branchId: number | null;
    editing: ReservationRow | null;
    canSeeSensitive: boolean;
}>();

const emit = defineEmits<{ (e: 'close'): void; (e: 'saved', row: ReservationRow): void }>();

const { success, danger } = useToast();

const form = ref({
    customer_name: '',
    customer_phone: '',
    customer_email: '',
    date: '',
    time: '19:00',
    duration_minutes: 120,
    buffer_minutes: 15,
    party_size: 2,
    area_id: '' as string,
    table_ids: [] as number[],
    special_note: '',
    allergy_note: '',
    occasion: '',
    occasion_note: '',
    deposit_tl: '',
    status: 'confirmed',
});

const errors = ref<Record<string, string>>({});
const saving = ref(false);

const occasionOptions = [
    { value: '', label: '— Yok —' },
    { value: 'birthday', label: 'Doğum günü' },
    { value: 'anniversary', label: 'Yıldönümü' },
    { value: 'business', label: 'İş yemeği' },
    { value: 'other', label: 'Diğer özel gün' },
];

const statusOptions = computed(() =>
    props.meta.statuses
        .filter((s) => ['requested', 'pending', 'confirmed'].includes(s.value))
        .map((s) => ({ value: s.value, label: s.label })),
);

/* ---- Masa uygunluğu ---- */
const availability = ref<AvailabilityTable[]>([]);
const availabilityLoading = ref(false);

const reservedAt = computed(() => (form.value.date ? `${form.value.date} ${form.value.time}:00` : ''));

async function loadAvailability(): Promise<void> {
    if (!props.branchId || !reservedAt.value) {
        availability.value = [];
        return;
    }

    availabilityLoading.value = true;
    try {
        availability.value = await fetchAvailability({
            branch_id: props.branchId,
            reserved_at: reservedAt.value,
            duration_minutes: Number(form.value.duration_minutes) || 120,
            buffer_minutes: Number(form.value.buffer_minutes) || 0,
            ignore_reservation_id: props.editing?.id,
        });
    } catch {
        availability.value = [];
    } finally {
        availabilityLoading.value = false;
    }
}

watch(
    () => [props.open, form.value.date, form.value.time, form.value.duration_minutes, form.value.buffer_minutes],
    () => {
        if (props.open) void loadAvailability();
    },
);

const areaOptions = computed(() => {
    const seen = new Map<number, string>();
    for (const t of availability.value) {
        if (t.area_id && t.area_name) seen.set(t.area_id, t.area_name);
    }
    return [{ value: '', label: '— Fark etmez —' }, ...[...seen].map(([id, name]) => ({ value: String(id), label: name }))];
});

const visibleTables = computed(() =>
    form.value.area_id
        ? availability.value.filter((t) => String(t.area_id ?? '') === form.value.area_id)
        : availability.value,
);

const selectedCapacity = computed(() =>
    availability.value.filter((t) => form.value.table_ids.includes(t.id)).reduce((sum, t) => sum + t.capacity, 0),
);

const capacityShort = computed(
    () => form.value.table_ids.length > 0 && selectedCapacity.value < Number(form.value.party_size),
);

function toggleTable(t: AvailabilityTable): void {
    if (!t.available && !form.value.table_ids.includes(t.id)) return;
    const i = form.value.table_ids.indexOf(t.id);
    if (i >= 0) form.value.table_ids.splice(i, 1);
    else form.value.table_ids.push(t.id);
}

/* ---- Doldurma / sıfırlama ---- */
watch(
    () => props.open,
    (open) => {
        if (!open) return;
        errors.value = {};

        const e = props.editing;
        if (e) {
            form.value = {
                customer_name: e.customer_name,
                customer_phone: e.customer_phone ?? '',
                customer_email: e.customer_email ?? '',
                date: e.reserved_date,
                time: e.reserved_time,
                duration_minutes: e.duration_minutes,
                buffer_minutes: e.buffer_minutes,
                party_size: e.party_size,
                area_id: e.area_id ? String(e.area_id) : '',
                table_ids: e.tables.map((t) => t.id),
                special_note: e.special_note ?? '',
                allergy_note: e.allergy_note ?? '',
                occasion: e.occasion ?? '',
                occasion_note: e.occasion_note ?? '',
                deposit_tl: e.deposit_minor > 0 ? String(e.deposit_minor / 100) : '',
                status: e.status,
            };
        } else {
            const today = new Date();
            form.value = {
                customer_name: '',
                customer_phone: '',
                customer_email: '',
                date: `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`,
                time: '19:00',
                duration_minutes: props.meta.defaults.duration_minutes,
                buffer_minutes: props.meta.defaults.buffer_minutes,
                party_size: 2,
                area_id: '',
                table_ids: [],
                special_note: '',
                allergy_note: '',
                occasion: '',
                occasion_note: '',
                deposit_tl: '',
                status: 'confirmed',
            };
        }
    },
);

async function save(): Promise<void> {
    if (!props.branchId) return;
    saving.value = true;
    errors.value = {};

    const depositMinor = form.value.deposit_tl ? Math.round(parseFloat(form.value.deposit_tl.replace(',', '.')) * 100) : 0;

    const payload: Record<string, unknown> = {
        branch_id: props.branchId,
        customer_name: form.value.customer_name,
        customer_phone: form.value.customer_phone || null,
        customer_email: form.value.customer_email || null,
        reserved_at: reservedAt.value,
        duration_minutes: Number(form.value.duration_minutes),
        buffer_minutes: Number(form.value.buffer_minutes),
        party_size: Number(form.value.party_size),
        area_id: form.value.area_id ? Number(form.value.area_id) : null,
        table_ids: form.value.table_ids,
        special_note: form.value.special_note || null,
        occasion: form.value.occasion || null,
        occasion_note: form.value.occasion_note || null,
        deposit_minor: Number.isFinite(depositMinor) ? depositMinor : 0,
    };

    // Alerji notu yalnız yetkili tarafından yazılabilir/değiştirilebilir.
    if (props.canSeeSensitive) payload.allergy_note = form.value.allergy_note || null;

    if (!props.editing) payload.status = form.value.status;

    try {
        const res = props.editing
            ? await api<{ reservation: ReservationRow }>(`/api/v1/reservations/${props.editing.id}`, { method: 'PUT', body: payload })
            : await api<{ reservation: ReservationRow }>('/api/v1/reservations', { method: 'POST', body: payload });

        success(props.editing ? 'Rezervasyon güncellendi' : 'Rezervasyon oluşturuldu');
        emit('saved', res.reservation);
        emit('close');
    } catch (e) {
        if (e instanceof ApiError) {
            for (const [field, msgs] of Object.entries(e.errors)) errors.value[field] = msgs[0] ?? '';
            danger('Kaydedilemedi', e.displayMessage);
        } else {
            danger('Kaydedilemedi', 'Beklenmeyen bir hata oluştu.');
        }
    } finally {
        saving.value = false;
    }
}
</script>

<template>
    <BaseDrawer :open="open" :title="editing ? 'Rezervasyonu Düzenle' : 'Yeni Rezervasyon'" width-class="sm:max-w-xl" @close="emit('close')">
        <form class="flex flex-col gap-4" @submit.prevent="save">
            <div class="grid gap-3 sm:grid-cols-2">
                <FormField label="Müşteri adı" required :error="errors.customer_name">
                    <BaseInput v-model="form.customer_name" placeholder="Ad Soyad" :invalid="!!errors.customer_name" />
                </FormField>
                <FormField label="Telefon" :error="errors.customer_phone">
                    <BaseInput v-model="form.customer_phone" inputmode="tel" placeholder="05xx xxx xx xx" :invalid="!!errors.customer_phone" />
                </FormField>
            </div>

            <FormField label="E-posta" hint="Onay ve hatırlatma e-postaları bu adrese gider" :error="errors.customer_email">
                <BaseInput v-model="form.customer_email" type="email" inputmode="email" placeholder="ornek@eposta.com" :invalid="!!errors.customer_email" />
            </FormField>

            <div class="grid gap-3 sm:grid-cols-3">
                <FormField label="Tarih" required :error="errors.reserved_at">
                    <BaseInput v-model="form.date" type="date" :invalid="!!errors.reserved_at" />
                </FormField>
                <FormField label="Saat" required>
                    <BaseInput v-model="form.time" type="time" />
                </FormField>
                <FormField label="Kişi sayısı" required :error="errors.party_size">
                    <BaseInput v-model="form.party_size" type="number" inputmode="numeric" :invalid="!!errors.party_size" />
                </FormField>
            </div>

            <div class="grid gap-3 sm:grid-cols-2">
                <FormField label="Süre (dk)" hint="Masanın dolu kalacağı süre">
                    <BaseInput v-model="form.duration_minutes" type="number" inputmode="numeric" />
                </FormField>
                <FormField label="Tampon (dk)" hint="Sonraki rezervasyona hazırlık/temizlik payı">
                    <BaseInput v-model="form.buffer_minutes" type="number" inputmode="numeric" />
                </FormField>
            </div>

            <FormField label="Bölüm tercihi">
                <BaseSelect v-model="form.area_id" :options="areaOptions" />
            </FormField>

            <!-- Masa seçimi + uygunluk -->
            <FormField
                label="Masalar"
                :hint="form.table_ids.length === 0 ? 'Masa seçilmezse atamayı sonra yapabilirsiniz' : `Seçili kapasite: ${selectedCapacity} kişi`"
                :error="errors.table_ids || (capacityShort ? 'Seçili masaların kapasitesi kişi sayısına yetmiyor.' : '')"
            >
                <div v-if="availabilityLoading" class="text-sm text-muted">Uygunluk yükleniyor…</div>
                <div v-else-if="visibleTables.length === 0" class="text-sm text-muted">Bu şubede uygun masa bulunamadı.</div>
                <div v-else class="flex flex-wrap gap-2" role="group" aria-label="Masa seçimi">
                    <button
                        v-for="t in visibleTables"
                        :key="t.id"
                        type="button"
                        class="flex items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-sm transition-colors duration-(--dur-fast)"
                        :class="[
                            form.table_ids.includes(t.id)
                                ? 'border-primary bg-primary-soft text-primary'
                                : t.available
                                    ? 'border-default text-body hover:bg-inset'
                                    : 'cursor-not-allowed border-default text-muted line-through opacity-60',
                        ]"
                        :aria-pressed="form.table_ids.includes(t.id)"
                        :disabled="!t.available && !form.table_ids.includes(t.id)"
                        @click="toggleTable(t)"
                    >
                        <AppIcon :name="form.table_ids.includes(t.id) ? 'check' : 'qr-code'" :size="13" />
                        {{ t.name }}
                        <span class="text-xs opacity-70">({{ t.capacity }})</span>
                    </button>
                </div>
            </FormField>

            <div class="grid gap-3 sm:grid-cols-2">
                <FormField label="Özel gün">
                    <BaseSelect v-model="form.occasion" :options="occasionOptions" />
                </FormField>
                <FormField v-if="form.occasion" label="Özel gün notu">
                    <BaseInput v-model="form.occasion_note" placeholder="ör. pasta sürprizi" />
                </FormField>
            </div>

            <FormField label="Özel not" :error="errors.special_note">
                <BaseInput v-model="form.special_note" placeholder="ör. cam kenarı, bebek sandalyesi" />
            </FormField>

            <FormField
                v-if="canSeeSensitive"
                label="Alerji notu (hassas)"
                hint="Yalnız 'Hassas notları gör' yetkisi olan personel görebilir"
                :error="errors.allergy_note"
            >
                <BaseInput v-model="form.allergy_note" placeholder="ör. fıstık alerjisi" />
            </FormField>
            <p v-else-if="editing?.has_allergy_note" class="flex items-center gap-2 text-sm text-muted">
                <AppIcon name="alert-triangle" :size="15" />
                Bu rezervasyonda alerji notu var; görüntüleme yetkiniz yok.
            </p>

            <div class="grid gap-3 sm:grid-cols-2">
                <FormField label="Kapora (₺)" hint="Boş = kapora yok" :error="errors.deposit_minor">
                    <BaseInput v-model="form.deposit_tl" inputmode="decimal" placeholder="0,00" />
                </FormField>
                <FormField v-if="!editing" label="Başlangıç durumu">
                    <BaseSelect v-model="form.status" :options="statusOptions" />
                </FormField>
            </div>

            <div class="flex justify-end gap-2 border-t border-default pt-4">
                <BaseButton variant="secondary" @click="emit('close')">Vazgeç</BaseButton>
                <BaseButton type="submit" :loading="saving" :disabled="!form.customer_name || !form.date">
                    {{ editing ? 'Kaydet' : 'Rezervasyon oluştur' }}
                </BaseButton>
            </div>
        </form>
    </BaseDrawer>
</template>
