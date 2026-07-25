<script setup lang="ts">
import { toRef } from 'vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import ReportTable from '../components/ReportTable.vue';
import ExportButtons from '../components/ExportButtons.vue';
import { useReport, type ReportFilterState } from '../reports';

/**
 * Personel performansı — DENGELİ metrik seti (prompt §7). Tek "en iyi"
 * sıralaması yok: satış tutarının yanında servis süresi, indirim/ikram/
 * iptal oranı ve karşılanan servis talepleri birlikte okunur.
 */
const props = defineProps<{ filters: ReportFilterState }>();
const filters = toRef(props, 'filters');

const report = useReport<{ rows: Record<string, unknown>[] }>('staff-performance', filters);
</script>

<template>
    <div class="flex flex-col gap-4">
        <p v-if="report.error.value" class="text-sm text-danger">{{ report.error.value }}</p>

        <BaseCard title="Personel performansı" flush>
            <template #actions>
                <ExportButtons report="staff-performance" :filters="filters" />
            </template>
            <ReportTable
                :columns="[
                    { key: 'name', label: 'Personel' },
                    { key: 'orders', label: 'Sipariş', align: 'right', format: 'number' },
                    { key: 'items', label: 'Kalem', align: 'right', format: 'number' },
                    { key: 'sales_minor', label: 'Satış', align: 'right', format: 'minor' },
                    { key: 'avg_basket_minor', label: 'Ort. sepet', align: 'right', format: 'minor' },
                    { key: 'avg_service_minutes', label: 'Ort. servis', align: 'right', format: 'minutes' },
                    { key: 'discount_minor', label: 'İndirim', align: 'right', format: 'minor' },
                    { key: 'comp_count', label: 'İkram', align: 'right', format: 'number' },
                    { key: 'cancelled', label: 'İptal', align: 'right', format: 'number' },
                    { key: 'cancel_rate', label: 'İptal oranı', align: 'right', format: 'percent' },
                    { key: 'requests_handled', label: 'Talep', align: 'right', format: 'number' },
                ]"
                :rows="report.data.value?.rows ?? []"
                empty-text="Bu aralıkta personele bağlanabilen işlem yok."
            />
            <p class="border-t border-default px-4 py-2 text-xs text-subtle">
                Not: bu tablo bilinçli olarak tek bir "en iyi" sıralaması sunmaz. Yüksek satış, yüksek iptal ya da
                bol indirimle birlikte geliyorsa iyi performans değildir; sütunları birlikte değerlendirin.
            </p>
        </BaseCard>
    </div>
</template>
