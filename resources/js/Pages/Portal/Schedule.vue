<script setup lang="ts">
/**
 * Portal "Takvim": İZİN TALEPLERİ + kişinin YAKLAŞAN vardiyaları.
 *
 * Üstte "İzinlerim" (talep oluştur + liste, durum rozetleri, iptal), altında
 * güne göre gruplu yaklaşan vardiyalar (bugün/yarın rozetleri, saat aralığı,
 * pozisyon). Özel görsel kimlik: p-card / p-tile-* / p-chip (app.css .portal-root).
 * Sunucu grouped_by_day verirse onu kullanır; yalnız düz shifts[] gelirse
 * güne göre KENDİ gruplar.
 */
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PortalLayout from '@/Layouts/PortalLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import FormField from '@/Components/ui/FormField.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';

/* ------------------------------------------------------------------ */
/* Vardiyalar (mevcut)                                                 */
/* ------------------------------------------------------------------ */

interface ScheduleShift {
    id: number;
    starts_at: string;
    ends_at: string;
    position: string | null;
    branch_name: string | null;
    note: string | null;
}

interface ScheduleDay {
    date: string;
    label: string;
    items: ScheduleShift[];
}

interface ScheduleResponse {
    shifts: ScheduleShift[];
    grouped_by_day?: ScheduleDay[];
}

const loading = ref(true);
const days = ref<ScheduleDay[]>([]);

const timeFmt = new Intl.DateTimeFormat('tr-TR', { hour: '2-digit', minute: '2-digit' });
const dayFmt = new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'long', weekday: 'long' });

const clockTime = (iso: string | null | undefined): string => (iso ? timeFmt.format(new Date(iso)) : '—');

