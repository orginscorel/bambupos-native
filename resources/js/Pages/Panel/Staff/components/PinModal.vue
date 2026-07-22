<script setup lang="ts">
import { ref, watch } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import FormField from '@/Components/ui/FormField.vue';
import type { StaffRow } from '../types';

/** Yönetici eliyle PIN belirleme / kaldırma (personel kodu + PIN girişi için). */
const props = defineProps<{ open: boolean; staff: StaffRow | null }>();

const emit = defineEmits<{ close: []; saved: [] }>();

const { success, danger } = useToast();

const pin = ref('');
const error = ref('');
const busy = ref(false);

watch(
    () => props.open,
    () => {
        pin.value = '';
        error.value = '';
    },
);

async function save(): Promise<void> {
    if (!props.staff || busy.value) return;
    busy.value = true;
    error.value = '';
    try {
        await api(`/api/v1/staff-access/${props.staff.id}/pin`, { method: 'POST', body: { pin: pin.value } });
        success('PIN belirlendi', `${props.staff.name} artık personel koduyla PIN girişi yapabilir.`);
        emit('saved');
        emit('close');
    } catch (e) {
        error.value = e instanceof ApiError ? e.displayMessage : 'PIN belirlenemedi.';
    } finally {
        busy.value = false;
    }
}

async function clearPin(): Promise<void> {
    if (!props.staff || busy.value) return;
    busy.value = true;
    try {
        await api(`/api/v1/staff-access/${props.staff.id}/pin`, { method: 'DELETE' });
        success('PIN kaldırıldı', 'Personel PIN ile giriş yapamaz; e-posta + parola geçerli.');
        emit('saved');
        emit('close');
    } catch (e) {
        danger('PIN kaldırılamadı', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        busy.value = false;
    }
}
</script>

<template>
    <BaseModal :open="open" :title="staff ? `PIN — ${staff.name}` : 'PIN'" size="sm" @close="emit('close')">
        <form class="flex flex-col gap-4" @submit.prevent="save">
            <FormField
                label="Yeni PIN"
                :error="error"
                hint="6-10 hane, yalnız rakam. 111111 gibi tek-tip ve 123456 gibi ardışık diziler kabul edilmez."
            >
                <BaseInput v-model="pin" type="password" inputmode="numeric" autocomplete="off" placeholder="••••••" />
            </FormField>

            <div class="flex flex-wrap items-center justify-between gap-2">
                <BaseButton
                    v-if="staff?.has_pin"
                    variant="danger"
                    size="sm"
                    :disabled="busy"
                    @click="clearPin"
                >
                    PIN'i kaldır
                </BaseButton>
                <span v-else />
                <span class="flex gap-2">
                    <BaseButton variant="secondary" @click="emit('close')">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="busy">PIN Belirle</BaseButton>
                </span>
            </div>
        </form>
    </BaseModal>
</template>
