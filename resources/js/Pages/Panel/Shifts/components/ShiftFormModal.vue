<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import FormField from '@/Components/ui/FormField.vue';
import type { ShiftRow, ShiftsMeta } from '../types';
import { joinDateTime, timeOf, dayKey } from '../lib';

/**
 * Vardiya oluşturma/düzenleme modalı.
 * - Çakışma 422'si "yine de kaydet" onayına dönüşür (allow_overlap).
 * - Oluşturmada tekrar (haftalık) desteklenir; düzenlemede desteklenmez.
 * - Kendi vardiyası için (veya yönetici) değişim talebi açılabilir.
 */
const props = defineProps<{
    open: boolean;
    meta: ShiftsMeta | null;
    /** null → yeni kayıt */
    shift: ShiftRow | null;
    /** yeni kayıt ön dolgusu */
    presetUserId?: number | null;
    presetDate?: string | null;
    canManage: boolean;
    myUserId: number;
}>();

const emit = defineEmits<{ close: []; saved: [] }>();

const { success, danger } = useToast();

const form = ref({
    user_id: '' as string | number,
    branch_id: '' as string | number,
    position: '',
    date: '',
    start_time: '09:00',
    end_time: '17:00',
    break_min: '30',
    note: '',
    repeat_weeks: '0',
});

const saving = ref(false);
const deleting = ref(false);
const conflictAsk = ref(false);
const errors = ref<Record<string, string>>({});

/* Değişim talebi */
const swapTarget = ref('');
const swapReason = ref('');
const swapSending = ref(false);

const isEdit = computed(() => props.shift !== null);

watch(
    () => props.open,
    (open) => {
        if (!open) return;
        errors.value = {};
        conflictAsk.value = false;
        swapTarget.value = '';
        swapReason.value = '';

        if (props.shift) {
            form.value = {
                user_id: props.shift.user_id,
                branch_id: props.shift.branch_id,
                position: props.shift.position ?? '',
                date: dayKey(props.shift.starts_at),
                start_time: timeOf(props.shift.starts_at),
                end_time: timeOf(props.shift.ends_at),
                break_min: String(props.shift.break_min),
                note: props.shift.note ?? '',
                repeat_weeks: '0',
            };
        } else {
            form.value = {
                user_id: props.presetUserId ?? props.meta?.staff[0]?.id ?? '',
                branch_id: props.meta?.branches[0]?.id ?? '',
                position: '',
                date: props.presetDate ?? '',
                start_time: '09:00',
                end_time: '17:00',
                break_min: String(props.meta?.default_break_min ?? 30),
                note: '',
                repeat_weeks: '0',
            };
        }
    },
);

const staffOptions = computed(() =>
    (props.meta?.staff ?? []).map((s) => ({ value: s.id, label: s.name + (s.position ? ` — ${s.position}` : '') })),
);
const branchOptions = computed(() => (props.meta?.branches ?? []).map((b) => ({ value: b.id, label: b.name })));
const repeatOptions = [
    { value: '0', label: 'Tek sefer' },
    { value: '1', label: '2 hafta' },
    { value: '3', label: '4 hafta' },
    { value: '7', label: '8 hafta' },
    { value: '12', label: '13 hafta' },
];

const canSwap = computed(
    () => isEdit.value && (props.canManage || props.shift?.user_id === props.myUserId),
);

async function save(allowOverlap = false): Promise<void> {
    if (!form.value.date) {
        errors.value = { date: 'Tarih seçin.' };
        return;
    }

    saving.value = true;
    errors.value = {};

    const payload: Record<string, unknown> = {
        branch_id: Number(form.value.branch_id),
        user_id: Number(form.value.user_id),
        position: form.value.position || null,
        starts_at: joinDateTime(form.value.date, form.value.start_time),
        ends_at: joinDateTime(form.value.date, form.value.end_time),
        break_min: Number(form.value.break_min || 0),
        note: form.value.note || null,
        allow_overlap: allowOverlap,
    };

    try {
        if (isEdit.value && props.shift) {
            await api(`/api/v1/shifts/shifts/${props.shift.id}`, { method: 'PUT', body: payload });
            success('Vardiya güncellendi');
        } else {
            payload.repeat_weeks = Number(form.value.repeat_weeks || 0);
            const result = await api<{ skipped: string[] }>('/api/v1/shifts/shifts', { method: 'POST', body: payload });
            success('Vardiya oluşturuldu');
            if (result.skipped?.length) {
                danger('Bazı tekrar günleri çakışma nedeniyle atlandı', result.skipped.join(', '));
            }
        }
        emit('saved');
        emit('close');
    } catch (e) {
        if (e instanceof ApiError && e.status === 422 && e.errors.starts_at?.[0]?.includes('başka vardiyası')) {
            conflictAsk.value = true;
        } else if (e instanceof ApiError) {
            errors.value = Object.fromEntries(Object.entries(e.errors).map(([k, v]) => [k, v[0]]));
            if (Object.keys(errors.value).length === 0) danger('Kaydedilemedi', e.displayMessage);
        }
    } finally {
        saving.value = false;
    }
}

async function remove(withSeries: boolean): Promise<void> {
    if (!props.shift) return;
    deleting.value = true;
    try {
        const qs = withSeries ? '?with_series=1' : '';
        await api(`/api/v1/shifts/shifts/${props.shift.id}${qs}`, { method: 'DELETE' });
        success(withSeries ? 'Seri silindi' : 'Vardiya silindi');
        emit('saved');
        emit('close');
    } catch (e) {
        if (e instanceof ApiError) danger('Silinemedi', e.displayMessage);
    } finally {
        deleting.value = false;
    }
}

