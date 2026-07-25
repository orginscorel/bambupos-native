<script setup lang="ts">
import { computed, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { formatDate } from '@/lib/format';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseTabs, { type TabItem } from '@/Components/ui/BaseTabs.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';

/**
 * Panel > Sürüm Notları
 *
 * İki bölüm: Site (panel + müşteri menüsü) ve Uygulama (native, henüz
 * yayınlanmadı). Veri tamamen sunucudan gelir (config/changelog.php +
 * config/native_changelog.php) — burada tarih/sıra uydurulmaz, yalnız
 * biçimlendirilir. Alt bilgideki sürüm rozetleri de bu sayfaya bağlanır
 * (query string ile sekme seçilir: ?sekme=native).
 */

type ChangeType = 'new' | 'improved' | 'fixed';

interface ChangeItem {
    type: ChangeType;
    text: string;
}

interface VersionEntry {
    version: string;
    date: string;
    title: string;
    changes: ChangeItem[];
}

interface SiteChangelog {
    current_version: string;
    released_at: string;
    entries: VersionEntry[];
}

interface NativeChangelog {
    status: 'not_released' | 'released';
    current_version: string | null;
    released_at: string | null;
    planned_version?: string | null;
    status_message?: string;
    entries: VersionEntry[];
}

const props = defineProps<{
    site: SiteChangelog;
    native: NativeChangelog;
}>();

const page = usePage();
const initialTab = new URLSearchParams(page.url.split('?')[1] ?? '').get('sekme');

const tabs: TabItem[] = [
    { key: 'site', label: 'Site', icon: 'dashboard' },
    { key: 'native', label: 'Uygulama (Native)', icon: 'qr-code' },
];
const activeTab = ref<string>(initialTab === 'native' ? 'native' : 'site');

const typeMeta: Record<ChangeType, { variant: 'success' | 'info' | 'warning'; icon: string; label: string }> = {
    new: { variant: 'success', icon: 'plus', label: 'Yeni' },
    improved: { variant: 'info', icon: 'chart', label: 'İyileştirme' },
    fixed: { variant: 'warning', icon: 'check-circle', label: 'Düzeltme' },
};

const siteEntries = computed(() => props.site.entries);
const nativeEntries = computed(() => props.native.entries);
</script>

<template>
    <Head title="Sürüm Notları" />

    <PanelShell title="Sürüm Notları">
        <div class="mx-auto flex w-full max-w-5xl flex-col gap-8">
            <div class="flex flex-col gap-2">
                <h1 class="text-2xl font-semibold text-body">Sürüm notları</h1>
                <p class="max-w-2xl text-[15px] leading-relaxed text-muted">
                    QR Menü'ye eklenen her özellik ve yapılan her güncelleme burada yayınlanır — hem web panel
                    hem de (ileride) native uygulama için.
                </p>
            </div>

            <BaseTabs :tabs="tabs" v-model="activeTab">
                <!-- ---- SİTE ---- -->
                <template #site>
                    <div class="flex flex-col gap-8 pt-2">
                        <!-- Güncel sürüm: hero -->
                        <BaseCard flush>
                            <div
                                class="flex flex-wrap items-center justify-between gap-4 rounded-lg bg-linear-to-br from-primary-soft to-transparent p-6 sm:p-8"
                            >
                                <div class="flex items-center gap-4">
                                    <span class="flex size-14 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
                                        <AppIcon name="dashboard" :size="26" />
                                    </span>
                                    <div>
                                        <p class="text-xs font-semibold tracking-wide text-muted uppercase">Güncel sürüm</p>
                                        <p class="mt-0.5 text-3xl font-bold text-body">v{{ site.current_version }}</p>
                                    </div>
                                </div>
                                <BaseBadge variant="primary">
                                    {{ formatDate(site.released_at) }} tarihinde yayınlandı
                                </BaseBadge>
                            </div>
                        </BaseCard>

                        <ol class="relative flex flex-col gap-8 border-l border-default pl-8">
                            <li v-for="(entry, i) in siteEntries" :key="entry.version" class="relative">
                                <span
                                    class="absolute top-2 -left-[37px] flex size-4 items-center justify-center rounded-full ring-4 ring-surface-alt"
                                    :class="i === 0 ? 'bg-primary' : 'bg-subtle'"
                                />
                                <BaseCard>
                                    <template #header>
                                        <div class="flex flex-wrap items-center gap-2.5 py-0.5">
                                            <h2 class="text-base font-semibold text-body">{{ entry.title }}</h2>
                                            <BaseBadge v-if="i === 0" variant="primary" no-icon>Güncel</BaseBadge>
                                        </div>
                                    </template>
                                    <template #actions>
                                        <div class="flex flex-col items-end text-right">
                                            <span class="text-sm font-semibold text-body">v{{ entry.version }}</span>
                                            <span class="text-xs text-subtle">{{ formatDate(entry.date) }}</span>
                                        </div>
                                    </template>

                                    <ul class="flex flex-col gap-3.5 py-1.5">
                                        <li v-for="(change, ci) in entry.changes" :key="ci" class="flex items-start gap-3">
                                            <BaseBadge :variant="typeMeta[change.type].variant" no-icon class="mt-0.5 shrink-0">
                                                <AppIcon :name="typeMeta[change.type].icon" :size="12" />
                                                {{ typeMeta[change.type].label }}
                                            </BaseBadge>
                                            <span class="text-sm leading-relaxed text-body">{{ change.text }}</span>
                                        </li>
                                    </ul>
                                </BaseCard>
                            </li>
                        </ol>
                    </div>
                </template>

                <!-- ---- NATIVE (henüz yayınlanmadı) ---- -->
                <template #native>
                    <div class="flex flex-col gap-8 pt-2">
                        <template v-if="native.status === 'released' && nativeEntries.length > 0">
                            <BaseCard flush>
                                <div
                                    class="flex flex-wrap items-center justify-between gap-4 rounded-lg bg-linear-to-br from-primary-soft to-transparent p-6 sm:p-8"
                                >
                                    <div class="flex items-center gap-4">
                                        <span class="flex size-14 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
                                            <AppIcon name="qr-code" :size="26" />
                                        </span>
                                        <div>
                                            <p class="text-xs font-semibold tracking-wide text-muted uppercase">Güncel sürüm</p>
                                            <p class="mt-0.5 text-3xl font-bold text-body">v{{ native.current_version }}</p>
                                        </div>
                                    </div>
                                    <BaseBadge v-if="native.released_at" variant="primary">
                                        {{ formatDate(native.released_at) }} tarihinde yayınlandı
                                    </BaseBadge>
                                </div>
                            </BaseCard>

                            <ol class="relative flex flex-col gap-8 border-l border-default pl-8">
                                <li v-for="(entry, i) in nativeEntries" :key="entry.version" class="relative">
                                    <span
                                        class="absolute top-2 -left-[37px] flex size-4 items-center justify-center rounded-full ring-4 ring-surface-alt"
                                        :class="i === 0 ? 'bg-primary' : 'bg-subtle'"
                                    />
                                    <BaseCard>
                                        <template #header>
                                            <h2 class="text-base font-semibold text-body">{{ entry.title }}</h2>
                                        </template>
                                        <template #actions>
                                            <div class="flex flex-col items-end text-right">
                                                <span class="text-sm font-semibold text-body">v{{ entry.version }}</span>
                                                <span class="text-xs text-subtle">{{ formatDate(entry.date) }}</span>
                                            </div>
                                        </template>
                                        <ul class="flex flex-col gap-3.5 py-1.5">
                                            <li v-for="(change, ci) in entry.changes" :key="ci" class="flex items-start gap-3">
                                                <BaseBadge :variant="typeMeta[change.type].variant" no-icon class="mt-0.5 shrink-0">
                                                    <AppIcon :name="typeMeta[change.type].icon" :size="12" />
                                                    {{ typeMeta[change.type].label }}
                                                </BaseBadge>
                                                <span class="text-sm leading-relaxed text-body">{{ change.text }}</span>
                                            </li>
                                        </ul>
                                    </BaseCard>
                                </li>
                            </ol>
                        </template>

                        <BaseCard v-else flush>
                            <div class="p-6 sm:p-10">
                                <EmptyState
                                    icon="qr-code"
                                    title="Uygulama henüz yayınlanmadı"
                                    :description="
                                        native.status_message ??
                                        'QR Menü native (mobil/masaüstü) uygulaması henüz yayınlanmadı. Şu an QR Menü, tarayıcı üzerinden panel ve müşteri menüsü olarak sunuluyor.'
                                    "
                                >
                                    <template v-if="native.planned_version" #action>
                                        <p class="text-xs text-subtle">
                                            Hedeflenen ilk sürüm: v{{ native.planned_version }} — henüz kesinleşmiş bir tarih yok.
                                        </p>
                                    </template>
                                </EmptyState>
                            </div>
                        </BaseCard>
                    </div>
                </template>
            </BaseTabs>
        </div>
    </PanelShell>
</template>
