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
import BaseCheckbox from '@/Components/ui/BaseCheckbox.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BasePagination from '@/Components/ui/BasePagination.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import DataTable, { type TableColumn } from '@/Components/ui/DataTable.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import FormField from '@/Components/ui/FormField.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import VenueNav from './VenueNav.vue';
import {
    fetchAreas,
    fetchBranches,
    metaFromProps,
    type AreaRow,
    type BranchRow,
    type Paginated,
    type TableRow,
} from './venue';

const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

/* ================= Liste durumu ================= */
const loading = ref(true);
const rows = ref<TableRow[]>([]);
const currentPage = ref(1);
const lastPage = ref(1);
const total = ref(0);

const branches = ref<BranchRow[]>([]);
const areas = ref<AreaRow[]>([]);

const filters = ref({ branch_id: '', area_id: '', status: '', active: '', q: '' });

const branchOptions = computed(() => branches.value.map((b) => ({ value: String(b.id), label: b.name })));
const areaOptions = computed(() => [
    { value: 'none', label: '— Alansız —' },
    ...areas.value
        .filter((a) => !filters.value.branch_id || a.branch_id === Number(filters.value.branch_id))
        .map((a) => ({ value: String(a.id), label: a.floor_name ? `${a.name} (${a.floor_name})` : a.name })),
]);
const statusOptions = computed(() => meta.statuses.map((s) => ({ value: s.value, label: s.label })));
const shapeOptions = computed(() => meta.shapes.map((s) => ({ value: s.value, label: s.label })));

