<script setup lang="ts">
import { ref } from 'vue';
import { Head, Link } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import AuthLayout from '@/Layouts/AuthLayout.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import FormField from '@/Components/ui/FormField.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';

const props = defineProps<{
    token: string;
    email: string;
}>();

const email = ref(props.email);
const password = ref('');
const passwordConfirmation = ref('');
const loading = ref(false);
const done = ref(false);
const errors = ref<{ email?: string; password?: string }>({});
const alertMessage = ref('');

async function submit(): Promise<void> {
    if (loading.value) return;
    loading.value = true;
    errors.value = {};
    alertMessage.value = '';

    try {
        await api('/api/v1/auth/reset-password', {
            method: 'POST',
            body: {
                token: props.token,
                email: email.value.trim(),
                password: password.value,
                password_confirmation: passwordConfirmation.value,
            },
        });
        done.value = true;
    } catch (e) {
        if (e instanceof ApiError) {
            errors.value = { email: e.first('email'), password: e.first('password') };
            if (!e.first('email') && !e.first('password')) alertMessage.value = e.displayMessage;
        } else {
            alertMessage.value = 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';
        }
    } finally {
        loading.value = false;
    }
}
</script>

<template>
    <Head title="Yeni parola belirle" />

    <AuthLayout heading="Yeni parola belirleyin" subheading="Hesabınız için en az 10 karakterlik yeni bir parola seçin.">
        <div v-if="done" class="flex flex-col items-center gap-3 py-2 text-center">
            <span class="flex size-11 items-center justify-center rounded-full bg-success-soft text-success">
                <AppIcon name="check-circle" :size="22" />
            </span>
            <p class="text-sm text-body">Parolanız güncellendi. Artık yeni parolanızla giriş yapabilirsiniz.</p>
            <BaseButton href="/giris" class="mt-1">Giriş yap</BaseButton>
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

            <FormField label="E-posta adresi" :error="errors.email" required>
                <BaseInput v-model="email" type="email" autocomplete="username" />
            </FormField>

            <FormField label="Yeni parola" :error="errors.password" hint="En az 10 karakter" required>
                <BaseInput v-model="password" type="password" autocomplete="new-password" placeholder="••••••••••" />
            </FormField>

            <FormField label="Yeni parola (tekrar)" required>
                <BaseInput
                    v-model="passwordConfirmation"
                    type="password"
                    autocomplete="new-password"
                    placeholder="••••••••••"
                />
            </FormField>

            <BaseButton type="submit" block :loading="loading">Parolayı güncelle</BaseButton>
        </form>

        <template #footer>
            <Link href="/giris" class="font-medium text-link hover:underline">← Giriş ekranına dön</Link>
        </template>
    </AuthLayout>
</template>
