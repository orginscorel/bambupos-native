<script setup lang="ts">
import { computed, toRef } from 'vue';
import { formatCurrencyMinor, formatNumber } from '@/lib/format';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import ChartStackedBar from '../components/ChartStackedBar.vue';
import ReportTable from '../components/ReportTable.vue';
import ExportButtons from '../components/ExportButtons.vue';
import StatTile from '../components/StatTile.vue';
import { useReport, type FinanceSummary, type PaymentMethodRow, type ReportFilterState } from '../reports';

const props = defineProps<{ filters: ReportFilterState }>();
const filters = toRef(props, 'filters');

const summary = useReport<FinanceSummary>('finance-summary', filters);
const vat = useReport<{ rows: { rate: number; gross_minor: number; vat_minor: number; net_minor: number }[] }>('finance-vat', filters);
const methods = useReport<{ total_minor: number; rows: PaymentMethodRow[]; refunds: { label: string; count: number; amount_minor: number }[] }>('finance-payment-methods', filters);
const cash = useReport<{ rows: Record<string, unknown>[] }>('finance-cash-sessions', filters);
const openAccounts = useReport<{ open_orders: Record<string, unknown>[]; on_account: { count: number; amount_minor: number } }>('finance-open-accounts', filters);

const s = computed(() => summary.data.value);

/** Ödeme yöntemi payları: sabit sıra caller'da (tutara göre ilk 4 + Diğer). */
const methodSegments = computed(() => {
    const rows = methods.data.value?.rows ?? [];
    const head = rows.slice(0, 4).map((r, i) => ({
        label: r.label,
        value: r.amount_minor,
        colorIndex: i,
        hint: `${formatNumber(r.count)} işlem`,
    }));
    const tail = rows.slice(4);
    if (tail.length > 0) {
        head.push({
            label: 'Diğer',
            value: tail.reduce((sum, r) => sum + r.amount_minor, 0),
            colorIndex: 4,
            hint: `${tail.length} yöntem`,
        });
    }
    return head;
});

/** Kesintiler tablosu — brütten nete iniş, tek yerde. */
const deductionRows = computed(() => {
    if (s.value === null) return [];
    return [
        { name: 'Kalem toplamı (indirim öncesi)', amount_minor: s.value.items_total_minor },
        { name: 'Adisyon indirimi', amount_minor: -s.value.order_discount_minor },
        { name: 'Satır indirimi', amount_minor: -s.value.item_discount_minor },
        { name: 'İkram (bedelsiz değer)', amount_minor: -s.value.comp_minor },
        { name: 'Servis bedeli', amount_minor: s.value.service_charge_minor },
        { name: 'Yuvarlama', amount_minor: s.value.rounding_minor },
        { name: 'Satış toplamı (KDV dahil)', amount_minor: s.value.gross_minor },
        { name: 'KDV', amount_minor: -s.value.vat_minor },
        { name: 'Net satış (KDV hariç)', amount_minor: s.value.net_minor },
    ];
});
</script>

