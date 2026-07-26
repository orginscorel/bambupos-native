<script setup lang="ts">
import { computed, ref, onMounted } from 'vue';
import { Head, Link, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';

/*
 * Panel > Ayarlar > İşletme / Marka
 * Tek görevi var: kiracının public menü başlığında görünen logosunu
 * yükle / kaldır. Gerçek doğrulama (MIME + getimagesize + boyut) sunucuda
 * TenantLogoService'te — burası yalnız kullanıcı deneyimi.
 */

interface BrandingDto {
    name: string;
    logo_url: string | null;
}

const { success, danger } = useToast();

/** Ayarlar alt sekmeleri (E-posta / İşletme-Marka). navigation.ts'te tek
 *  "Ayarlar" girişi var (/panel/ayarlar/e-posta); bu sayfaya buradan geçilir. */
const page = usePage();
const settingsTabs = [
    { href: '/panel/ayarlar/e-posta', label: 'E-posta' },
    { href: '/panel/ayarlar/isletme', label: 'İşletme / Marka' },
    { href: '/panel/ayarlar/eklentiler', label: 'Eklentiler' },
];
const isActiveTab = (href: string) => page.url.startsWith(href);

const loading = ref(true);
const loadFailed = ref(false);
const branding = ref<BrandingDto | null>(null);
const uploading = ref(false);
const removing = ref(false);
const removeModalOpen = ref(false);
const fileInput = ref<HTMLInputElement | null>(null);

const initial = computed(() => (branding.value?.name?.trim()?.charAt(0) ?? '?').toUpperCase());

async function load(): Promise<void> {
    loading.value = true;
    loadFailed.value = false;
    try {
        const data = await api<{ branding: BrandingDto }>('/api/v1/settings/branding');
        branding.value = data.branding;
    } catch (e) {
        loadFailed.value = true;
        danger('Ayarlar yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

function xsrfToken(): string {
    const match = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]+)/);
    return match ? decodeURIComponent(match[1]) : '';
}

async function uploadLogo(e: Event): Promise<void> {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file || uploading.value) return;
    uploading.value = true;

    try {
        const data = new FormData();
        data.append('logo', file);
        const response = await fetch('/api/v1/settings/branding/logo', {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
                Accept: 'application/json',
                'X-Requested-With': 'XMLHttpRequest',
                'X-XSRF-TOKEN': xsrfToken(),
            },
            body: data,
        });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) {
            const message =
                (payload as { errors?: Record<string, string[]>; message?: string }).errors?.logo?.[0] ??
                (payload as { message?: string }).message ??
                'Logo yüklenemedi.';
            throw new Error(message);
        }
        branding.value = (payload as { branding: BrandingDto }).branding;
        success('Logo yüklendi', 'Public menü başlığı güncellendi.');
    } catch (e2) {
        danger('Logo yüklenemedi', e2 instanceof Error ? e2.message : 'Lütfen tekrar deneyin.');
    } finally {
        uploading.value = false;
        input.value = '';
    }
}

async function removeLogo(): Promise<void> {
    if (removing.value) return;
    removing.value = true;
    try {
        const data = await api<{ branding: BrandingDto }>('/api/v1/settings/branding/logo', { method: 'DELETE' });
        branding.value = data.branding;
        removeModalOpen.value = false;
        success('Logo kaldırıldı', 'Menü başlığında artık işletme adının baş harfi gösterilecek.');
    } catch (e) {
        danger('Kaldırılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        removing.value = false;
    }
}
</script>

<template>
    <Head title="İşletme / Marka" />

    <PanelShell title="İşletme / Marka">
        <div class="mx-auto flex w-full max-w-5xl flex-col gap-6">
            <div class="flex flex-col gap-1.5">
                <h1 class="text-2xl font-semibold text-body">Ayarlar</h1>
                <p class="max-w-2xl text-[15px] leading-relaxed text-muted">
                    İşletmenizin markası — müşterilerin QR ile açtığı public menüde görünen kimliği.
                </p>
            </div>

            <div class="flex gap-1 overflow-x-auto border-b border-default">
                <Link
                    v-for="tab in settingsTabs"
                    :key="tab.href"
                    :href="tab.href"
                    class="-mb-px inline-flex h-10 items-center gap-1.5 border-b-2 px-3 text-sm font-medium whitespace-nowrap transition-colors duration-(--dur-fast)"
                    :class="isActiveTab(tab.href) ? 'border-primary text-primary' : 'border-transparent text-muted hover:border-strong hover:text-body'"
                >
                    {{ tab.label }}
                </Link>
            </div>

            <template v-if="loading">
                <BaseCard><BaseSkeleton class="h-40" /></BaseCard>
            </template>

            <template v-else-if="!loadFailed && branding">
                <section class="grid grid-cols-1 gap-x-12 gap-y-4 py-2 md:grid-cols-[260px_1fr]">
                    <div class="flex flex-col gap-1.5">
                        <h2 class="text-base font-semibold text-body">Logo</h2>
                        <p class="text-sm leading-relaxed text-muted">
                            Bu logo, müşterilerin QR kod ile açtığı public menünün üst başlığında gösterilir.
                            Logo tanımlı değilse yerine işletme adının baş harfiyle markalı bir daire gösterilir —
                            menü hiçbir zaman "bozuk" görünmez.
                        </p>
                    </div>
                    <div class="min-w-0">
                        <BaseCard>
                            <div class="flex flex-col gap-6 sm:flex-row sm:items-center">
                                <div
                                    class="flex h-24 w-24 shrink-0 items-center justify-center overflow-hidden rounded-full border border-default bg-primary text-3xl font-bold text-on-primary"
                                >
                                    <img v-if="branding.logo_url" :src="branding.logo_url" alt="" class="h-full w-full object-cover" />
                                    <span v-else>{{ initial }}</span>
                                </div>

                                <div class="flex flex-col gap-3">
                                    <div class="flex flex-wrap gap-2">
                                        <input
                                            ref="fileInput"
                                            type="file"
                                            accept=".jpg,.jpeg,.png,.webp"
                                            class="hidden"
                                            @change="uploadLogo"
                                        />
                                        <BaseButton variant="secondary" :loading="uploading" @click="fileInput?.click()">
                                            <AppIcon name="plus" :size="16" />
                                            {{ branding.logo_url ? 'Logoyu değiştir' : 'Logo yükle' }}
                                        </BaseButton>
                                        <BaseButton v-if="branding.logo_url" variant="ghost" @click="removeModalOpen = true">
                                            <AppIcon name="trash" :size="16" />
                                            Kaldır
                                        </BaseButton>
                                    </div>
                                    <p class="text-xs text-muted">JPG, PNG veya WebP · en fazla 2 MB · kare görsel önerilir</p>
                                </div>
                            </div>
                        </BaseCard>
                    </div>
                </section>
            </template>

            <BaseModal :open="removeModalOpen" title="Logo kaldırılsın mı?" @close="removeModalOpen = false">
                <p class="text-sm text-muted">
                    Logo silinecek; public menü başlığında bundan sonra işletme adının baş harfi gösterilecek.
                </p>
                <div class="mt-5 flex justify-end gap-3">
                    <BaseButton variant="ghost" @click="removeModalOpen = false">Vazgeç</BaseButton>
                    <BaseButton variant="danger" :loading="removing" @click="removeLogo">Kaldır</BaseButton>
                </div>
            </BaseModal>
        </div>
    </PanelShell>
</template>
