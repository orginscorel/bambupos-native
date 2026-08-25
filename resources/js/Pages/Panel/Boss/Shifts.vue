<script setup lang="ts">
/**
 * PATRON PANELİ · Vardiya Düzenleme.
 * Haftalık takvim; patron gün seçip personele vardiya ekler/düzenler/siler.
 * Mevcut planlayıcı uçlarını kullanır (meta / schedule / shifts POST·PUT·DELETE)
 * — yetki: staff.manage (backend). Şube kapsamı bağlamdan (BranchContext).
 */
import { computed, onMounted, reactive, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BossLayout from '@/Layouts/BossLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import { shiftTone, shiftPeriodLabel } from '@/lib/shift';

interface StaffLite {
    id: number;
    name: string;
    position: string | null;
}
interface ShiftDto {
    id: number;
    user_id: number;
    position: string | null;
    starts_at: string;
    ends_at: string;
    break_min: number | null;
    note: string | null;
    user?: { id: number; name: string; position: string | null } | null;
}

const { success, danger } = useToast();
const DAY_NAMES = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

const loading = ref(true);
const staff = ref<StaffLite[]>([]);
const shifts = ref<ShiftDto[]>([]);
/* Yönetim izni (staff.manage) — backend ScheduleController::meta `can.manage`
 * alanını döner. Frontend bunu okumadan ekle/düzenle/sil butonlarını
 * koşulsuz gösteriyordu; backend 403 ile korunuyordu ama tıklama "her zaman
 * başarılı" değildi (kişiye-özel yetki override senaryosu). */
const can = ref<{ view_all: boolean; manage: boolean }>({ view_all: false, manage: false });

/* ---- Hafta gezinme ---- */
function mondayOf(d: Date): Date {
    const x = new Date(d);
    x.setHours(0, 0, 0, 0);
    const dow = (x.getDay() + 6) % 7; // 0=Pzt
    x.setDate(x.getDate() - dow);
    return x;
}
const weekStart = ref<Date>(mondayOf(new Date()));
const selectedIdx = ref<number>((new Date().getDay() + 6) % 7);

const weekDays = computed<Date[]>(() =>
    Array.from({ length: 7 }, (_, i) => {
        const d = new Date(weekStart.value);
        d.setDate(d.getDate() + i);
        return d;
    }),
);
const selectedDay = computed(() => weekDays.value[selectedIdx.value]);

function isoDate(d: Date): string {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
const weekLabel = computed(() => {
    const a = weekDays.value[0];
    const b = weekDays.value[6];
    const f = (d: Date) => d.toLocaleDateString('tr-TR', { day: '2-digit', month: 'short' });
    return `${f(a)} – ${f(b)}`;
});

async function load(): Promise<void> {
    loading.value = true;
    try {
        const from = isoDate(weekDays.value[0]);
        const toD = new Date(weekDays.value[6]);
        toD.setDate(toD.getDate() + 1);
        const to = isoDate(toD);
        const [meta, sched] = await Promise.all([
            api<{ staff: StaffLite[]; can?: { view_all: boolean; manage: boolean } }>('/api/v1/shifts/meta'),
            api<{ shifts: ShiftDto[] }>(`/api/v1/shifts/schedule?from=${from}&to=${to}`),
        ]);
        staff.value = meta.staff ?? [];
        can.value = meta.can ?? { view_all: false, manage: false };
        shifts.value = sched.shifts ?? [];
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}
onMounted(load);

function shiftWeek(delta: number): void {
    const d = new Date(weekStart.value);
    d.setDate(d.getDate() + delta * 7);
    weekStart.value = d;
    void load();
}
function goToday(): void {
    weekStart.value = mondayOf(new Date());
    selectedIdx.value = (new Date().getDay() + 6) % 7;
    void load();
}

/* ---- Seçili günün vardiyaları (personele göre) ---- */
function sameDay(iso: string, d: Date): boolean {
    const s = new Date(iso);
    return s.getFullYear() === d.getFullYear() && s.getMonth() === d.getMonth() && s.getDate() === d.getDate();
}
function hm(iso: string): string {
    return new Date(iso).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
}
const dayShiftsByUser = computed<Record<number, ShiftDto[]>>(() => {
    const map: Record<number, ShiftDto[]> = {};
    for (const s of shifts.value) {
        if (sameDay(s.starts_at, selectedDay.value)) (map[s.user_id] ??= []).push(s);
    }
    return map;
});
const dayCount = computed(() => Object.values(dayShiftsByUser.value).reduce((n, a) => n + a.length, 0));

/* ---- Ekle / düzenle modalı ---- */
const modal = reactive({
    open: false,
    editingId: null as number | null,
    user_id: 0,
    userName: '',
    start: '09:00',
    end: '17:00',
    break_min: 0,
    note: '',
    repeat_weeks: 0,
});
const saving = ref(false);
const modalErr = ref('');

function openAdd(s: StaffLite): void {
    Object.assign(modal, {
        open: true, editingId: null, user_id: s.id, userName: s.name,
        start: '09:00', end: '17:00', break_min: 0, note: '', repeat_weeks: 0,
    });
    modalErr.value = '';
}
function openEdit(sh: ShiftDto): void {
    Object.assign(modal, {
        open: true, editingId: sh.id, user_id: sh.user_id,
        userName: sh.user?.name ?? staff.value.find((x) => x.id === sh.user_id)?.name ?? 'Personel',
        start: hm(sh.starts_at), end: hm(sh.ends_at),
        break_min: sh.break_min ?? 0, note: sh.note ?? '', repeat_weeks: 0,
    });
    modalErr.value = '';
}

async function saveShift(): Promise<void> {
    if (saving.value) return;
    if (!modal.start || !modal.end) { modalErr.value = 'Başlangıç ve bitiş saati gerekli.'; return; }
    saving.value = true;
    modalErr.value = '';

    const dayIso = isoDate(selectedDay.value);
    // Gece devri: bitiş ≤ başlangıç ise ertesi güne taşı.
    const endDay = modal.end <= modal.start
        ? isoDate(new Date(selectedDay.value.getTime() + 86400000))
        : dayIso;

    const body: Record<string, unknown> = {
        branch_id: 0, // backend geçerli şubeyi zorlar (istek değeri yok sayılır)
        user_id: modal.user_id,
        starts_at: `${dayIso} ${modal.start}`,
        ends_at: `${endDay} ${modal.end}`,
        break_min: modal.break_min || 0,
        note: modal.note.trim() || null,
    };
    if (modal.editingId === null && modal.repeat_weeks > 0) body.repeat_weeks = modal.repeat_weeks;

    try {
        if (modal.editingId === null) {
            await api('/api/v1/shifts/shifts', { method: 'POST', body });
            success('Vardiya eklendi', `${modal.userName} · ${modal.start}–${modal.end}`);
        } else {
            await api(`/api/v1/shifts/shifts/${modal.editingId}`, { method: 'PUT', body });
            success('Vardiya güncellendi', `${modal.userName} · ${modal.start}–${modal.end}`);
        }
        modal.open = false;
        await load();
    } catch (e) {
        if (e instanceof ApiError) {
            const first = Object.values(e.errors)[0]?.[0];
            modalErr.value = first ?? e.displayMessage;
        } else {
            modalErr.value = 'Beklenmeyen bir hata oluştu.';
        }
    } finally {
        saving.value = false;
    }
}

async function deleteShift(): Promise<void> {
    if (saving.value || modal.editingId === null) return;
    saving.value = true;
    try {
        await api(`/api/v1/shifts/shifts/${modal.editingId}`, { method: 'DELETE' });
        success('Vardiya silindi', modal.userName);
        modal.open = false;
        await load();
    } catch (e) {
        modalErr.value = e instanceof ApiError ? e.displayMessage : 'Silinemedi.';
    } finally {
        saving.value = false;
    }
}

function dayHasToday(d: Date): boolean {
    const t = new Date();
    return d.getFullYear() === t.getFullYear() && d.getMonth() === t.getMonth() && d.getDate() === t.getDate();
}
</script>

<template>
    <Head title="Vardiya · Patron Paneli" />
    <BossLayout title="Vardiya Düzenleme" subtitle="Haftalık plan · ekle, düzenle, sil">
        <template #actions>
            <button type="button" class="inline-flex h-10 items-center gap-1.5 rounded-lg bg-white/15 px-3 text-sm font-semibold text-white ring-1 ring-white/25 hover:bg-white/25" @click="goToday">
                Bugün
            </button>
        </template>

        <!-- Hafta gezinme -->
        <div class="mb-4 flex items-center justify-between gap-3 rounded-2xl border border-default bg-surface p-2.5 shadow-sm">
            <button type="button" class="flex size-9 items-center justify-center rounded-lg hover:bg-surface-alt" aria-label="Önceki hafta" @click="shiftWeek(-1)">
                <AppIcon name="chevron-left" :size="18" />
            </button>
            <div class="text-center">
                <p class="text-sm font-bold">{{ weekLabel }}</p>
                <p class="text-[11px] text-muted">Haftalık plan</p>
            </div>
            <button type="button" class="flex size-9 items-center justify-center rounded-lg hover:bg-surface-alt" aria-label="Sonraki hafta" @click="shiftWeek(1)">
                <AppIcon name="chevron-right" :size="18" />
            </button>
        </div>

        <!-- Gün seçici -->
        <div class="mb-5 grid grid-cols-7 gap-1.5">
            <button
                v-for="(d, i) in weekDays" :key="i" type="button"
                class="flex flex-col items-center rounded-xl border py-2 transition-colors"
                :class="i === selectedIdx
                    ? 'border-primary bg-primary text-on-primary'
                    : 'border-default bg-surface hover:bg-surface-alt'"
                @click="selectedIdx = i"
            >
                <span class="text-[11px] font-medium" :class="i === selectedIdx ? 'text-on-primary/80' : 'text-muted'">{{ DAY_NAMES[i] }}</span>
                <span class="text-base font-bold leading-tight">{{ d.getDate() }}</span>
                <span v-if="dayHasToday(d)" class="mt-0.5 size-1.5 rounded-full" :class="i === selectedIdx ? 'bg-on-primary' : 'bg-primary'"></span>
            </button>
        </div>

        <!-- Seçili gün başlığı -->
        <div class="mb-3 flex items-center justify-between">
            <h2 class="text-sm font-bold">
                {{ selectedDay.toLocaleDateString('tr-TR', { weekday: 'long', day: 'numeric', month: 'long' }) }}
            </h2>
            <span class="text-xs text-muted">{{ dayCount }} vardiya</span>
        </div>

        <!-- Personel listesi -->
        <div v-if="loading" class="flex flex-col gap-2">
            <BaseSkeleton v-for="i in 6" :key="i" class="h-16 rounded-xl" />
        </div>
        <ul v-else class="stagger-in flex flex-col gap-2">
            <li v-for="s in staff" :key="s.id" class="rounded-xl border border-default bg-surface p-3 shadow-sm">
                <div class="flex items-center gap-3">
                    <span class="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-bold text-primary">
                        {{ s.name.slice(0, 2).toUpperCase() }}
                    </span>
                    <div class="min-w-0 flex-1">
                        <p class="truncate text-sm font-semibold">{{ s.name }}</p>
                        <p v-if="s.position" class="truncate text-xs text-muted">{{ s.position }}</p>
                    </div>
                    <button v-if="can.manage" type="button" class="flex size-9 shrink-0 items-center justify-center rounded-lg border border-default text-primary hover:bg-surface-alt" aria-label="Vardiya ekle" @click="openAdd(s)">
                        <AppIcon name="plus" :size="18" />
                    </button>
                </div>
                <div v-if="dayShiftsByUser[s.id]?.length" class="mt-2 flex flex-wrap gap-1.5 pl-12">
                    <component
                        :is="can.manage ? 'button' : 'span'"
                        v-for="sh in dayShiftsByUser[s.id]" :key="sh.id" :type="can.manage ? 'button' : undefined"
                        class="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1 text-xs font-semibold"
                        :class="[shiftTone(sh.starts_at), can.manage ? 'transition-opacity hover:opacity-80' : 'cursor-default']"
                        :title="`${shiftPeriodLabel(sh.starts_at)} vardiyası`"
                        @click="can.manage ? openEdit(sh) : undefined"
                    >
                        <AppIcon name="clock" :size="13" />
                        {{ hm(sh.starts_at) }}–{{ hm(sh.ends_at) }}
                        <span v-if="sh.break_min" class="font-normal opacity-70">· {{ sh.break_min }}dk mola</span>
                    </component>
                </div>
            </li>
        </ul>

        <!-- ===== Ekle / düzenle modalı ===== -->
        <BaseModal :open="modal.open" :title="modal.editingId ? 'Vardiyayı düzenle' : 'Vardiya ekle'" size="sm" @close="modal.open = false">
            <div class="flex flex-col gap-3.5">
                <p class="text-sm text-muted">
                    <strong class="text-primary">{{ modal.userName }}</strong> ·
                    {{ selectedDay.toLocaleDateString('tr-TR', { weekday: 'long', day: 'numeric', month: 'long' }) }}
                </p>
                <div class="grid grid-cols-2 gap-3">
                    <label class="flex flex-col gap-1">
                        <span class="text-xs font-semibold text-muted">Başlangıç</span>
                        <input v-model="modal.start" type="time" class="rounded-lg border border-default bg-surface-alt px-3 py-2.5 text-sm" />
                    </label>
                    <label class="flex flex-col gap-1">
                        <span class="text-xs font-semibold text-muted">Bitiş</span>
                        <input v-model="modal.end" type="time" class="rounded-lg border border-default bg-surface-alt px-3 py-2.5 text-sm" />
                    </label>
                </div>
                <div class="grid grid-cols-2 gap-3">
                    <label class="flex flex-col gap-1">
                        <span class="text-xs font-semibold text-muted">Mola (dk)</span>
                        <input v-model.number="modal.break_min" type="number" min="0" max="480" class="rounded-lg border border-default bg-surface-alt px-3 py-2.5 text-sm" />
                    </label>
                    <label v-if="modal.editingId === null" class="flex flex-col gap-1">
                        <span class="text-xs font-semibold text-muted">Tekrar (hafta)</span>
                        <input v-model.number="modal.repeat_weeks" type="number" min="0" max="26" class="rounded-lg border border-default bg-surface-alt px-3 py-2.5 text-sm" />
                    </label>
                </div>
                <label class="flex flex-col gap-1">
                    <span class="text-xs font-semibold text-muted">Not <span class="font-normal">(isteğe bağlı)</span></span>
                    <input v-model="modal.note" type="text" maxlength="255" class="rounded-lg border border-default bg-surface-alt px-3 py-2.5 text-sm" />
                </label>
                <p v-if="modalErr" class="text-xs text-danger">{{ modalErr }}</p>
            </div>
            <template #footer>
                <button v-if="modal.editingId !== null" type="button" class="mr-auto inline-flex items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-semibold text-danger hover:bg-danger/10" :disabled="saving" @click="deleteShift">
                    <AppIcon name="trash" :size="15" /> Sil
                </button>
                <button type="button" class="rounded-lg border border-default px-4 py-2 text-sm font-semibold hover:bg-surface-alt" @click="modal.open = false">Vazgeç</button>
                <button type="button" class="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-on-primary disabled:opacity-50" :disabled="saving" @click="saveShift">
                    {{ saving ? 'Kaydediliyor…' : (modal.editingId ? 'Kaydet' : 'Ekle') }}
                </button>
            </template>
        </BaseModal>
    </BossLayout>
</template>