/** Bir tarihin yerel gün anahtarı (YYYY-MM-DD). */
function dayKey(d: Date): string {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

const todayKey = computed(() => dayKey(new Date()));
const tomorrowKey = computed(() => {
    const t = new Date();
    t.setDate(t.getDate() + 1);
    return dayKey(t);
});

function relLabel(key: string): 'today' | 'tomorrow' | null {
    if (key === todayKey.value) return 'today';
    if (key === tomorrowKey.value) return 'tomorrow';
    return null;
}

/** grouped_by_day yoksa shifts[] listesini güne göre grupla. */
function groupShifts(shifts: ScheduleShift[]): ScheduleDay[] {
    const map = new Map<string, ScheduleDay>();
    const sorted = [...shifts].sort((a, b) => a.starts_at.localeCompare(b.starts_at));
    for (const s of sorted) {
        const d = new Date(s.starts_at);
        const key = dayKey(d);
        if (!map.has(key)) {
            map.set(key, { date: key, label: dayFmt.format(d), items: [] });
        }
        map.get(key)!.items.push(s);
    }
    return [...map.values()];
}

async function loadShifts(): Promise<void> {
    loading.value = true;
    try {
        const res = await api<ScheduleResponse>('/api/v1/portal/schedule');
        if (res.grouped_by_day && res.grouped_by_day.length > 0) {
            days.value = res.grouped_by_day;
        } else {
            days.value = groupShifts(res.shifts ?? []);
        }
    } catch {
        days.value = [];
    } finally {
        loading.value = false;
    }
}

const isEmpty = computed(() => !loading.value && days.value.length === 0);

const shiftTotal = computed(() => days.value.reduce((sum, d) => sum + d.items.length, 0));

/* ---- Canlı geri sayım: sıradaki / devam eden vardiya ---- */
const nowMs = ref(Date.now());
let countdownTimer: ReturnType<typeof setInterval> | null = null;

const allShiftsSorted = computed<ScheduleShift[]>(() =>
    days.value.flatMap((d) => d.items).slice().sort((a, b) => a.starts_at.localeCompare(b.starts_at)),
);

/** Şu an devam eden vardiya (varsa). */
const currentShift = computed<ScheduleShift | null>(
    () =>
        allShiftsSorted.value.find((s) => {
            const st = new Date(s.starts_at).getTime();
            const en = new Date(s.ends_at).getTime();
            return st <= nowMs.value && nowMs.value < en;
        }) ?? null,
);

/** Başlamamış en yakın vardiya. */
const nextShift = computed<ScheduleShift | null>(
    () => allShiftsSorted.value.find((s) => new Date(s.starts_at).getTime() > nowMs.value) ?? null,
);

function humanDuration(ms: number): string {
    const totalMin = Math.max(0, Math.floor(ms / 60000));
    const h = Math.floor(totalMin / 60);
    const m = totalMin % 60;
    if (h > 0 && m > 0) return `${h} saat ${m} dakika`;
    if (h > 0) return `${h} saat`;
    return `${m} dakika`;
}

const startCountdown = computed(() =>
    nextShift.value ? humanDuration(new Date(nextShift.value.starts_at).getTime() - nowMs.value) : '',
);
const endCountdown = computed(() =>
    currentShift.value ? humanDuration(new Date(currentShift.value.ends_at).getTime() - nowMs.value) : '',
);
const nextShiftDayLabel = computed<string>(() => {
    if (!nextShift.value) return '';
    const d = new Date(nextShift.value.starts_at);
    const key = dayKey(d);
    const rel = relLabel(key);
    return rel === 'today' ? 'Bugün' : rel === 'tomorrow' ? 'Yarın' : dayFmt.format(d);
});
const subtitle = computed(() => {
    if (loading.value) return 'Takvim yükleniyor…';
    if (days.value.length === 0) return 'Planlı vardiya yok';
    return shiftTotal.value === 1 ? 'Yaklaşan 1 vardiya' : `Yaklaşan ${shiftTotal.value} vardiya`;
});

/** Gün grubunun sol renkli kenar/nokta aksanı: bugün emerald, yarın indigo, gerisi nötr. */
function dayAccent(key: string): string {
    const rel = relLabel(key);
    if (rel === 'today') return 'var(--p-emerald)';
    if (rel === 'tomorrow') return 'var(--p-indigo)';
    return 'var(--p-violet)';
}

/* ------------------------------------------------------------------ */
/* İzin talepleri                                                      */
/* ------------------------------------------------------------------ */

type LeaveType = 'annual' | 'sick' | 'unpaid' | 'other';

interface LeaveRequest {
    id: number;
    type: string;
    type_label: string;
    starts_on: string;
    ends_on: string;
    days: number;
    reason: string;
    status: string;
    status_label: string;
    created_at: string;
    decided_at: string | null;
}

interface LeaveResponse {
    requests: LeaveRequest[];
}

const { success, danger } = useToast();

const leaveLoading = ref(true);
const leaves = ref<LeaveRequest[]>([]);

const TYPE_LABELS: Record<string, string> = {
    annual: 'Yıllık izin',
    sick: 'Rapor',
    unpaid: 'Ücretsiz izin',
    other: 'Diğer',
};
const STATUS_LABELS: Record<string, string> = {
    pending: 'Beklemede',
    approved: 'Onaylandı',
    rejected: 'Reddedildi',
    cancelled: 'İptal',
};

const typeOptions: { value: LeaveType; label: string }[] = (Object.keys(TYPE_LABELS) as LeaveType[]).map((v) => ({
    value: v,
    label: TYPE_LABELS[v]!,
}));

const dateFmt = new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'long', year: 'numeric' });
/** "YYYY-MM-DD" tarihini yerel olarak biçimlendir (UTC kayması olmadan). */
function fmtDate(iso: string): string {
    if (!iso) return '—';
    const d = new Date(`${iso}T00:00:00`);
    return Number.isNaN(d.getTime()) ? iso : dateFmt.format(d);
}
function dateRange(r: LeaveRequest): string {
    return r.starts_on === r.ends_on ? fmtDate(r.starts_on) : `${fmtDate(r.starts_on)} – ${fmtDate(r.ends_on)}`;
}

