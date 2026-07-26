<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { Head, Link, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';

/**
 * Eklentiler ekranı (§9 feature-flag). Yönetici opsiyonel özellikleri tek tek
 * aç/kapatır; kapalı özellik menüden ve rotalardan kalkar (ADR: kapalı=yok).
 * Çekirdek (siparişler/masalar/kasa/menü/personel/raporlar) katalogda YOK →
 * kapatılamaz. İzin: settings.manage.
 */

interface FeatureDto {
    key: string;
    name: string;
    description: string;
    enabled: boolean;
}

const page = usePage();
const { success, danger } = useToast();

/** Ayarlar alt sekmeleri — navigation.ts'te tek "Ayarlar" girişi var. */
const settingsTabs = [
    { href: '/panel/ayarlar/e-posta', label: 'E-posta' },
    { href: '/panel/ayarlar/isletme', label: 'İşletme / Marka' },
    { href: '/panel/ayarlar/eklentiler', label: 'Eklentiler' },
];
const isActiveTab = (href: string) => page.url.startsWith(href);

const loading = ref(true);
const loadFailed = ref(false);
const features = ref<FeatureDto[]>([]);
/** Anlık istek süren özellik anahtarları (çift tık engeli). */
const busy = ref<Record<string, boolean>>({});

async function load(): Promise<void> {
    loading.value = true;
    loadFailed.value = false;
    try {
        const data = await api<{ features: FeatureDto[] }>('/api/v1/settings/features');
        features.value = data.features;
    } catch {
        loadFailed.value = true;
    } finally {
        loading.value = false;
    }
}

async function toggle(feature: FeatureDto, next: boolean): Promise<void> {
    if (busy.value[feature.key]) return;
    busy.value = { ...busy.value, [feature.key]: true };

    const previous = feature.enabled;
    feature.enabled = next; // iyimser güncelleme

    try {
        await api('/api/v1/settings/features', {
            method: 'PUT',
            body: { feature: feature.key, enabled: next },
        });
        success(next ? `${feature.name} açıldı.` : `${feature.name} kapatıldı.`);
    } catch (e) {
        feature.enabled = previous; // geri al
        danger(e instanceof ApiError ? e.displayMessage : 'İşlem tamamlanamadı.');
    } finally {
        busy.value = { ...busy.value, [feature.key]: false };
    }
}

onMounted(load);
</script>

<template>
    <Head title="Eklentiler" />

    <PanelShell title="Eklentiler">
        <div class="mx-auto flex w-full max-w-5xl flex-col gap-6">
            <div class="flex flex-col gap-1.5">
                <h1 class="text-2xl font-semibold text-body">Ayarlar</h1>
                <p class="max-w-2xl text-[15px] leading-relaxed text-muted">
                    İşletmenizde hangi özelliklerin kullanılacağını buradan açıp kapatın.
                    Kapatılan özellik menüden ve müşteri menüsünden kalkar; çekirdek
                    özellikler (siparişler, masalar, kasa, menü, personel, raporlar) her
                    zaman açıktır.
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

            <!-- Yükleniyor -->
            <template v-if="loading">
                <BaseCard><BaseSkeleton class="h-20" /></BaseCard>
                <BaseCard><BaseSkeleton class="h-20" /></BaseCard>
            </template>

            <!-- Hata -->
            <BaseCard v-else-if="loadFailed" class="text-center">
                <p class="text-sm text-muted">Eklentiler yüklenemedi.</p>
                <button
                    type="button"
                    class="mt-3 text-sm font-medium text-primary hover:underline"
                    @click="load"
                >
                    Yeniden dene
                </button>
            </BaseCard>

            <!-- Liste -->
            <BaseCard v-else class="p-0">
                <ul class="divide-y divide-(--ui-border)">
                    <li
                        v-for="feature in features"
                        :key="feature.key"
                        class="flex items-start justify-between gap-4 px-4 py-4 sm:px-6"
                    >
                        <div class="min-w-0 flex flex-col gap-0.5">
                            <span class="text-[15px] font-semibold text-body">{{ feature.name }}</span>
                            <span class="text-sm leading-relaxed text-muted">{{ feature.description }}</span>
                        </div>
                        <BaseSwitch
                            :model-value="feature.enabled"
                            :busy="busy[feature.key]"
                            :aria-label="`${feature.name} özelliğini aç/kapat`"
                            @update:model-value="toggle(feature, $event)"
                        />
                    </li>
                </ul>
            </BaseCard>
        </div>
    </PanelShell>
</template>
