<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import FormField from '@/Components/ui/FormField.vue';
import type { StaffMeta, StaffRow } from '../types';

/**
 * Personel hesabı açma / düzenleme çekmecesi.
 * Rol ataması switch listesiyle; açılış ekranı tercihi seçilebilir
 * (boş = izinlere göre otomatik).
 */
const props = defineProps<{
    open: boolean;
    meta: StaffMeta | null;
    /** null → yeni kayıt */
    staff: StaffRow | null;
}>();

const emit = defineEmits<{ close: []; saved: [] }>();

const { success, danger } = useToast();

const isNew = computed(() => props.staff === null);

const form = ref({
    first_name: '',
    last_name: '',
    email: '',
    phone: '',
    staff_code: '',
    department: '',
    position: '',
    hired_at: '',
    password: '',
    branch_id: '',
    default_screen: '',
    is_active: true,
    roleIds: [] as number[],
});

const errors = ref<Record<string, string>>({});
const saving = ref(false);

watch(
    () => [props.open, props.staff?.id],
    () => {
        if (!props.open) return;
        errors.value = {};
        const s = props.staff;
        form.value = {
            first_name: s?.first_name ?? '',
            last_name: s?.last_name ?? '',
            email: s?.email ?? '',
            phone: s?.phone ?? '',
            staff_code: s?.staff_code ?? '',
            department: s?.department ?? '',
            position: s?.position ?? '',
            hired_at: s?.hired_at ? s.hired_at.slice(0, 10) : '',
            password: '',
            branch_id: s?.branch?.id ? String(s.branch.id) : (s?.branch_id ? String(s.branch_id) : ''),
            default_screen: s?.default_screen ?? '',
            is_active: s?.is_active ?? true,
            roleIds: (s?.roles ?? []).map((r) => r.id),
        };
    },
    { immediate: true },
);

const branchOptions = computed(() => [
    { value: '', label: 'Şube seçin' },
    ...(props.meta?.branches ?? []).map((b) => ({ value: String(b.id), label: b.name })),
]);

const screenOptions = computed(() => [
    { value: '', label: 'Otomatik (rolüne en uygun ekran)' },
    ...(props.meta?.screens ?? []).map((s) => ({ value: s.key, label: s.label })),
]);

function toggleRole(roleId: number, on: boolean): void {
    const next = new Set(form.value.roleIds);
    if (on) next.add(roleId);
    else next.delete(roleId);
    form.value.roleIds = [...next];
}

async function save(): Promise<void> {
    if (saving.value) return;
    saving.value = true;
    errors.value = {};

    const body: Record<string, unknown> = {
        first_name: form.value.first_name,
        last_name: form.value.last_name,
        phone: form.value.phone || null,
        department: form.value.department || null,
        position: form.value.position || null,
        hired_at: form.value.hired_at || null,
        branch_id: form.value.branch_id ? Number(form.value.branch_id) : null,
        default_screen: form.value.default_screen || null,
        roles: form.value.roleIds,
    };

    try {
        if (isNew.value) {
            await api('/api/v1/staff', {
                method: 'POST',
                body: {
                    ...body,
                    email: form.value.email,
                    staff_code: form.value.staff_code || null,
                    password: form.value.password,
                },
            });
            success('Personel oluşturuldu', `${form.value.first_name} ${form.value.last_name} eklendi.`);
        } else {
            await api(`/api/v1/staff/${props.staff!.id}`, {
                method: 'PUT',
                body: { ...body, is_active: form.value.is_active },
            });
            success('Personel güncellendi');
        }
        emit('saved');
        emit('close');
    } catch (e) {
        if (e instanceof ApiError) {
            for (const [field, msgs] of Object.entries(e.errors)) errors.value[field] = msgs[0] ?? '';
            danger(isNew.value ? 'Personel oluşturulamadı' : 'Güncellenemedi', e.displayMessage);
        } else {
            danger('İşlem başarısız', 'Lütfen tekrar deneyin.');
        }
    } finally {
        saving.value = false;
    }
}
</script>