<template>
    <div class="flex flex-col gap-4">
        <p v-if="summary.error.value" class="text-sm text-danger">{{ summary.error.value }}</p>

        <div v-if="s" class="grid grid-cols-2 gap-3 xl:grid-cols-4">
            <StatTile label="Brüt satış (KDV dahil)" :value="formatCurrencyMinor(s.gross_minor)" :hint="`${formatNumber(s.orders)} adisyon`" />
            <StatTile label="Net satış (KDV hariç)" :value="formatCurrencyMinor(s.net_minor)" :hint="`KDV ${formatCurrencyMinor(s.vat_minor)}`" />
            <StatTile label="Tahsilat" :value="formatCurrencyMinor(s.collected_minor)" :hint="`${formatNumber(s.collected_count)} işlem · bahşiş ${formatCurrencyMinor(s.tips_minor)}`" />
            <StatTile label="İade" :value="formatCurrencyMinor(s.refund_payments_minor)" :hint="`${formatNumber(s.refund_payments_count)} işlem`" />
        </div>

        <BaseCard title="Ödeme yöntemleri kırılımı">
            <template #actions>
                <ExportButtons report="finance-payment-methods" :filters="filters" />
            </template>
            <ChartStackedBar
                v-if="methodSegments.length > 0"
                :segments="methodSegments"
                money
                label="Ödeme yöntemi bazında tahsilat payı"
            />
            <EmptyState
                v-else
                icon="cart"
                title="Bu aralıkta tahsilat yok"
                description="Kasadan ödeme alındığında yöntem kırılımı burada görünür."
            />
            <div v-if="(methods.data.value?.refunds.length ?? 0) > 0" class="mt-3 border-t border-default pt-3">
                <p class="mb-1 text-xs font-semibold text-muted">İadeler</p>
                <p v-for="r in methods.data.value!.refunds" :key="r.label" class="text-sm text-muted">
                    {{ r.label }}: <span class="font-medium text-danger">−{{ formatCurrencyMinor(r.amount_minor) }}</span>
                    ({{ formatNumber(r.count) }} işlem)
                </p>
            </div>
        </BaseCard>

        <div class="grid gap-4 xl:grid-cols-2">
            <BaseCard title="Brütten nete" flush>
                <template #actions>
                    <ExportButtons report="finance-summary" :filters="filters" />
                </template>
                <ReportTable
                    :columns="[
                        { key: 'name', label: 'Kalem' },
                        { key: 'amount_minor', label: 'Tutar', align: 'right', format: 'minor' },
                    ]"
                    :rows="deductionRows"
                />
                <div v-if="s" class="border-t border-default px-3 py-2 text-sm text-muted">
                    İptal edilen {{ formatNumber(s.cancelled_orders) }} adisyon
                    ({{ formatCurrencyMinor(s.cancelled_minor) }}) satışa DAHİL DEĞİLDİR.
                </div>
            </BaseCard>

            <BaseCard title="KDV dağılımı" flush>
                <template #actions>
                    <ExportButtons report="finance-vat" :filters="filters" />
                </template>
                <ReportTable
                    :columns="[
                        { key: 'rate', label: 'KDV oranı', format: 'percent' },
                        { key: 'gross_minor', label: 'Brüt', align: 'right', format: 'minor' },
                        { key: 'vat_minor', label: 'KDV', align: 'right', format: 'minor' },
                        { key: 'net_minor', label: 'Net', align: 'right', format: 'minor' },
                    ]"
                    :rows="vat.data.value?.rows ?? []"
                />
            </BaseCard>
        </div>

        <BaseCard title="Kasa oturumları ve kasa farkı" flush>
            <template #actions>
                <ExportButtons report="finance-cash-sessions" :filters="filters" />
            </template>
            <ReportTable
                :columns="[
                    { key: 'z_number', label: 'Z No', format: 'number' },
                    { key: 'register', label: 'Kasa' },
                    { key: 'opened_by', label: 'Açan' },
                    { key: 'status', label: 'Durum' },
                    { key: 'expected_minor', label: 'Beklenen', align: 'right', format: 'minor' },
                    { key: 'counted_minor', label: 'Sayılan', align: 'right', format: 'minor' },
                    { key: 'difference_minor', label: 'Fark', align: 'right', format: 'minor' },
                ]"
                :rows="cash.data.value?.rows ?? []"
                empty-text="Bu aralıkta kasa oturumu yok."
            >
                <template #cell-status="{ value }">
                    <BaseBadge :variant="value === 'open' ? 'warning' : 'neutral'">
                        {{ value === 'open' ? 'Açık' : 'Kapalı (Z)' }}
                    </BaseBadge>
                </template>
            </ReportTable>
        </BaseCard>

        <BaseCard title="Açık hesap / bakiyeli adisyonlar" flush>
            <template #actions>
                <ExportButtons report="finance-open-accounts" :filters="filters" />
            </template>
            <div v-if="openAccounts.data.value" class="border-b border-default px-4 py-2 text-sm text-muted">
                Açık hesap (cari) tahsilatı:
                <span class="font-medium text-body">{{ formatCurrencyMinor(openAccounts.data.value.on_account.amount_minor) }}</span>
                ({{ formatNumber(openAccounts.data.value.on_account.count) }} işlem)
            </div>
            <ReportTable
                :columns="[
                    { key: 'id', label: 'Adisyon', format: 'number' },
                    { key: 'table', label: 'Masa' },
                    { key: 'customer', label: 'Müşteri' },
                    { key: 'total_minor', label: 'Tutar', align: 'right', format: 'minor' },
                    { key: 'paid_minor', label: 'Ödenen', align: 'right', format: 'minor' },
                    { key: 'balance_minor', label: 'Bakiye', align: 'right', format: 'minor' },
                ]"
                :rows="openAccounts.data.value?.open_orders ?? []"
                empty-text="Bakiyesi kalan adisyon yok."
            />
        </BaseCard>
    </div>
</template>
