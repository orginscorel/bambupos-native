<script setup lang="ts">
/**
 * AYARLAR › TEMA — kiracı panel teması: marka rengi + font + varsayılan mod.
 * Marka rengi tüm vurgu renklerini (--brand-* → --ui-primary/accent/link/focus)
 * sürer; semantik gri tonlar değişmez → kontrast korunur. Seçim CANLI uygulanır
 * (applyTenantTheme) → tüm panel anında değişir; Kaydet ile kalıcı olur.
 */
import { computed, onMounted, reactive, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import { applyTenantTheme, type TenantTheme } from '@/lib/theme';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import FormField from '@/Components/ui/FormField.vue';

const page = usePage();
const { success, danger } = useToast();

const settingsTabs = [
    { href: '/panel/ayarlar/e-posta', label: 'E-posta' },
    { href: '/panel/ayarlar/isletme', label: 'İşletme / Marka' },
    { href: '/panel/ayarlar/tema', label: 'Tema' },
    { href: '/panel/ayarlar/eklentiler', label: 'Eklentiler' },
];
const isActiveTab = (href: string): boolean => page.url.startsWith(href);

const FONT_LABELS: Record<string, string> = {
    poppins: 'Poppins (Varsayılan)',
    system: 'Sistem (hızlı, yerel)',
    serif: 'Klasik (Serif)',
    mono: 'Daktilo (Mono)',
    rounded: 'Yuvarlak',
};
const PRESETS = ['#2563eb', '#0ea5e9', '#059669', '#d97706', '#dc2626', '#7c3aed', '#db2777', '#0f766e', '#b45309', '#111827'];

const loading = ref(true);
const saving = ref(false);
const fonts = ref<string[]>(['poppins']);
const theme = reactive<{ primary: string; accent: string; font: string; mode: string }>({ primary: '#2563eb', accent: '', font: 'poppins', mode: 'system' });

const fontOptions = computed(() => fonts.value.map((f) => ({ value: f, label: FONT_LABELS[f] ?? f })));

/** Her değişimde CANLI uygula → tüm panel anında güncellenir. */
function live(): void {
    applyTenantTheme({ ...theme });
}

async function load(): Promise<void> {
    loading.value = true;
    try {
        const res = await api<{ branding: { theme?: TenantTheme; fonts?: string[] } }>('/api/v1/settings/branding');
        fonts.value = res.branding.fonts ?? ['poppins'];
        const t = res.branding.theme ?? {};
        theme.primary = t.primary || '#2563eb';
        theme.accent = t.accent || '';
        theme.font = t.font || 'poppins';
        theme.mode = t.mode || 'system';
        live();
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

async function save(): Promise<void> {
    if (saving.value) return;
    saving.value = true;
    try {
        await api('/api/v1/settings/branding/theme', {
            method: 'PUT',
            body: { primary: theme.primary, accent: theme.accent || null, font: theme.font, mode: theme.mode },
        });
        live();
        success('Tema kaydedildi', 'Panel yeni tema ile görünüyor.');
    } catch (e) {
        danger('Kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        saving.value = false;
    }
}

function resetDefault(): void {
    theme.primary = '#2563eb';
    theme.accent = '';
    theme.font = 'poppins';
    theme.mode = 'system';
    live();
}

function pickPreset(c: string): void {
    theme.primary = c;
    live();
}

onMounted(load);
</script>

<template>
    <Head title="Tema" />
    <PanelShell title="Ayarlar" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1080px] flex-col gap-3">

        <div class="mx-auto flex w-full max-w-3xl flex-col gap-5">
            <h1 class="text-2xl font-semibold text-body">Ayarlar</h1>
            <nav class="flex flex-wrap gap-1 border-b border-default">
                <a
                    v-for="tab in settingsTabs"
                    :key="tab.href"
                    :href="tab.href"
                    class="-mb-px inline-flex h-10 items-center gap-1.5 border-b-2 px-3 text-sm font-medium whitespace-nowrap transition-colors"
                    :class="isActiveTab(tab.href) ? 'border-primary text-primary' : 'border-transparent text-muted hover:border-strong hover:text-body'"
                >
                    {{ tab.label }}
                </a>
            </nav>

            <template v-if="loading">
                <BaseSkeleton size-class="h-40 w-full" />
            </template>

            <template v-else>
                <BaseCard title="Marka rengi">
                    <p class="mb-3 text-sm text-muted">
                        Butonlar, bağlantılar, seçili durumlar ve vurgular bu renge göre uyum sağlar. Metin/arka plan
                        okunabilirliği (kontrast) korunur.
                    </p>
                    <div class="flex flex-wrap items-center gap-2">
                        <button
                            v-for="c in PRESETS"
                            :key="c"
                            type="button"
                            class="size-8 rounded-full border-2 transition-transform hover:scale-110"
                            :style="{ backgroundColor: c, borderColor: theme.primary.toLowerCase() === c ? 'var(--ui-text)' : 'transparent' }"
                            :aria-label="c"
                            @click="pickPreset(c)"
                        />
                        <span class="mx-1 h-6 w-px bg-default"></span>
                        <input v-model="theme.primary" type="color" class="h-9 w-12 cursor-pointer rounded-md border border-strong bg-raised" aria-label="Özel renk" @input="live" />
                        <BaseInput v-model="theme.primary" size="sm" class="w-28" @update:model-value="live" />
                    </div>
                </BaseCard>

                <BaseCard title="Yazı tipi">
                    <FormField label="Panel fontu">
                        <BaseSelect v-model="theme.font" :options="fontOptions" @update:model-value="live" />
                    </FormField>
                    <p class="mt-2 text-xs text-muted">Ek dosya indirilmez; mevcut veya sistem fontları kullanılır (hızlı, güvenli).</p>
                </BaseCard>

                <BaseCard title="Varsayılan görünüm">
                    <FormField label="Açılış modu">
                        <BaseSelect
                            v-model="theme.mode"
                            :options="[
                                { value: 'system', label: 'Cihaza göre (otomatik)' },
                                { value: 'light', label: 'Açık' },
                                { value: 'dark', label: 'Koyu' },
                            ]"
                            @update:model-value="live"
                        />
                    </FormField>
                    <p class="mt-2 text-xs text-muted">Personel üst çubuktan açık/koyu geçişi yapabilir; bu yalnız varsayılanı belirler.</p>
                </BaseCard>

                <!-- Canlı önizleme -->
                <BaseCard title="Önizleme">
                    <div class="flex flex-col gap-3">
                        <div class="flex flex-wrap items-center gap-2">
                            <BaseButton>Birincil buton</BaseButton>
                            <BaseButton variant="secondary">İkincil</BaseButton>
                            <BaseButton variant="ghost">Hayalet</BaseButton>
                            <span class="rounded-full bg-primary-soft px-3 py-1 text-sm font-medium text-primary">Rozet</span>
                            <a class="text-sm font-medium text-primary underline" href="#" @click.prevent>Bağlantı</a>
                        </div>
                        <div class="rounded-lg border border-primary-soft bg-primary-soft p-3 text-sm text-body">
                            Seçili satır / yumuşak vurgu zemini bu renkten türetilir.
                        </div>
                    </div>
                </BaseCard>

                <div class="flex flex-wrap items-center justify-end gap-2">
                    <BaseButton variant="ghost" @click="resetDefault">
                        <AppIcon name="refresh-cw" :size="14" /> Varsayılana dön
                    </BaseButton>
                    <BaseButton :loading="saving" @click="save">
                        <AppIcon name="check" :size="14" /> Kaydet
                    </BaseButton>
                </div>
            </template>
        </div>
        </div>
        </div>
    </PanelShell>
</template>
