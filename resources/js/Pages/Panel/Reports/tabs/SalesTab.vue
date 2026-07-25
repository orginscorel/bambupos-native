<script setup lang="ts">
import { computed, toRef } from 'vue';
import { formatCurrencyMinor, formatNumber } from '@/lib/format';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import StatTile from '../components/StatTile.vue';
import ChartColumn from '../components/ChartColumn.vue';
import ChartStackedBar from '../components/ChartStackedBar.vue';
import ReportTable from '../components/ReportTable.vue';
import ExportButtons from '../components/ExportButtons.vue';
import {
    pctChange,
    shortDay,
    useReport,
    type ChannelRow,
    type DayPoint,
    type HourPoint,
    type NamedSalesRow,
    type ProductsReport,
    type ReportFilterState,
    type SalesSummary,
    type TableSalesRow,
} from '../reports';

const props = defineProps<{ filters: ReportFilterState }>();
const filters = toRef(props, 'filters');

const summary = useReport<SalesSummary>('sales-summary', filters);
const daily = useReport<{ days: DayPoint[] }>('sales-daily', filters);
const hourly = useReport<{ hours: HourPoint[] }>('sales-hourly', filters);
const categories = useReport<{ rows: NamedSalesRow[] }>('sales-categories', filters);
const products = useReport<ProductsReport>('sales-products', filters);
const variants = useReport<{ rows: { name: string; variant: string; qty: number; revenue_minor: number }[] }>('sales-variants', filters);
const tables = useReport<{ rows: TableSalesRow[] }>('sales-tables', filters);
const channels = useReport<{ total_minor: number; rows: ChannelRow[] }>('sales-channels', filters);

/** En çok oturulan (devir) ve en çok sipariş verilen masalar — mevcut
 * masa satışı verisinden istemci tarafında türetilir (yeni sorgu yok). */
const mostTurnedTables = computed(() =>
    [...(tables.data.value?.rows ?? [])].filter((r) => r.turns > 0).sort((a, b) => b.turns - a.turns).slice(0, 5),
);
const mostOrderedTables = computed(() =>
    [...(tables.data.value?.rows ?? [])].sort((a, b) => b.orders - a.orders).slice(0, 5),
);

const tiles = computed(() => {
    const s = summary.data.value;
    if (s === null) return [];
    return [
        {
            label: 'Ciro',
            value: formatCurrencyMinor(s.current.revenue_minor),
            delta: pctChange(s.current.revenue_minor, s.previous.revenue_minor),
        },
        {
            label: 'Sipariş',
            value: formatNumber(s.current.orders),
            delta: pctChange(s.current.orders, s.previous.orders),
        },
        {
            label: 'Ortalama sepet',
            value: formatCurrencyMinor(s.current.avg_basket_minor),
            delta: pctChange(s.current.avg_basket_minor, s.previous.avg_basket_minor),
        },
        {
            label: 'Kişi başı harcama',
            value: s.current.per_guest_minor !== null ? formatCurrencyMinor(s.current.per_guest_minor) : '—',
            delta: null,
            hint: s.current.per_guest_minor !== null ? `${formatNumber(s.current.guests)} misafir girildi` : 'Misafir sayısı girilmemiş',
        },
    ];
});

const dailyPoints = computed(() =>
    (daily.data.value?.days ?? []).map((d) => ({ label: shortDay(d.date), title: d.date, value: d.revenue_minor })),
);

const hourlyPoints = computed(() =>
    (hourly.data.value?.hours ?? []).map((h) => ({
        label: `${String(h.hour).padStart(2, '0')}`,
        title: `${String(h.hour).padStart(2, '0')}:00 – ${String(h.hour).padStart(2, '0')}:59`,
        value: h.orders,
    })),
);