function typeLabelOf(r: LeaveRequest): string {
    return r.type_label || TYPE_LABELS[r.type] || 'İzin';
}
function statusLabelOf(r: LeaveRequest): string {
    return r.status_label || STATUS_LABELS[r.status] || r.status;
}

/** Tür çipi aksan rengi. */
function typeAccent(type: string): string {
    switch (type) {
        case 'annual':
            return 'var(--p-sky)';
        case 'sick':
            return 'var(--p-rose)';
        case 'unpaid':
            return 'var(--p-amber)';
        default:
            return 'var(--p-violet)';
    }
}
function typeIcon(type: string): string {
    switch (type) {
        case 'annual':
            return 'sun';
        case 'sick':
            return 'alert-circle';
        case 'unpaid':
            return 'calendar';
        default:
            return 'tag';
    }
}

/** Durum rozeti sınıfları (renkli, temaya duyarlı). */
function statusBadge(status: string): string {
    switch (status) {
        case 'approved':
            return 'bg-(--p-emerald-soft) text-(--p-emerald)';
        case 'rejected':
            return 'bg-(--p-rose-soft) text-(--p-rose)';
        case 'cancelled':
            return 'bg-(--color-inset) text-muted';
        default:
            return 'bg-(--p-amber-soft) text-(--p-amber)';
    }
}
const isPending = (status: string): boolean => status === 'pending';

const leavesEmpty = computed(() => !leaveLoading.value && leaves.value.length === 0);

async function loadLeaves(): Promise<void> {
    leaveLoading.value = true;
    try {
        const res = await api<LeaveResponse>('/api/v1/portal/leave-requests');
        leaves.value = res.requests ?? [];
    } catch {
        leaves.value = [];
    } finally {
        leaveLoading.value = false;
    }
}

/* ---- Talep oluşturma modalı ---- */

const modalOpen = ref(false);
const submitting = ref(false);
const form = reactive<{ type: string; starts_on: string; ends_on: string; reason: string }>({
    type: 'annual',
    starts_on: '',
    ends_on: '',
    reason: '',
});
const errors = reactive<Record<string, string>>({});

function clearErrors(): void {
    for (const k of Object.keys(errors)) delete errors[k];
}

function openModal(): void {
    clearErrors();
    form.type = 'annual';
    form.starts_on = '';
    form.ends_on = '';
    form.reason = '';
    modalOpen.value = true;
}
function closeModal(): void {
    if (submitting.value) return;
    modalOpen.value = false;
}

/** İstemci-tarafı doğrulama; hata varsa false döner. */
function validate(): boolean {
    clearErrors();
    if (!form.starts_on) errors.starts_on = 'Başlangıç tarihi gerekli.';
    if (!form.ends_on) errors.ends_on = 'Bitiş tarihi gerekli.';
    if (form.starts_on && form.ends_on && form.ends_on < form.starts_on) {
        errors.ends_on = 'Bitiş tarihi başlangıçtan önce olamaz.';
    }
    if (!form.reason.trim()) errors.reason = 'Mazeret girmelisiniz.';
    return Object.keys(errors).length === 0;
}

async function submit(): Promise<void> {
    if (submitting.value) return;
    if (!validate()) return;
    submitting.value = true;
    try {
        await api('/api/v1/portal/leave-requests', {
            method: 'POST',
            body: {
                type: form.type,
                starts_on: form.starts_on,
                ends_on: form.ends_on,
                reason: form.reason.trim(),
            },
        });
        success('İzin talebi oluşturuldu');
        modalOpen.value = false;
        await loadLeaves();
    } catch (e) {
        if (e instanceof ApiError && e.status === 422) {
            clearErrors();
            for (const [field, msgs] of Object.entries(e.errors)) errors[field] = msgs[0] ?? '';
        } else {
            danger(e instanceof ApiError ? e.displayMessage : 'İşlem tamamlanamadı.');
        }
    } finally {
        submitting.value = false;
    }
}

/* ---- İptal ---- */

const cancellingId = ref<number | null>(null);

