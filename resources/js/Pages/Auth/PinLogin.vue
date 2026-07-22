<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head, Link } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import AuthLayout from '@/Layouts/AuthLayout.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import FormField from '@/Components/ui/FormField.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';

const MIN = 6;
const MAX = 10;
const STORAGE_KEY = 'pin-login-ctx';

const tenant = ref('');
const staffCode = ref('');
const pin = ref('');

const loading = ref(false);
const locked = ref(false);
const alertMessage = ref('');
const fieldErrors = ref<{ tenant?: string; staff_code?: string; pin?: string }>({});

onMounted(() => {
    try {
        const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '{}') as {
            tenant?: string;
            staff_code?: string;
        };
        tenant.value = saved.tenant ?? '';
        staffCode.value = saved.staff_code ?? '';
    } catch {
        /* yoksay */
    }
});

const canSubmit = computed(
    () => pin.value.length >= MIN && tenant.value.trim() !== '' && staffCode.value.trim() !== '',
);

function press(digit: string): void {
    if (loading.value || pin.value.length >= MAX) return;
    pin.value += digit;
}

function backspace(): void {
    if (loading.value) return;
    pin.value = pin.value.slice(0, -1);
}

function clearPin(): void {
    if (loading.value) return;
    pin.value = '';
}

/** Fiziksel klavye desteği: rakamlar, Backspace, Enter. */
function onKeydown(e: KeyboardEvent): void {
    if (/^[0-9]$/.test(e.key)) press(e.key);
    else if (e.key === 'Backspace') backspace();
    else if (e.key === 'Enter' && canSubmit.value) void submit();
}

async function submit(): Promise<void> {
    if (loading.value || !canSubmit.value) return;
    loading.value = true;
    locked.value = false;
    alertMessage.value = '';
    fieldErrors.value = {};

    try {
        const result = await api<{ redirect_to?: string }>('/api/v1/auth/pin-login', {
            method: 'POST',
            body: { tenant: tenant.value.trim().toLowerCase(), staff_code: staffCode.value.trim(), pin: pin.value },
        });

        try {
            localStorage.setItem(
                STORAGE_KEY,
                JSON.stringify({ tenant: tenant.value.trim().toLowerCase(), staff_code: staffCode.value.trim() }),
            );
        } catch {
            /* gizli mod */
        }

        // Role özel açılış ekranı (garson → sipariş, mutfak → KDS…)
        window.location.href = result.redirect_to || '/panel';
    } catch (e) {
        loading.value = false;
        pin.value = '';
        if (e instanceof ApiError) {
            if (e.status === 429) {
                locked.value = true;
                alertMessage.value = e.first('pin') || e.displayMessage;
            } else {
                fieldErrors.value = {
                    tenant: e.first('tenant'),
                    staff_code: e.first('staff_code'),
                    pin: e.first('pin'),
                };
                if (!e.first('tenant') && !e.first('staff_code') && !e.first('pin')) {
                    alertMessage.value = e.displayMessage;
                }
            }
        } else {
            alertMessage.value = 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';
        }
    }
}
</script>

<template>
    <Head title="PIN ile giriş" />

    <AuthLayout
        heading="PIN ile hızlı giriş"
        subheading="Personel girişi: işletme kodu, personel kodu ve 6-10 haneli PIN."
        wide
    >
        <div class="flex flex-col gap-4" @keydown="onKeydown">
            <div
                v-if="alertMessage"
                class="flex items-start gap-2.5 rounded-md border border-danger-border bg-danger-soft px-3 py-2.5 text-sm text-danger"
                role="alert"
            >
                <AppIcon :name="locked ? 'alert-triangle' : 'alert-circle'" :size="17" class="mt-0.5" />
                <div>
                    <p v-if="locked" class="font-semibold">PIN girişi geçici olarak kilitli</p>
                    <p>{{ alertMessage }}</p>
                </div>
            </div>

            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <FormField label="İşletme kodu" :error="fieldErrors.tenant" required>
                    <BaseInput v-model="tenant" autocomplete="organization" placeholder="ör. demo" />
                </FormField>
                <FormField label="Personel kodu" :error="fieldErrors.staff_code" required>
                    <BaseInput v-model="staffCode" autocomplete="username" placeholder="ör. SAHIP01" />
                </FormField>
            </div>

            <!-- PIN göstergesi -->
            <div class="flex flex-col items-center gap-1.5">
                <span class="text-sm font-medium text-body">PIN</span>
                <div
                    class="flex h-11 min-w-52 items-center justify-center gap-2 rounded-md border bg-inset px-4"
                    :class="fieldErrors.pin ? 'border-danger' : 'border-default'"
                    role="status"
                    :aria-label="`PIN: ${pin.length} hane girildi`"
                >
                    <template v-if="pin.length > 0">
                        <span
                            v-for="n in pin.length"
                            :key="n"
                            class="size-2.5 rounded-full bg-body"
                            aria-hidden="true"
                        />
                    </template>
                    <span v-else class="text-sm text-subtle">6-10 hane</span>
                </div>
                <p v-if="fieldErrors.pin" class="flex items-center gap-1 text-xs font-medium text-danger">
                    <AppIcon name="alert-circle" :size="14" />
                    {{ fieldErrors.pin }}
                </p>
            </div>

            <!-- Dokunmatik tuş takımı -->
            <div class="mx-auto grid w-full max-w-72 grid-cols-3 gap-2" role="group" aria-label="PIN tuş takımı">
                <button
                    v-for="digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9']"
                    :key="digit"
                    type="button"
                    class="h-14 rounded-md border border-default bg-raised text-xl font-semibold text-body transition-colors duration-(--dur-fast) select-none hover:bg-inset active:bg-primary-soft disabled:cursor-not-allowed disabled:opacity-55"
                    :disabled="loading || locked"
                    @click="press(digit)"
                >
                    {{ digit }}
                </button>
                <button
                    type="button"
                    class="h-14 rounded-md border border-default bg-raised text-sm font-medium text-muted transition-colors duration-(--dur-fast) select-none hover:bg-inset disabled:cursor-not-allowed disabled:opacity-55"
                    :disabled="loading || locked || pin.length === 0"
                    @click="clearPin"
                >
                    Temizle
                </button>
                <button
                    type="button"
                    class="h-14 rounded-md border border-default bg-raised text-xl font-semibold text-body transition-colors duration-(--dur-fast) select-none hover:bg-inset active:bg-primary-soft disabled:cursor-not-allowed disabled:opacity-55"
                    :disabled="loading || locked"
                    @click="press('0')"
                >
                    0
                </button>
                <button
                    type="button"
                    class="flex h-14 items-center justify-center rounded-md border border-default bg-raised text-muted transition-colors duration-(--dur-fast) select-none hover:bg-inset disabled:cursor-not-allowed disabled:opacity-55"
                    aria-label="Son haneyi sil"
                    :disabled="loading || locked || pin.length === 0"
                    @click="backspace"
                >
                    <AppIcon name="arrow-left" :size="20" />
                </button>
            </div>

            <BaseButton block size="lg" :loading="loading" :disabled="!canSubmit || locked" @click="submit">
                Giriş yap
            </BaseButton>
        </div>

        <template #footer>
            <Link href="/giris" class="font-medium text-link hover:underline">← E-posta ve parola ile giriş</Link>
        </template>
    </AuthLayout>
</template>
