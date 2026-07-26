<script setup lang="ts">
/**
 * Portal "Raporlarım": bugün/bu ay çalışılan saat + toplam mola/tuvalet
 * dakikası + mesai geçmişi (time_entries/breaks). Detaylı performans sonraki faz.
 */
import { onMounted, ref } from 'vue';
import { api } from '@/lib/http';
import { formatDate } from '@/lib/format';
import PortalLayout from '@/Layouts/PortalLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import type { PortalReports } from '@/types/portal';
import { formatMinutes } from '@/types/portal';

const data = ref<PortalReports | null>(null);
const loading = ref(true);

const timeFmt = new Intl.DateTimeFormat('tr-TR', { hour: '2-digit', minute: '2-digit' });
const clockTime = (iso: string | null): string => (iso ? timeFmt.format(new Date(iso)) : '—');

async function load(): Promise<void> {
    try {
        data.value = await api<PortalReports>('/api/v1/portal/reports');
    } catch {
        /* sessiz */
    } finally {
        loading.value = false;
    }
}

onMounted(load);
</script>

<template>
    <PortalLayout title="Raporlarım" active="reports">
        <div v-if="loading" class="rounded-xl border border-(--ui-border) bg-raised p-6 text-center text-sm text-muted">
            Yükleniyor…
        </div>

        <template v-else-if="data">
            <!-- Bugün / Bu ay özet -->
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div class="rounded-xl border border-(--ui-border) bg-raised p-4 shadow-(--shadow-card)">
                    <p class="text-xs font-medium text-subtle">Bugün</p>
                    <p class="mt-1 text-2xl font-bold text-body">{{ formatMinutes(data.today.worked_min) }}</p>
                    <p class="mt-2 text-xs text-muted">
                        Mola {{ formatMinutes(data.today.break_min) }} · Tuvalet {{ formatMinutes(data.today.toilet_min) }}
                    </p>
                </div>
                <div class="rounded-xl border border-(--ui-border) bg-raised p-4 shadow-(--shadow-card)">
                    <p class="text-xs font-medium text-subtle">Bu ay</p>
                    <p class="mt-1 text-2xl font-bold text-body">{{ formatMinutes(data.month.worked_min) }}</p>
                    <p class="mt-2 text-xs text-muted">
                        {{ data.month.entries }} mesai · Mola {{ formatMinutes(data.month.break_min) }} · Tuvalet {{ formatMinutes(data.month.toilet_min) }}
                    </p>
                </div>
            </div>

            <!-- Geçmiş -->
            <p class="mb-2 mt-6 text-sm font-semibold text-body">Mesai geçmişi</p>

            <div v-if="!data.history.length" class="rounded-xl border border-(--ui-border) bg-raised p-6 text-center text-sm text-muted">
                Bu ay henüz mesai kaydı yok.
            </div>

            <ul v-else class="flex flex-col divide-y divide-(--ui-border) overflow-hidden rounded-xl border border-(--ui-border) bg-raised">
                <li v-for="row in data.history" :key="row.id" class="flex items-center gap-3 px-4 py-3">
                    <span class="flex size-9 shrink-0 items-center justify-center rounded-full bg-(--color-inset) text-muted">
                        <AppIcon :name="row.status === 'open' ? 'clock' : 'check'" :size="16" />
                    </span>
                    <div class="min-w-0 flex-1">
                        <p class="text-sm font-medium text-body">{{ formatDate(row.date) }}</p>
                        <p class="text-xs text-muted">
                            {{ clockTime(row.clock_in_at) }} – {{ row.clock_out_at ? clockTime(row.clock_out_at) : 'sürüyor' }}
                        </p>
                    </div>
                    <div class="text-right">
                        <p class="text-sm font-semibold text-body">{{ formatMinutes(row.worked_min) }}</p>
                        <p v-if="row.break_min || row.toilet_min" class="text-xs text-muted">
                            mola {{ formatMinutes(row.break_min + row.toilet_min) }}
                        </p>
                    </div>
                </li>
            </ul>
        </template>
    </PortalLayout>
</template>
