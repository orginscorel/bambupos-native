<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
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
import DataTable, { type TableColumn } from '@/Components/ui/DataTable.vue';
import FormField from '@/Components/ui/FormField.vue';
import VenueNav from './VenueNav.vue';
import { fetchBranches, type BranchRow } from './venue';

const { success, danger } = useToast();

const branches = ref<BranchRow[]>([]);
const loading = ref(true);

async function load(): Promise<void> {
    loading.value = true;
    try {
        branches.value = await fetchBranches();
    } catch (e) {
        danger('Şubeler yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/* ================= Oluştur / düzenle ================= */
const drawerOpen = ref(false);
const editing = ref<BranchRow | null>(null);
const form = ref({ name: '', code: '', address: '', phone: '', timezone: 'Europe/Istanbul', is_active: true });
const formErrors = ref<Record<string, string>>({});
const formBusy = ref(false);

function openCreate(): void {
    editing.value = null;
    formErrors.value = {};
    form.value = { name: '', code: '', address: '', phone: '', timezone: 'Europe/Istanbul', is_active: true };
    drawerOpen.value = true;
}

function openEdit(row: BranchRow): void {
    editing.value = row;
    formErrors.value = {};
    form.value = {
        name: row.name,
        code: row.code ?? '',
        address: row.address ?? '',
        phone: row.phone ?? '',
        timezone: row.timezone,
        is_active: row.is_active,
    };
    drawerOpen.value = true;
}

async function submit(): Promise<void> {
    if (formBusy.value) return;
    formBusy.value = true;
    formErrors.value = {};

    const body = {
        name: form.value.name,
        code: form.value.code || null,
        address: form.value.address || null,
        phone: form.value.phone || null,
        timezone: form.value.timezone,
        is_active: form.value.is_active,
    };

    try {
        if (editing.value === null) {
            await api('/api/v1/venue/branches', { method: 'POST', body });
            success('Şube oluşturuldu', `${form.value.name} eklendi.`);
        } else {
            await api(`/api/v1/venue/branches/${editing.value.id}`, { method: 'PUT', body });
            success('Şube güncellendi', `${form.value.name} kaydedildi.`);
        }
        drawerOpen.value = false;
        await load();
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

/* ================= Silme ================= */
const deleting = ref<BranchRow | null>(null);

async function remove(): Promise<void> {
    const row = deleting.value;
    if (!row) return;
    deleting.value = null;
    try {
        await api(`/api/v1/venue/branches/${row.id}`, { method: 'DELETE' });
        success('Şube silindi', `${row.name} kaldırıldı.`);
        await load();
    } catch (e) {
        danger('Şube silinemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    }
}

const columns: TableColumn[] = [
    { key: 'name', label: 'Şube' },
    { key: 'code', label: 'Kod' },
    { key: 'phone', label: 'Telefon' },
    { key: 'areas_count', label: 'Alan', align: 'center' },
    { key: 'tables_count', label: 'Masa', align: 'center' },
    { key: 'is_active', label: 'Durum' },
    { key: 'actions', label: 'İşlemler', align: 'right' },
];
</script>

<template>
    <Head title="Şubeler" />
    <PanelShell title="Şubeler">
        <VenueNav />

        <div class="flex flex-col gap-4">
            <BaseCard flush>
                <template #header>
                    <h2 class="text-sm font-semibold text-body">Şubeler</h2>
                </template>
                <template #actions>
                    <BaseButton size="sm" @click="openCreate">
                        <AppIcon name="plus" :size="15" />
                        Yeni şube
                    </BaseButton>
                </template>
                <DataTable :columns="columns" :rows="branches" :loading="loading" caption="Şube listesi" empty-title="Şube yok" empty-description="İlk şubenizi oluşturun.">
                    <template #cell-name="{ row }">
                        <div class="flex flex-col">
                            <span class="font-medium">{{ (row as unknown as BranchRow).name }}</span>
                            <span v-if="(row as unknown as BranchRow).address" class="max-w-64 truncate text-xs text-muted">{{ (row as unknown as BranchRow).address }}</span>
                        </div>
                    </template>
                    <template #cell-code="{ row }">
                        <span v-if="(row as unknown as BranchRow).code" class="font-mono text-xs">{{ (row as unknown as BranchRow).code }}</span>
                        <span v-else class="text-subtle">—</span>
                    </template>
                    <template #cell-phone="{ row }">
                        <span v-if="(row as unknown as BranchRow).phone">{{ (row as unknown as BranchRow).phone }}</span>
                        <span v-else class="text-subtle">—</span>
                    </template>
                    <template #cell-is_active="{ row }">
                        <BaseBadge v-if="(row as unknown as BranchRow).is_active" variant="success">Aktif</BaseBadge>
                        <BaseBadge v-else variant="neutral" no-icon>
                            <AppIcon name="x" :size="12" />
                            Pasif
                        </BaseBadge>
                    </template>
                    <template #cell-actions="{ row }">
                        <div class="flex items-center justify-end gap-1">
                            <BaseButton size="sm" variant="ghost" icon-only label="Şubeyi düzenle" @click="openEdit(row as unknown as BranchRow)">
                                <AppIcon name="pencil" :size="16" />
                            </BaseButton>
                            <BaseButton size="sm" variant="ghost" icon-only label="Şubeyi sil" @click="deleting = row as unknown as BranchRow">
                                <AppIcon name="trash" :size="16" />
                            </BaseButton>
                        </div>
                    </template>
                </DataTable>
            </BaseCard>
        </div>

        <BaseDrawer :open="drawerOpen" :title="editing ? 'Şubeyi düzenle' : 'Yeni şube'" @close="drawerOpen = false">
            <form class="flex flex-col gap-4" @submit.prevent="submit">
                <FormField label="Şube adı" required :error="formErrors.name">
                    <BaseInput v-model="form.name" placeholder="ör. Merkez Şube" />
                </FormField>
                <FormField label="Kod" :error="formErrors.code" hint="Kısa tekil kod (raporlarda kullanılır)">
                    <BaseInput v-model="form.code" placeholder="ör. MERKEZ" />
                </FormField>
                <FormField label="Adres" :error="formErrors.address">
                    <BaseInput v-model="form.address" />
                </FormField>
                <FormField label="Telefon" :error="formErrors.phone">
                    <BaseInput v-model="form.phone" inputmode="tel" />
                </FormField>
                <FormField label="Saat dilimi" :error="formErrors.timezone">
                    <BaseInput v-model="form.timezone" placeholder="Europe/Istanbul" />
                </FormField>
                <BaseSwitch v-model="form.is_active" label="Aktif" description="Pasif şubenin menüsü ve masaları müşteriye kapalıdır" />
                <div class="flex justify-end gap-2 pt-2">
                    <BaseButton variant="secondary" @click="drawerOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="formBusy">{{ editing ? 'Kaydet' : 'Oluştur' }}</BaseButton>
                </div>
            </form>
        </BaseDrawer>

        <BaseModal :open="deleting !== null" title="Şubeyi sil" size="sm" @close="deleting = null">
            <p class="text-sm text-muted">
                <strong>{{ deleting?.name }}</strong> silinecek. Masası olan şube silinemez; son şube de silinemez.
            </p>
            <template #footer>
                <BaseButton variant="secondary" @click="deleting = null">Vazgeç</BaseButton>
                <BaseButton variant="danger" @click="remove">Sil</BaseButton>
            </template>
        </BaseModal>
    </PanelShell>
</template>
