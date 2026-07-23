<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseTabs from '@/Components/ui/BaseTabs.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import ReservationDrawer from './ReservationDrawer.vue';
import ReservationsNav from './ReservationsNav.vue';
import {
    addDays,
    fetchReservations,
    formatDayLabel,
    formatMinor,
    formatShortDay,
    isoDate,
    metaFromProps,
    startOfWeek,
    type ReservationRow,
} from './reservations';

/**
 * Rezervasyonlar: gün/hafta görünümü + durum yönetimi.
 * Gün görünümü saat sıralı zaman çizelgesidir; hafta görünümü 7 sütunlu
 * özettir. Tüm veriler /api/v1/reservations'tan gelir (tenant-scope'lu).
 */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

const auth = computed(() => (page.props as Record<string, unknown>).auth as {
    permissions?: string[];
    activeBranchId?: number | null;
} | null);

const permissions = computed<string[]>(() => auth.value?.permissions ?? []);
const branchId = computed<number | null>(() => auth.value?.activeBranchId ?? null);
const canCreate = computed(() => permissions.value.includes('reservations.create'));
const canManage = computed(() => permissions.value.includes('reservations.manage'));
const canSeeSensitive = computed(() => permissions.value.includes('reservations.view_sensitive'));
const canDelete = computed(() => permissions.value.includes('reservations.delete'));

/* ---- Görünüm durumu ---- */
const view = ref<'day' | 'week'>('day');
const anchor = ref(new Date());
const statusFilter = ref('');
const q = ref('');

const loading = ref(true);
const rows = ref<ReservationRow[]>([]);

const range = computed<{ from: string; to: string }>(() => {
    if (view.value === 'day') {
        const d = isoDate(anchor.value);
        return { from: d, to: d };
    }
    const start = startOfWeek(anchor.value);
    return { from: isoDate(start), to: isoDate(addDays(start, 6)) };
});

const rangeLabel = computed(() =>
    view.value === 'day'
        ? formatDayLabel(range.value.from)
        : `${formatShortDay(range.value.from)} – ${formatShortDay(range.value.to)}`,
);

