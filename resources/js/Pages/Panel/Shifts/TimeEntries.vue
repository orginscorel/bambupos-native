<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BasePagination from '@/Components/ui/BasePagination.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import ShiftsShell from './components/ShiftsShell.vue';
import type { Paginated, ShiftsMeta, TimeEntryRow } from './types';
import { fmtDate, fmtMin, fmtTime, ymd } from './lib';

/**
 * /panel/mesai — mesai kayıtları.
 * - staff.view yoksa yalnız kendi kayıtları görünür.
 * - Yönetici: nedenli manuel düzeltme (denetim kaydına düşer) + onay.
 */
const { success, danger } = useToast();
const page = usePage();

const permissions = computed<string[]>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
    return auth?.permissions ?? [];
});
const canManage = computed(() => permissions.value.includes('staff.manage'));
const canViewAll = computed(() => canManage.value || permissions.value.includes('staff.view'));

const meta = ref<ShiftsMeta | null>(null);
const rows = ref<TimeEntryRow[]>([]);
const loading = ref(true);
const pageNo = ref(1);
const lastPage = ref(1);
const total = ref(0);

const userId = ref('');
const status = ref('');
const from = ref(ymd(new Date(Date.now() - 13 * 86400000)));
const to = ref(ymd(new Date()));

async function load(): Promise<void> {
    loading.value = true;
    try {
        const params = new URLSearchParams({ page: String(pageNo.value), from: from.value, to: to.value });
        if (userId.value) params.set('user_id', userId.value);
        if (status.value) params.set('status', status.value);
        const result = await api<Paginated<TimeEntryRow>>(`/api/v1/shifts/time-entries?${params}`);
        rows.value = result.data;
        lastPage.value = result.last_page;
        total.value = result.total;
    } catch (e) {
        if (e instanceof ApiError) danger('Kayıtlar yüklenemedi', e.displayMessage);
    } finally {
        loading.value = false;
    }
}

onMounted(async () => {
    try {
        meta.value = await api<ShiftsMeta>('/api/v1/shifts/meta');
    } catch {
        /* filtre listesi olmadan da tablo çalışır */
    }
    await load();
});

watch([userId, status, from, to], () => {
    pageNo.value = 1;
    void load();
});
watch(pageNo, () => void load());

const staffOptions = computed(() => [
    { value: '', label: 'Tüm personel' },
    ...(meta.value?.staff ?? []).map((s) => ({ value: String(s.id), label: s.name })),
]);
const statusOptions = [
    { value: '', label: 'Tüm durumlar' },
    { value: 'open', label: 'Açık (mesaide)' },
    { value: 'closed', label: 'Kapalı' },
];

/* ---- Düzeltme modalı ---- */
const editOpen = ref(false);
const editing = ref<TimeEntryRow | null>(null);
const editForm = ref({ in_date: '', in_time: '', out_date: '', out_time: '', break_min: '', reason: '' });
const editErrors = ref<Record<string, string>>({});
const savingEdit = ref(false);

function openEdit(row: TimeEntryRow): void {
    editing.value = row;
    const inD = new Date(row.clock_in_at);
    const outD = row.clock_out_at ? new Date(row.clock_out_at) : null;
    const pad = (n: number) => String(n).padStart(2, '0');
    editForm.value = {
        in_date: ymd(inD),
        in_time: `${pad(inD.getHours())}:${pad(inD.getMinutes())}`,
        out_date: outD ? ymd(outD) : ymd(inD),
        out_time: outD ? `${pad(outD.getHours())}:${pad(outD.getMinutes())}` : '',
        break_min: String(row.break_total_min),
        reason: '',
    };
    editErrors.value = {};
    editOpen.value = true;
}