async function cancelLeave(id: number): Promise<void> {
    if (cancellingId.value !== null) return;
    cancellingId.value = id;
    try {
        await api(`/api/v1/portal/leave-requests/${id}/cancel`, { method: 'POST' });
        success('İzin talebi iptal edildi');
        await loadLeaves();
    } catch (e) {
        danger(e instanceof ApiError ? e.displayMessage : 'İşlem tamamlanamadı.');
    } finally {
        cancellingId.value = null;
    }
}

onMounted(() => {
    void loadShifts();
    void loadLeaves();
    countdownTimer = setInterval(() => {
        nowMs.value = Date.now();
    }, 1000);
});

onBeforeUnmount(() => {
    if (countdownTimer) clearInterval(countdownTimer);
});
</script>

<template>
    <PortalLayout title="Takvim" active="schedule" :heading="'Takvim'" :subtitle="subtitle">
        <!-- ===================== SIRADAKİ / DEVAM EDEN VARDİYA ===================== -->
        <section v-if="currentShift || nextShift" class="p-hero relative mb-4 overflow-hidden rounded-2xl p-4 text-white">
            <div class="p-dots pointer-events-none absolute inset-0 opacity-20" />
            <div class="relative flex items-center gap-3">
                <span class="flex size-12 shrink-0 items-center justify-center rounded-2xl bg-white/20 ring-2 ring-white/25 backdrop-blur">
                    <AppIcon name="clock" :size="24" />
                </span>
                <div class="min-w-0 flex-1">
                    <template v-if="currentShift">
                        <p class="text-xs font-medium uppercase tracking-wide text-white/75">Vardiyan devam ediyor</p>
                        <p class="text-lg font-bold">Bitişe {{ endCountdown }} kaldı</p>
                        <p class="text-sm text-white/80">{{ clockTime(currentShift.starts_at) }} – {{ clockTime(currentShift.ends_at) }}</p>
                    </template>
                    <template v-else-if="nextShift">
                        <p class="text-xs font-medium uppercase tracking-wide text-white/75">Sıradaki vardiya</p>
                        <p class="text-lg font-bold">Başlamasına {{ startCountdown }} kaldı</p>
                        <p class="text-sm text-white/80">
                            {{ nextShiftDayLabel }} · {{ clockTime(nextShift.starts_at) }} – {{ clockTime(nextShift.ends_at) }}
                            <template v-if="nextShift.position"> · {{ nextShift.position }}</template>
                        </p>
                    </template>
                </div>
            </div>
        </section>

        <!-- ============================ İZİNLERİM ============================ -->
        <section class="p-card p-4">
            <div class="flex flex-wrap items-center justify-between gap-3">
                <p class="flex items-center gap-2 font-semibold text-body">
                    <span class="p-chip" style="--chip-bg: var(--p-sky-soft); --chip-fg: var(--p-sky)">
                        <AppIcon name="calendar" :size="17" />
                    </span>
                    İzinlerim
                    <span
                        v-if="!leaveLoading && leaves.length"
                        class="rounded-full bg-(--p-sky-soft) px-2 py-0.5 text-xs font-bold text-(--p-sky)"
                    >
                        {{ leaves.length }}
                    </span>
                </p>
                <BaseButton size="sm" @click="openModal">
                    <AppIcon name="plus" :size="16" />
                    İzin Talebi Oluştur
                </BaseButton>
            </div>

            <!-- Yükleniyor -->
            <div v-if="leaveLoading" class="mt-4 flex flex-col gap-2.5">
                <BaseSkeleton v-for="i in 2" :key="i" class="h-20 w-full rounded-2xl" />
            </div>

            <!-- Boş -->
            <p v-else-if="leavesEmpty" class="mt-4 rounded-xl bg-(--color-inset) px-4 py-6 text-center text-sm text-muted">
                Henüz izin talebiniz yok. Yeni bir talep oluşturmak için yukarıdaki butonu kullanın.
            </p>

            <!-- Liste -->
            <ul v-else class="mt-4 flex flex-col gap-3">
                <li
                    v-for="r in leaves"
                    :key="r.id"
                    class="rounded-2xl border border-(--p-card-border) bg-(--color-inset) p-4"
                >
                    <!-- Başlık: tür çipi + tür + durum -->
                    <div class="flex items-center gap-3">
                        <span
                            class="flex size-11 shrink-0 items-center justify-center rounded-xl"
                            :style="{
                                backgroundColor: 'color-mix(in oklab, ' + typeAccent(r.type) + ' 13%, transparent)',
                                color: typeAccent(r.type),
                            }"
                        >
                            <AppIcon :name="typeIcon(r.type)" :size="20" />
                        </span>
                        <div class="min-w-0 flex-1">
                            <p class="truncate font-semibold text-body">{{ typeLabelOf(r) }}</p>
                            <p class="mt-0.5 text-xs text-muted">
                                {{ dateRange(r) }} · <span class="font-semibold text-body">{{ r.days }} gün</span>
                            </p>
                        </div>
                        <span
                            class="shrink-0 rounded-full px-2.5 py-1 text-[11px] font-bold"
                            :class="statusBadge(r.status)"
                        >
                            {{ statusLabelOf(r) }}
                        </span>
                    </div>

                    <!-- Mazeret -->
                    <div class="mt-3 rounded-xl border border-(--p-card-border) bg-(--p-card) px-3 py-2.5">
                        <p class="mb-0.5 text-[11px] font-semibold uppercase tracking-wide text-subtle">Mazeret</p>
                        <p class="text-sm text-body">{{ r.reason }}</p>
                    </div>

                    <!-- Bekleyen talep: iptal -->
                    <div v-if="isPending(r.status)" class="mt-3 flex justify-end border-t border-(--p-card-border) pt-3">
                        <BaseButton
                            size="sm"
                            variant="ghost"
                            class="text-(--p-rose)"
                            :loading="cancellingId === r.id"
                            :disabled="cancellingId !== null && cancellingId !== r.id"
                            @click="cancelLeave(r.id)"
                        >
                            Talebi iptal et
                        </BaseButton>
                    </div>
                </li>
            </ul>
        </section>

        <!-- ======================= YAKLAŞAN VARDİYALAR ======================= -->
        <section class="mt-6">
            <div class="mb-3 flex items-center gap-2">
                <span class="p-chip" style="--chip-bg: var(--p-violet-soft); --chip-fg: var(--p-violet)">
                    <AppIcon name="clock" :size="17" />
                </span>
                <h2 class="font-semibold text-body">Yaklaşan Vardiyalar</h2>
            </div>

            <!-- Yükleniyor -->
            <div v-if="loading" class="flex flex-col gap-5">
                <div v-for="i in 2" :key="i" class="flex flex-col gap-2.5">
                    <BaseSkeleton class="h-4 w-32" />
                    <BaseSkeleton class="h-24 w-full rounded-2xl" />
                </div>
            </div>

            <!-- Boş durum -->
            <div v-else-if="isEmpty" class="p-card p-2">
                <EmptyState
                    icon="calendar"
                    title="Planlı vardiya yok"
                    description="Yaklaşan günler için size atanmış bir vardiya bulunmuyor."
                />
            </div>

            <!-- Gün grupları (zaman çizelgesi hissi: sol renkli kenar + nokta) -->
            <div v-else class="flex flex-col gap-6">
                <div v-for="day in days" :key="day.date">
                    <div class="mb-2.5 flex items-center gap-2">
                        <span
                            class="size-2.5 shrink-0 rounded-full"
                            :style="{ backgroundColor: dayAccent(day.date) }"
                        />
                        <h3 class="text-sm font-bold text-body">{{ day.label }}</h3>
                        <span
                            v-if="relLabel(day.date) === 'today'"
                            class="rounded-full bg-(--p-emerald-soft) px-2 py-0.5 text-[11px] font-bold text-(--p-emerald)"
                        >
                            Bugün
                        </span>
                        <span
                            v-else-if="relLabel(day.date) === 'tomorrow'"
                            class="rounded-full bg-(--p-indigo-soft) px-2 py-0.5 text-[11px] font-bold text-(--p-indigo)"
                        >
                            Yarın
                        </span>
                    </div>

                    <ul class="flex flex-col gap-2.5">
                        <li
                            v-for="shift in day.items"
                            :key="shift.id"
                            class="p-card flex items-start gap-3 overflow-hidden p-4 pl-3.5"
                            :style="{ borderLeft: `4px solid ${dayAccent(day.date)}` }"
                        >
                            <span
                                class="flex size-11 shrink-0 items-center justify-center rounded-2xl"
                                :style="{ backgroundColor: 'color-mix(in oklab, ' + dayAccent(day.date) + ' 14%, transparent)', color: dayAccent(day.date) }"
                            >
                                <AppIcon name="clock" :size="20" />
                            </span>
                            <div class="min-w-0 flex-1">
                                <p class="text-lg font-extrabold text-body tabular-nums">
                                    {{ clockTime(shift.starts_at) }} – {{ clockTime(shift.ends_at) }}
                                </p>
                                <div class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
                                    <span v-if="shift.position" class="inline-flex items-center gap-1">
                                        <AppIcon name="user" :size="13" />
                                        {{ shift.position }}
                                    </span>
                                    <span v-if="shift.branch_name" class="inline-flex items-center gap-1">
                                        <AppIcon name="store" :size="13" />
                                        {{ shift.branch_name }}
                                    </span>
                                </div>
                                <p v-if="shift.note" class="mt-2 rounded-lg bg-(--color-inset) px-2.5 py-1.5 text-xs text-muted">
                                    {{ shift.note }}
                                </p>
                            </div>
                        </li>
                    </ul>
                </div>
            </div>
        </section>

        <!-- ======================= TALEP OLUŞTURMA MODALI ======================= -->
        <BaseModal :open="modalOpen" title="İzin Talebi Oluştur" size="md" @close="closeModal">
            <form class="flex flex-col gap-4" @submit.prevent="submit">
                <FormField label="İzin türü" required :error="errors.type">
                    <BaseSelect v-model="form.type" :options="typeOptions" />
                </FormField>

                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                    <FormField label="Başlangıç tarihi" required :error="errors.starts_on">
                        <BaseInput v-model="form.starts_on" type="date" />
                    </FormField>
                    <FormField label="Bitiş tarihi" required :error="errors.ends_on">
                        <BaseInput v-model="form.ends_on" type="date" :min="form.starts_on || undefined" />
                    </FormField>
                </div>

                <div class="flex flex-col gap-1.5">
                    <label for="leave-reason" class="text-sm font-medium text-body">
                        Mazeret
                        <span class="text-danger" aria-hidden="true">*</span>
                        <span class="sr-only">(zorunlu)</span>
                    </label>
                    <textarea
                        id="leave-reason"
                        v-model="form.reason"
                        rows="3"
                        placeholder="İzin talebinizin gerekçesini yazın…"
                        class="w-full rounded-md border bg-raised px-3 py-2 text-sm text-body placeholder:text-subtle transition-colors duration-(--dur-fast) focus:border-strong focus:outline-none focus:ring-2 focus:ring-ring-brand"
                        :class="errors.reason ? 'border-danger' : 'border-strong'"
                        :aria-invalid="errors.reason ? true : undefined"
                    />
                    <p v-if="errors.reason" class="flex items-center gap-1 text-xs font-medium text-danger">
                        <AppIcon name="alert-circle" :size="14" />
                        {{ errors.reason }}
                    </p>
                </div>
            </form>

            <template #footer>
                <BaseButton variant="secondary" :disabled="submitting" @click="closeModal">Vazgeç</BaseButton>
                <BaseButton :loading="submitting" @click="submit">Talebi Gönder</BaseButton>
            </template>
        </BaseModal>
    </PortalLayout>
</template>