async function requestSwap(): Promise<void> {
    if (!props.shift) return;
    swapSending.value = true;
    try {
        await api(`/api/v1/shifts/shifts/${props.shift.id}/swap-requests`, {
            method: 'POST',
            body: {
                target_user_id: swapTarget.value ? Number(swapTarget.value) : null,
                reason: swapReason.value || null,
            },
        });
        success('Değişim talebi gönderildi', 'Yönetici onayı bekleniyor.');
        emit('close');
    } catch (e) {
        if (e instanceof ApiError) danger('Talep gönderilemedi', e.displayMessage);
    } finally {
        swapSending.value = false;
    }
}
</script>

<template>
    <BaseModal :open="open" :title="isEdit ? 'Vardiyayı Düzenle' : 'Yeni Vardiya'" size="md" @close="emit('close')">
        <div class="flex flex-col gap-4">
            <!-- Çakışma onayı -->
            <div
                v-if="conflictAsk"
                class="rounded-md border border-warning-border bg-warning-soft p-3 text-sm text-warning"
                role="alert"
            >
                <p class="font-semibold">Çakışan vardiya uyarısı</p>
                <p class="mt-1">Bu personelin aynı aralıkta başka vardiyası var. Yine de kaydedilsin mi?</p>
                <div class="mt-2 flex gap-2">
                    <BaseButton size="sm" variant="secondary" @click="conflictAsk = false">Vazgeç</BaseButton>
                    <BaseButton size="sm" :loading="saving" @click="save(true)">Yine de kaydet</BaseButton>
                </div>
            </div>

            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <FormField label="Personel" :error="errors.user_id" required>
                    <BaseSelect v-model="form.user_id" :options="staffOptions" :disabled="!canManage" />
                </FormField>
                <FormField label="Şube" :error="errors.branch_id" required>
                    <BaseSelect v-model="form.branch_id" :options="branchOptions" :disabled="!canManage" />
                </FormField>
                <FormField label="Tarih" :error="errors.date || errors.starts_at" required>
                    <BaseInput v-model="form.date" type="date" :disabled="!canManage" />
                </FormField>
                <FormField label="Pozisyon" :error="errors.position" hint="Boşsa personelin pozisyonu">
                    <BaseInput v-model="form.position" placeholder="ör. Garson" :disabled="!canManage" />
                </FormField>
                <FormField label="Başlangıç" :error="errors.starts_at" required>
                    <BaseInput v-model="form.start_time" type="time" :disabled="!canManage" />
                </FormField>
                <FormField label="Bitiş" :error="errors.ends_at" required>
                    <BaseInput v-model="form.end_time" type="time" :disabled="!canManage" />
                </FormField>
                <FormField label="Mola (dk)" :error="errors.break_min">
                    <BaseInput v-model="form.break_min" type="number" inputmode="numeric" :disabled="!canManage" />
                </FormField>
                <FormField v-if="!isEdit" label="Tekrar" :error="errors.repeat_weeks" hint="Aynı gün ve saatte haftalık">
                    <BaseSelect v-model="form.repeat_weeks" :options="repeatOptions" :disabled="!canManage" />
                </FormField>
            </div>

            <FormField label="Not" :error="errors.note">
                <BaseInput v-model="form.note" placeholder="ör. Açılış vardiyası" :disabled="!canManage" />
            </FormField>

            <!-- Değişim talebi (vardiya sahibi ya da yönetici) -->
            <div v-if="canSwap" class="rounded-md border border-default bg-inset p-3">
                <h4 class="text-sm font-semibold text-body">Vardiya değişim talebi</h4>
                <p class="mt-0.5 text-xs text-muted">
                    Bu vardiyayı devretmek için talep açın; yönetici onayıyla devrolur.
                </p>
                <div class="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2">
                    <BaseSelect
                        v-model="swapTarget"
                        :options="staffOptions.filter((o) => o.value !== shift?.user_id)"
                        placeholder="Devralacak kişi (opsiyonel)"
                    />
                    <BaseInput v-model="swapReason" placeholder="Neden (opsiyonel)" />
                </div>
                <div class="mt-2">
                    <BaseButton size="sm" variant="secondary" :loading="swapSending" @click="requestSwap">
                        Talep gönder
                    </BaseButton>
                </div>
            </div>
        </div>

        <template #footer>
            <div class="flex w-full items-center justify-between gap-2">
                <div class="flex gap-2">
                    <BaseButton
                        v-if="isEdit && canManage"
                        variant="danger"
                        size="sm"
                        :loading="deleting"
                        @click="remove(false)"
                    >
                        Sil
                    </BaseButton>
                    <BaseButton
                        v-if="isEdit && canManage && shift?.repeat_group"
                        variant="ghost"
                        size="sm"
                        :loading="deleting"
                        @click="remove(true)"
                    >
                        Seriyi sil
                    </BaseButton>
                </div>
                <div class="flex gap-2">
                    <BaseButton variant="secondary" @click="emit('close')">Kapat</BaseButton>
                    <BaseButton v-if="canManage" :loading="saving" @click="save(false)">Kaydet</BaseButton>
                </div>
            </div>
        </template>
    </BaseModal>
</template>