async function saveEdit(): Promise<void> {
    if (!editing.value) return;
    savingEdit.value = true;
    editErrors.value = {};
    try {
        const body: Record<string, unknown> = {
            clock_in_at: `${editForm.value.in_date} ${editForm.value.in_time}:00`,
            break_total_min: Number(editForm.value.break_min || 0),
            reason: editForm.value.reason,
        };
        if (editForm.value.out_time) {
            body.clock_out_at = `${editForm.value.out_date} ${editForm.value.out_time}:00`;
        }
        await api(`/api/v1/shifts/time-entries/${editing.value.id}`, { method: 'PUT', body });
        success('Kayıt düzeltildi', 'Düzeltme denetim kaydına işlendi.');
        editOpen.value = false;
        await load();
    } catch (e) {
        if (e instanceof ApiError) {
            editErrors.value = Object.fromEntries(Object.entries(e.errors).map(([k, v]) => [k, v[0]]));
            if (Object.keys(editErrors.value).length === 0) danger('Düzeltilemedi', e.displayMessage);
        }
    } finally {
        savingEdit.value = false;
    }
}

async function approve(row: TimeEntryRow): Promise<void> {
    try {
        await api(`/api/v1/shifts/time-entries/${row.id}/approve`, { method: 'POST' });
        success('Kayıt onaylandı');
        await load();
    } catch (e) {
        if (e instanceof ApiError) danger('Onaylanamadı', e.displayMessage);
    }
}

function methodLabel(m: string | null): string {
    if (!m) return '';
    return { pin: 'PIN', device: 'Cihaz', manual: 'Manuel', qr: 'QR', nfc: 'NFC' }[m] ?? m;
}
</script>

