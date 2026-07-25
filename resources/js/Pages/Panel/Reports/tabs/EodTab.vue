<script setup lang="ts">
import { computed, toRef } from 'vue';
import { formatCurrencyMinor, formatNumber } from '@/lib/format';
import BaseCard from '@/Components/ui/BaseCard.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import ChartColumn from '../components/ChartColumn.vue';
import ChartStackedBar from '../components/ChartStackedBar.vue';
import ExportButtons from '../components/ExportButtons.vue';
import StatTile from '../components/StatTile.vue';
import ReportTable from '../components/ReportTable.vue';
import {
    useReport,
    type EodSummary,
    type HourPoint,
    type PaymentMethodRow,
    type ReceivablesReport,
    type ReportFilterState,
} from '../reports';

/**
 * Gün sonu raporu (operasyonel özet, Z BENZERİ ama kasa Z raporunun
 * YERİNE GEÇMEZ — o Ödemeler modülünde ayrıdır). Seçilen tarih aralığı
 * için ciro, açılan/kapanan adisyon, ortalama sepet, kişi sayısı,
 * iptal/ikram/indirim/iade toplamları + ödeme yöntemi kırılımı + en
 * yoğun saatler TEK ekranda. Ödeme kırılımı ve saatlik dağılım ZATEN
 * ayrı raporlar (finance-payment-methods, sales-hourly) — burada
 * TEKRAR HESAPLANMAZ, aynı filtreyle tekrar çekilir (tek doğruluk
 * kaynağı, kopya SQL yok).
 */
const props = defineProps<{ filters: ReportFilterState }>();
const filters = toRef(props, 'filters');

const eod = useReport<EodSummary>('ops-eod', filters);
const methods = useReport<{ total_minor: number; rows: PaymentMethodRow[] }>('finance-payment-methods', filters);
const hourly = useReport<{ hours: HourPoint[] }>('sales-hourly', filters);
const receivables = useReport<ReceivablesReport>('ops-open-receivables', filters);

const s = computed(() => eod.data.value);
const hasActivity = computed(() => (s.value?.orders ?? 0) > 0 || (s.value?.orders_opened ?? 0) > 0);

const methodSegments = computed(() => {
    const rows = methods.data.value?.rows ?? [];
    const head = rows.slice(0, 4).map((r, i) => ({ label: r.label, value: r.amount_minor, colorIndex: i, hint: `${formatNumber(r.count)} işlem` }));
    const tail = rows.slice(4);
    if (tail.length > 0) {
        head.push({ label: 'Diğer', value: tail.reduce((sum, r) => sum + r.amount_minor, 0), colorIndex: 4, hint: `${tail.length} yöntem` });
    }
    return head;
});

const hourPoints = computed(() =>
    (hourly.data.value?.hours ?? []).map((h) => ({
        label: `${String(h.hour).padStart(2, '0')}`,
        title: `${String(h.hour).padStart(2, '0')}:00 – ${String(h.hour).padStart(2, '0')}:59`,
        value: h.orders,
    })),
);

const busiestHours = computed(() =>
    [...(hourly.data.value?.hours ?? [])]
        .filter((h) => h.orders > 0)
        .sort((a, b) => b.orders - a.orders)
        .slice(0, 3),
);
</script>

