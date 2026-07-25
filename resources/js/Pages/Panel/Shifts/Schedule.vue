<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import ShiftsShell from './components/ShiftsShell.vue';
import ShiftFormModal from './components/ShiftFormModal.vue';
import type { ScheduleData, ShiftRow, ShiftsMeta, StaffingWarning, StaffLite } from './types';
import { addDays, dayKey, fmtTime, startOfWeek, ymd, WEEKDAY_LABELS as WD } from './lib';

/**
 * /panel/vardiya — vardiya takvimi.
 * - Haftalık görünüm: personel × gün ızgarası, sürükle-bırak atama/taşıma.
 * - Aylık görünüm: gün başına vardiya sayısı; güne tıklayınca haftaya iner.
 * - Çakışma uyarısı (422 → "yine de kaydet"), minimum personel uyarıları.
 */
const { success, danger } = useToast();
const page = usePage();

const myUserId = computed<number>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { user?: { id: number } } | undefined;
    return auth?.user?.id ?? 0;
});

const meta = ref<ShiftsMeta | null>(null);
const data = ref<ScheduleData | null>(null);
const loading = ref(true);
const view = ref<'week' | 'month'>('week');
const anchor = ref(startOfWeek(new Date()));
const branchId = ref('');

const canManage = computed(() => meta.value?.can.manage ?? false);

/* ---- Aralık ---- */
const weekDays = computed(() => Array.from({ length: 7 }, (_, i) => addDays(anchor.value, i)));

const monthStart = computed(() => {
    const d = new Date(anchor.value.getFullYear(), anchor.value.getMonth(), 1);
    return d;
});

const monthGrid = computed(() => {
    // Ayın kapsadığı tam haftalar (Pzt başlangıçlı)
    const first = startOfWeek(monthStart.value);
    const weeks: Date[][] = [];
    let cursor = first;
    do {
        weeks.push(Array.from({ length: 7 }, (_, i) => addDays(cursor, i)));
        cursor = addDays(cursor, 7);
    } while (cursor.getMonth() === monthStart.value.getMonth() || weeks.length < 4);
    return weeks;
});

const rangeLabel = computed(() => {
    if (view.value === 'month') {
        return monthStart.value.toLocaleDateString('tr-TR', { month: 'long', year: 'numeric' });
    }
    const end = addDays(anchor.value, 6);
    return (
        anchor.value.toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' }) +
        ' – ' +
        end.toLocaleDateString('tr-TR', { day: 'numeric', month: 'short', year: 'numeric' })
    );
});

/* ---- Veri ---- */
async function loadMeta(): Promise<void> {
    meta.value = await api<ShiftsMeta>('/api/v1/shifts/meta');
}

async function loadSchedule(): Promise<void> {
    loading.value = true;
    try {
        let from: Date;
        let to: Date;
        if (view.value === 'week') {
            from = anchor.value;
            to = addDays(anchor.value, 7);
        } else {
            from = monthGrid.value[0][0];
            to = addDays(monthGrid.value[monthGrid.value.length - 1][6], 1);
        }
        const params = new URLSearchParams({ from: ymd(from), to: ymd(to) });
        if (branchId.value) params.set('branch_id', branchId.value);
        data.value = await api<ScheduleData>(`/api/v1/shifts/schedule?${params}`);
    } catch (e) {
        if (e instanceof ApiError) danger('Takvim yüklenemedi', e.displayMessage);
    } finally {
        loading.value = false;
    }
}

onMounted(async () => {
    try {
        await loadMeta();
    } catch {
        /* meta hatası takvimi engellemesin */
    }
    await loadSchedule();
});

watch([view, branchId], () => void loadSchedule());

function go(dir: -1 | 0 | 1): void {
    if (dir === 0) {
        anchor.value = startOfWeek(new Date());
    } else if (view.value === 'week') {
        anchor.value = addDays(anchor.value, dir * 7);
    } else {
        const d = new Date(anchor.value.getFullYear(), anchor.value.getMonth() + dir, 1);
        anchor.value = startOfWeek(d);
    }
    void loadSchedule();
}

/* ---- Izgara verisi ---- */
const visibleStaff = computed<StaffLite[]>(() => {
    const staff = meta.value?.staff ?? [];
    if (!branchId.value) return staff;
    // Şube süzgecinde, o şubede vardiyası olanlar + o şubeye bağlı personel
    const withShift = new Set((data.value?.shifts ?? []).map((s) => s.user_id));
    return staff.filter((s) => String(s.branch_id ?? '') === branchId.value || withShift.has(s.id));
});

function shiftsFor(userId: number, day: Date): ShiftRow[] {
    const key = ymd(day);
    return (data.value?.shifts ?? []).filter((s) => s.user_id === userId && dayKey(s.starts_at) === key);
}

