<script setup lang="ts">
import { onMounted, ref, watch } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BaseTabs from '@/Components/ui/BaseTabs.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import ShiftsShell from './components/ShiftsShell.vue';
import type { AttendanceRow, PerformanceRow } from './types';
import { LEAVE_TYPE_LABELS } from './types';
import { fmtMin, fmtMoney, ymd } from './lib';

/**
 * /panel/mesai/performans — iki sekme:
 * - Devam: çalışılan süre / fazla mesai / eksik / geç / izin / devamsızlık.
 * - Performans: DENGELİ metrik seti (yalnız ciro değil): sipariş sayısı,
 *   ortalama servis süresi, iptal oranı, indirim/ikram oranı, masa devri.
 */
const { danger } = useToast();

const tab = ref('attendance');
const tabs = [
    { key: 'attendance', label: 'Devam Takibi' },
    { key: 'performance', label: 'Performans' },
];

const monthStart = new Date();
monthStart.setDate(1);
const from = ref(ymd(monthStart));
const to = ref(ymd(new Date()));

const loading = ref(true);
const attendance = ref<AttendanceRow[]>([]);
const performance = ref<PerformanceRow[]>([]);

async function load(): Promise<void> {
    loading.value = true;
    try {
        const range = `from=${from.value}&to=${ymd(new Date(new Date(to.value + 'T00:00:00').getTime() + 86400000))}`;
        const [att, perf] = await Promise.all([
            api<{ summary: AttendanceRow[] }>(`/api/v1/shifts/attendance-summary?${range}`),
            api<{ metrics: PerformanceRow[] }>(`/api/v1/shifts/performance?${range}`),
        ]);
        attendance.value = att.summary;
        performance.value = perf.metrics;
    } catch (e) {
        if (e instanceof ApiError) danger('Veriler yüklenemedi', e.displayMessage);
    } finally {
        loading.value = false;
    }
}

onMounted(load);
watch([from, to], () => void load());

function leaveSummary(row: AttendanceRow): string {
    const parts = Object.entries(row.leave_days)
        .filter(([, days]) => days > 0)
        .map(([type, days]) => `${LEAVE_TYPE_LABELS[type] ?? type}: ${days}g`);
    if (row.auto_absent_days > 0) parts.push(`Gelmedi: ${row.auto_absent_days}g`);
    return parts.length ? parts.join(', ') : '—';
}
</script>