<template>
    <BaseDrawer :open="open" :title="isNew ? 'Yeni Personel' : 'Personeli Düzenle'" width-class="sm:max-w-lg" @close="emit('close')">
        <form class="flex flex-col gap-4" @submit.prevent="save">
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <FormField label="Ad" required :error="errors.first_name">
                    <BaseInput v-model="form.first_name" autocomplete="off" />
                </FormField>
                <FormField label="Soyad" required :error="errors.last_name">
                    <BaseInput v-model="form.last_name" autocomplete="off" />
                </FormField>
            </div>

            <FormField label="E-posta" required :error="errors.email" :hint="isNew ? '' : 'E-posta sonradan değiştirilemez.'">
                <BaseInput v-model="form.email" type="email" inputmode="email" :disabled="!isNew" autocomplete="off" />
            </FormField>

            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <FormField label="Telefon" :error="errors.phone">
                    <BaseInput v-model="form.phone" type="tel" inputmode="tel" autocomplete="off" />
                </FormField>
                <FormField label="Personel kodu" :error="errors.staff_code" :hint="isNew ? 'PIN girişinde kullanılır.' : 'Kod sonradan değiştirilemez.'">
                    <BaseInput v-model="form.staff_code" :disabled="!isNew" autocomplete="off" />
                </FormField>
            </div>

            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <FormField label="Departman" :error="errors.department">
                    <BaseInput v-model="form.department" placeholder="Servis, Mutfak, Kasa…" autocomplete="off" />
                </FormField>
                <FormField label="Pozisyon" :error="errors.position">
                    <BaseInput v-model="form.position" placeholder="Garson, Şef…" autocomplete="off" />
                </FormField>
            </div>

            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <FormField label="İşe giriş tarihi" :error="errors.hired_at">
                    <BaseInput v-model="form.hired_at" type="date" />
                </FormField>
                <FormField label="Şube" :error="errors.branch_id">
                    <BaseSelect v-model="form.branch_id" :options="branchOptions" />
                </FormField>
            </div>

            <FormField v-if="isNew" label="Geçici parola" required :error="errors.password" hint="En az 10 karakter. Personel 'Parolamı unuttum' ile değiştirebilir.">
                <BaseInput v-model="form.password" type="password" autocomplete="new-password" />
            </FormField>

            <FormField label="Varsayılan açılış ekranı" :error="errors.default_screen" hint="Giriş sonrası düşeceği ekran. Otomatik: garson → sipariş, kasiyer → kasa, mutfak → KDS.">
                <BaseSelect v-model="form.default_screen" :options="screenOptions" />
            </FormField>

            <fieldset class="flex flex-col gap-1 rounded-lg border border-default p-3">
                <legend class="px-1 text-sm font-medium text-body">Roller</legend>
                <p v-if="errors.roles" class="text-xs text-danger">{{ errors.roles }}</p>
                <BaseSwitch
                    v-for="role in meta?.roles ?? []"
                    :key="role.id"
                    size="sm"
                    :model-value="form.roleIds.includes(role.id)"
                    :label="role.name"
                    :description="role.description ?? ''"
                    @update:model-value="toggleRole(role.id, $event)"
                />
            </fieldset>

            <BaseSwitch
                v-if="!isNew"
                v-model="form.is_active"
                label="Hesap aktif"
                description="Kapatınca personel giriş yapamaz; verileri KORUNUR."
            />

            <div class="mt-2 flex justify-end gap-2">
                <BaseButton variant="secondary" @click="emit('close')">Vazgeç</BaseButton>
                <BaseButton type="submit" :loading="saving">{{ isNew ? 'Personeli Oluştur' : 'Kaydet' }}</BaseButton>
            </div>
        </form>
    </BaseDrawer>
</template>