async function loadTables(): Promise<void> {
    loading.value = true;
    try {
        const params = new URLSearchParams();
        params.set('page', String(currentPage.value));
        if (filters.value.branch_id) params.set('branch_id', filters.value.branch_id);
        if (filters.value.area_id) params.set('area_id', filters.value.area_id);
        if (filters.value.status) params.set('status', filters.value.status);
        if (filters.value.active !== '') params.set('active', filters.value.active);
        if (filters.value.q) params.set('q', filters.value.q);

        const res = await api<{ tables: Paginated<TableRow> }>(`/api/v1/venue/tables?${params}`);
        rows.value = res.tables.data;
        lastPage.value = res.tables.last_page;
        total.value = res.tables.total;
    } catch (e) {
        danger('Masalar yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

watch(
    filters,
    () => {
        currentPage.value = 1;
        selected.value = new Set();
        void loadTables();
    },
    { deep: true },
);

watch(currentPage, () => void loadTables());

onMounted(async () => {
    try {
        [branches.value, areas.value] = await Promise.all([fetchBranches(), fetchAreas(null)]);
    } catch {
        /* filtre listeleri boş kalır; tablo yine yüklenir */
    }
    await loadTables();
});

/* ================= Seçim / toplu işlem ================= */
const selected = ref<Set<number>>(new Set());

const allSelected = computed(() => rows.value.length > 0 && rows.value.every((r) => selected.value.has(r.id)));

function toggleAll(value: boolean): void {
    const next = new Set(selected.value);
    rows.value.forEach((r) => (value ? next.add(r.id) : next.delete(r.id)));
    selected.value = next;
}

function toggleOne(id: number, value: boolean): void {
    const next = new Set(selected.value);
    if (value) next.add(id);
    else next.delete(id);
    selected.value = next;
}

const bulkStatus = ref('');
const bulkArea = ref('');
const bulkBusy = ref(false);

async function runBulk(action: string, extra: Record<string, unknown> = {}): Promise<void> {
    if (bulkBusy.value || selected.value.size === 0) return;
    bulkBusy.value = true;
    try {
        const res = await api<{ affected: number }>('/api/v1/venue/tables/bulk-action', {
            method: 'POST',
            body: { table_ids: [...selected.value], action, ...extra },
        });
        success('Toplu işlem tamamlandı', `${res.affected} masa güncellendi.`);
        selected.value = new Set();
        await loadTables();
    } catch (e) {
        danger('Toplu işlem başarısız', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        bulkBusy.value = false;
    }
}

async function bulkRotateQr(): Promise<void> {
    if (bulkBusy.value || selected.value.size === 0) return;
    bulkBusy.value = true;
    try {
        const res = await api<{ rotated: number }>('/api/v1/venue/qr/rotate-bulk', {
            method: 'POST',
            body: { table_ids: [...selected.value] },
        });
        success('QR kodları yenilendi', `${res.rotated} masanın eski QR kodu geçersiz kılındı. Yeni kartları yazdırmayı unutmayın.`);
        selected.value = new Set();
        await loadTables();
    } catch (e) {
        danger('QR yenileme başarısız', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        bulkBusy.value = false;
    }
}

const bulkDeleteOpen = ref(false);

async function bulkDelete(): Promise<void> {
    bulkDeleteOpen.value = false;
    await runBulk('delete');
}

/* ================= Tekil düzenleme (drawer) ================= */
const drawerOpen = ref(false);
const editing = ref<TableRow | null>(null);
const form = ref({
    branch_id: '',
    area_id: '',
    name: '',
    number: '',
    capacity: '4',
    shape: 'square',
    status: 'available',
    is_joinable: true,
    notes: '',
    is_active: true,
});
const formErrors = ref<Record<string, string>>({});
const formBusy = ref(false);

function openCreate(): void {
    editing.value = null;
    formErrors.value = {};
    form.value = {
        branch_id: filters.value.branch_id || String(branches.value[0]?.id ?? ''),
        area_id: '',
        name: '',
        number: '',
        capacity: '4',
        shape: 'square',
        status: 'available',
        is_joinable: true,
        notes: '',
        is_active: true,
    };
    drawerOpen.value = true;
}

function openEdit(row: TableRow): void {
    editing.value = row;
    formErrors.value = {};
    form.value = {
        branch_id: String(row.branch_id),
        area_id: row.area_id === null ? '' : String(row.area_id),
        name: row.name,
        number: row.number === null ? '' : String(row.number),
        capacity: String(row.capacity),
        shape: row.shape,
        status: row.status,
        is_joinable: row.is_joinable,
        notes: row.notes ?? '',
        is_active: row.is_active,
    };
    drawerOpen.value = true;
}

const drawerAreaOptions = computed(() =>
    areas.value
        .filter((a) => String(a.branch_id) === form.value.branch_id)
        .map((a) => ({ value: String(a.id), label: a.floor_name ? `${a.name} (${a.floor_name})` : a.name })),
);

async function submitForm(): Promise<void> {
    if (formBusy.value) return;
    formBusy.value = true;
    formErrors.value = {};

    const body: Record<string, unknown> = {
        name: form.value.name,
        capacity: Number(form.value.capacity) || 4,
        shape: form.value.shape,
        is_joinable: form.value.is_joinable,
        notes: form.value.notes || null,
        is_active: form.value.is_active,
        area_id: form.value.area_id === '' ? null : Number(form.value.area_id),
    };

    if (form.value.number !== '') body.number = Number(form.value.number);

    try {
        if (editing.value === null) {
            body.branch_id = Number(form.value.branch_id);
            await api('/api/v1/venue/tables', { method: 'POST', body });
            success('Masa oluşturuldu', `${form.value.name} eklendi; QR kodu hazır.`);
        } else {
            body.status = form.value.status;
            await api(`/api/v1/venue/tables/${editing.value.id}`, { method: 'PUT', body });
            success('Masa güncellendi', `${form.value.name} kaydedildi.`);
        }
        drawerOpen.value = false;
        await loadTables();
    } catch (e) {
        if (e instanceof ApiError) {
            for (const [k, v] of Object.entries(e.errors)) formErrors.value[k] = v[0];
            if (Object.keys(formErrors.value).length === 0) danger('Kaydedilemedi', e.displayMessage);
        } else {
            danger('Kaydedilemedi', 'Beklenmeyen bir hata oluştu.');
        }
    } finally {
        formBusy.value = false;
    }
}

/* ================= Toplu oluşturma (drawer) ================= */
const bulkOpen = ref(false);
const bulkForm = ref({ branch_id: '', area_id: '', name_prefix: '', start: '1', end: '10', capacity: '4', shape: 'square' });
const bulkErrors = ref<Record<string, string>>({});
const bulkCreateBusy = ref(false);

function openBulkCreate(): void {
    bulkErrors.value = {};
    bulkForm.value = {
        branch_id: filters.value.branch_id || String(branches.value[0]?.id ?? ''),
        area_id: '',
        name_prefix: '',
        start: '1',
        end: '10',
        capacity: '4',
        shape: 'square',
    };
    bulkOpen.value = true;
}

const bulkAreaOptions = computed(() =>
    areas.value
        .filter((a) => String(a.branch_id) === bulkForm.value.branch_id)
        .map((a) => ({ value: String(a.id), label: a.floor_name ? `${a.name} (${a.floor_name})` : a.name })),
);

async function submitBulkCreate(): Promise<void> {
    if (bulkCreateBusy.value) return;
    bulkCreateBusy.value = true;
    bulkErrors.value = {};
    try {
        const res = await api<{ created_count: number }>('/api/v1/venue/tables/bulk', {
            method: 'POST',
            body: {
                branch_id: Number(bulkForm.value.branch_id),
                area_id: bulkForm.value.area_id === '' ? null : Number(bulkForm.value.area_id),
                name_prefix: bulkForm.value.name_prefix,
                start: Number(bulkForm.value.start),
                end: Number(bulkForm.value.end),
                capacity: Number(bulkForm.value.capacity) || 4,
                shape: bulkForm.value.shape,
            },
        });
        success('Masalar oluşturuldu', `${res.created_count} masa QR kodlarıyla birlikte eklendi.`);
        bulkOpen.value = false;
        await loadTables();
    } catch (e) {
        if (e instanceof ApiError) {
            for (const [k, v] of Object.entries(e.errors)) bulkErrors.value[k] = v[0];
            if (Object.keys(bulkErrors.value).length === 0) danger('Oluşturulamadı', e.displayMessage);
        } else {
            danger('Oluşturulamadı', 'Beklenmeyen bir hata oluştu.');
        }
    } finally {
        bulkCreateBusy.value = false;
    }
}

/* ================= Satır işlemleri ================= */
async function setStatus(row: TableRow, status: string): Promise<void> {
    try {
        await api(`/api/v1/venue/tables/${row.id}/status`, { method: 'PUT', body: { status } });
        await loadTables();
    } catch (e) {
        danger('Durum değiştirilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    }
}

const rotatingRow = ref<TableRow | null>(null);

async function rotateRow(): Promise<void> {
    const row = rotatingRow.value;
    if (!row) return;
    rotatingRow.value = null;
    try {
        await api(`/api/v1/venue/tables/${row.id}/qr-rotate`, { method: 'POST' });
        success('QR kodu yenilendi', `${row.name} masasının eski QR kodu artık geçersiz. Yeni kartı yazdırın.`);
        await loadTables();
    } catch (e) {
        danger('QR yenilenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    }
}

const deletingRow = ref<TableRow | null>(null);

async function deleteRow(): Promise<void> {
    const row = deletingRow.value;
    if (!row) return;
    deletingRow.value = null;
    try {
        await api(`/api/v1/venue/tables/${row.id}`, { method: 'DELETE' });
        success('Masa silindi', `${row.name} kaldırıldı.`);
        await loadTables();
    } catch (e) {
        danger('Silinemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    }
}

function downloadQr(row: TableRow, format: 'png' | 'svg'): void {
    window.location.href = `/api/v1/venue/tables/${row.id}/qr-image?format=${format}&download=1`;
}

/* ================= Tablo tanımı ================= */
const columns: TableColumn[] = [
    { key: 'select', label: '', widthClass: 'w-10' },
    { key: 'number', label: 'No', widthClass: 'w-16' },
    { key: 'name', label: 'Masa' },
    { key: 'location', label: 'Alan / Kat' },
    { key: 'capacity', label: 'Kapasite', align: 'center' },
    { key: 'status', label: 'Durum' },
    { key: 'is_active', label: 'Aktif' },
    { key: 'actions', label: 'İşlemler', align: 'right' },
];
</script>

<template>
    <Head title="Masalar" />
    <PanelShell title="Masalar">
        <VenueNav />

        <div class="flex flex-col gap-4">
            <!-- Filtreler + eylemler -->
            <BaseCard>
                <div class="flex flex-wrap items-end gap-3">
                    <div class="w-full sm:w-44">
                        <FormField label="Şube">
                            <BaseSelect v-model="filters.branch_id" :options="branchOptions" placeholder="Tümü" size="sm" />
                        </FormField>
                    </div>
                    <div class="w-full sm:w-44">
                        <FormField label="Alan">
                            <BaseSelect v-model="filters.area_id" :options="areaOptions" placeholder="Tümü" size="sm" />
                        </FormField>
                    </div>
                    <div class="w-full sm:w-44">
                        <FormField label="Durum">
                            <BaseSelect v-model="filters.status" :options="statusOptions" placeholder="Tümü" size="sm" />
                        </FormField>
                    </div>
                    <div class="w-full sm:w-36">
                        <FormField label="Aktiflik">
                            <BaseSelect
                                v-model="filters.active"
                                :options="[
                                    { value: '1', label: 'Aktif' },
                                    { value: '0', label: 'Pasif' },
                                ]"
                                placeholder="Tümü"
                                size="sm"
                            />
                        </FormField>
                    </div>
                    <div class="w-full grow sm:w-52">
                        <FormField label="Ara">
                            <SearchInput v-model="filters.q" placeholder="Masa adı veya no…" />
                        </FormField>
                    </div>
                    <div class="flex gap-2">
                        <BaseButton variant="secondary" @click="openBulkCreate">
                            <AppIcon name="plus" :size="16" />
                            Toplu oluştur
                        </BaseButton>
                        <BaseButton @click="openCreate">
                            <AppIcon name="plus" :size="16" />
                            Yeni masa
                        </BaseButton>
                    </div>
                </div>
            </BaseCard>

            <!-- Toplu işlem çubuğu -->
            <BaseCard v-if="selected.size > 0">
                <div class="flex flex-wrap items-center gap-3">
                    <p class="text-sm font-medium text-body">{{ selected.size }} masa seçili</p>
                    <div class="flex items-center gap-1.5">
                        <BaseSelect v-model="bulkStatus" :options="statusOptions" placeholder="Durum seç…" size="sm" />
                        <BaseButton size="sm" variant="secondary" :disabled="!bulkStatus" :loading="bulkBusy" @click="runBulk('set_status', { status: bulkStatus })">
                            Durumu ata
                        </BaseButton>
                    </div>
                    <div class="flex items-center gap-1.5">
                        <BaseSelect v-model="bulkArea" :options="areaOptions.filter((o) => o.value !== 'none')" placeholder="Alan seç…" size="sm" />
                        <BaseButton size="sm" variant="secondary" :disabled="!bulkArea" :loading="bulkBusy" @click="runBulk('set_area', { area_id: Number(bulkArea) })">
                            Alana taşı
                        </BaseButton>
                    </div>
                    <div class="flex items-center gap-1.5">
                        <BaseButton size="sm" variant="secondary" :loading="bulkBusy" @click="runBulk('activate')">Aktifleştir</BaseButton>
                        <BaseButton size="sm" variant="secondary" :loading="bulkBusy" @click="runBulk('deactivate')">Pasifleştir</BaseButton>
                        <BaseButton size="sm" variant="secondary" :loading="bulkBusy" @click="bulkRotateQr">
                            <AppIcon name="qr-code" :size="14" />
                            QR yenile
                        </BaseButton>
                        <BaseButton size="sm" variant="danger" :loading="bulkBusy" @click="bulkDeleteOpen = true">
                            <AppIcon name="trash" :size="14" />
                            Sil
                        </BaseButton>
                    </div>
                </div>
            </BaseCard>

            <!-- Masa listesi -->
            <BaseCard flush>
                <DataTable :columns="columns" :rows="rows" :loading="loading" caption="Masa listesi" empty-title="Masa bulunamadı" empty-description="Filtreleri değiştirin veya yeni masa oluşturun.">
                    <template #cell-select="{ row }">
                        <BaseCheckbox
                            :model-value="selected.has((row as unknown as TableRow).id)"
                            label=""
                            @update:model-value="(v: boolean) => toggleOne((row as unknown as TableRow).id, v)"
                        />
                    </template>
                    <template #cell-number="{ row }">
                        <span class="font-mono text-sm">{{ (row as unknown as TableRow).number ?? '—' }}</span>
                    </template>
                    <template #cell-name="{ row }">
                        <div class="flex flex-col">
                            <span class="font-medium">{{ (row as unknown as TableRow).name }}</span>
                            <span class="text-xs text-muted">{{ (row as unknown as TableRow).branch_name }} · {{ (row as unknown as TableRow).shape_label }}</span>
                        </div>
                    </template>
                    <template #cell-location="{ row }">
                        <span v-if="(row as unknown as TableRow).area_name">
                            {{ (row as unknown as TableRow).area_name }}
                            <span v-if="(row as unknown as TableRow).floor_name" class="text-xs text-muted"> · {{ (row as unknown as TableRow).floor_name }}</span>
                        </span>
                        <span v-else class="text-subtle">—</span>
                    </template>
                    <template #cell-capacity="{ row }">
                        <span class="inline-flex items-center gap-1">
                            <AppIcon name="users" :size="14" class="text-muted" />
                            {{ (row as unknown as TableRow).capacity }}
                        </span>
                    </template>
                    <template #cell-status="{ row }">
                        <!-- Durum: renk + ikon + metin birlikte (renk körlüğü desteği) -->
                        <BaseBadge :variant="(row as unknown as TableRow).status_variant" no-icon>
                            <AppIcon :name="(row as unknown as TableRow).status_icon" :size="12" />
                            {{ (row as unknown as TableRow).status_label }}
                        </BaseBadge>
                    </template>
                    <template #cell-is_active="{ row }">
                        <BaseBadge v-if="(row as unknown as TableRow).is_active" variant="success">Aktif</BaseBadge>
                        <BaseBadge v-else variant="neutral" no-icon>
                            <AppIcon name="x" :size="12" />
                            Pasif
                        </BaseBadge>
                    </template>
                    <template #cell-actions="{ row }">
                        <div class="flex items-center justify-end gap-1">
                            <BaseButton size="sm" variant="ghost" icon-only label="Masayı düzenle" @click="openEdit(row as unknown as TableRow)">
                                <AppIcon name="pencil" :size="16" />
                            </BaseButton>
                            <BaseDropdown menu-label="Masa işlemleri">
                                <template #trigger="{ toggle, ariaAttrs }">
                                    <button
                                        type="button"
                                        v-bind="ariaAttrs"
                                        class="flex size-8 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                                        aria-label="Diğer işlemler"
                                        @click="toggle"
                                    >
                                        <AppIcon name="dots-vertical" :size="16" />
                                    </button>
                                </template>
                                <DropdownItem icon="qr-code" @click="downloadQr(row as unknown as TableRow, 'png')">QR indir (PNG)</DropdownItem>
                                <DropdownItem icon="qr-code" @click="downloadQr(row as unknown as TableRow, 'svg')">QR indir (SVG)</DropdownItem>
                                <DropdownItem icon="alert-triangle" @click="rotatingRow = row as unknown as TableRow">QR kodunu yenile</DropdownItem>
                                <DropdownItem icon="trash" danger @click="deletingRow = row as unknown as TableRow">Masayı sil</DropdownItem>
                            </BaseDropdown>
                        </div>
                    </template>
                </DataTable>
                <div class="border-t border-default p-3">
                    <div class="mb-2 flex items-center gap-2 px-1">
                        <BaseCheckbox :model-value="allSelected" label="Sayfadakilerin tümünü seç" @update:model-value="toggleAll" />
                    </div>
                    <BasePagination v-model:page="currentPage" :last-page="lastPage" :total="total" />
                </div>
            </BaseCard>
        </div>

        <!-- Tekil masa drawer -->
        <BaseDrawer :open="drawerOpen" :title="editing ? 'Masayı düzenle' : 'Yeni masa'" @close="drawerOpen = false">
            <form class="flex flex-col gap-4" @submit.prevent="submitForm">
                <FormField v-if="!editing" label="Şube" required :error="formErrors.branch_id">
                    <BaseSelect v-model="form.branch_id" :options="branchOptions" placeholder="Şube seçin" />
                </FormField>
                <FormField label="Masa adı / etiketi" required :error="formErrors.name" hint="Şube içinde tekildir (ör. Teras 4, Pencere Kenarı)">
                    <BaseInput v-model="form.name" placeholder="ör. Teras 4" />
                </FormField>
                <FormField label="Masa no" :error="formErrors.number" hint="Boş bırakılırsa sıradaki numara verilir; şube içinde tekildir">
                    <BaseInput v-model="form.number" inputmode="numeric" placeholder="Otomatik" />
                </FormField>
                <FormField label="Alan" :error="formErrors.area_id">
                    <BaseSelect v-model="form.area_id" :options="drawerAreaOptions" placeholder="Alansız" />
                </FormField>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Kapasite" :error="formErrors.capacity">
                        <BaseInput v-model="form.capacity" inputmode="numeric" />
                    </FormField>
                    <FormField label="Şekil" :error="formErrors.shape">
                        <BaseSelect v-model="form.shape" :options="shapeOptions" />
                    </FormField>
                </div>
                <FormField v-if="editing" label="Durum" :error="formErrors.status">
                    <BaseSelect v-model="form.status" :options="statusOptions" />
                </FormField>
                <FormField label="Not" :error="formErrors.notes">
                    <BaseInput v-model="form.notes" placeholder="İsteğe bağlı not" />
                </FormField>
                <BaseCheckbox v-model="form.is_joinable" label="Birleştirilebilir" description="Yan masalarla birleştirilerek büyük grup ağırlayabilir" />
                <BaseCheckbox v-model="form.is_active" label="Aktif" description="Pasif masalar public menüde ve operasyonda görünmez" />
                <div class="flex justify-end gap-2 pt-2">
                    <BaseButton variant="secondary" @click="drawerOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="formBusy">{{ editing ? 'Kaydet' : 'Oluştur' }}</BaseButton>
                </div>
            </form>
        </BaseDrawer>

        <!-- Toplu oluşturma drawer -->
        <BaseDrawer :open="bulkOpen" title="Toplu masa oluştur" @close="bulkOpen = false">
            <form class="flex flex-col gap-4" @submit.prevent="submitBulkCreate">
                <p class="text-sm text-muted">
                    "Önek + numara aralığı" ile tek seferde en fazla 200 masa oluşturur; her masa kendi QR koduyla gelir.
                    Örnek: önek <strong>Teras</strong>, aralık <strong>1–20</strong> → Teras 1 … Teras 20.
                </p>
                <FormField label="Şube" required :error="bulkErrors.branch_id">
                    <BaseSelect v-model="bulkForm.branch_id" :options="branchOptions" placeholder="Şube seçin" />
                </FormField>
                <FormField label="Alan" :error="bulkErrors.area_id">
                    <BaseSelect v-model="bulkForm.area_id" :options="bulkAreaOptions" placeholder="Alansız" />
                </FormField>
                <FormField label="Ad öneki" required :error="bulkErrors.name_prefix">
                    <BaseInput v-model="bulkForm.name_prefix" placeholder="ör. Teras" />
                </FormField>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Başlangıç no" required :error="bulkErrors.start">
                        <BaseInput v-model="bulkForm.start" inputmode="numeric" />
                    </FormField>
                    <FormField label="Bitiş no" required :error="bulkErrors.end">
                        <BaseInput v-model="bulkForm.end" inputmode="numeric" />
                    </FormField>
                </div>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Kapasite" :error="bulkErrors.capacity">
                        <BaseInput v-model="bulkForm.capacity" inputmode="numeric" />
                    </FormField>
                    <FormField label="Şekil" :error="bulkErrors.shape">
                        <BaseSelect v-model="bulkForm.shape" :options="shapeOptions" />
                    </FormField>
                </div>
                <div class="flex justify-end gap-2 pt-2">
                    <BaseButton variant="secondary" @click="bulkOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="bulkCreateBusy">Masaları oluştur</BaseButton>
                </div>
            </form>
        </BaseDrawer>

        <!-- Onay pencereleri -->
        <BaseModal :open="rotatingRow !== null" title="QR kodunu yenile" size="sm" @close="rotatingRow = null">
            <p class="text-sm text-muted">
                <strong>{{ rotatingRow?.name }}</strong> masasının QR kodu yenilenecek; masadaki basılı eski kod
                <strong>anında geçersiz</strong> olacak. Yeni kartı yazdırıp masaya koymadan eski kod çalışmayacaktır.
            </p>
            <template #footer>
                <BaseButton variant="secondary" @click="rotatingRow = null">Vazgeç</BaseButton>
                <BaseButton variant="danger" @click="rotateRow">Yenile</BaseButton>
            </template>
        </BaseModal>

        <BaseModal :open="deletingRow !== null" title="Masayı sil" size="sm" @close="deletingRow = null">
            <p class="text-sm text-muted">
                <strong>{{ deletingRow?.name }}</strong> masası ve QR kodu kalıcı olarak silinecek. Bu işlem geri alınamaz.
            </p>
            <template #footer>
                <BaseButton variant="secondary" @click="deletingRow = null">Vazgeç</BaseButton>
                <BaseButton variant="danger" @click="deleteRow">Sil</BaseButton>
            </template>
        </BaseModal>

        <BaseModal :open="bulkDeleteOpen" title="Seçili masaları sil" size="sm" @close="bulkDeleteOpen = false">
            <p class="text-sm text-muted">{{ selected.size }} masa ve QR kodları kalıcı olarak silinecek. Bu işlem geri alınamaz.</p>
            <template #footer>
                <BaseButton variant="secondary" @click="bulkDeleteOpen = false">Vazgeç</BaseButton>
                <BaseButton variant="danger" :loading="bulkBusy" @click="bulkDelete">Sil</BaseButton>
            </template>
        </BaseModal>
    </PanelShell>
</template>
