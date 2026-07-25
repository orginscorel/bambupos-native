<script setup lang="ts">
import { computed } from 'vue';
import { formatCurrencyMinor, formatNumber } from '@/lib/format';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import {
    isoDate,
    useReport,
    type EodSummary,
    type ProductsReport,
    type ReconciliationSummary,
    type ReportFilterState,
    type SalesSummary,
} from '../reports';

/**
 * GENEL BAKIŞ (landing) — Raporlar modülünün açılış ekranı.
 * Amaç: kullanıcı sekmelerde kaybolmadan BUGÜNÜN durumunu tek bakışta
 * görsün ve doğru rapora tek tıkla gitsin. Tüm veriler mevcut salt-okunur
 * uçlardan gelir (yeni backend YOK): sales-summary, finance-reconciliation,
 * ops-eod, sales-products.
 *
 * Bu ekran DAİMA bugüne bakar; üstteki tarih filtresi burada gizlidir.
 * Yalnız şube seçimi (branchId) devralınır.
 */
const props = defineProps<{ branchId: number | 'all' | null }>();
const emit = defineEmits<{ navigate: [tab: string] }>();

/** Bugün, seçili şube — filtre değişkeni olarak tek dilim. */
const todayFilters = computed<ReportFilterState>(() => {
    const t = isoDate(new Date());
    return { from: t, to: t, branchId: props.branchId };
});

const sales = useReport<SalesSummary>('sales-summary', todayFilters);
const recon = useReport<ReconciliationSummary>('finance-reconciliation', todayFilters);
const eod = useReport<EodSummary>('ops-eod', todayFilters);
const products = useReport<ProductsReport>('sales-products', todayFilters);

const loading = computed(
    () =>
        (sales.loading.value && sales.data.value === null) ||
        (recon.loading.value && recon.data.value === null),
);

const topProduct = computed(() => products.data.value?.top_by_qty?.[0] ?? null);
const cashMinor = computed(() => recon.data.value?.cash_minor ?? 0);
const posMinor = computed(() => recon.data.value?.pos_minor ?? 0);
const otherMinor = computed(() => recon.data.value?.other_minor ?? 0);
const collectedMinor = computed(() => recon.data.value?.payments_total_minor ?? 0);

/** Üst KPI kartları — tıklanınca ilgili rapora götürür. */
const kpis = computed(() => {
    const s = sales.data.value;
    const e = eod.data.value;
    return [
        {
            key: 'ciro',
            label: 'Ciro (bugün)',
            value: formatCurrencyMinor(s?.current.revenue_minor ?? 0),
            hint: `${formatNumber(s?.current.orders ?? 0)} adisyon`,
            icon: 'chart',
            tab: 'sales',
        },
        {
            key: 'tahsilat',
            label: 'Tahsilat (Nakit / POS)',
            value: formatCurrencyMinor(collectedMinor.value),
            hint: `Nakit ${formatCurrencyMinor(cashMinor.value)} · POS ${formatCurrencyMinor(posMinor.value)}`,
            icon: 'cart',
            tab: 'finance',
        },
        {
            key: 'acikmasa',
            label: 'Açık masa',
            value: formatNumber(e?.open_table_orders ?? 0),
            hint: (e?.open_table_orders ?? 0) > 0 ? `${formatCurrencyMinor(e?.open_table_minor ?? 0)} bekliyor` : 'Açık adisyon yok',
            icon: 'utensils',
            tab: 'eod',
        },
        {
            key: 'encoksatan',
            label: 'En çok satan (bugün)',
            value: topProduct.value ? topProduct.value.name : '—',
            hint: topProduct.value ? `${formatNumber(topProduct.value.qty)} adet` : 'Bugün satış yok',
            icon: 'package',
            tab: 'sales',
        },
    ];
});

/** Hızlı işlem butonları — ilgili sekmeye geçer. */
const actions = [
    { label: 'Gün Sonu', desc: 'Z özeti · açık masa · cari', icon: 'calendar', tab: 'eod' },
    { label: 'Ürün Raporu', desc: 'En çok / en az satan', icon: 'package', tab: 'sales' },
    { label: 'Personel Raporu', desc: 'Satış & performans', icon: 'users', tab: 'staff' },
    { label: 'Nakit-Kıyas', desc: 'Ödeme vs sistem mutabakat', icon: 'cart', tab: 'reconciliation' },
    { label: 'Kârlılık', desc: 'Satış fiyatı vs maliyet', icon: 'chart', tab: 'profit' },
    { label: 'Operasyon', desc: 'Hazırlama · iptal · QR', icon: 'coffee', tab: 'ops' },
];

