<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import ShiftsShell from './components/ShiftsShell.vue';
import { fmtMin, fmtMoney } from './lib';

/**
 * /panel/mesai/maaslar — Maaş / Bordro.
 *  - Aylık sabit: tutar dönemden bağımsız sabit.
 *  - Saatlik: saat başı ücret; kazanç mesai (worked_min) üzerinden otomatik.
 * Yönetici her personelin maaş tipini + tutarını girer; ay/gün hak edişi anında.
 */
const { success, danger } = useToast();

interface Row {
    id: number;
    name: string;
    position: string | null;
    salary_type: 'monthly' | 'hourly' | null;
    salary_amount_minor: number | null;
    month_worked_min: number;
    today_worked_min: number;
    month_earned_minor: number;
    today_earned_minor: number;
    daily_rate_minor: number | null;
    // yerel düzenleme durumu
    _type: '' | 'monthly' | 'hourly';
    _amount: string;
    _saving: boolean;
}

const now = new Date();
const month = ref(`${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`);
const loading = ref(true);
const rows = ref<Row[]>([]);
const totals = ref({ month_earned_minor: 0, today_earned_minor: 0, month_worked_min: 0 });

const typeOptions = [
    { value: '', label: 'Tanımsız' },
    { value: 'monthly', label: 'Aylık sabit' },
    { value: 'hourly', label: 'Saatlik' },
];

async function load(): Promise<void> {
    loading.value = true;
    try {
        const res = await api<{ rows: Omit<Row, '_type' | '_amount' | '_saving'>[]; totals: typeof totals.value }>(
            `/api/v1/shifts/payroll?month=${month.value}`,
        );
        rows.value = res.rows.map((r) => ({
            ...r,
            _type: r.salary_type ?? '',
            _amount: r.salary_amount_minor ? String(r.salary_amount_minor / 100) : '',
            _saving: false,
        }));
        totals.value = res.totals;
    } catch (e) {
        if (e instanceof ApiError) danger('Maaş verileri yüklenemedi', e.displayMessage);
    } finally {
        loading.value = false;
    }
}

onMounted(load);
watch(month, () => void load());

const monthLabel = computed(() => {
    const [y, m] = month.value.split('-').map(Number);
    return new Date(y, m - 1, 1).toLocaleDateString('tr-TR', { month: 'long', year: 'numeric' });
});

async function save(row: Row): Promise<void> {
    if (row._saving) return;
    if (row._type !== '' && (!row._amount || Number(row._amount) <= 0)) {
        danger('Tutar gerekli', 'Maaş tipi seçtiyseniz tutar girin.');
        return;
    }
    row._saving = true;
    try {
        await api(`/api/v1/shifts/payroll/${row.id}`, {
            method: 'PUT',
            body: {
                salary_type: row._type || null,
                salary_amount: row._type ? Number(row._amount) : null,
            },
        });
        success('Maaş güncellendi', row.name);
        await load();
    } catch (e) {
        danger('Kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Tekrar deneyin.');
        row._saving = false;
    }
}

function dirty(row: Row): boolean {
    const savedType = row.salary_type ?? '';
    const savedAmount = row.salary_amount_minor ? String(row.salary_amount_minor / 100) : '';
    return row._type !== savedType || row._amount !== savedAmount;
}
</script>

