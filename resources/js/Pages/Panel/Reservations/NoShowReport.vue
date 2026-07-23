<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import DataTable, { type TableColumn } from '@/Components/ui/DataTable.vue';
import FormField from '@/Components/ui/FormField.vue';
import ReservationsNav from './ReservationsNav.vue';
import { formatMinor, isoDate, addDays, type NoShowReport } from './reservations';

/** No-show raporu: aralık özeti + tekrar eden müşteriler + kayıt dökümü. */
const { danger } = useToast();

const from = ref(isoDate(addDays(new Date(), -30)));
const to = ref(isoDate(new Date()));
const loading = ref(true);
const report = ref<NoShowReport | null>(null);

async function load(): Promise<void> {
    loading.value = true;
    try {
        const params = new URLSearchParams({ from: from.value, to: to.value });
        const res = await api<{ report: NoShowReport }>(`/api/v1/reservations/reports/no-show?${params}`);
        report.value = res.report;
    } catch (e) {
        danger('Rapor yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

const offenderColumns: TableColumn[] = [
    { key: 'customer_name', label: 'Müşteri' },
    { key: 'customer_phone', label: 'Telefon' },
    { key: 'no_show_count', label: 'No-show sayısı', align: 'right', widthClass: 'w-36' },
];

const rowColumns: TableColumn[] = [
    { key: 'when', label: 'Tarih / Saat', widthClass: 'w-40' },
    { key: 'customer', label: 'Müşteri' },
    { key: 'party_size', label: 'Kişi', align: 'right', widthClass: 'w-16' },
    { key: 'tables', label: 'Masa' },
    { key: 'deposit', label: 'Kapora', align: 'right', widthClass: 'w-40' },
];
</script>

<template>
    <Head title="No-Show Raporu" />
    <PanelShell title="No-Show Raporu">
        <ReservationsNav />

        <div class="flex flex-col gap-4">
            <BaseCard>
                <form class="flex flex-wrap items-end gap-3" @submit.prevent="load">
                    <div class="w-40">
                        <FormField label="Başlangıç">
                            <BaseInput v-model="from" type="date" />
                        </FormField>
                    </div>
                    <div class="w-40">
                        <FormField label="Bitiş">
                            <BaseInput v-model="to" type="date" />
                        </FormField>
                    </div>
                    <BaseButton type="submit" :loading="loading">
                        <AppIcon name="chart" :size="16" />
                        Raporu getir
                    </BaseButton>
                </form>
            </BaseCard>

            <template v-if="report">
                <!-- Özet kartları -->
                <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
                    <BaseCard>
                        <p class="text-xs text-muted">Toplam rezervasyon</p>
                        <p class="mt-1 text-2xl font-semibold tabular-nums text-body">{{ report.total }}</p>
                    </BaseCard>
                    <BaseCard>
                        <p class="text-xs text-muted">Gelmedi (no-show)</p>
                        <p class="mt-1 text-2xl font-semibold tabular-nums text-danger">{{ report.no_shows }}</p>
                    </BaseCard>
                    <BaseCard>
                        <p class="text-xs text-muted">No-show oranı</p>
                        <p class="mt-1 text-2xl font-semibold tabular-nums text-body">%{{ report.no_show_rate }}</p>
                    </BaseCard>
                    <BaseCard>
                        <p class="text-xs text-muted">Tamamlanan</p>
                        <p class="mt-1 text-2xl font-semibold tabular-nums text-success">{{ report.completed }}</p>
                    </BaseCard>
                    <BaseCard>
                        <p class="text-xs text-muted">Yanan kapora</p>
                        <p class="mt-1 text-2xl font-semibold tabular-nums text-body">{{ formatMinor(report.forfeited_deposit_minor) }}</p>
                    </BaseCard>
                </div>

                <!-- Tekrar edenler -->
                <BaseCard flush title="Tekrar eden no-show müşterileri">
                    <DataTable
                        :columns="offenderColumns"
                        :rows="report.repeat_offenders as unknown as Record<string, unknown>[]"
                        row-key="customer_phone"
                        empty-title="Tekrar eden no-show yok"
                        empty-description="Seçili aralıkta aynı telefonla birden fazla no-show kaydı bulunmadı."
                        caption="Tekrar eden no-show müşterileri"
                    >
                        <template #cell-no_show_count="{ row }">
                            <BaseBadge variant="danger">{{ (row as { no_show_count: number }).no_show_count }}×</BaseBadge>
                        </template>
                    </DataTable>
                </BaseCard>

                <!-- Döküm -->
                <BaseCard flush title="No-show kayıtları">
                    <DataTable
                        :columns="rowColumns"
                        :rows="report.rows as unknown as Record<string, unknown>[]"
                        :loading="loading"
                        empty-title="Kayıt yok"
                        empty-description="Seçili aralıkta no-show rezervasyon bulunmadı."
                        caption="No-show kayıtları"
                    >
                        <template #cell-when="{ row }">
                            <span class="tabular-nums">{{ (row as never as { reserved_date: string }).reserved_date }} {{ (row as never as { reserved_time: string }).reserved_time }}</span>
                        </template>
                        <template #cell-customer="{ row }">
                            <div class="flex flex-col">
                                <span class="font-medium">{{ (row as never as { customer_name: string }).customer_name }}</span>
                                <span class="text-xs text-muted">{{ (row as never as { customer_phone: string | null }).customer_phone ?? '—' }}</span>
                            </div>
                        </template>
                        <template #cell-tables="{ row }">
                            {{ ((row as never as { tables: { name: string }[] }).tables ?? []).map((t) => t.name).join(', ') || '—' }}
                        </template>
                        <template #cell-deposit="{ row }">
                            <span v-if="(row as never as { deposit_minor: number }).deposit_minor > 0">
                                {{ formatMinor((row as never as { deposit_minor: number }).deposit_minor) }}
                                · {{ (row as never as { deposit_status_label: string }).deposit_status_label }}
                            </span>
                            <span v-else class="text-muted">—</span>
                        </template>
                    </DataTable>
                </BaseCard>
            </template>
        </div>
    </PanelShell>
</template>
