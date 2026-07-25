<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import ShiftsShell from './components/ShiftsShell.vue';
import type { LeaveRow, Paginated, ShiftsMeta, SwapRow } from './types';
import { LEAVE_TYPE_LABELS } from './types';
import { fmtDateTime, fmtTime } from './lib';

/**
 * /panel/mesai/talepler — onay bekleyenler (yalnız staff.manage):
 * vardiya değişim talepleri + izin talepleri tek ekranda.
 */
const { success, danger } = useToast();

const meta = ref<ShiftsMeta | null>(null);
const swaps = ref<SwapRow[]>([]);
const leaves = ref<LeaveRow[]>([]);
const loading = ref(true);

/** Hedefi boş bırakılan taleplerde onay öncesi seçilen kişi. */
const swapTargets = ref<Record<number, string>>({});

async function load(): Promise<void> {
    loading.value = true;
    try {
        const [swapPage, leavePage] = await Promise.all([
            api<Paginated<SwapRow>>('/api/v1/shifts/swap-requests?status=pending'),
            api<Paginated<LeaveRow>>('/api/v1/shifts/leave-requests?status=pending'),
        ]);
        swaps.value = swapPage.data;
        leaves.value = leavePage.data;
    } catch (e) {
        if (e instanceof ApiError) danger('Talepler yüklenemedi', e.displayMessage);
    } finally {
        loading.value = false;
    }
}

onMounted(async () => {
    try {
        meta.value = await api<ShiftsMeta>('/api/v1/shifts/meta');
    } catch {
        /* hedef seçimi olmadan da liste görünür */
    }
    await load();
});

const staffOptions = computed(() => [
    { value: '', label: 'Personel seçin…' },
    ...(meta.value?.staff ?? []).map((s) => ({ value: String(s.id), label: s.name })),
]);

async function decideSwap(row: SwapRow, action: 'approve' | 'reject'): Promise<void> {
    try {
        const body: Record<string, unknown> = {};
        if (action === 'approve' && !row.target_user?.id) {
            const chosen = swapTargets.value[row.id];
            if (!chosen) {
                danger('Devralacak personel seçin', 'Talepte hedef belirtilmemiş.');
                return;
            }
            body.target_user_id = Number(chosen);
        }
        await api(`/api/v1/shifts/swap-requests/${row.id}/${action}`, { method: 'POST', body });
        success(action === 'approve' ? 'Değişim onaylandı, vardiya devredildi' : 'Talep reddedildi');
        await load();
    } catch (e) {
        if (e instanceof ApiError) danger('İşlem tamamlanamadı', e.displayMessage);
    }
}

async function decideLeave(row: LeaveRow, action: 'approve' | 'reject'): Promise<void> {
    try {
        await api(`/api/v1/shifts/leave-requests/${row.id}/${action}`, { method: 'POST' });
        success(action === 'approve' ? 'İzin onaylandı' : 'İzin reddedildi');
        await load();
    } catch (e) {
        if (e instanceof ApiError) danger('İşlem tamamlanamadı', e.displayMessage);
    }
}
</script>

<template>
    <Head title="Onay Bekleyenler" />
    <ShiftsShell title="Onay Bekleyen Talepler" active="approvals">
        <BaseSkeleton v-if="loading" class="h-64 w-full" />

        <div v-else class="grid grid-cols-1 gap-4 xl:grid-cols-2">
            <!-- Vardiya değişimleri -->
            <BaseCard :title="`Vardiya değişim talepleri (${swaps.length})`" flush>
                <EmptyState v-if="swaps.length === 0" title="Bekleyen değişim talebi yok" icon="check-circle" />
                <ul v-else class="divide-y divide-[color:var(--color-border-default,inherit)]">
                    <li v-for="row in swaps" :key="row.id" class="flex flex-col gap-2 border-b border-default p-3 last:border-0">
                        <div class="flex items-start justify-between gap-2">
                            <div class="text-sm">
                                <p class="font-medium text-body">
                                    {{ row.requested_by?.name ?? '—' }}
                                    <span class="text-muted">→</span>
                                    {{ row.target_user?.name ?? 'hedef seçilmedi' }}
                                </p>
                                <p v-if="row.shift" class="text-xs text-muted">
                                    {{ fmtDateTime(row.shift.starts_at) }} – {{ fmtTime(row.shift.ends_at) }}
                                    <template v-if="row.shift.branch"> · {{ row.shift.branch.name }}</template>
                                </p>
                                <p v-if="row.reason" class="mt-0.5 text-xs text-muted">Neden: {{ row.reason }}</p>
                            </div>
                            <BaseBadge variant="info">Bekliyor</BaseBadge>
                        </div>
                        <div class="flex flex-wrap items-center justify-end gap-2">
                            <BaseSelect
                                v-if="!row.target_user"
                                :model-value="swapTargets[row.id] ?? ''"
                                :options="staffOptions"
                                size="sm"
                                class="w-44"
                                @update:model-value="(v: string) => (swapTargets[row.id] = v)"
                            />
                            <BaseButton size="sm" @click="decideSwap(row, 'approve')">Onayla</BaseButton>
                            <BaseButton size="sm" variant="ghost" @click="decideSwap(row, 'reject')">Reddet</BaseButton>
                        </div>
                    </li>
                </ul>
            </BaseCard>

            <!-- İzin talepleri -->
            <BaseCard :title="`İzin talepleri (${leaves.length})`" flush>
                <EmptyState v-if="leaves.length === 0" title="Bekleyen izin talebi yok" icon="check-circle" />
                <ul v-else>
                    <li v-for="row in leaves" :key="row.id" class="flex flex-col gap-2 border-b border-default p-3 last:border-0">
                        <div class="flex items-start justify-between gap-2">
                            <div class="text-sm">
                                <p class="font-medium text-body">{{ row.user?.name ?? '—' }}</p>
                                <p class="text-xs text-muted">
                                    {{ LEAVE_TYPE_LABELS[row.type] ?? row.type }} ·
                                    {{ new Date(row.starts_on).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' }) }}
                                    –
                                    {{ new Date(row.ends_on).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' }) }}
                                </p>
                                <p v-if="row.reason" class="mt-0.5 text-xs text-muted">Neden: {{ row.reason }}</p>
                            </div>
                            <BaseBadge variant="info">Bekliyor</BaseBadge>
                        </div>
                        <div class="flex justify-end gap-2">
                            <BaseButton size="sm" @click="decideLeave(row, 'approve')">Onayla</BaseButton>
                            <BaseButton size="sm" variant="ghost" @click="decideLeave(row, 'reject')">Reddet</BaseButton>
                        </div>
                    </li>
                </ul>
            </BaseCard>
        </div>
    </ShiftsShell>
</template>
