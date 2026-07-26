<script setup lang="ts">
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import FormField from '@/Components/ui/FormField.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import { useTerminalPinDialog } from '@/composables/useTerminalPin';

/**
 * §13 Faz B — Terminal PIN modalı. Kasa / sipariş-giriş terminalinde hassas
 * para eylemi yapılırken personel PIN'ini toplar (işlem PIN sahibine
 * kaydedilir). Sayfa bunu BİR kez render eder; durum useTerminalPin
 * composable'ında tekildir, `collectPin()` bu modalı açar.
 */
const { open, pin, staffCode, showStaffCode, submit, cancel } = useTerminalPinDialog();
</script>

<template>
    <BaseModal :open="open" title="Personel PIN" size="sm" @close="cancel">
        <div class="flex items-start gap-3 pb-3">
            <span class="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
                <AppIcon name="user" :size="18" />
            </span>
            <p class="text-sm text-muted">
                Bu işlem için personel PIN'i gerekli. İşlem, PIN'i giren personele kaydedilir.
            </p>
        </div>

        <FormField label="PIN" required>
            <BaseInput
                v-model="pin"
                type="password"
                inputmode="numeric"
                autocomplete="off"
                placeholder="••••••"
                @keydown.enter="submit"
            />
        </FormField>

        <FormField v-if="showStaffCode" label="Personel kodu" hint="Aynı PIN birden fazla personelde eşleşirse kodunuzu girin.">
            <BaseInput v-model="staffCode" autocomplete="off" placeholder="ör. G12" @keydown.enter="submit" />
        </FormField>

        <template #footer>
            <BaseButton variant="secondary" @click="cancel">Vazgeç</BaseButton>
            <BaseButton variant="primary" :disabled="!pin" @click="submit">Onayla</BaseButton>
        </template>
    </BaseModal>
</template>