async function load(): Promise<void> {
    loading.value = true;
    try {
        const params = new URLSearchParams();
        params.set('from', range.value.from);
        params.set('to', range.value.to);
        params.set('per_page', '300');
        if (statusFilter.value) params.set('status', statusFilter.value);
        if (q.value) params.set('q', q.value);

        const res = await fetchReservations(params);
        rows.value = res.data;
    } catch (e) {
        danger('Rezervasyonlar yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);
watch([view, anchor, statusFilter], load);
watch(q, load);

function shift(dir: -1 | 1): void {
    anchor.value = addDays(anchor.value, view.value === 'day' ? dir : dir * 7);
}

function goToday(): void {
    anchor.value = new Date();
}

/* ---- Gün/hafta gruplama ---- */
const byDay = computed<Map<string, ReservationRow[]>>(() => {
    const map = new Map<string, ReservationRow[]>();
    for (const r of rows.value) {
        const list = map.get(r.reserved_date) ?? [];
        list.push(r);
        map.set(r.reserved_date, list);
    }
    for (const list of map.values()) list.sort((a, b) => a.reserved_time.localeCompare(b.reserved_time));
    return map;
});

const weekDays = computed<string[]>(() => {
    if (view.value === 'day') return [range.value.from];
    const start = startOfWeek(anchor.value);
    return Array.from({ length: 7 }, (_, i) => isoDate(addDays(start, i)));
});

const statusFilterOptions = computed(() => [
    { value: '', label: 'Tüm durumlar' },
    ...meta.statuses.map((s) => ({ value: s.value, label: s.label })),
]);

const statusLabel = (value: string) => meta.statuses.find((s) => s.value === value)?.label ?? value;

/* ---- Drawer ---- */
const drawerOpen = ref(false);
const editing = ref<ReservationRow | null>(null);

function openCreate(): void {
    editing.value = null;
    drawerOpen.value = true;
}

function openEdit(row: ReservationRow): void {
    editing.value = row;
    drawerOpen.value = true;
}

/* ---- Durum geçişleri ---- */
const busyId = ref<number | null>(null);

async function transition(row: ReservationRow, status: string): Promise<void> {
    let reason: string | null = null;
    if (status === 'cancelled') {
        reason = window.prompt('İptal sebebi (isteğe bağlı):');
        if (reason === null) return; // vazgeçti
    }

    busyId.value = row.id;
    try {
        const res = await api<{ reservation: ReservationRow }>(`/api/v1/reservations/${row.id}/status`, {
            method: 'POST',
            body: { status, reason: reason || undefined },
        });
        const i = rows.value.findIndex((r) => r.id === row.id);
        if (i >= 0) rows.value[i] = res.reservation;
        success(`Durum güncellendi: ${res.reservation.status_label}`);
    } catch (e) {
        danger('Durum değiştirilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        busyId.value = null;
    }
}

async function remind(row: ReservationRow): Promise<void> {
    busyId.value = row.id;
    try {
        await api(`/api/v1/reservations/${row.id}/remind`, { method: 'POST' });
        success('Hatırlatma e-postası gönderildi');
        void load();
    } catch (e) {
        danger('Gönderilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        busyId.value = null;
    }
}

/* ---- Silme ---- */
const deleting = ref<ReservationRow | null>(null);
const deleteBusy = ref(false);

async function confirmDelete(): Promise<void> {
    if (!deleting.value) return;
    deleteBusy.value = true;
    try {
        await api(`/api/v1/reservations/${deleting.value.id}`, { method: 'DELETE' });
        rows.value = rows.value.filter((r) => r.id !== deleting.value?.id);
        success('Rezervasyon silindi');
        deleting.value = null;
    } catch (e) {
        danger('Silinemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        deleteBusy.value = false;
    }
}

function onSaved(row: ReservationRow): void {
    const i = rows.value.findIndex((r) => r.id === row.id);
    if (i >= 0) rows.value[i] = row;
    else void load();
}
</script>

<template>
    <Head title="Rezervasyonlar" />
    <PanelShell title="Rezervasyonlar">
        <ReservationsNav />

        <div class="flex flex-col gap-4">
            <!-- Araç çubuğu -->
            <BaseCard>
                <div class="flex flex-wrap items-center gap-3">
                    <BaseTabs
                        :tabs="[{ key: 'day', label: 'Gün' }, { key: 'week', label: 'Hafta' }]"
                        :model-value="view"
                        @update:model-value="view = $event as 'day' | 'week'"
                    />

                    <div class="flex items-center gap-1">
                        <BaseButton size="sm" variant="ghost" icon-only label="Önceki" @click="shift(-1)">
                            <AppIcon name="chevron-left" :size="16" />
                        </BaseButton>
                        <BaseButton size="sm" variant="secondary" @click="goToday">Bugün</BaseButton>
                        <BaseButton size="sm" variant="ghost" icon-only label="Sonraki" @click="shift(1)">
                            <AppIcon name="chevron-right" :size="16" />
                        </BaseButton>
                    </div>

                    <span class="text-sm font-medium text-body">{{ rangeLabel }}</span>

                    <div class="ms-auto flex flex-wrap items-center gap-2">
                        <div class="w-44">
                            <BaseSelect v-model="statusFilter" size="sm" :options="statusFilterOptions" />
                        </div>
                        <div class="w-52">
                            <SearchInput v-model="q" placeholder="Ad / telefon ara…" />
                        </div>
                        <BaseButton v-if="canCreate" @click="openCreate">
                            <AppIcon name="plus" :size="16" />
                            Yeni rezervasyon
                        </BaseButton>
                    </div>
                </div>
            </BaseCard>

            <!-- Takvim / liste -->
            <div v-if="loading" class="py-12 text-center text-sm text-muted">Yükleniyor…</div>

            <EmptyState
                v-else-if="rows.length === 0"
                title="Bu aralıkta rezervasyon yok"
                description="Yeni rezervasyon oluşturabilir ya da tarih aralığını değiştirebilirsiniz."
                icon="inbox"
            />

            <div v-else class="grid gap-4" :class="view === 'week' ? 'lg:grid-cols-2 xl:grid-cols-3' : ''">
                <BaseCard v-for="day in weekDays.filter((d) => (byDay.get(d) ?? []).length > 0)" :key="day" :title="formatDayLabel(day)" flush>
                    <ul class="flex flex-col">
                        <li
                            v-for="r in byDay.get(day) ?? []"
                            :key="r.id"
                            class="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-default px-4 py-3 last:border-b-0"
                        >
                            <!-- Saat -->
                            <div class="flex w-14 flex-col text-center">
                                <span class="text-base font-semibold tabular-nums text-body">{{ r.reserved_time }}</span>
                                <span class="text-[11px] text-muted">{{ r.duration_minutes }} dk</span>
                            </div>

                            <!-- Müşteri + detay -->
                            <div class="min-w-0 grow">
                                <div class="flex flex-wrap items-center gap-2">
                                    <span class="font-medium text-body">{{ r.customer_name }}</span>
                                    <span class="text-sm text-muted">{{ r.party_size }} kişi</span>
                                    <BaseBadge :variant="r.status_variant">
                                        <AppIcon :name="r.status_icon" :size="12" />
                                        {{ r.status_label }}
                                    </BaseBadge>
                                    <BaseBadge v-if="r.has_allergy_note" variant="danger" :title="r.allergy_note ?? undefined">
                                        <AppIcon name="alert-triangle" :size="12" />
                                        Alerji
                                    </BaseBadge>
                                    <BaseBadge v-if="r.occasion" variant="info">
                                        <AppIcon name="bell" :size="12" />
                                        Özel gün
                                    </BaseBadge>
                                    <BaseBadge v-if="r.deposit_minor > 0" :variant="r.deposit_status_variant as never">
                                        Kapora {{ formatMinor(r.deposit_minor) }} · {{ r.deposit_status_label }}
                                    </BaseBadge>
                                </div>
                                <div class="mt-0.5 flex flex-wrap items-center gap-x-3 text-xs text-muted">
                                    <span v-if="r.tables.length > 0">
                                        Masa: {{ r.tables.map((t) => t.name).join(', ') }}
                                    </span>
                                    <span v-else class="text-warning">Masa atanmadı</span>
                                    <span v-if="r.area_name">Bölüm: {{ r.area_name }}</span>
                                    <span v-if="r.customer_phone">{{ r.customer_phone }}</span>
                                    <span>Kaynak: {{ r.source_label }}</span>
                                    <span v-if="r.special_note" class="italic">“{{ r.special_note }}”</span>
                                    <span v-if="canSeeSensitive && r.allergy_note" class="font-medium text-danger">
                                        Alerji: {{ r.allergy_note }}
                                    </span>
                                </div>
                            </div>

                            <!-- Eylemler -->
                            <div class="flex items-center gap-1">
                                <template v-if="canManage && r.allowed_transitions.includes('confirmed')">
                                    <BaseButton size="sm" variant="secondary" :loading="busyId === r.id" @click="transition(r, 'confirmed')">
                                        <AppIcon name="check-circle" :size="14" />
                                        Onayla
                                    </BaseButton>
                                </template>
                                <template v-else-if="canManage && r.allowed_transitions.includes('arrived')">
                                    <BaseButton size="sm" variant="secondary" :loading="busyId === r.id" @click="transition(r, 'arrived')">
                                        <AppIcon name="user" :size="14" />
                                        Geldi
                                    </BaseButton>
                                </template>
                                <template v-else-if="canManage && r.allowed_transitions.includes('seated')">
                                    <BaseButton size="sm" variant="secondary" :loading="busyId === r.id" @click="transition(r, 'seated')">
                                        <AppIcon name="users" :size="14" />
                                        Masaya al
                                    </BaseButton>
                                </template>

                                <BaseDropdown align="right">
                                    <template #trigger="{ toggle }">
                                        <BaseButton size="sm" variant="ghost" icon-only label="Diğer işlemler" @click="toggle">
                                            <AppIcon name="dots-vertical" :size="16" />
                                        </BaseButton>
                                    </template>

                                    <DropdownItem @select="openEdit(r)">
                                        <AppIcon name="pencil" :size="14" />
                                        Düzenle
                                    </DropdownItem>

                                    <template v-if="canManage">
                                        <DropdownItem
                                            v-for="t in r.allowed_transitions"
                                            :key="t"
                                            @select="transition(r, t)"
                                        >
                                            <AppIcon name="arrow-right" :size="14" />
                                            {{ statusLabel(t) }}
                                        </DropdownItem>
                                        <DropdownItem v-if="r.customer_email" @select="remind(r)">
                                            <AppIcon name="bell" :size="14" />
                                            Hatırlatma gönder
                                        </DropdownItem>
                                    </template>

                                    <DropdownItem v-if="canDelete" @select="deleting = r">
                                        <AppIcon name="trash" :size="14" />
                                        Sil
                                    </DropdownItem>
                                </BaseDropdown>
                            </div>
                        </li>
                    </ul>
                </BaseCard>
            </div>
        </div>

        <ReservationDrawer
            :open="drawerOpen"
            :meta="meta"
            :branch-id="branchId"
            :editing="editing"
            :can-see-sensitive="canSeeSensitive"
            @close="drawerOpen = false"
            @saved="onSaved"
        />

        <BaseModal :open="deleting !== null" title="Rezervasyonu sil" size="sm" @close="deleting = null">
            <p class="text-sm text-body">
                <strong>{{ deleting?.customer_name }}</strong> adına {{ deleting?.reserved_date }} {{ deleting?.reserved_time }}
                rezervasyonu kalıcı olarak silinecek. Emin misiniz?
            </p>
            <div class="mt-4 flex justify-end gap-2">
                <BaseButton variant="secondary" @click="deleting = null">Vazgeç</BaseButton>
                <BaseButton variant="danger" :loading="deleteBusy" @click="confirmDelete">Sil</BaseButton>
            </div>
        </BaseModal>
    </PanelShell>
</template>
