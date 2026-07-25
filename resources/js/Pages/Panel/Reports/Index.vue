<script setup lang="ts">
import { computed, reactive, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { authFromPage } from '@/types/auth';
import PanelShell from '@/Components/panel/PanelShell.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import ReportsNav from './components/ReportsNav.vue';
import OverviewTab from './tabs/OverviewTab.vue';
import SalesTab from './tabs/SalesTab.vue';
import FinanceTab from './tabs/FinanceTab.vue';
import ProfitTab from './tabs/ProfitTab.vue';
import OpsTab from './tabs/OpsTab.vue';
import EodTab from './tabs/EodTab.vue';
import ReconciliationTab from './tabs/ReconciliationTab.vue';
import StaffTab from './tabs/StaffTab.vue';
import ExportsTab from './tabs/ExportsTab.vue';
import { isoDate, lastDays, type ReportFilterState } from './reports';

/**
 * Raporlar ana ekranı. Filtre satırı (tarih ön ayarları + şube) TÜM
 * sekmeleri kapsar — her grafik/tablo aynı dilime bakar, sayılar tutarlıdır.
 */
const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));
const branches = computed(() => auth.value?.branches ?? []);

/* ---- Tarih ön ayarları (dataviz: preset satırları önce, özel aralık sonra) ---- */
type PresetKey = 'today' | 'yesterday' | '7d' | '30d' | 'month' | 'custom';

const presets: { key: PresetKey; label: string }[] = [
    { key: 'today', label: 'Bugün' },
    { key: 'yesterday', label: 'Dün' },
    { key: '7d', label: 'Son 7 gün' },
    { key: '30d', label: 'Son 30 gün' },
    { key: 'month', label: 'Bu ay' },
    { key: 'custom', label: 'Özel' },
];

const activePreset = ref<PresetKey>('7d');

const initial = lastDays(7);
const filters = reactive<ReportFilterState>({
    from: initial.from,
    to: initial.to,
    branchId: auth.value?.activeBranchId ?? 'all',
});

function applyPreset(key: PresetKey): void {
    activePreset.value = key;
    const today = new Date();

    if (key === 'today') {
        filters.from = isoDate(today);
        filters.to = isoDate(today);
    } else if (key === 'yesterday') {
        const y = new Date();
        y.setDate(today.getDate() - 1);
        filters.from = isoDate(y);
        filters.to = isoDate(y);
    } else if (key === '7d') {
        Object.assign(filters, lastDays(7));
    } else if (key === '30d') {
        Object.assign(filters, lastDays(30));
    } else if (key === 'month') {
        filters.from = isoDate(new Date(today.getFullYear(), today.getMonth(), 1));
        filters.to = isoDate(today);
    }
    // 'custom': mevcut değerler korunur, girişler serbest kalır
}

const branchOptions = computed(() => [
    { value: 'all', label: 'Tüm şubeler' },
    ...branches.value.map((b) => ({ value: String(b.id), label: b.name })),
]);

const branchValue = computed({
    get: () => String(filters.branchId ?? 'all'),
    set: (v: string) => {
        filters.branchId = v === 'all' ? 'all' : Number(v);
    },
});

/* ---- Sekmeler ---- */
/**
 * Gruplu 2 kademeli gezinme ReportsNav'da; burada yalnız aktif sekme tutulur.
 * Açılış "overview" (Genel Bakış landing) — bugüne bakar, filtre satırını gizler.
 */
const tab = ref('overview');
</script>

<template>
    <Head title="Raporlar" />

    <PanelShell title="Raporlar">
        <div class="flex flex-col gap-4">
            <!-- Gruplu 2 kademeli gezinme + açıklama -->
            <ReportsNav :active="tab" @select="tab = $event" />

            <!-- Filtre satırı: içeriğin ÜSTÜNDE tek satır; her şeyi kapsar.
                 Genel Bakış daima bugüne baktığı için orada gizlenir. -->
            <div v-if="tab !== 'overview'" class="flex flex-wrap items-center gap-2">
                <div class="flex flex-wrap gap-1 rounded-md border border-default bg-raised p-1" role="group" aria-label="Tarih aralığı">
                    <button
                        v-for="p in presets"
                        :key="p.key"
                        type="button"
                        class="rounded px-2.5 py-1 text-xs font-medium transition-colors duration-(--dur-fast)"
                        :class="activePreset === p.key ? 'bg-primary-soft text-primary' : 'text-muted hover:bg-inset'"
                        :aria-pressed="activePreset === p.key ? 'true' : 'false'"
                        @click="applyPreset(p.key)"
                    >
                        {{ p.label }}
                    </button>
                </div>

                <template v-if="activePreset === 'custom'">
                    <BaseInput v-model="filters.from" type="date" size="sm" class="w-36" aria-label="Başlangıç tarihi" />
                    <span class="text-xs text-subtle">–</span>
                    <BaseInput v-model="filters.to" type="date" size="sm" class="w-36" aria-label="Bitiş tarihi" />
                </template>

                <span v-else class="text-xs text-subtle">{{ filters.from }} – {{ filters.to }}</span>

                <div v-if="branches.length > 1" class="ml-auto w-44">
                    <BaseSelect v-model="branchValue" :options="branchOptions" size="sm" aria-label="Şube" />
                </div>
            </div>

            <OverviewTab v-if="tab === 'overview'" :branch-id="filters.branchId" @navigate="tab = $event" />
            <SalesTab v-else-if="tab === 'sales'" :filters="filters" />
            <FinanceTab v-else-if="tab === 'finance'" :filters="filters" />
            <ProfitTab v-else-if="tab === 'profit'" :filters="filters" />
            <OpsTab v-else-if="tab === 'ops'" :filters="filters" />
            <EodTab v-else-if="tab === 'eod'" :filters="filters" />
            <ReconciliationTab v-else-if="tab === 'reconciliation'" :filters="filters" />
            <StaffTab v-else-if="tab === 'staff'" :filters="filters" />
            <ExportsTab v-else-if="tab === 'exports'" />
        </div>
    </PanelShell>
</template>
