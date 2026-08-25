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

/* ---- Mevcut PIN'i görüntüleme (yönetici) ---- */
const revealedPin = ref<string | null>(null);
const revealed = ref(false);
const revealing = ref(false);
const revealMsg = ref('');

watch(
    () => props.open,
    () => {
        pin.value = '';
        error.value = '';
        revealedPin.value = null;
        revealed.value = false;
        revealMsg.value = '';
    },
);

async function revealPin(): Promise<void> {
    if (!props.staff || revealing.value) return;
    revealing.value = true;
    revealMsg.value = '';
    try {
        const res = await api<{ pin: string | null }>(`/api/v1/staff-access/${props.staff.id}/pin`);
        revealedPin.value = res.pin;
        revealed.value = true;
        if (res.pin === null) {
            revealMsg.value = 'Bu PIN eski kayıt olduğu için görüntülenemiyor. Aşağıdan yeni bir PIN atayın.';
        }
    } catch (e) {
        revealMsg.value = e instanceof ApiError ? e.displayMessage : 'PIN görüntülenemedi.';
    } finally {
        revealing.value = false;
    }
}

async function copyPin(): Promise<void> {
    if (!revealedPin.value) return;
    try {
        await navigator.clipboard.writeText(revealedPin.value);
        success('Kopyalandı', 'PIN panoya kopyalandı.');
    } catch {
        /* pano izni yok — kullanıcı elle okur */
    }
}

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
            <!-- Mevcut PIN'i görüntüle (yönetici) -->
            <div v-if="staff?.has_pin" class="rounded-lg border border-default bg-inset/60 p-3">
                <div class="flex items-center justify-between gap-2">
                    <span class="text-sm font-medium text-body">Mevcut PIN</span>
                    <BaseButton v-if="!revealed" size="sm" variant="secondary" :loading="revealing" @click="revealPin">
                        Göster
                    </BaseButton>
                </div>
                <div v-if="revealed && revealedPin" class="mt-2 flex items-center gap-2">
                    <code class="rounded bg-raised px-3 py-1.5 text-lg font-bold tracking-widest tabular-nums text-body">{{ revealedPin }}</code>
                    <BaseButton size="sm" variant="ghost" @click="copyPin">Kopyala</BaseButton>
                </div>
                <p v-if="revealMsg" class="mt-1.5 text-xs text-warning">{{ revealMsg }}</p>
                <p v-else-if="!revealed" class="mt-1 text-xs text-subtle">Görüntüleme denetim kaydına düşer.</p>
            </div>

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
