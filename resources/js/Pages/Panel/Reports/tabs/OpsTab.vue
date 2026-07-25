<script setup lang="ts">
import { computed, toRef } from 'vue';
import { formatNumber } from '@/lib/format';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import ChartColumn from '../components/ChartColumn.vue';
import ReportTable from '../components/ReportTable.vue';
import ExportButtons from '../components/ExportButtons.vue';
import { shortDay, useReport, type ReportFilterState } from '../reports';

const props = defineProps<{ filters: ReportFilterState }>();
const filters = toRef(props, 'filters');

const delayed = useReport<{ threshold_minutes: number; rows: Record<string, unknown>[] }>('ops-delayed', filters);
const stations = useReport<{ rows: Record<string, unknown>[] }>('ops-station-prep', filters);
const requests = useReport<{ rows: Record<string, unknown>[] }>('ops-service-requests', filters);
const cancels = useReport<{
    order_cancels: Record<string, unknown>[];
    item_cancels: Record<string, unknown>[];
    comps: Record<string, unknown>[];
}>('ops-cancellations', filters);
const usage = useReport<{
    orders_total: number;
    channels: { channel: string; label: string; orders: number; share: number }[];
    scans: { date: string; total: number; ok: number }[];
}>('ops-channel-usage', filters);

const scanPoints = computed(() =>
    (usage.data.value?.scans ?? []).map((s) => ({ label: shortDay(s.date), title: `${s.date} · ${s.ok} başarılı`, value: s.total })),
);

const qrShare = computed(() => {
    const rows = usage.data.value?.channels ?? [];
    const qr = rows.find((r) => r.channel === 'qr');
    const kiosk = rows.find((r) => r.channel === 'kiosk');
    return { qr, kiosk };
});
</script>

<template>
    <div class="flex flex-col gap-4">
        <!-- Geciken siparişler (anlık) -->
        <BaseCard flush>
            <template #header>
                <h2 class="text-sm font-semibold text-body">
                    Geciken siparişler
                    <span class="ml-1 font-normal text-subtle">
                        (şu an; {{ delayed.data.value?.threshold_minutes ?? 20 }} dk eşiği)
                    </span>
                </h2>
            </template>
            <template #actions>
                <ExportButtons report="ops-delayed" :filters="filters" />
            </template>
            <ReportTable
                :columns="[
                    { key: 'id', label: 'Adisyon', format: 'number' },
                    { key: 'table', label: 'Masa' },
                    { key: 'status_label', label: 'Durum' },
                    { key: 'age_minutes', label: 'Bekleme', align: 'right', format: 'minutes' },
                    { key: 'total_minor', label: 'Tutar', align: 'right', format: 'minor' },
                ]"
                :rows="delayed.data.value?.rows ?? []"
                empty-text="Şu an geciken sipariş yok."
            />
        </BaseCard>

        <div class="grid gap-4 xl:grid-cols-2">
            <BaseCard title="İstasyon hazırlama süreleri" flush>
                <template #actions>
                    <ExportButtons report="ops-station-prep" :filters="filters" />
                </template>
                <ReportTable
                    :columns="[
                        { key: 'station', label: 'İstasyon' },
                        { key: 'items', label: 'Kalem', align: 'right', format: 'number' },
                        { key: 'avg_minutes', label: 'Ortalama', align: 'right', format: 'minutes' },
                        { key: 'max_minutes', label: 'En uzun', align: 'right', format: 'minutes' },
                    ]"
                    :rows="stations.data.value?.rows ?? []"
                    empty-text="Bu aralıkta 'hazır' işaretlenmiş kalem yok — süre ölçülemedi."
                />
            </BaseCard>

            <BaseCard title="Servis talebine yanıt" flush>
                <template #actions>
                    <ExportButtons report="ops-service-requests" :filters="filters" />
                </template>
                <ReportTable
                    :columns="[
                        { key: 'label', label: 'Talep' },
                        { key: 'total', label: 'Toplam', align: 'right', format: 'number' },
                        { key: 'open', label: 'Açık', align: 'right', format: 'number' },
                        { key: 'avg_response_minutes', label: 'Ort. yanıt', align: 'right', format: 'minutes' },
                    ]"
                    :rows="requests.data.value?.rows ?? []"
                    empty-text="Bu aralıkta masadan servis talebi gelmedi."
                />
            </BaseCard>
        </div>

        <div class="grid gap-4 xl:grid-cols-3">
            <BaseCard title="Adisyon iptal nedenleri" flush>
                <template #actions>
                    <ExportButtons report="ops-cancellations" :filters="filters" />
                </template>
                <ReportTable
                    :columns="[
                        { key: 'reason', label: 'Neden' },
                        { key: 'count', label: 'Adet', align: 'right', format: 'number' },
                        { key: 'value_minor', label: 'Değer', align: 'right', format: 'minor' },
                    ]"
                    :rows="cancels.data.value?.order_cancels ?? []"
                    empty-text="Bu aralıkta adisyon iptali yok."
                />
            </BaseCard>

            <BaseCard title="Kalem iptal nedenleri" flush>
                <ReportTable
                    :columns="[
                        { key: 'reason', label: 'Neden' },
                        { key: 'count', label: 'Adet', align: 'right', format: 'number' },
                        { key: 'value_minor', label: 'Değer', align: 'right', format: 'minor' },
                    ]"
                    :rows="cancels.data.value?.item_cancels ?? []"
                    empty-text="Bu aralıkta kalem iptali yok."
                />
            </BaseCard>

            <BaseCard title="İkram nedenleri" flush>
                <ReportTable
                    :columns="[
                        { key: 'reason', label: 'Neden' },
                        { key: 'count', label: 'Adet', align: 'right', format: 'number' },
                        { key: 'value_minor', label: 'Değer', align: 'right', format: 'minor' },
                    ]"
                    :rows="cancels.data.value?.comps ?? []"
                    empty-text="Bu aralıkta ikram yok."
                />
            </BaseCard>
        </div>

        <BaseCard title="QR / Kiosk kullanımı">
            <template #actions>
                <ExportButtons report="ops-channel-usage" :filters="filters" />
            </template>
            <div class="mb-3 flex flex-wrap gap-2">
                <BaseBadge variant="success">
                    QR siparişi: {{ formatNumber(qrShare.qr?.orders ?? 0) }}
                    <template v-if="qrShare.qr"> (%{{ qrShare.qr.share.toFixed(1).replace('.', ',') }})</template>
                </BaseBadge>
                <BaseBadge variant="neutral">
                    Kiosk siparişi: {{ formatNumber(qrShare.kiosk?.orders ?? 0) }}
                    <template v-if="qrShare.kiosk"> (%{{ qrShare.kiosk.share.toFixed(1).replace('.', ',') }})</template>
                </BaseBadge>
            </div>
            <ChartColumn
                v-if="scanPoints.length > 0 && scanPoints.some((p) => p.value > 0)"
                :points="scanPoints"
                label="Günlük QR okutma sayısı"
            />
            <EmptyState
                v-else
                icon="qr-code"
                title="Bu aralıkta QR okutulmadı"
                description="Masalardaki QR kodlar okutuldukça günlük kullanım burada görünür."
            />
        </BaseCard>
    </div>
</template>
