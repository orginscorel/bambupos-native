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
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import DataTable, { type TableColumn } from '@/Components/ui/DataTable.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import VenueNav from './VenueNav.vue';
import { fetchAreas, fetchBranches, fetchFloors, metaFromProps, type AreaRow, type BranchRow, type FloorRow } from './venue';

const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

const branches = ref<BranchRow[]>([]);
const floors = ref<FloorRow[]>([]);
const areas = ref<AreaRow[]>([]);
const branchId = ref('');
const loading = ref(true);

const branchOptions = computed(() => branches.value.map((b) => ({ value: String(b.id), label: b.name })));
const floorOptions = computed(() => floors.value.map((f) => ({ value: String(f.id), label: f.name })));
const typeOptions = computed(() => meta.areaTypes.map((t) => ({ value: t.value, label: t.label })));

async function loadAll(): Promise<void> {
    loading.value = true;
    try {
        const id = branchId.value ? Number(branchId.value) : null;
        [floors.value, areas.value] = await Promise.all([fetchFloors(id), fetchAreas(id)]);
    } catch (e) {
        danger('Alanlar yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

watch(branchId, () => void loadAll());

onMounted(async () => {
    try {
        branches.value = await fetchBranches();
        branchId.value = String(branches.value[0]?.id ?? '');
    } catch {
        /* şubeler yüklenemezse boş liste gösterilir */
    }
    if (!branchId.value) await loadAll();
});

/* ================= Kat yönetimi ================= */
const floorName = ref('');
const floorBusy = ref(false);
const editingFloor = ref<FloorRow | null>(null);
const editingFloorName = ref('');
const deletingFloor = ref<FloorRow | null>(null);

async function addFloor(): Promise<void> {
    if (floorBusy.value || !floorName.value.trim() || !branchId.value) return;
    floorBusy.value = true;
    try {
        await api('/api/v1/venue/floors', {
            method: 'POST',
            body: { branch_id: Number(branchId.value), name: floorName.value.trim(), sort_order: floors.value.length },
        });
        success('Kat eklendi', `${floorName.value.trim()} oluşturuldu.`);
        floorName.value = '';
        await loadAll();
    } catch (e) {
        danger('Kat eklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        floorBusy.value = false;
    }
}

async function renameFloor(): Promise<void> {
    const floor = editingFloor.value;
    if (!floor || !editingFloorName.value.trim()) return;
    try {
        await api(`/api/v1/venue/floors/${floor.id}`, { method: 'PUT', body: { name: editingFloorName.value.trim() } });
        success('Kat güncellendi', 'Kat adı kaydedildi.');
        editingFloor.value = null;
        await loadAll();
    } catch (e) {
        danger('Kat güncellenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    }
}

async function removeFloor(): Promise<void> {
    const floor = deletingFloor.value;
    if (!floor) return;
    deletingFloor.value = null;
    try {
        await api(`/api/v1/venue/floors/${floor.id}`, { method: 'DELETE' });
        success('Kat silindi', `${floor.name} kaldırıldı; alanlar katsız kaldı.`);
        await loadAll();
    } catch (e) {
        danger('Kat silinemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    }
}

/* ================= Alan yönetimi ================= */
const drawerOpen = ref(false);
const editingArea = ref<AreaRow | null>(null);
const form = ref({ name: '', type: 'indoor', floor_id: '', is_active: true });
const formErrors = ref<Record<string, string>>({});
const formBusy = ref(false);
const deletingArea = ref<AreaRow | null>(null);

function openCreate(): void {
    editingArea.value = null;
    formErrors.value = {};
    form.value = { name: '', type: 'indoor', floor_id: '', is_active: true };
    drawerOpen.value = true;
}

function openEdit(area: AreaRow): void {
    editingArea.value = area;
    formErrors.value = {};
    form.value = {
        name: area.name,
        type: area.type,
        floor_id: area.floor_id === null ? '' : String(area.floor_id),
        is_active: area.is_active,
    };
    drawerOpen.value = true;
}

async function submitArea(): Promise<void> {
    if (formBusy.value) return;
    formBusy.value = true;
    formErrors.value = {};

    const body: Record<string, unknown> = {
        name: form.value.name,
        type: form.value.type,
        floor_id: form.value.floor_id === '' ? null : Number(form.value.floor_id),
        is_active: form.value.is_active,
    };

    try {
        if (editingArea.value === null) {
            body.branch_id = Number(branchId.value);
            await api('/api/v1/venue/areas', { method: 'POST', body });
            success('Alan oluşturuldu', `${form.value.name} eklendi.`);
        } else {
            await api(`/api/v1/venue/areas/${editingArea.value.id}`, { method: 'PUT', body });
            success('Alan güncellendi', `${form.value.name} kaydedildi.`);
        }
        drawerOpen.value = false;
        await loadAll();
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

async function removeArea(): Promise<void> {
    const area = deletingArea.value;
    if (!area) return;
    deletingArea.value = null;
    try {
        await api(`/api/v1/venue/areas/${area.id}`, { method: 'DELETE' });
        success('Alan silindi', `${area.name} kaldırıldı; masaları alansız kaldı.`);
        await loadAll();
    } catch (e) {
        danger('Alan silinemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    }
}

const areaColumns: TableColumn[] = [
    { key: 'name', label: 'Alan' },
    { key: 'type_label', label: 'Tür' },
    { key: 'floor_name', label: 'Kat' },
    { key: 'tables_count', label: 'Masa sayısı', align: 'center' },
    { key: 'is_active', label: 'Aktif' },
    { key: 'actions', label: 'İşlemler', align: 'right' },
];
</script>

<template>
    <Head title="Alanlar ve Katlar" />
    <!-- TAM KAPLAMA: mekân gezinmesi SABİT şeritte; içerik kendi içinde kayar. -->
    <PanelShell title="Alanlar ve Katlar" flush canvas>
        <div class="shrink-0 border-b border-default bg-raised px-4 py-2.5 sm:px-6">
            <VenueNav />
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">
            <BaseCard>
                <div class="flex flex-wrap items-end gap-3">
                    <div class="w-full sm:w-64">
                        <FormField label="Şube" hint="Alan hiyerarşisi: şube → kat → salon/alan → masa">
                            <BaseSelect v-model="branchId" :options="branchOptions" placeholder="Şube seçin" />
                        </FormField>
                    </div>
                    <BaseButton :disabled="!branchId" @click="openCreate">
                        <AppIcon name="plus" :size="16" />
                        Yeni alan
                    </BaseButton>
                </div>
            </BaseCard>

            <div class="grid gap-4 lg:grid-cols-3">
                <!-- Katlar -->
                <BaseCard title="Katlar">
                    <div class="flex flex-col gap-2">
                        <form class="flex gap-2" @submit.prevent="addFloor">
                            <BaseInput v-model="floorName" size="sm" placeholder="ör. Zemin Kat" :disabled="!branchId" />
                            <BaseButton size="sm" type="submit" :loading="floorBusy" :disabled="!branchId || !floorName.trim()">Ekle</BaseButton>
                        </form>
                        <EmptyState v-if="floors.length === 0" title="Kat yok" description="Kat tanımı isteğe bağlıdır; tek katlı işletmelerde gerekmez." icon="home" />
                        <ul v-else class="flex flex-col">
                            <li v-for="floor in floors" :key="floor.id" class="flex items-center gap-2 border-b border-default py-2 last:border-b-0">
                                <AppIcon name="home" :size="15" class="text-muted" />
                                <span class="grow text-sm text-body">{{ floor.name }}</span>
                                <span class="text-xs text-muted">{{ floor.areas_count }} alan</span>
                                <BaseButton size="sm" variant="ghost" icon-only label="Katı yeniden adlandır" @click="editingFloor = floor; editingFloorName = floor.name">
                                    <AppIcon name="pencil" :size="14" />
                                </BaseButton>
                                <BaseButton size="sm" variant="ghost" icon-only label="Katı sil" @click="deletingFloor = floor">
                                    <AppIcon name="trash" :size="14" />
                                </BaseButton>
                            </li>
                        </ul>
                    </div>
                </BaseCard>

                <!-- Alanlar -->
                <div class="lg:col-span-2">
                    <BaseCard flush title="Salonlar ve Alanlar">
                        <DataTable :columns="areaColumns" :rows="areas" :loading="loading" caption="Alan listesi" empty-title="Alan yok" empty-description="İç salon, teras, bahçe gibi alanlar oluşturup masaları gruplayın.">
                            <template #cell-name="{ row }">
                                <span class="font-medium">{{ (row as unknown as AreaRow).name }}</span>
                            </template>
                            <template #cell-floor_name="{ row }">
                                <span v-if="(row as unknown as AreaRow).floor_name">{{ (row as unknown as AreaRow).floor_name }}</span>
                                <span v-else class="text-subtle">—</span>
                            </template>
                            <template #cell-is_active="{ row }">
                                <BaseBadge v-if="(row as unknown as AreaRow).is_active" variant="success">Aktif</BaseBadge>
                                <BaseBadge v-else variant="neutral" no-icon>
                                    <AppIcon name="x" :size="12" />
                                    Pasif
                                </BaseBadge>
                            </template>
                            <template #cell-actions="{ row }">
                                <div class="flex items-center justify-end gap-1">
                                    <BaseButton size="sm" variant="ghost" icon-only label="Alanı düzenle" @click="openEdit(row as unknown as AreaRow)">
                                        <AppIcon name="pencil" :size="16" />
                                    </BaseButton>
                                    <BaseButton size="sm" variant="ghost" icon-only label="Alanı sil" @click="deletingArea = row as unknown as AreaRow">
                                        <AppIcon name="trash" :size="16" />
                                    </BaseButton>
                                </div>
                            </template>
                        </DataTable>
                    </BaseCard>
                </div>
            </div>
        </div>

        <!-- Alan drawer -->
        <BaseDrawer :open="drawerOpen" :title="editingArea ? 'Alanı düzenle' : 'Yeni alan'" @close="drawerOpen = false">
            <form class="flex flex-col gap-4" @submit.prevent="submitArea">
                <FormField label="Alan adı" required :error="formErrors.name">
                    <BaseInput v-model="form.name" placeholder="ör. Teras" />
                </FormField>
                <FormField label="Tür" :error="formErrors.type">
                    <BaseSelect v-model="form.type" :options="typeOptions" />
                </FormField>
                <FormField label="Kat" :error="formErrors.floor_id" hint="İsteğe bağlı">
                    <BaseSelect v-model="form.floor_id" :options="floorOptions" placeholder="Katsız" />
                </FormField>
                <BaseSwitch v-model="form.is_active" label="Aktif" />
                <div class="flex justify-end gap-2 pt-2">
                    <BaseButton variant="secondary" @click="drawerOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="formBusy">{{ editingArea ? 'Kaydet' : 'Oluştur' }}</BaseButton>
                </div>
            </form>
        </BaseDrawer>

        <!-- Kat yeniden adlandırma -->
        <BaseModal :open="editingFloor !== null" title="Katı yeniden adlandır" size="sm" @close="editingFloor = null">
            <FormField label="Kat adı">
                <BaseInput v-model="editingFloorName" />
            </FormField>
            <template #footer>
                <BaseButton variant="secondary" @click="editingFloor = null">Vazgeç</BaseButton>
                <BaseButton @click="renameFloor">Kaydet</BaseButton>
            </template>
        </BaseModal>

        <!-- Silme onayları -->
        <BaseModal :open="deletingFloor !== null" title="Katı sil" size="sm" @close="deletingFloor = null">
            <p class="text-sm text-muted">
                <strong>{{ deletingFloor?.name }}</strong> silinecek; bu kattaki alanlar silinmez, katsız kalır.
            </p>
            <template #footer>
                <BaseButton variant="secondary" @click="deletingFloor = null">Vazgeç</BaseButton>
                <BaseButton variant="danger" @click="removeFloor">Sil</BaseButton>
            </template>
        </BaseModal>

        <BaseModal :open="deletingArea !== null" title="Alanı sil" size="sm" @close="deletingArea = null">
            <p class="text-sm text-muted">
                <strong>{{ deletingArea?.name }}</strong> silinecek; alandaki masalar silinmez, alansız kalır.
            </p>
            <template #footer>
                <BaseButton variant="secondary" @click="deletingArea = null">Vazgeç</BaseButton>
                <BaseButton variant="danger" @click="removeArea">Sil</BaseButton>
            </template>
        </BaseModal>
        </div>
    </PanelShell>
</template>
