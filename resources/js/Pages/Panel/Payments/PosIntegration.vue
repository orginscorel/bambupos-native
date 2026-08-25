<script setup lang="ts">
/**
 * POS / YAZARKASA ENTEGRATÖR KURULUM SİHİRBAZI.
 *
 * İşletme kendi ödeme cihazını (YN-POS/ÖKC), banka sanal POS'unu ya da ödeme
 * kuruluşunu buradan seçip yapılandırır. Sağlayıcıdan bağımsız TEK arayüz:
 * marka (preset) seçilir → alanlar katalogtan üretilir → adres+kimlik girilir →
 * "Terminali test et". Sırlar maskeli (••••) döner; yeniden kaydetmede korunur.
 * API: GET/PUT /api/v1/payments/pos-integration + POST .../test.
 */
import { computed, onMounted, reactive, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';

interface Field { key: string; label: string; type: string; required: boolean }
interface Preset { key: string; label: string; category: string; verified: boolean; doc_url: string; provider: string }

const { success, danger } = useToast();

const loading = ref(true);
const saving = ref(false);
const testing = ref(false);
const enabled = ref(false);
const preset = ref('');
const catalog = ref<Record<string, { fields: Field[] }>>({});
const presets = ref<Preset[]>([]);
const categories = ref<Record<string, string>>({});
const config = reactive<Record<string, unknown>>({});
const testResult = ref<{ online: boolean; message: string } | null>(null);

/* Nokta-yollu get/set ("auth.secret" → config.auth.secret) */
function getPath(obj: Record<string, unknown>, path: string): unknown {
    return path.split('.').reduce<unknown>((o, k) => (o && typeof o === 'object' ? (o as Record<string, unknown>)[k] : undefined), obj);
}
function setPath(obj: Record<string, unknown>, path: string, value: unknown): void {
    const keys = path.split('.');
    let cur = obj;
    keys.slice(0, -1).forEach((k) => {
        if (typeof cur[k] !== 'object' || cur[k] === null) cur[k] = {};
        cur = cur[k] as Record<string, unknown>;
    });
    cur[keys[keys.length - 1]] = value;
}

const groupedPresets = computed(() => {
    const groups: Record<string, Preset[]> = {};
    for (const p of presets.value) (groups[p.category] ??= []).push(p);
    return groups;
});

const currentPreset = computed(() => presets.value.find((p) => p.key === preset.value) ?? null);

/* Seçili markanın adaptörü (generic_rest = JSON PSP/TSM; generic_soap = banka XML).
   Alanlar o adaptörün katalog tanımından üretilir (banka → kullanıcı/şifre). */
const activeProvider = computed(() => currentPreset.value?.provider ?? 'generic_rest');
const fields = computed<Field[]>(() => catalog.value[activeProvider.value]?.fields ?? catalog.value.generic_rest?.fields ?? []);

async function load(): Promise<void> {
    loading.value = true;
    try {
        const res = await api<{
            catalog: Record<string, { fields: Field[] }>;
            presets: Preset[];
            categories: Record<string, string>;
            enabled: boolean;
            config: Record<string, unknown>;
        }>('/api/v1/payments/pos-integration');

        catalog.value = res.catalog;
        presets.value = res.presets;
        categories.value = res.categories;
        enabled.value = res.enabled;
        Object.keys(config).forEach((k) => delete config[k]);
        Object.assign(config, res.config ?? {});
        preset.value = (config.preset as string) ?? '';
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

function onPresetChange(): void {
    setPath(config, 'preset', preset.value);
    testResult.value = null;
}

async function save(): Promise<void> {
    if (saving.value) return;
    saving.value = true;
    try {
        setPath(config, 'preset', preset.value);
        const res = await api<{ config: Record<string, unknown> }>('/api/v1/payments/pos-integration', {
            method: 'PUT',
            body: { enabled: enabled.value, provider: activeProvider.value, config },
        });
        Object.keys(config).forEach((k) => delete config[k]);
        Object.assign(config, res.config ?? {});
        success('Kaydedildi', 'POS yapılandırması güncellendi.');
    } catch (e) {
        danger('Kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        saving.value = false;
    }
}

async function test(): Promise<void> {
    if (testing.value) return;
    testing.value = true;
    testResult.value = null;
    try {
        const res = await api<{ online: boolean; message: string }>('/api/v1/payments/pos-integration/test', {
            method: 'POST',
            body: { terminal_id: getPath(config, 'defaults.terminal_id') ?? '' },
        });
        testResult.value = res;
    } catch (e) {
        danger('Test başarısız', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        testing.value = false;
    }
}

onMounted(load);
</script>

<template>
    <Head title="POS / Yazarkasa Entegrasyonu" />
    <PanelShell flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1080px] flex-col gap-3">

        <div class="mx-auto flex max-w-3xl flex-col gap-5 p-4 sm:p-6">
            <header class="flex flex-col gap-1">
                <h1 class="text-xl font-semibold text-body">POS / Yazarkasa Entegrasyonu</h1>
                <p class="text-sm text-muted">
                    Ödeme cihazınızı (YN-POS/ÖKC), banka sanal POS'unuzu ya da ödeme kuruluşunuzu seçip bağlayın.
                    Marka fark etmez — hepsi tek çatıdan yönetilir.
                </p>
            </header>

            <template v-if="loading">
                <BaseSkeleton class="h-40" />
                <BaseSkeleton class="h-64" />
            </template>

            <template v-else>
                <!-- Aç/kapat -->
                <BaseCard>
                    <div class="flex items-center justify-between gap-4">
                        <div>
                            <p class="font-medium text-body">Entegrasyonu etkinleştir</p>
                            <p class="text-sm text-muted">Kapalıyken kartlı ödemeler varsayılan yönteme düşer.</p>
                        </div>
                        <BaseSwitch v-model="enabled" />
                    </div>
                </BaseCard>

                <!-- Marka / sağlayıcı seçimi -->
                <BaseCard>
                    <div class="flex flex-col gap-3">
                        <label class="text-sm font-medium text-body">Cihaz / Sağlayıcı</label>
                        <select
                            v-model="preset"
                            class="w-full rounded-lg border border-default bg-surface px-3 py-2 text-sm text-body"
                            @change="onPresetChange"
                        >
                            <option value="">— Seçin —</option>
                            <optgroup v-for="(list, cat) in groupedPresets" :key="cat" :label="categories[cat] ?? cat">
                                <option v-for="p in list" :key="p.key" :value="p.key">{{ p.label }}</option>
                            </optgroup>
                        </select>
                        <p v-if="currentPreset" class="flex flex-wrap items-center gap-2 text-xs text-muted">
                            <a
                                v-if="currentPreset.doc_url"
                                :href="currentPreset.doc_url"
                                target="_blank"
                                rel="noopener"
                                class="inline-flex items-center gap-1 font-medium text-primary hover:underline"
                            >
                                <AppIcon name="external-link" :size="12" /> Entegrasyon dokümanı
                            </a>
                            <span
                                v-if="!currentPreset.verified"
                                class="inline-flex items-center gap-1 rounded-full border border-warning bg-warning-soft px-2 py-0.5 font-medium text-warning"
                            >
                                <AppIcon name="alert-circle" :size="11" /> Şablon — uç/eşleme dokümandan doğrulanmalı
                            </span>
                        </p>
                    </div>
                </BaseCard>

                <!-- Yapılandırma alanları (katalogtan üretilir) -->
                <BaseCard>
                    <div class="flex flex-col gap-4">
                        <p class="text-sm font-medium text-body">Bağlantı bilgileri</p>
                        <div v-for="f in fields.filter((x) => x.type !== 'preset')" :key="f.key" class="flex flex-col gap-1.5">
                            <label class="text-sm text-body">
                                {{ f.label }} <span v-if="f.required" class="text-danger">*</span>
                            </label>
                            <BaseInput
                                :model-value="(getPath(config, f.key) as string) ?? ''"
                                :type="f.type === 'secret' ? 'password' : 'text'"
                                :placeholder="f.type === 'url' ? 'https://…' : ''"
                                autocomplete="off"
                                @update:model-value="(v: string) => setPath(config, f.key, v)"
                            />
                        </div>
                    </div>
                </BaseCard>

                <!-- Test sonucu -->
                <div
                    v-if="testResult"
                    class="flex items-center gap-2 rounded-lg border px-3 py-2 text-sm"
                    :class="testResult.online ? 'border-success bg-success-soft text-success' : 'border-danger bg-danger-soft text-danger'"
                >
                    <AppIcon :name="testResult.online ? 'check-circle' : 'alert-circle'" :size="15" />
                    <span>{{ testResult.online ? 'Terminal çevrimiçi.' : 'Terminale ulaşılamadı.' }} {{ testResult.message }}</span>
                </div>

                <!-- Aksiyonlar -->
                <div class="flex flex-wrap items-center justify-end gap-2">
                    <BaseButton variant="secondary" :loading="testing" @click="test">
                        <AppIcon name="activity" :size="14" /> Terminali test et
                    </BaseButton>
                    <BaseButton :loading="saving" @click="save">
                        <AppIcon name="check" :size="14" /> Kaydet
                    </BaseButton>
                </div>

                <p class="text-xs text-subtle">
                    Güvenlik: Sonuç sağlayıcıdan kesin onay/imzalı callback ile doğrulanmadıkça ödeme
                    "başarılı" sayılmaz — yanlış ayar para kaybettirmez, işlemi bekletir.
                </p>
            </template>
        </div>
        </div>
        </div>
    </PanelShell>
</template>
