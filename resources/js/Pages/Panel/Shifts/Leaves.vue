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
import type { LeaveRow, Paginated, ShiftsMeta } from './types';
import { LEAVE_TYPE_LABELS, STATUS_LABELS } from './types';
import { ymd } from './lib';

/**
 * /panel/mesai/izinler — izin/rapor/tatil/devamsızlık.
 * Personel kendi talebini açar; yönetici başkası adına kayıt açar (örn.
 * devamsızlık — doğrudan onaylı işlenir) ve karar verir.
 */
const { success, danger } = useToast();
const page = usePage();

const auth = computed(() => (page.props as Record<string, unknown>).auth as
    | { user?: { id: number }; permissions?: string[] }
    | undefined);
const myId = computed(() => auth.value?.user?.id ?? 0);
const permissions = computed(() => auth.value?.permissions ?? []);
const canManage = computed(() => permissions.value.includes('staff.manage'));

const meta = ref<ShiftsMeta | null>(null);
const rows = ref<LeaveRow[]>([]);
const loading = ref(true);
const pageNo = ref(1);
const lastPage = ref(1);
const status = ref('');
const type = ref('');

async function load(): Promise<void> {
    loading.value = true;
    try {
        const params = new URLSearchParams({ page: String(pageNo.value) });
        if (status.value) params.set('status', status.value);
        if (type.value) params.set('type', type.value);
        const result = await api<Paginated<LeaveRow>>(`/api/v1/shifts/leave-requests?${params}`);
        rows.value = result.data;
        lastPage.value = result.last_page;
    } catch (e) {
        if (e instanceof ApiError) danger('İzinler yüklenemedi', e.displayMessage);
    } finally {
        loading.value = false;
    }
}

onMounted(async () => {
    try {
        meta.value = await api<ShiftsMeta>('/api/v1/shifts/meta');
    } catch {
        /* form yine çalışır (kendi adına) */
    }
    await load();
});

watch([status, type], () => {
    pageNo.value = 1;
    void load();
});
watch(pageNo, () => void load());

const typeOptions = computed(() => [
    { value: '', label: 'Tüm türler' },
    ...Object.entries(LEAVE_TYPE_LABELS).map(([value, label]) => ({ value, label })),
]);
const statusOptions = [
    { value: '', label: 'Tüm durumlar' },
    ...Object.entries(STATUS_LABELS).map(([value, label]) => ({ value, label })),
];

/* ---- Yeni talep ---- */
const formOpen = ref(false);
const saving = ref(false);
const formErrors = ref<Record<string, string>>({});
const form = ref({ user_id: '', type: 'annual', starts_on: ymd(new Date()), ends_on: ymd(new Date()), reason: '' });

const formTypeOptions = computed(() =>
    Object.entries(LEAVE_TYPE_LABELS)
        .filter(([value]) => canManage.value || value !== 'absence')
        .map(([value, label]) => ({ value, label })),
);
const staffOptions = computed(() => [
    { value: '', label: 'Kendim' },
    ...(meta.value?.staff ?? []).filter((s) => s.id !== myId.value).map((s) => ({ value: String(s.id), label: s.name })),
]);

async function save(): Promise<void> {
    saving.value = true;
    formErrors.value = {};
    try {
        await api('/api/v1/shifts/leave-requests', {
            method: 'POST',
            body: {
                user_id: form.value.user_id ? Number(form.value.user_id) : null,
                type: form.value.type,
                starts_on: form.value.starts_on,
                ends_on: form.value.ends_on,
                reason: form.value.reason || null,
            },
        });
        success('Kayıt oluşturuldu');
        formOpen.value = false;
        form.value = { user_id: '', type: 'annual', starts_on: ymd(new Date()), ends_on: ymd(new Date()), reason: '' };
        await load();
    } catch (e) {
        if (e instanceof ApiError) {
            formErrors.value = Object.fromEntries(Object.entries(e.errors).map(([k, v]) => [k, v[0]]));
            if (Object.keys(formErrors.value).length === 0) danger('Oluşturulamadı', e.displayMessage);
        }
    } finally {
        saving.value = false;
    }
}

async function decide(row: LeaveRow, action: 'approve' | 'reject' | 'cancel'): Promise<void> {
    try {
        await api(`/api/v1/shifts/leave-requests/${row.id}/${action}`, { method: 'POST' });
        success(action === 'approve' ? 'Onaylandı' : action === 'reject' ? 'Reddedildi' : 'İptal edildi');
        await load();
    } catch (e) {
        if (e instanceof ApiError) danger('İşlem tamamlanamadı', e.displayMessage);
    }
}

