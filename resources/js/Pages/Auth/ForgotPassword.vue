<script setup lang="ts">
import { ref } from 'vue';
import { Head, Link } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import AuthLayout from '@/Layouts/AuthLayout.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import FormField from '@/Components/ui/FormField.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';

const email = ref('');
const loading = ref(false);
const sent = ref(false);
const error = ref('');
const alertMessage = ref('');

async function submit(): Promise<void> {
    if (loading.value) return;
    loading.value = true;
    error.value = '';
    alertMessage.value = '';

    try {
        await api('/api/v1/auth/forgot-password', {
            method: 'POST',
            body: { email: email.value.trim() },
        });
        sent.value = true;
    } catch (e) {
        if (e instanceof ApiError) {
            if (e.status === 429) alertMessage.value = e.displayMessage;
            else error.value = e.first('email') || e.displayMessage;
        } else {
            alertMessage.value = 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';
        }
    } finally {
        loading.value = false;
    }
}
</script>

<template>
    <Head title="Parola sıfırlama" />

    <AuthLayout
        heading="Parolanızı mı unuttunuz?"
        subheading="E-posta adresinizi girin; kayıtlıysa size bir sıfırlama bağlantısı gönderelim."
    >
        <div v-if="sent" class="flex flex-col items-center gap-3 py-2 text-center">
            <span class="flex size-11 items-center justify-center rounded-full bg-success-soft text-success">
                <AppIcon name="check-circle" :size="22" />
            </span>
            <p class="text-sm text-body">
                Eğer <strong>{{ email }}</strong> adresi kayıtlıysa, parola sıfırlama bağlantısı gönderildi.
                Gelen kutunuzu ve istenmeyen posta klasörünü kontrol edin.
            </p>
            <BaseButton href="/giris" variant="secondary" class="mt-1">Giriş ekranına dön</BaseButton>
        </div>

        <form v-else class="flex flex-col gap-4" novalidate @submit.prevent="submit">
            <div
                v-if="alertMessage"
                class="flex items-start gap-2.5 rounded-md border border-danger-border bg-danger-soft px-3 py-2.5 text-sm text-danger"
                role="alert"
            >
                <AppIcon name="alert-circle" :size="17" class="mt-0.5" />
                <p>{{ alertMessage }}</p>
            </div>

            <FormField label="E-posta adresi" :error="error" required>
                <BaseInput
                    v-model="email"
                    type="email"
                    inputmode="email"
                    autocomplete="username"
                    placeholder="ornek@isletme.com"
                />
            </FormField>

            <BaseButton type="submit" block :loading="loading">Sıfırlama bağlantısı gönder</BaseButton>
        </form>

        <template #footer>
            <Link href="/giris" class="font-medium text-link hover:underline">← Giriş ekranına dön</Link>
        </template>
    </AuthLayout>
</template>