/** Bugünün tahsilat kırılımı (nakit/POS/diğer). */
const collectionRows = computed(() => [
    { label: 'Nakit', value: cashMinor.value },
    { label: 'POS / kart', value: posMinor.value },
    { label: 'Diğer', value: otherMinor.value },
]);
</script>

<template>
    <div class="flex flex-col gap-4">
        <div v-if="loading" class="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <div v-for="n in 4" :key="n" class="h-24 rounded-lg border border-default bg-raised" />
        </div>

        <template v-else>
            <!-- KPI kartları (tıklanınca ilgili rapora gider) -->
            <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
                <button
                    v-for="k in kpis"
                    :key="k.key"
                    type="button"
                    class="group rounded-lg border border-default bg-raised p-4 text-left shadow-card transition-colors hover:border-primary"
                    @click="emit('navigate', k.tab)"
                >
                    <div class="flex items-center justify-between">
                        <p class="text-xs font-medium text-muted uppercase">{{ k.label }}</p>
                        <AppIcon :name="k.icon" :size="16" class="text-primary" />
                    </div>
                    <p class="mt-2 truncate text-2xl font-semibold tabular-nums text-body">{{ k.value }}</p>
                    <p class="mt-0.5 truncate text-xs text-subtle">{{ k.hint }}</p>
                </button>
            </div>

            <!-- Hızlı işlemler -->
            <BaseCard title="Hızlı işlemler">
                <div class="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
                    <button
                        v-for="a in actions"
                        :key="a.tab + a.label"
                        type="button"
                        class="flex flex-col gap-1 rounded-md border border-default p-3 text-left transition-colors hover:border-primary hover:bg-inset"
                        @click="emit('navigate', a.tab)"
                    >
                        <AppIcon :name="a.icon" :size="18" class="text-primary" />
                        <span class="text-sm font-medium text-body">{{ a.label }}</span>
                        <span class="text-xs text-subtle">{{ a.desc }}</span>
                    </button>
                </div>
            </BaseCard>

            <div class="grid gap-4 lg:grid-cols-2">
                <!-- En çok satan (bugün) -->
                <BaseCard>
                    <template #header>
                        <h2 class="text-sm font-semibold text-body">En çok satan (bugün)</h2>
                    </template>
                    <template #actions>
                        <button type="button" class="text-xs font-medium text-primary hover:underline" @click="emit('navigate', 'sales')">
                            Satış raporu
                        </button>
                    </template>
                    <ol v-if="(products.data.value?.top_by_qty.length ?? 0) > 0" class="divide-y divide-default text-sm">
                        <li v-for="(p, i) in products.data.value!.top_by_qty.slice(0, 6)" :key="p.name" class="flex items-center gap-2 py-2">
                            <span class="w-5 text-right tabular-nums text-subtle">{{ i + 1 }}.</span>
                            <span class="font-medium text-body">{{ p.name }}</span>
                            <span class="ms-auto tabular-nums text-muted">{{ formatNumber(p.qty) }} adet</span>
                            <span class="w-24 text-right tabular-nums text-body">{{ formatCurrencyMinor(p.revenue_minor) }}</span>
                        </li>
                    </ol>
                    <EmptyState v-else icon="chart" title="Bugün satış yok" description="Bugün tamamlanmış ürün satışı bulunmuyor." />
                </BaseCard>

                <!-- Tahsilat kırılımı (bugün) -->
                <BaseCard>
                    <template #header>
                        <h2 class="text-sm font-semibold text-body">Tahsilat kırılımı (bugün)</h2>
                    </template>
                    <template #actions>
                        <button type="button" class="text-xs font-medium text-primary hover:underline" @click="emit('navigate', 'reconciliation')">
                            Mutabakat
                        </button>
                    </template>
                    <ul v-if="collectedMinor > 0" class="text-sm">
                        <li v-for="r in collectionRows" :key="r.label" class="flex items-center justify-between border-b border-default py-2 last:border-0">
                            <span class="text-body">{{ r.label }}</span>
                            <span class="tabular-nums text-muted">{{ formatCurrencyMinor(r.value) }}</span>
                        </li>
                        <li class="flex items-center justify-between py-2 font-semibold">
                            <span class="text-body">Toplam tahsilat</span>
                            <span class="tabular-nums text-body">{{ formatCurrencyMinor(collectedMinor) }}</span>
                        </li>
                    </ul>
                    <EmptyState v-else icon="cart" title="Bugün tahsilat yok" description="Kasadan ödeme alındığında nakit/POS kırılımı burada görünür." />
                </BaseCard>
            </div>
        </template>
    </div>
</template>