type BadgeVariant = 'neutral' | 'primary' | 'success' | 'warning' | 'danger' | 'info';
const statusVariant = (s: string): BadgeVariant =>
    (({ pending: 'info', approved: 'success', rejected: 'danger', cancelled: 'neutral' }) as Record<string, BadgeVariant>)[s] ??
    'neutral';
</script>

<template>
    <Head title="İzinler" />
    <ShiftsShell title="İzin & Devamsızlık" active="leaves">
        <div class="flex flex-col gap-4">
            <div class="flex flex-wrap items-center gap-2">
                <BaseSelect v-model="type" :options="typeOptions" size="sm" class="w-40" />
                <BaseSelect v-model="status" :options="statusOptions" size="sm" class="w-40" />
                <BaseButton class="ml-auto" size="sm" @click="formOpen = true">Yeni Talep / Kayıt</BaseButton>
            </div>

            <BaseSkeleton v-if="loading" class="h-64 w-full" />

            <BaseCard v-else flush>
                <EmptyState v-if="rows.length === 0" title="Kayıt yok" description="Henüz izin talebi ya da kaydı bulunmuyor." />
                <div v-else class="overflow-x-auto">
                    <table class="w-full min-w-[760px] text-sm">
                        <thead>
                            <tr class="border-b border-default text-left text-xs text-muted">
                                <th class="px-3 py-2 font-medium">Personel</th>
                                <th class="px-3 py-2 font-medium">Tür</th>
                                <th class="px-3 py-2 font-medium">Aralık</th>
                                <th class="px-3 py-2 font-medium">Neden</th>
                                <th class="px-3 py-2 font-medium">Durum</th>
                                <th class="px-3 py-2 text-right font-medium">İşlem</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="row in rows" :key="row.id" class="border-b border-default last:border-0 hover:bg-inset">
                                <td class="px-3 py-2 font-medium text-body">{{ row.user?.name ?? '—' }}</td>
                                <td class="px-3 py-2">{{ LEAVE_TYPE_LABELS[row.type] ?? row.type }}</td>
                                <td class="px-3 py-2 text-muted">
                                    {{ new Date(row.starts_on).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' }) }}
                                    –
                                    {{ new Date(row.ends_on).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' }) }}
                                </td>
                                <td class="max-w-48 truncate px-3 py-2 text-muted" :title="row.reason ?? ''">{{ row.reason ?? '—' }}</td>
                                <td class="px-3 py-2">
                                    <BaseBadge :variant="statusVariant(row.status)">{{ STATUS_LABELS[row.status] ?? row.status }}</BaseBadge>
                                </td>
                                <td class="px-3 py-2 text-right">
                                    <div v-if="row.status === 'pending'" class="flex justify-end gap-1">
                                        <template v-if="canManage">
                                            <BaseButton size="sm" variant="secondary" @click="decide(row, 'approve')">Onayla</BaseButton>
                                            <BaseButton size="sm" variant="ghost" @click="decide(row, 'reject')">Reddet</BaseButton>
                                        </template>
                                        <BaseButton
                                            v-if="row.user_id === myId"
                                            size="sm"
                                            variant="ghost"
                                            @click="decide(row, 'cancel')"
                                        >
                                            Geri çek
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

        <BaseModal :open="formOpen" title="Yeni İzin / Kayıt" size="md" @close="formOpen = false">
            <div class="flex flex-col gap-3">
                <FormField v-if="canManage" label="Personel" :error="formErrors.user_id" hint="Devamsızlık kaydı ancak başkası adına açılır">
                    <BaseSelect v-model="form.user_id" :options="staffOptions" />
                </FormField>
                <FormField label="Tür" :error="formErrors.type" required>
                    <BaseSelect v-model="form.type" :options="formTypeOptions" />
                </FormField>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Başlangıç" :error="formErrors.starts_on" required>
                        <BaseInput v-model="form.starts_on" type="date" />
                    </FormField>
                    <FormField label="Bitiş" :error="formErrors.ends_on" required>
                        <BaseInput v-model="form.ends_on" type="date" />
                    </FormField>
                </div>
                <FormField label="Neden" :error="formErrors.reason">
                    <BaseInput v-model="form.reason" placeholder="ör. Aile ziyareti" />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="formOpen = false">Vazgeç</BaseButton>
                <BaseButton :loading="saving" @click="save">Kaydet</BaseButton>
            </template>
        </BaseModal>
    </ShiftsShell>
</template>
