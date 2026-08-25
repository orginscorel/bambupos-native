<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head, Link, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';

/**
 * Eklentiler ekranı (§9 feature-flag). Yönetici opsiyonel özellikleri tek tek
 * aç/kapatır; kapalı özellik menüden ve rotalardan kalkar (ADR: kapalı=yok).
 * Çekirdek (siparişler/masalar/kasa/menü/personel/raporlar) katalogda YOK →
 * kapatılamaz. İzin: settings.manage.
 *
 * Bu ekran DETAYLI sunum yapar: her özellik için ikon, açıklama, durum rozeti
 * (Açık/Kapalı) ve (varsa) ilişki/bağımlılık notu. Aç/kapa davranışı ve API
 * DEĞİŞMEZ (aynı /api/v1/settings/features uçları).
 */

interface FeatureDto {
    key: string;
    name: string;
    description: string;
    enabled: boolean;
}

/** Özellik ikonları — yalnız görsel; bilinmeyen anahtar boş ikonla düşer. */
const FEATURE_ICON: Record<string, string> = {
    branches: 'store',
    kiosk: 'monitor',
    reservations: 'calendar',
    qr_ordering: 'utensils',
    service_calls: 'bell',
    inventory: 'package',
    shifts: 'clock',
    receivables: 'wallet',
    terminals: 'tablet',
    delivery: 'truck',
    commission: 'chart',
};

/** (Varsa) ilişki / bağımlılık notu — kapatınca hangi yüzeyin kalktığı. */
const FEATURE_NOTE: Record<string, string> = {
    branches: 'Kapatılırsa sistem tek-şube modunda çalışır; şube seçici gizlenir.',
    qr_ordering: 'Kapalıyken QR menü yalnız görüntülenir, sipariş alınmaz.',
    service_calls: 'QR menüdeki garson/su/hesap çağır butonlarını yönetir.',
    delivery: 'Kurye atama ve teslimat panosu bu özelliğe bağlıdır.',
    commission: 'Prim raporu ve şema ekranları bu özelliğe bağlıdır.',
};

const iconOf = (key: string): string => FEATURE_ICON[key] ?? 'plug';
const noteOf = (key: string): string | undefined => FEATURE_NOTE[key];

const page = usePage();
const { success, danger } = useToast();

/** Ayarlar alt sekmeleri — navigation.ts'te tek "Ayarlar" girişi var. */
const settingsTabs = [
    { href: '/panel/ayarlar/e-posta', label: 'E-posta' },
    { href: '/panel/ayarlar/isletme', label: 'İşletme / Marka' },
    { href: '/panel/ayarlar/tema', label: 'Tema' },
    { href: '/panel/ayarlar/eklentiler', label: 'Eklentiler' },
];
const isActiveTab = (href: string) => page.url.startsWith(href);

const loading = ref(true);
const loadFailed = ref(false);
const features = ref<FeatureDto[]>([]);
/** Anlık istek süren özellik anahtarları (çift tık engeli). */
const busy = ref<Record<string, boolean>>({});

/** Açık özellik sayısı — üst bilgi rozeti. */
const activeCount = computed(() => features.value.filter((f) => f.enabled).length);

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

    <PanelShell title="Eklentiler" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1080px] flex-col gap-3">

        <div class="mx-auto flex w-full max-w-5xl flex-col gap-6">
            <div class="flex flex-col gap-1.5">
                <div class="flex items-center gap-3">
                    <h1 class="text-2xl font-semibold text-body">Ayarlar</h1>
                    <span
                        v-if="!loading && !loadFailed"
                        class="rounded-full bg-primary-soft px-2.5 py-0.5 text-xs font-bold text-primary"
                    >{{ activeCount }} / {{ features.length }} açık</span>
                </div>
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
                        class="flex items-start gap-4 px-4 py-4 sm:px-6"
                    >
                        <span
                            class="mt-0.5 flex size-10 shrink-0 items-center justify-center rounded-lg"
                            :class="feature.enabled ? 'bg-primary-soft text-primary' : 'bg-inset text-muted'"
                        >
                            <AppIcon :name="iconOf(feature.key)" :size="20" />
                        </span>
                        <div class="min-w-0 flex flex-1 flex-col gap-0.5">
                            <div class="flex flex-wrap items-center gap-2">
                                <span class="text-[15px] font-semibold text-body">{{ feature.name }}</span>
                                <span
                                    class="rounded-full px-2 py-0.5 text-[11px] font-bold"
                                    :class="feature.enabled ? 'bg-(--color-success-soft) text-(--color-success)' : 'bg-inset text-muted'"
                                >{{ feature.enabled ? 'Açık' : 'Kapalı' }}</span>
                            </div>
                            <span class="text-sm leading-relaxed text-muted">{{ feature.description }}</span>
                            <span v-if="noteOf(feature.key)" class="mt-1 inline-flex items-start gap-1 text-xs text-subtle">
                                <AppIcon name="info" :size="13" class="mt-0.5 shrink-0" />
                                {{ noteOf(feature.key) }}
                            </span>
                        </div>
                        <BaseSwitch
                            class="mt-0.5"
                            :model-value="feature.enabled"
                            :busy="busy[feature.key]"
                            :aria-label="`${feature.name} özelliğini aç/kapat`"
                            @update:model-value="toggle(feature, $event)"
                        />
                    </li>
                </ul>
            </BaseCard>
        </div>
        </div>
        </div>
    </PanelShell>
</template>