<template>
    <Head title="Mesai Kayıtları" />
    <ShiftsShell title="Mesai Kayıtları" active="entries">
        <div class="flex flex-col gap-4">
            <div class="flex flex-wrap items-end gap-2">
                <BaseSelect v-if="canViewAll" v-model="userId" :options="staffOptions" size="sm" class="w-44" />
                <BaseSelect v-model="status" :options="statusOptions" size="sm" class="w-40" />
                <BaseInput v-model="from" type="date" size="sm" class="w-38" />
                <span class="pb-1.5 text-xs text-muted">—</span>
                <BaseInput v-model="to" type="date" size="sm" class="w-38" />
                <span class="ml-auto pb-1.5 text-xs text-muted">{{ total }} kayıt</span>
            </div>

            <BaseSkeleton v-if="loading" class="h-64 w-full" />

            <BaseCard v-else flush>
                <EmptyState
                    v-if="rows.length === 0"
                    title="Mesai kaydı yok"
                    description="Seçili aralıkta giriş/çıkış kaydı bulunmuyor."
                />
                <div v-else class="overflow-x-auto">
                    <table class="w-full min-w-[900px] text-sm">
                        <thead>
                            <tr class="border-b border-default text-left text-xs text-muted">
                                <th class="px-3 py-2 font-medium">Personel</th>
                                <th class="px-3 py-2 font-medium">Tarih</th>
                                <th class="px-3 py-2 font-medium">Giriş</th>
                                <th class="px-3 py-2 font-medium">Çıkış</th>
                                <th class="px-3 py-2 font-medium">Mola</th>
                                <th class="px-3 py-2 font-medium">Çalışılan</th>
                                <th class="px-3 py-2 font-medium">FM / Eksik</th>
                                <th class="px-3 py-2 font-medium">Durum</th>
                                <th v-if="canManage" class="px-3 py-2 text-right font-medium">İşlem</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="row in rows" :key="row.id" class="border-b border-default last:border-0 hover:bg-inset">
                                <td class="px-3 py-2">
                                    <p class="font-medium text-body">{{ row.user?.name ?? '—' }}</p>
                                    <p class="text-xs text-muted">
                                        {{ methodLabel(row.method_in) }}<template v-if="row.device"> · {{ row.device.name }}</template>
                                        <template v-if="canViewAll && row.ip_in"> · {{ row.ip_in }}</template>
                                    </p>
                                </td>
                                <td class="px-3 py-2 text-muted">{{ fmtDate(row.clock_in_at) }}</td>
                                <td class="px-3 py-2">
                                    {{ fmtTime(row.clock_in_at) }}
                                    <span v-if="row.late_min > 0" class="block text-xs text-warning">+{{ row.late_min }}dk geç</span>
                                </td>
                                <td class="px-3 py-2">
                                    {{ row.clock_out_at ? fmtTime(row.clock_out_at) : '—' }}
                                    <span v-if="row.early_leave_min > 0" class="block text-xs text-warning">
                                        {{ row.early_leave_min }}dk erken
                                    </span>
                                </td>
                                <td class="px-3 py-2 text-muted">{{ fmtMin(row.break_total_min) }}</td>
                                <td class="px-3 py-2 font-medium text-body">{{ fmtMin(row.worked_min) }}</td>
                                <td class="px-3 py-2">
                                    <span v-if="row.overtime_min > 0" class="text-success">+{{ fmtMin(row.overtime_min) }}</span>
                                    <span v-else-if="row.missing_min > 0" class="text-danger">−{{ fmtMin(row.missing_min) }}</span>
                                    <span v-else class="text-muted">—</span>
                                </td>
                                <td class="px-3 py-2">
                                    <div class="flex flex-col items-start gap-1">
                                        <BaseBadge v-if="row.status === 'open'" variant="info">Mesaide</BaseBadge>
                                        <BaseBadge v-else-if="row.approved_at" variant="success">Onaylı</BaseBadge>
                                        <BaseBadge v-else variant="neutral" no-icon>Onay bekliyor</BaseBadge>
                                        <BaseBadge v-if="row.edited_at" variant="warning" :title="row.edit_reason ?? ''">
                                            Düzeltildi
                                        </BaseBadge>
                                    </div>
                                </td>
                                <td v-if="canManage" class="px-3 py-2 text-right">
                                    <div class="flex justify-end gap-1">
                                        <BaseButton size="sm" variant="ghost" @click="openEdit(row)">Düzelt</BaseButton>
                                        <BaseButton
                                            v-if="row.status === 'closed' && !row.approved_at"
                                            size="sm"
                                            variant="secondary"
                                            @click="approve(row)"
                                        >
                                            Onayla
                                        </BaseButton>
                                    </div>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </BaseCard>

            <BasePagination v-if="lastPage > 1" v-model:page="pageNo" :last-page="lastPage" />
        </div>

        <!-- Düzeltme modalı -->
        <BaseModal :open="editOpen" title="Mesai Kaydını Düzelt" size="md" @close="editOpen = false">
            <div class="flex flex-col gap-3">
                <p class="rounded-md bg-inset p-2 text-xs text-muted">
                    Manuel düzeltme neden ister ve eski/yeni değerlerle birlikte denetim kaydına işlenir. Düzeltilen
                    kayıt yeniden onay bekler.
                </p>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Giriş tarihi" :error="editErrors.clock_in_at" required>
                        <BaseInput v-model="editForm.in_date" type="date" />
                    </FormField>
                    <FormField label="Giriş saati" required>
                        <BaseInput v-model="editForm.in_time" type="time" />
                    </FormField>
                    <FormField label="Çıkış tarihi" :error="editErrors.clock_out_at">
                        <BaseInput v-model="editForm.out_date" type="date" />
                    </FormField>
                    <FormField label="Çıkış saati" hint="Boşsa kayıt açık kalır">
                        <BaseInput v-model="editForm.out_time" type="time" />
                    </FormField>
                    <FormField label="Toplam mola (dk)" :error="editErrors.break_total_min">
                        <BaseInput v-model="editForm.break_min" type="number" inputmode="numeric" />
                    </FormField>
                </div>
                <FormField label="Düzeltme nedeni" :error="editErrors.reason" required>
                    <BaseInput v-model="editForm.reason" placeholder="ör. Personel çıkış yapmayı unuttu" />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="editOpen = false">Vazgeç</BaseButton>
                <BaseButton :loading="savingEdit" @click="saveEdit">Kaydet</BaseButton>
            </template>
        </BaseModal>
    </ShiftsShell>
</template>
