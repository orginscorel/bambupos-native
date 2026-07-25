<script setup lang="ts">
import { computed, ref } from 'vue';
import { Head, Link } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import AuthLayout from '@/Layouts/AuthLayout.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCheckbox from '@/Components/ui/BaseCheckbox.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import FormField from '@/Components/ui/FormField.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';

type Step = 'credentials' | 'two-factor';

const step = ref<Step>('credentials');
const email = ref('');
const password = ref('');
const remember = ref(false);
const code = ref('');

const loading = ref(false);
const fieldErrors = ref<{ email?: string; password?: string; code?: string }>({});
/** Alan-üstü uyarı: kilit (429) ve genel hatalar burada gösterilir. */
const alertMessage = ref('');
const locked = ref(false);

const showPassword = ref(false);
const passwordFieldType = computed(() => (showPassword.value ? 'text' : 'password'));

async function submitCredentials(): Promise<void> {
    if (loading.value) return;
    loading.value = true;
    fieldErrors.value = {};
    alertMessage.value = '';
    locked.value = false;

    try {
        const result = await api<{ two_factor: boolean }>('/api/v1/auth/login', {
            method: 'POST',
            body: { email: email.value.trim(), password: password.value, remember: remember.value },
        });

        if (result.two_factor) {
            step.value = 'two-factor';
            loading.value = false;
            return;
        }

        // Oturum kuruldu: paylaşılan prop'ların tazelenmesi için tam yükleme.
        window.location.href = '/panel';
    } catch (e) {
        loading.value = false;
        if (e instanceof ApiError) {
            if (e.status === 429) {
                locked.value = true;
                alertMessage.value =
                    e.displayMessage ||
                    'Çok fazla hatalı deneme yapıldı. Hesap girişi geçici olarak kilitlendi, lütfen biraz sonra tekrar deneyin.';
            } else if (e.status === 422 || e.status === 403) {
                fieldErrors.value = { email: e.first('email'), password: e.first('password') };
                if (!e.first('email') && !e.first('password')) alertMessage.value = e.displayMessage;
            } else {
                alertMessage.value = e.displayMessage;
            }
        } else {
            alertMessage.value = 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';
        }
    }
}

async function submitTwoFactor(): Promise<void> {
    if (loading.value) return;
    loading.value = true;
    fieldErrors.value = {};
    alertMessage.value = '';

    try {
        await api('/api/v1/auth/two-factor-challenge', {
            method: 'POST',
            body: { code: code.value.trim() },
        });
        window.location.href = '/panel';
    } catch (e) {
        loading.value = false;
        if (e instanceof ApiError) {
            if (e.status === 429) alertMessage.value = e.displayMessage;
            else fieldErrors.value = { code: e.first('code') || e.displayMessage };
        } else {
            alertMessage.value = 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';
        }
    }
}
</script>

<template>
    <Head title="Giriş" />

    <AuthLayout
        :heading="step === 'credentials' ? 'Panele giriş yapın' : 'İki adımlı doğrulama'"
        :subheading="
            step === 'credentials'
                ? 'İşletme yönetim paneline erişmek için hesabınızla oturum açın.'
                : 'Doğrulama uygulamanızdaki 6 haneli kodu ya da kurtarma kodunuzu girin.'
        "
    >
        <!-- Kilit / genel hata uyarısı -->
        <div
            v-if="alertMessage"
            class="mb-4 flex items-start gap-2.5 rounded-md border border-danger-border bg-danger-soft px-3 py-2.5 text-sm text-danger"
            role="alert"
        >
            <AppIcon :name="locked ? 'alert-triangle' : 'alert-circle'" :size="17" class="mt-0.5" />
            <div>
                <p v-if="locked" class="font-semibold">Giriş geçici olarak kilitlendi</p>
                <p>{{ alertMessage }}</p>
            </div>
        </div>

        <form v-if="step === 'credentials'" class="flex flex-col gap-4" novalidate @submit.prevent="submitCredentials">
            <FormField label="E-posta adresi" :error="fieldErrors.email" required>
                <BaseInput
                    v-model="email"
                    type="email"
                    inputmode="email"
                    autocomplete="username"
                    placeholder="ornek@isletme.com"
                />
            </FormField>

            <FormField label="Parola" :error="fieldErrors.password" required>
                <div class="relative">
                    <BaseInput
                        v-model="password"
                        :type="passwordFieldType"
                        autocomplete="current-password"
                        placeholder="••••••••••"
                        class="pr-16"
                    />
                    <button
                        type="button"
                        class="absolute inset-y-0 right-0 flex w-14 items-center justify-center rounded-r-md text-subtle transition-colors duration-(--dur-fast) hover:text-body"
                        :aria-label="showPassword ? 'Parolayı gizle' : 'Parolayı göster'"
                        :aria-pressed="showPassword"
                        @click="showPassword = !showPassword"
                    >
                        <span class="text-xs font-medium select-none">{{ showPassword ? 'Gizle' : 'Göster' }}</span>
                    </button>
                </div>
            </FormField>

            <div class="flex items-center justify-between gap-2">
                <BaseCheckbox v-model="remember" label="Beni hatırla" />
                <Link href="/parola-sifirla" class="text-sm font-medium text-link hover:underline">
                    Parolamı unuttum
                </Link>
            </div>

            <BaseButton type="submit" block :loading="loading">Giriş yap</BaseButton>
        </form>

        <form v-else class="flex flex-col gap-4" novalidate @submit.prevent="submitTwoFactor">
            <FormField
                label="Doğrulama kodu"
                :error="fieldErrors.code"
                hint="6 haneli uygulama kodu ya da XXXXX-XXXXX biçiminde kurtarma kodu"
                required
            >
                <BaseInput v-model="code" inputmode="numeric" autocomplete="one-time-code" placeholder="000000" />
            </FormField>

            <BaseButton type="submit" block :loading="loading">Doğrula ve giriş yap</BaseButton>

            <button
                type="button"
                class="text-sm font-medium text-muted hover:text-body"
                @click="
                    step = 'credentials';
                    code = '';
                    fieldErrors = {};
                    alertMessage = '';
                "
            >
                ← Farklı bir hesapla giriş yap
            </button>
        </form>

        <template #footer>
            <p>
                Personel misiniz?
                <Link href="/giris/pin" class="font-medium text-link hover:underline">PIN ile hızlı giriş</Link>
            </p>
        </template>
    </AuthLayout>
</template>