function leavesFor(userId: number, day: Date): boolean {
    const key = ymd(day);
    return (data.value?.leaves ?? []).some(
        (l) => l.user_id === userId && l.starts_on.slice(0, 10) <= key && l.ends_on.slice(0, 10) >= key,
    );
}

function warningsFor(day: Date): StaffingWarning[] {
    const key = ymd(day);
    return (data.value?.warnings ?? []).filter((w) => w.date === key);
}

function monthCount(day: Date): number {
    const key = ymd(day);
    return (data.value?.shifts ?? []).filter((s) => dayKey(s.starts_at) === key).length;
}

/* ---- Sürükle-bırak ---- */
const draggingId = ref<number | null>(null);
const dropTarget = ref<string | null>(null);
const pendingMove = ref<{ shift: ShiftRow; userId: number; date: string } | null>(null);
const movingConflict = ref(false);

function onDragStart(e: DragEvent, shift: ShiftRow): void {
    if (!canManage.value) return;
    draggingId.value = shift.id;
    e.dataTransfer?.setData('text/plain', String(shift.id));
    if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
}

function onDragOver(e: DragEvent, userId: number, day: Date): void {
    if (!canManage.value || draggingId.value === null) return;
    e.preventDefault();
    dropTarget.value = `${userId}:${ymd(day)}`;
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'move';
}

async function onDrop(e: DragEvent, userId: number, day: Date): Promise<void> {
    e.preventDefault();
    dropTarget.value = null;
    const id = Number(e.dataTransfer?.getData('text/plain') || draggingId.value);
    draggingId.value = null;
    const shift = (data.value?.shifts ?? []).find((s) => s.id === id);
    if (!shift) return;
    const date = ymd(day);
    if (shift.user_id === userId && dayKey(shift.starts_at) === date) return;

    await moveShift(shift, userId, date, false);
}

async function moveShift(shift: ShiftRow, userId: number, date: string, allowOverlap: boolean): Promise<void> {
    const start = new Date(shift.starts_at);
    const end = new Date(shift.ends_at);
    const dayMs = 24 * 60 * 60 * 1000;
    const nights = Math.round((new Date(dayKey(shift.ends_at)).getTime() - new Date(dayKey(shift.starts_at)).getTime()) / dayMs);

    const pad = (n: number) => String(n).padStart(2, '0');
    const startAt = `${date} ${pad(start.getHours())}:${pad(start.getMinutes())}:00`;
    const endDate = ymd(addDays(new Date(date + 'T00:00:00'), nights));
    const endAt = `${endDate} ${pad(end.getHours())}:${pad(end.getMinutes())}:00`;

    try {
        await api(`/api/v1/shifts/shifts/${shift.id}`, {
            method: 'PUT',
            body: { user_id: userId, starts_at: startAt, ends_at: endAt, allow_overlap: allowOverlap },
        });
        success('Vardiya taşındı');
        pendingMove.value = null;
        await loadSchedule();
    } catch (err) {
        if (err instanceof ApiError && err.status === 422 && err.errors.starts_at?.[0]?.includes('başka vardiyası')) {
            pendingMove.value = { shift, userId, date };
            movingConflict.value = true;
        } else if (err instanceof ApiError) {
            danger('Taşınamadı', err.displayMessage);
        }
    }
}

/* ---- Modal ---- */
const modalOpen = ref(false);
const editingShift = ref<ShiftRow | null>(null);
const presetUserId = ref<number | null>(null);
const presetDate = ref<string | null>(null);

function openCreate(userId?: number, day?: Date): void {
    if (!canManage.value) return;
    editingShift.value = null;
    presetUserId.value = userId ?? null;
    presetDate.value = day ? ymd(day) : ymd(new Date());
    modalOpen.value = true;
}

function openEdit(shift: ShiftRow): void {
    editingShift.value = shift;
    modalOpen.value = true;
}

function openDay(day: Date): void {
    anchor.value = startOfWeek(day);
    view.value = 'week';
}

const branchOptions = computed(() => [
    { value: '', label: 'Tüm şubeler' },
    ...(meta.value?.branches ?? []).map((b) => ({ value: String(b.id), label: b.name })),
]);

const positionOf = (s: ShiftRow): string => s.position || s.user?.position || '';
</script>