<template>
    <div class="flex flex-col gap-4">
        <p v-if="eod.error.value" class="text-sm text-danger">{{ eod.error.value }}</p>

        <div class="flex items-center justify-between">
            <p class="text-xs text-subtle">
                Seçilen aralık: <span class="font-medium text-muted">{{ filters.from }} – {{ filters.to }}</span>
                — kasa Z raporundan bağımsız operasyonel özet.
            </p>
            <ExportButtons report="ops-eod" :filters="filters" />
        </div>

        <EmptyState
            v-if="s && !hasActivity"
            icon="chart"
            title="Bu aralıkta hareket yok"
            description="Adisyon açıldıkça gün sonu özeti (ciro, açılan/kapanan adisyon, ödeme kırılımı) burada oluşur."
        />

        <template v-else-if="s">
            <div class="grid grid-cols-2 gap-3 xl:grid-cols-4">
                <StatTile label="Ciro (borç dahil)" :value="formatCurrencyMinor(s.revenue_minor)" :hint="`${formatNumber(s.orders)} kapandı — ödendi + borca taşındı`" />
                <StatTile label="Ortalama sepet" :value="s.orders > 0 ? formatCurrencyMinor(s.avg_basket_minor) : '—'" />
                <StatTile
                    label="Kişi başı harcama"
                    :value="s.per_guest_minor !== null ? formatCurrencyMinor(s.per_guest_minor) : '—'"
                    :hint="s.per_guest_minor !== null ? `${formatNumber(s.guests)} misafir girildi` : 'Misafir sayısı girilmemiş'"
                />
                <StatTile label="Tahsil edilen" :value="formatCurrencyMinor(s.collected_minor)" :hint="`${formatNumber(s.collected_count)} işlem · yalnız kasaya giren · bahşiş ${formatCurrencyMinor(s.tips_minor)}`" />
            </div>

            <!-- Ciro vs Tahsilat netliği (#9): borca taşınan tutar ciroya dahil ama henüz tahsil edilmedi -->
            <p v-if="s.debt_transferred_balance_minor > 0" class="-mt-1 text-xs text-subtle">
                "Ciro (borç dahil)" içine borca taşınan
                <span class="font-medium text-muted">{{ formatCurrencyMinor(s.debt_transferred_balance_minor) }}</span>
                dahildir — {{ formatNumber(s.debt_transferred_count) }} adisyon cariye yazıldı, henüz tahsil edilmedi.
                "Tahsil edilen" yalnız kasaya fiilen giren tutardır.
            </p>

            <div class="grid grid-cols-2 gap-3 xl:grid-cols-4">
                <StatTile label="Açılan adisyon" :value="formatNumber(s.orders_opened)" hint="bu aralıkta sipariş verildi" />
                <StatTile label="Kapanan adisyon" :value="formatNumber(s.orders_closed)" hint="tam ödenip kapandı" />
                <StatTile label="İndirim" :value="formatCurrencyMinor(s.discount_total_minor)" hint="adisyon + satır indirimi" />
                <StatTile
                    label="İkram (maliyet)"
                    :value="formatCurrencyMinor(s.comp_minor)"
                    :hint="s.comp_count > 0
                        ? `${formatNumber(s.comp_count)} adet · stok maliyeti ${formatCurrencyMinor(s.comp_cost_minor)}`
                        : 'bedelsiz değer'"
                    :up-is-good="false"
                />
            </div>

            <div class="grid grid-cols-2 gap-3 xl:grid-cols-4">
                <StatTile
                    label="İptal"
                    :value="formatNumber(s.cancelled_orders)"
                    :hint="s.cancelled_orders > 0 ? formatCurrencyMinor(s.cancelled_minor) : ''"
                    :up-is-good="false"
                />
                <StatTile
                    label="İade"
                    :value="formatCurrencyMinor(s.refunded_minor)"
                    :hint="s.refund_payments_count > 0 ? `${formatNumber(s.refund_payments_count)} işlem` : ''"
                    :up-is-good="false"
                />
                <StatTile
                    label="Açık borç (güncel)"
                    :value="s.open_receivables_available ? formatCurrencyMinor(s.open_receivables_total_minor ?? 0) : '—'"
                    :hint="
                        s.open_receivables_available
                            ? `${formatNumber(s.open_receivables_count)} cari hesap`
                            : 'Cari modülü henüz aktif değil'
                    "
                    :up-is-good="false"
                />
                <StatTile
                    label="Açık masa tutarı (anlık)"
                    :value="formatCurrencyMinor(s.open_table_minor)"
                    :hint="`${formatNumber(s.open_table_orders)} adisyon — Ciro DEĞİL, henüz kapanmadı`"
                    :up-is-good="false"
                />
            </div>

            <div class="grid gap-4 xl:grid-cols-2">
                <BaseCard title="Ödeme yöntemi kırılımı">
                    <ChartStackedBar v-if="methodSegments.length > 0" :segments="methodSegments" money label="Gün sonu ödeme yöntemi payı" />
                    <EmptyState v-else icon="cart" title="Tahsilat yok" description="Bu aralıkta kasadan ödeme alınmadı." />
                </BaseCard>

                <BaseCard title="Yoğun saatler">
                    <ChartColumn v-if="hourPoints.some((p) => p.value > 0)" :points="hourPoints" :label-every="3" label="Saat başına sipariş adedi" />
                    <EmptyState v-else icon="chart" title="Veri yok" description="Bu aralıkta saatlik dağılım hesaplanamadı." />
                    <ul v-if="busiestHours.length > 0" class="mt-3 flex flex-wrap gap-2 border-t border-default pt-3">
                        <li
                            v-for="h in busiestHours"
                            :key="h.hour"
                            class="rounded-md border border-default bg-inset px-2.5 py-1 text-xs text-muted"
                        >
                            <span class="font-semibold text-body">{{ String(h.hour).padStart(2, '0') }}:00</span>
                            — {{ formatNumber(h.orders) }} sipariş
                        </li>
                    </ul>
                </BaseCard>
            </div>

            <BaseCard title="Açık cariler (borç hesapları)" flush>
                <template #actions>
                    <ExportButtons v-if="receivables.data.value?.available" report="ops-open-receivables" :filters="filters" />
                </template>
                <p v-if="receivables.error.value" class="px-4 py-3 text-sm text-danger">{{ receivables.error.value }}</p>

                <EmptyState
                    v-else-if="receivables.data.value && !receivables.data.value.available"
                    icon="user"
                    title="Cari modülü henüz aktif değil"
                    description="Cari hesap (borç takibi) modülü tamamlanınca açık bakiyeler ve kimin hesabı olduğu burada listelenecek."
                />

                <template v-else-if="receivables.data.value">
                    <div v-if="receivables.data.value.count > 0" class="border-b border-default px-4 py-2 text-sm text-muted">
                        Toplam açık bakiye:
                        <span class="font-semibold text-body">{{ formatCurrencyMinor(receivables.data.value.total_minor ?? 0) }}</span>
                        ({{ formatNumber(receivables.data.value.count) }} cari hesap)
                    </div>
                    <ReportTable
                        :columns="[
                            { key: 'name', label: 'Cari' },
                            { key: 'phone', label: 'Telefon' },
                            { key: 'balance_minor', label: 'Bakiye', align: 'right', format: 'minor' },
                        ]"
                        :rows="receivables.data.value.rows"
                        empty-text="Açık (bakiyesi olan) cari hesap yok."
                    />
                    <p class="border-t border-default px-4 py-2 text-xs text-subtle">
                        Bakiye GÜNCEL toplamdır (seçili tarih aralığından bağımsız). Hangi adisyondan/ne zaman
                        borca taşındığı, cari modülünün hareket dökümü tamamlanınca eklenecek.
                    </p>
                </template>
            </BaseCard>
        </template>
    </div>
</template>