<template>
    <Head title="Maaşlar" />
    <ShiftsShell title="Maaşlar & Bordro" active="payroll">
        <div class="flex flex-col gap-4">
            <!-- Dönem + özet -->
            <div class="flex flex-wrap items-end justify-between gap-3">
                <label class="flex flex-col gap-1">
                    <span class="text-xs font-medium text-muted">Dönem</span>
                    <input
                        v-model="month"
                        type="month"
                        class="h-10 rounded-lg border border-default bg-surface px-3 text-sm text-body"
                    />
                </label>
                <div class="grid grid-cols-3 gap-3">
                    <div class="rounded-xl border border-default bg-raised px-4 py-2.5">
                        <p class="text-xs font-medium text-muted">Bu ay toplam hak ediş</p>
                        <p class="mt-0.5 text-lg font-bold tabular-nums text-body">{{ fmtMoney(totals.month_earned_minor) }}</p>
                    </div>
                    <div class="rounded-xl border border-default bg-raised px-4 py-2.5">
                        <p class="text-xs font-medium text-muted">Bugün hak ediş</p>
                        <p class="mt-0.5 text-lg font-bold tabular-nums text-body">{{ fmtMoney(totals.today_earned_minor) }}</p>
                    </div>
                    <div class="rounded-xl border border-default bg-raised px-4 py-2.5">
                        <p class="text-xs font-medium text-muted">Toplam çalışılan</p>
                        <p class="mt-0.5 text-lg font-bold tabular-nums text-body">{{ fmtMin(totals.month_worked_min) }}</p>
                    </div>
                </div>
            </div>

            <BaseCard flush>
                <template v-if="loading">
                    <div class="p-4"><BaseSkeleton class="h-64" /></div>
                </template>
                <template v-else-if="rows.length === 0">
                    <EmptyState title="Personel yok" description="Aktif personel bulunamadı." icon="users" />
                </template>
                <template v-else>
                    <div class="overflow-x-auto">
                        <table class="w-full min-w-[880px] text-sm">
                            <thead>
                                <tr class="border-b border-default text-left text-xs font-semibold text-muted">
                                    <th class="px-4 py-3">Personel</th>
                                    <th class="px-3 py-3 w-40">Maaş tipi</th>
                                    <th class="px-3 py-3 w-40">Tutar (₺)</th>
                                    <th class="px-3 py-3 text-right">Bu ay çalışılan</th>
                                    <th class="px-3 py-3 text-right">Bu ay hak ediş</th>
                                    <th class="px-3 py-3 text-right">Bugün</th>
                                    <th class="px-3 py-3 w-24"></th>
                                </tr>
                            </thead>
                            <tbody>
                                <tr v-for="r in rows" :key="r.id" class="border-b border-default last:border-b-0">
                                    <td class="px-4 py-2.5">
                                        <p class="font-semibold text-body">{{ r.name }}</p>
                                        <p v-if="r.position" class="text-xs text-muted">{{ r.position }}</p>
                                    </td>
                                    <td class="px-3 py-2.5">
                                        <BaseSelect v-model="r._type" :options="typeOptions" size="sm" />
                                    </td>
                                    <td class="px-3 py-2.5">
                                        <BaseInput
                                            v-model="r._amount"
                                            :disabled="r._type === ''"
                                            inputmode="decimal"
                                            :placeholder="r._type === 'hourly' ? '₺/saat' : (r._type === 'monthly' ? '₺/ay' : '—')"
                                        />
                                    </td>
                                    <td class="px-3 py-2.5 text-right tabular-nums text-muted">{{ fmtMin(r.month_worked_min) }}</td>
                                    <td class="px-3 py-2.5 text-right font-semibold tabular-nums text-body">
                                        {{ r.salary_type ? fmtMoney(r.month_earned_minor) : '—' }}
                                    </td>
                                    <td class="px-3 py-2.5 text-right tabular-nums text-muted">
                                        {{ r.salary_type ? fmtMoney(r.today_earned_minor) : '—' }}
                                    </td>
                                    <td class="px-3 py-2.5 text-right">
                                        <BaseButton size="sm" :variant="dirty(r) ? 'primary' : 'ghost'" :disabled="!dirty(r)" :loading="r._saving" @click="save(r)">
                                            <AppIcon name="check" :size="14" />
                                            Kaydet
                                        </BaseButton>
                                    </td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </template>
            </BaseCard>

            <p class="flex items-start gap-2 rounded-lg border border-default bg-inset px-3 py-2.5 text-xs text-muted">
                <AppIcon name="info" :size="15" class="mt-0.5 shrink-0 text-subtle" />
                <span>
                    <strong class="text-body">Aylık sabit:</strong> tutar dönemden bağımsız sabittir (ör. 30.000 ₺/ay).
                    <strong class="text-body">Saatlik:</strong> hak ediş, personelin mesai giriş/çıkışından hesaplanan
                    gerçek çalışma süresi × saat ücreti ile otomatik hesaplanır. “{{ monthLabel }}” dönemi gösteriliyor.
                </span>
            </p>
        </div>
    </ShiftsShell>
</template>