<template>
    <Head title="Vardiya Takvimi" />
    <ShiftsShell title="Vardiya Takvimi">
        <div class="flex flex-col gap-4">
            <!-- Araç çubuğu -->
            <div class="flex flex-wrap items-center justify-between gap-2">
                <div class="flex items-center gap-1">
                    <BaseButton variant="secondary" size="sm" icon-only label="Önceki" @click="go(-1)">
                        <AppIcon name="chevron-left" :size="16" />
                    </BaseButton>
                    <BaseButton variant="secondary" size="sm" @click="go(0)">Bugün</BaseButton>
                    <BaseButton variant="secondary" size="sm" icon-only label="Sonraki" @click="go(1)">
                        <AppIcon name="chevron-right" :size="16" />
                    </BaseButton>
                    <span class="ml-2 text-sm font-semibold text-body">{{ rangeLabel }}</span>
                </div>
                <div class="flex items-center gap-2">
                    <BaseSelect v-model="branchId" :options="branchOptions" size="sm" class="w-40" />
                    <div class="flex rounded-md border border-strong" role="group" aria-label="Görünüm">
                        <button
                            type="button"
                            class="h-8 rounded-l-[5px] px-3 text-sm font-medium transition-colors"
                            :class="view === 'week' ? 'bg-primary text-on-primary' : 'bg-raised text-muted hover:text-body'"
                            @click="view = 'week'"
                        >
                            Hafta
                        </button>
                        <button
                            type="button"
                            class="h-8 rounded-r-[5px] px-3 text-sm font-medium transition-colors"
                            :class="view === 'month' ? 'bg-primary text-on-primary' : 'bg-raised text-muted hover:text-body'"
                            @click="view = 'month'"
                        >
                            Ay
                        </button>
                    </div>
                    <BaseButton v-if="canManage" size="sm" @click="openCreate()">
                        <AppIcon name="plus" :size="16" />
                        Vardiya
                    </BaseButton>
                </div>
            </div>

            <!-- Minimum personel uyarıları -->
            <div
                v-if="!loading && (data?.warnings?.length ?? 0) > 0"
                class="rounded-md border border-warning-border bg-warning-soft p-3 text-sm text-warning"
                role="alert"
            >
                <p class="flex items-center gap-1.5 font-semibold">
                    <AppIcon name="alert-triangle" :size="16" />
                    Minimum personel uyarısı
                </p>
                <ul class="mt-1 list-inside list-disc space-y-0.5">
                    <li v-for="(w, i) in data!.warnings.slice(0, 6)" :key="i">
                        {{ new Date(w.date + 'T00:00:00').toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' }) }}
                        <template v-if="w.position"> · {{ w.position }}</template>
                        : {{ w.planned }}/{{ w.required }} kişi planlı
                    </li>
                    <li v-if="data!.warnings.length > 6">… ve {{ data!.warnings.length - 6 }} uyarı daha</li>
                </ul>
            </div>

            <BaseSkeleton v-if="loading" class="h-72 w-full" />

            <!-- HAFTALIK: personel × gün -->
            <BaseCard v-else-if="view === 'week'" flush>
                <div class="overflow-x-auto">
                    <table class="w-full min-w-[860px] border-collapse text-sm">
                        <thead>
                            <tr class="border-b border-default">
                                <th class="w-44 px-3 py-2 text-left font-medium text-muted">Personel</th>
                                <th
                                    v-for="(day, i) in weekDays"
                                    :key="i"
                                    class="border-l border-default px-2 py-2 text-left font-medium"
                                    :class="ymd(day) === ymd(new Date()) ? 'text-primary' : 'text-muted'"
                                >
                                    <span class="flex items-center gap-1">
                                        {{ WD[i] }} {{ day.getDate() }}
                                        <span
                                            v-if="warningsFor(day).length"
                                            class="inline-block size-1.5 rounded-full bg-warning"
                                            :title="`${warningsFor(day).length} personel uyarısı`"
                                        />
                                    </span>
                                </th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-if="visibleStaff.length === 0">
                                <td colspan="8">
                                    <EmptyState title="Personel bulunamadı" description="Önce personel hesabı ekleyin." icon="users" />
                                </td>
                            </tr>
                            <tr v-for="person in visibleStaff" :key="person.id" class="border-b border-default last:border-0">
                                <td class="px-3 py-2 align-top">
                                    <p class="font-medium text-body">{{ person.name }}</p>
                                    <p v-if="person.position" class="text-xs text-muted">{{ person.position }}</p>
                                </td>
                                <td
                                    v-for="(day, i) in weekDays"
                                    :key="i"
                                    class="h-16 min-w-[100px] border-l border-default p-1 align-top transition-colors"
                                    :class="dropTarget === `${person.id}:${ymd(day)}` ? 'bg-primary-soft' : ''"
                                    @dragover="(e) => onDragOver(e, person.id, day)"
                                    @dragleave="dropTarget = null"
                                    @drop="(e) => onDrop(e, person.id, day)"
                                >
                                    <div class="flex flex-col gap-1">
                                        <button
                                            v-for="shift in shiftsFor(person.id, day)"
                                            :key="shift.id"
                                            type="button"
                                            :draggable="canManage"
                                            class="group w-full cursor-pointer rounded border border-primary-soft-border bg-primary-soft px-1.5 py-1 text-left text-xs text-primary transition-shadow hover:shadow-card"
                                            :class="draggingId === shift.id ? 'opacity-40' : ''"
                                            @dragstart="(e) => onDragStart(e, shift)"
                                            @dragend="draggingId = null"
                                            @click="openEdit(shift)"
                                        >
                                            <span class="font-semibold">{{ fmtTime(shift.starts_at) }}–{{ fmtTime(shift.ends_at) }}</span>
                                            <span v-if="positionOf(shift)" class="block truncate">{{ positionOf(shift) }}</span>
                                        </button>
                                        <span
                                            v-if="leavesFor(person.id, day)"
                                            class="inline-flex w-fit rounded border border-warning-border bg-warning-soft px-1.5 py-0.5 text-[11px] text-warning"
                                        >
                                            İzinli
                                        </span>
                                        <button
                                            v-if="canManage"
                                            type="button"
                                            class="hidden h-5 w-full items-center justify-center rounded border border-dashed border-strong text-subtle transition-colors hover:border-primary hover:text-primary [tr:hover_&]:flex"
                                            :aria-label="`${person.name} için ${ymd(day)} günü vardiya ekle`"
                                            @click="openCreate(person.id, day)"
                                        >
                                            <AppIcon name="plus" :size="12" />
                                        </button>
                                    </div>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </BaseCard>

            <!-- AYLIK -->
            <BaseCard v-else flush>
                <div class="overflow-x-auto">
                    <table class="w-full min-w-[640px] border-collapse text-sm">
                        <thead>
                            <tr class="border-b border-default">
                                <th v-for="(w, i) in WD" :key="i" class="px-2 py-2 text-left font-medium text-muted">{{ w }}</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="(week, wi) in monthGrid" :key="wi" class="border-b border-default last:border-0">
                                <td
                                    v-for="(day, di) in week"
                                    :key="di"
                                    class="h-20 w-[14.28%] cursor-pointer border-l border-default p-1.5 align-top first:border-l-0 hover:bg-inset"
                                    :class="day.getMonth() !== monthStart.getMonth() ? 'opacity-40' : ''"
                                    @click="openDay(day)"
                                >
                                    <div class="flex items-center justify-between">
                                        <span
                                            class="text-xs font-medium"
                                            :class="ymd(day) === ymd(new Date()) ? 'text-primary' : 'text-muted'"
                                        >
                                            {{ day.getDate() }}
                                        </span>
                                        <span
                                            v-if="warningsFor(day).length"
                                            class="inline-block size-1.5 rounded-full bg-warning"
                                            :title="`${warningsFor(day).length} personel uyarısı`"
                                        />
                                    </div>
                                    <BaseBadge v-if="monthCount(day) > 0" variant="primary" no-icon class="mt-1">
                                        {{ monthCount(day) }} vardiya
                                    </BaseBadge>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </BaseCard>

            <p v-if="canManage" class="text-xs text-muted">
                İpucu: vardiya kartlarını sürükleyip başka güne ya da personele bırakabilirsiniz. Boş hücrenin üzerine
                gelince çıkan + ile hızlı vardiya eklenir.
            </p>
        </div>

        <!-- Taşıma çakışması onayı -->
        <div
            v-if="movingConflict && pendingMove"
            class="fixed inset-x-0 bottom-4 z-50 mx-auto w-fit max-w-[95vw] rounded-lg border border-warning-border bg-raised p-4 shadow-card"
            role="alertdialog"
            aria-label="Çakışan vardiya uyarısı"
        >
            <p class="flex items-center gap-1.5 text-sm font-semibold text-warning">
                <AppIcon name="alert-triangle" :size="16" />
                Çakışan vardiya uyarısı
            </p>
            <p class="mt-1 text-sm text-muted">Hedef personelin aynı aralıkta başka vardiyası var. Yine de taşınsın mı?</p>
            <div class="mt-3 flex justify-end gap-2">
                <BaseButton size="sm" variant="secondary" @click="movingConflict = false; pendingMove = null">Vazgeç</BaseButton>
                <BaseButton
                    size="sm"
                    @click="moveShift(pendingMove!.shift, pendingMove!.userId, pendingMove!.date, true); movingConflict = false"
                >
                    Yine de taşı
                </BaseButton>
            </div>
        </div>

        <ShiftFormModal
            :open="modalOpen"
            :meta="meta"
            :shift="editingShift"
            :preset-user-id="presetUserId"
            :preset-date="presetDate"
            :can-manage="canManage"
            :my-user-id="myUserId"
            @close="modalOpen = false"
            @saved="loadSchedule"
        />
    </ShiftsShell>
</template>