/** Kanal payları: sabit slot (varlığa bağlı renk), 4'ten sonrası Diğer. */
const channelSegments = computed(() => {
    const rows = channels.data.value?.rows ?? [];
    const head = rows.slice(0, 4).map((r, i) => ({
        label: r.label,
        value: r.revenue_minor,
        colorIndex: i,
        hint: `${formatNumber(r.orders)} sipariş`,
    }));
    const tail = rows.slice(4);
    if (tail.length > 0) {
        head.push({
            label: 'Diğer',
            value: tail.reduce((sum, r) => sum + r.revenue_minor, 0),
            colorIndex: 4,
            hint: `${tail.length} kanal`,
        });
    }
    return head;
});

const anySales = computed(() => (summary.data.value?.current.orders ?? 0) > 0);
</script>

<template>
    <div class="flex flex-col gap-4">
        <!-- Özet kutuları -->
        <div v-if="summary.loading.value && summary.data.value === null" class="grid grid-cols-2 gap-3 xl:grid-cols-4">
            <div v-for="n in 4" :key="n" class="flex flex-col gap-3 rounded-lg border border-default bg-raised p-4">
                <BaseSkeleton size-class="h-4 w-20" />
                <BaseSkeleton size-class="h-7 w-24" />
            </div>
        </div>
        <p v-else-if="summary.error.value" class="text-sm text-danger">{{ summary.error.value }}</p>
        <div v-else-if="summary.data.value" class="grid grid-cols-2 gap-3 xl:grid-cols-4">
            <StatTile
                v-for="t in tiles"
                :key="t.label"
                :label="t.label"
                :value="t.value"
                :delta="t.delta"
                delta-label="önceki döneme göre"
                :hint="t.hint ?? ''"
            />
        </div>

        <BaseCard v-if="summary.data.value && !anySales" flush>
            <EmptyState
                icon="chart"
                title="Bu aralıkta satış yok"
                description="Seçilen tarih aralığında tamamlanmış sipariş bulunmuyor. Aralığı genişletmeyi deneyin."
            />
        </BaseCard>

        <template v-else>
            <!-- Günlük ciro -->
            <BaseCard title="Günlük ciro">
                <template #actions>
                    <ExportButtons report="sales-daily" :filters="filters" />
                </template>
                <ChartColumn
                    v-if="dailyPoints.length > 0"
                    :points="dailyPoints"
                    money
                    label="Günlük ciro sütun grafiği"
                />
            </BaseCard>

            <!-- Yoğun saatler -->
            <BaseCard title="Yoğun saatler (sipariş adedi)">
                <template #actions>
                    <ExportButtons report="sales-hourly" :filters="filters" />
                </template>
                <ChartColumn
                    v-if="hourlyPoints.length > 0"
                    :points="hourlyPoints"
                    :label-every="3"
                    label="Saat başına sipariş adedi grafiği"
                />
            </BaseCard>

            <!-- Kanal payı -->
            <BaseCard title="Sipariş kanalı payı">
                <template #actions>
                    <ExportButtons report="sales-channels" :filters="filters" />
                </template>
                <ChartStackedBar
                    v-if="channelSegments.length > 0"
                    :segments="channelSegments"
                    money
                    label="Kanal bazında ciro payı"
                />
                <EmptyState v-else icon="chart" title="Veri yok" description="Bu aralıkta kanal verisi yok." />
            </BaseCard>

            <div class="grid gap-4 xl:grid-cols-2">
                <BaseCard title="Kategori satışları" flush>
                    <template #actions>
                        <ExportButtons report="sales-categories" :filters="filters" />
                    </template>
                    <ReportTable
                        :columns="[
                            { key: 'name', label: 'Kategori' },
                            { key: 'qty', label: 'Adet', align: 'right', format: 'number' },
                            { key: 'orders', label: 'Sipariş', align: 'right', format: 'number' },
                            { key: 'revenue_minor', label: 'Ciro', align: 'right', format: 'minor' },
                        ]"
                        :rows="categories.data.value?.rows ?? []"
                    />
                </BaseCard>

                <BaseCard title="Ürün satışları (en çok satılan)" flush>
                    <template #actions>
                        <ExportButtons report="sales-products" :filters="filters" />
                    </template>
                    <ReportTable
                        :columns="[
                            { key: 'name', label: 'Ürün' },
                            { key: 'qty', label: 'Adet', align: 'right', format: 'number' },
                            { key: 'orders', label: 'Sipariş', align: 'right', format: 'number' },
                            { key: 'revenue_minor', label: 'Ciro', align: 'right', format: 'minor' },
                        ]"
                        :rows="products.data.value?.rows ?? []"
                    />
                </BaseCard>

                <BaseCard title="En az satılan ürünler" flush>
                    <ReportTable
                        :columns="[
                            { key: 'name', label: 'Ürün' },
                            { key: 'qty', label: 'Adet', align: 'right', format: 'number' },
                            { key: 'revenue_minor', label: 'Ciro', align: 'right', format: 'minor' },
                        ]"
                        :rows="products.data.value?.least_by_qty ?? []"
                        empty-text="Bu aralıkta satış yok."
                    />
                    <p class="border-t border-default px-4 py-2 text-xs text-subtle">
                        Not: yalnız bu aralıkta EN AZ satılan (ama satılmış) ürünler listelenir; hiç satılmayan menü
                        kalemleri burada gösterilmez (katalogla karşılaştırma gerektirir).
                    </p>
                </BaseCard>

                <BaseCard title="Varyant satışları" flush>
                    <template #actions>
                        <ExportButtons report="sales-variants" :filters="filters" />
                    </template>
                    <ReportTable
                        :columns="[
                            { key: 'name', label: 'Ürün' },
                            { key: 'variant', label: 'Varyant' },
                            { key: 'qty', label: 'Adet', align: 'right', format: 'number' },
                            { key: 'revenue_minor', label: 'Ciro', align: 'right', format: 'minor' },
                        ]"
                        :rows="variants.data.value?.rows ?? []"
                        empty-text="Bu aralıkta varyantlı ürün satışı yok."
                    />
                </BaseCard>

                <BaseCard title="Masa satışları ve devir" flush>
                    <template #actions>
                        <ExportButtons report="sales-tables" :filters="filters" />
                    </template>
                    <div v-if="(tables.data.value?.rows.length ?? 0) > 0" class="grid gap-3 border-b border-default px-4 py-3 sm:grid-cols-2">
                        <div>
                            <p class="mb-1.5 text-xs font-semibold text-muted">En çok oturulan masalar (devir)</p>
                            <ol class="flex flex-col gap-1 text-sm">
                                <li v-for="(t, i) in mostTurnedTables" :key="t.name" class="flex items-center justify-between gap-2">
                                    <span class="text-body">{{ i + 1 }}. {{ t.name }}</span>
                                    <span class="font-medium tabular-nums text-muted">{{ formatNumber(t.turns) }} devir</span>
                                </li>
                                <li v-if="mostTurnedTables.length === 0" class="text-xs text-subtle">Henüz kapanan adisyon yok.</li>
                            </ol>
                        </div>
                        <div>
                            <p class="mb-1.5 text-xs font-semibold text-muted">En çok sipariş verilen masalar</p>
                            <ol class="flex flex-col gap-1 text-sm">
                                <li v-for="(t, i) in mostOrderedTables" :key="t.name" class="flex items-center justify-between gap-2">
                                    <span class="text-body">{{ i + 1 }}. {{ t.name }}</span>
                                    <span class="font-medium tabular-nums text-muted">{{ formatNumber(t.orders) }} adisyon</span>
                                </li>
                            </ol>
                        </div>
                    </div>
                    <ReportTable
                        :columns="[
                            { key: 'name', label: 'Masa' },
                            { key: 'orders', label: 'Sipariş', align: 'right', format: 'number' },
                            { key: 'turns', label: 'Devir', align: 'right', format: 'number' },
                            { key: 'avg_minutes', label: 'Ort. oturum', align: 'right', format: 'minutes' },
                            { key: 'revenue_minor', label: 'Ciro', align: 'right', format: 'minor' },
                        ]"
                        :rows="tables.data.value?.rows ?? []"
                        empty-text="Bu aralıkta masaya bağlı satış yok."
                    />
                </BaseCard>
            </div>
        </template>
    </div>
</template>