<template>
    <Head title="Performans" />
    <ShiftsShell title="Devam & Performans">
        <div class="flex flex-col gap-4">
            <div class="flex flex-wrap items-center justify-between gap-2">
                <BaseTabs v-model="tab" :tabs="tabs" />
                <div class="flex items-center gap-2">
                    <BaseInput v-model="from" type="date" size="sm" class="w-38" />
                    <span class="text-xs text-muted">—</span>
                    <BaseInput v-model="to" type="date" size="sm" class="w-38" />
                </div>
            </div>

            <BaseSkeleton v-if="loading" class="h-64 w-full" />

            <!-- Devam -->
            <BaseCard v-else-if="tab === 'attendance'" flush>
                <EmptyState v-if="attendance.length === 0" title="Veri yok" />
                <div v-else class="overflow-x-auto">
                    <table class="w-full min-w-[860px] text-sm">
                        <thead>
                            <tr class="border-b border-default text-left text-xs text-muted">
                                <th class="px-3 py-2 font-medium">Personel</th>
                                <th class="px-3 py-2 font-medium">Gün</th>
                                <th class="px-3 py-2 font-medium">Çalışılan</th>
                                <th class="px-3 py-2 font-medium">Fazla Mesai</th>
                                <th class="px-3 py-2 font-medium">Eksik</th>
                                <th class="px-3 py-2 font-medium">Geç Kalma</th>
                                <th class="px-3 py-2 font-medium">Erken Çıkış</th>
                                <th class="px-3 py-2 font-medium">İzin / Devamsızlık</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="row in attendance" :key="row.user.id" class="border-b border-default last:border-0 hover:bg-inset">
                                <td class="px-3 py-2">
                                    <p class="font-medium text-body">{{ row.user.name }}</p>
                                    <p v-if="row.user.position" class="text-xs text-muted">{{ row.user.position }}</p>
                                </td>
                                <td class="px-3 py-2">{{ row.days_worked }} / {{ row.planned_shifts }}</td>
                                <td class="px-3 py-2 font-medium text-body">{{ fmtMin(row.worked_min) }}</td>
                                <td class="px-3 py-2" :class="row.overtime_min > 0 ? 'text-success' : 'text-muted'">
                                    {{ row.overtime_min > 0 ? '+' + fmtMin(row.overtime_min) : '—' }}
                                </td>
                                <td class="px-3 py-2" :class="row.missing_min > 0 ? 'text-danger' : 'text-muted'">
                                    {{ row.missing_min > 0 ? '−' + fmtMin(row.missing_min) : '—' }}
                                </td>
                                <td class="px-3 py-2" :class="row.late_count > 0 ? 'text-warning' : 'text-muted'">
                                    {{ row.late_count > 0 ? `${row.late_count}× (${fmtMin(row.late_min)})` : '—' }}
                                </td>
                                <td class="px-3 py-2" :class="row.early_leave_count > 0 ? 'text-warning' : 'text-muted'">
                                    {{ row.early_leave_count > 0 ? row.early_leave_count + '×' : '—' }}
                                </td>
                                <td class="px-3 py-2 text-xs text-muted">{{ leaveSummary(row) }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </BaseCard>

            <!-- Performans -->
            <template v-else>
                <p class="text-xs text-muted">
                    Denge notu: bu tablo yalnız satış tutarına göre sıralanmaz; servis hızı, iptal ve indirim/ikram
                    oranları birlikte değerlendirilmelidir. Sipariş verileri adisyonu açan personele göre hesaplanır.
                </p>
                <BaseCard flush>
                    <EmptyState v-if="performance.length === 0" title="Veri yok" />
                    <div v-else class="overflow-x-auto">
                        <table class="w-full min-w-[960px] text-sm">
                            <thead>
                                <tr class="border-b border-default text-left text-xs text-muted">
                                    <th class="px-3 py-2 font-medium">Personel</th>
                                    <th class="px-3 py-2 font-medium">Sipariş</th>
                                    <th class="px-3 py-2 font-medium">Satış</th>
                                    <th class="px-3 py-2 font-medium">Ort. Servis</th>
                                    <th class="px-3 py-2 font-medium">İptal</th>
                                    <th class="px-3 py-2 font-medium">İndirim</th>
                                    <th class="px-3 py-2 font-medium">İkram</th>
                                    <th class="px-3 py-2 font-medium">Masa Devri</th>
                                </tr>
                            </thead>
                            <tbody>
                                <tr
                                    v-for="row in performance"
                                    :key="row.user.id"
                                    class="border-b border-default last:border-0 hover:bg-inset"
                                >
                                    <td class="px-3 py-2">
                                        <p class="font-medium text-body">{{ row.user.name }}</p>
                                        <p v-if="row.user.position" class="text-xs text-muted">{{ row.user.position }}</p>
                                    </td>
                                    <td class="px-3 py-2 font-medium text-body">{{ row.order_count }}</td>
                                    <td class="px-3 py-2">{{ fmtMoney(row.sales_minor) }}</td>
                                    <td class="px-3 py-2">{{ row.avg_service_min !== null ? fmtMin(row.avg_service_min) : '—' }}</td>
                                    <td class="px-3 py-2" :class="row.cancel_rate > 10 ? 'text-danger' : ''">
                                        %{{ row.cancel_rate }}
                                        <span v-if="row.cancelled_count" class="text-xs text-muted">({{ row.cancelled_count }})</span>
                                    </td>
                                    <td class="px-3 py-2">
                                        %{{ row.discount_rate }}
                                        <span v-if="row.discount_minor" class="text-xs text-muted">({{ fmtMoney(row.discount_minor) }})</span>
                                    </td>
                                    <td class="px-3 py-2">
                                        %{{ row.comp_rate }}
                                        <span v-if="row.comp_minor" class="text-xs text-muted">({{ fmtMoney(row.comp_minor) }})</span>
                                    </td>
                                    <td class="px-3 py-2">
                                        {{ row.table_turnover_min !== null ? fmtMin(row.table_turnover_min) : '—' }}
                                    </td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </BaseCard>
            </template>
        </div>
    </ShiftsShell>
</template>
