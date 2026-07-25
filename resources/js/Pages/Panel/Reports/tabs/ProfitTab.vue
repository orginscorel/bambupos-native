<script setup lang="ts">
import { computed, toRef } from 'vue';
import { formatCurrencyMinor, formatNumber } from '@/lib/format';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import ReportTable from '../components/ReportTable.vue';
import ExportButtons from '../components/ExportButtons.vue';
import StatTile from '../components/StatTile.vue';
import { useReport, type ProfitRow, type ReportFilterState } from '../reports';

const props = defineProps<{ filters: ReportFilterState }>();
const filters = toRef(props, 'filters');

const report = useReport<{ rows: ProfitRow[]; missing_cost_count: number; median_margin: number | null }>(
    'product-profitability',
    filters,
);

const rows = computed(() => report.data.value?.rows ?? []);
const withCost = computed(() => rows.value.filter((r) => r.has_cost && r.margin !== null));

const best = computed(() =>
    withCost.value.length > 0 ? [...withCost.value].sort((a, b) => (b.margin ?? 0) - (a.margin ?? 0))[0] : null,
);
const worst = computed(() =>
    withCost.value.length > 0 ? [...withCost.value].sort((a, b) => (a.margin ?? 0) - (b.margin ?? 0))[0] : null,
);
const flagged = computed(() => rows.value.filter((r) => r.high_volume_low_margin));

const totalProfit = computed(() =>
    withCost.value.reduce((sum, r) => sum + (r.profit_minor ?? 0), 0),
);

const pct = (v: number | null) => (v === null ? '—' : `%${v.toFixed(1).replace('.', ',')}`);
</script>

<template>
    <div class="flex flex-col gap-4">
        <p v-if="report.error.value" class="text-sm text-danger">{{ report.error.value }}</p>

        <EmptyState
            v-if="report.data.value && rows.length === 0"
            icon="chart"
            title="Bu aralıkta satış yok"
            description="Kârlılık, satış gerçekleştikçe hesaplanır."
        />

        <template v-else-if="report.data.value">
            <!-- Maliyet eksiği: dürüst uyarı — kâr uydurulmaz -->
            <div
                v-if="report.data.value.missing_cost_count > 0"
                class="flex items-start gap-2.5 rounded-md border border-warning-border bg-warning-soft px-3 py-2.5 text-sm text-warning"
                role="status"
            >
                <span class="font-semibold">{{ report.data.value.missing_cost_count }} ürünün maliyeti girilmemiş.</span>
                <span>Bu ürünlerde kâr hesaplanmaz. Maliyetleri Menü &gt; Ürün kartından girebilirsiniz.</span>
            </div>

            <div class="grid grid-cols-2 gap-3 xl:grid-cols-4">
                <StatTile
                    label="Toplam brüt kâr (maliyeti bilinenler)"
                    :value="withCost.length > 0 ? formatCurrencyMinor(totalProfit) : '—'"
                    :hint="withCost.length > 0 ? `${formatNumber(withCost.length)} ürün` : 'Maliyet verisi yok'"
                />
                <StatTile
                    label="Medyan marj"
                    :value="report.data.value.median_margin !== null ? pct(report.data.value.median_margin) : '—'"
                    hint="KDV hariç net üzerinden"
                />
                <StatTile
                    label="En kârlı ürün"
                    :value="best ? best.name : '—'"
                    :hint="best ? `marj ${pct(best.margin)}` : 'Maliyet verisi yok'"
                />
                <StatTile
                    label="En düşük marjlı"
                    :value="worst ? worst.name : '—'"
                    :hint="worst ? `marj ${pct(worst.margin)}` : 'Maliyet verisi yok'"
                />
            </div>

            <BaseCard v-if="flagged.length > 0" title="Çok satan ama düşük kârlı" flush>
                <ReportTable
                    :columns="[
                        { key: 'name', label: 'Ürün' },
                        { key: 'qty', label: 'Adet', align: 'right', format: 'number' },
                        { key: 'revenue_minor', label: 'Ciro', align: 'right', format: 'minor' },
                        { key: 'margin', label: 'Marj', align: 'right', format: 'percent' },
                    ]"
                    :rows="flagged"
                />
            </BaseCard>

            <BaseCard title="Ürün kârlılığı (satış fiyatı vs maliyet)" flush>
                <template #actions>
                    <ExportButtons report="product-profitability" :filters="filters" />
                </template>
                <ReportTable
                    :columns="[
                        { key: 'name', label: 'Ürün' },
                        { key: 'qty', label: 'Adet', align: 'right', format: 'number' },
                        { key: 'revenue_minor', label: 'Ciro (brüt)', align: 'right', format: 'minor' },
                        { key: 'net_minor', label: 'Net', align: 'right', format: 'minor' },
                        { key: 'cost_minor', label: 'Maliyet', align: 'right', format: 'minor' },
                        { key: 'profit_minor', label: 'Brüt kâr', align: 'right', format: 'minor' },
                        { key: 'margin', label: 'Marj', align: 'right' },
                    ]"
                    :rows="rows"
                >
                    <template #cell-margin="{ row }">
                        <BaseBadge v-if="!(row as unknown as ProfitRow).has_cost" variant="neutral">maliyet yok</BaseBadge>
                        <span v-else class="tabular-nums">{{ pct((row as unknown as ProfitRow).margin) }}</span>
                    </template>
                </ReportTable>
                <p class="border-t border-default px-4 py-2 text-xs text-subtle">
                    Not: maliyet, ürün kartındaki güncel değerdir (satış anında dondurulmaz); reçete maliyetini
                    güncel tutmak rapor doğruluğunu artırır. Kâr ve marj KDV hariç net tutar üzerinden hesaplanır.
                </p>
            </BaseCard>
        </template>
    </div>
</template>
