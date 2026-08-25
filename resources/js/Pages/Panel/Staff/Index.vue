<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseDropdown from '@/Components/ui/BaseDropdown.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BasePagination from '@/Components/ui/BasePagination.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import DataTable, { type TableColumn } from '@/Components/ui/DataTable.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import TableToolbar from '@/Components/ui/TableToolbar.vue';
import FilterChip from '@/Components/ui/FilterChip.vue';
import BottomSheet from '@/Components/ui/BottomSheet.vue';
import StaffShell from './components/StaffShell.vue';
import StaffFormDrawer from './components/StaffFormDrawer.vue';
import OverridesDrawer from './components/OverridesDrawer.vue';
import PinModal from './components/PinModal.vue';
import type { Paginated, StaffMeta, StaffRow } from './types';

/**
 * /panel/personel — personel listesi:
 * arama + şube/rol/durum filtreleri, hesap açma/düzenleme,
 * aktif-pasif SWITCH, PIN, parola sıfırlama bağlantısı,
 * işten çıkarma (pasife alma — silme YOK, veri kaybı yok).
 */
const { success, danger } = useToast();
const page = usePage();

const actorId = computed<number>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { user?: { id: number } } | undefined;
    return auth?.user?.id ?? 0;
});

/* ---- Veri ---- */
const loading = ref(true);
const meta = ref<StaffMeta | null>(null);
const rows = ref<StaffRow[]>([]);
const pageNo = ref(1);
const lastPage = ref(1);
const total = ref(0);

/* ---- Filtreler ---- */
const q = ref('');
const branchId = ref('');
const roleId = ref('');
const status = ref('');

const branchOptions = computed(() => [
    { value: '', label: 'Tüm şubeler' },
    ...(meta.value?.branches ?? []).map((b) => ({ value: String(b.id), label: b.name })),
]);
const roleOptions = computed(() => [
    { value: '', label: 'Tüm roller' },
    ...(meta.value?.roles ?? []).map((r) => ({ value: String(r.id), label: r.name })),
]);
const statusOptions = [
    { value: '', label: 'Tüm durumlar' },
    { value: 'active', label: 'Aktif' },
    { value: 'passive', label: 'Pasif (işten çıkmış)' },
];

const canManage = computed(() => meta.value?.actor.can_manage_staff ?? false);

/* ---- Native mobil filtre (chip + bottom sheet) ---- */
const filterSheet = ref(false);
/** Şube/rol seçili mi (durum mobilde chip; sheet rozetine sayılmaz). */
const mobileFilterCount = computed(() => (branchId.value ? 1 : 0) + (roleId.value ? 1 : 0));
function clearMobileFilters(): void {
    branchId.value = '';
    roleId.value = '';
    status.value = '';
}

/* Kolonlar: 'name' kart başlığı; ikincil kolonlar dar ekranda karta iner;
 * 'actions' sağa yapışık kalır (kırpılmaz). */
const columns: TableColumn[] = [
    { key: 'name', label: 'Personel', priority: 'primary' },
    { key: 'branch', label: 'Şube', hideBelow: 'lg' },
    { key: 'roles', label: 'Roller', hideBelow: 'md' },
    { key: 'last_login', label: 'Son giriş', hideBelow: 'lg' },
    { key: 'is_active', label: 'Aktif', align: 'center', widthClass: 'w-20' },
    { key: 'actions', label: 'İşlemler', align: 'right', action: true },
];

async function load(): Promise<void> {
    loading.value = true;
    try {
        const params = new URLSearchParams();
        if (q.value) params.set('q', q.value);
        if (branchId.value) params.set('branch_id', branchId.value);
        if (roleId.value) params.set('role_id', roleId.value);
        if (status.value) params.set('status', status.value);
        params.set('page', String(pageNo.value));

        const result = await api<Paginated<StaffRow>>(`/api/v1/staff?${params}`);
        rows.value = result.data;
        lastPage.value = result.last_page;
        total.value = result.total;
    } catch (e) {
        danger('Personel listesi yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
}

onMounted(async () => {
    try {
        meta.value = await api<StaffMeta>('/api/v1/staff-access/meta');
    } catch {
        /* meta yüklenemedi; liste yine denenir */
    }
    await load();
});

watch([q, branchId, roleId, status], () => {
    pageNo.value = 1;
    void load();
});
watch(pageNo, () => void load());

/* ---- Aktif/pasif switch ---- */
const togglingId = ref(0);

async function toggleActive(row: StaffRow, value: boolean): Promise<void> {
    if (togglingId.value) return;
    togglingId.value = row.id;
    const previous = row.is_active;
    row.is_active = value; // iyimser
    try {
        await api(`/api/v1/staff/${row.id}`, { method: 'PUT', body: { is_active: value } });
        success(value ? 'Hesap aktifleştirildi' : 'Hesap pasife alındı', row.name);
    } catch (e) {
        row.is_active = previous;
        danger('Durum değiştirilemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        togglingId.value = 0;
    }
}

/* ---- Çekmeceler / modal ---- */
const formOpen = ref(false);
const overridesOpen = ref(false);
const pinOpen = ref(false);
const selected = ref<StaffRow | null>(null);

function openCreate(): void {
    selected.value = null;
    formOpen.value = true;
}
function openEdit(row: StaffRow): void {
    selected.value = row;
    formOpen.value = true;
}
function openOverrides(row: StaffRow): void {
    selected.value = row;
    overridesOpen.value = true;
}
function openPin(row: StaffRow): void {
    selected.value = row;
    pinOpen.value = true;
}

/* ---- Parola sıfırlama bağlantısı ---- */
async function sendResetLink(row: StaffRow): Promise<void> {
    try {
        await api(`/api/v1/staff-access/${row.id}/send-reset-link`, { method: 'POST' });
        success('Bağlantı gönderildi', `${row.email} adresine parola sıfırlama bağlantısı e-postalandı.`);
    } catch (e) {
        danger('Gönderilemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    }
}

/* ---- İşten çıkarma ---- */
const terminateTarget = ref<StaffRow | null>(null);
const terminating = ref(false);

async function terminate(): Promise<void> {
    const row = terminateTarget.value;
    if (!row || terminating.value) return;
    terminating.value = true;
    try {
        await api(`/api/v1/staff-access/${row.id}/terminate`, { method: 'POST' });
        success('İşten çıkarıldı', `${row.name} pasife alındı; tüm kayıtları KORUNUYOR.`);
        terminateTarget.value = null;
        await load();
    } catch (e) {
        danger('İşlem yapılamadı', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        terminating.value = false;
    }
}

async function reactivate(row: StaffRow): Promise<void> {
    try {
        await api(`/api/v1/staff-access/${row.id}/activate`, { method: 'POST' });
        success('Yeniden aktifleştirildi', row.name);
        await load();
    } catch (e) {
        danger('İşlem yapılamadı', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    }
}

/* ---- Test için giriş (impersonation) ----
 * Yönetici, personelin oturumuna geçip gördüğü ekran/yetkiyi test eder.
 * Sistem rolü (ör. Sahip) taşıyanlar gizlenir; nihai denetim backend'de. */
const impersonateTarget = ref<StaffRow | null>(null);
const impersonating = ref(false);

function canImpersonate(row: StaffRow): boolean {
    return canManage.value && row.is_active && row.id !== actorId.value && !row.roles.some((r) => r.is_system);
}

async function impersonate(): Promise<void> {
    const row = impersonateTarget.value;
    if (!row || impersonating.value) return;
    impersonating.value = true;
    try {
        const res = await api<{ redirect_to?: string }>(`/api/v1/staff/${row.id}/impersonate`, { method: 'POST' });
        // Tam sayfa yenileme: Inertia paylaşılan auth + impersonating prop'ları yeniden yüklensin.
        window.location.href = res.redirect_to ?? '/panel';
    } catch (e) {
        danger('Test girişi yapılamadı', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
        impersonating.value = false;
        impersonateTarget.value = null;
    }
}

function formatDate(value: string | null): string {
    if (!value) return '—';
    try {
        return new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }).format(new Date(value));
    } catch {
        return '—';
    }
}
</script>

<template>
    <Head title="Personel" />
    <StaffShell title="Personel">
        <div class="flex flex-col gap-4">
            <!-- Araç çubuğu (masaüstü): tüm filtreler tek satırda -->
            <div class="hidden md:block">
                <TableToolbar>
                    <SearchInput v-model="q" placeholder="Ad, e-posta, kod veya telefon ara" class="w-full sm:w-64" />
                    <BaseSelect v-model="branchId" :options="branchOptions" size="sm" class="w-full sm:w-40" />
                    <BaseSelect v-model="roleId" :options="roleOptions" size="sm" class="w-full sm:w-40" />
                    <BaseSelect v-model="status" :options="statusOptions" size="sm" class="w-full sm:w-44" />
                    <template #action>
                        <BaseButton v-if="canManage" class="w-full sm:w-auto" @click="openCreate">
                            <AppIcon name="plus" :size="16" />
                            Yeni Personel
                        </BaseButton>
                    </template>
                </TableToolbar>
            </div>

            <!-- Native mobil filtre: arama + durum chip'leri + "Filtrele" sheet -->
            <div class="flex flex-col gap-3 md:hidden">
                <SearchInput v-model="q" placeholder="Ad, e-posta, kod ara" class="w-full" />
                <div class="-mx-1 flex items-center gap-2 overflow-x-auto px-1 pb-0.5">
                    <FilterChip
                        v-for="opt in statusOptions"
                        :key="opt.value"
                        :label="opt.label"
                        :active="status === opt.value"
                        @click="status = opt.value"
                    />
                </div>
                <div class="flex gap-2">
                    <BaseButton variant="secondary" class="flex-1" @click="filterSheet = true">
                        <AppIcon name="filter" :size="15" />
                        Filtrele
                        <span
                            v-if="mobileFilterCount"
                            class="ml-1 inline-flex min-w-5 items-center justify-center rounded-full bg-primary px-1.5 text-[11px] font-semibold text-on-primary tabular-nums"
                        >{{ mobileFilterCount }}</span>
                    </BaseButton>
                    <BaseButton v-if="canManage" class="flex-1" @click="openCreate">
                        <AppIcon name="plus" :size="16" />
                        Yeni
                    </BaseButton>
                </div>
            </div>

            <!-- Mobil filtre bottom sheet: şube + rol + durum -->
            <BottomSheet v-model="filterSheet" title="Filtrele">
                <div class="flex flex-col gap-4">
                    <label class="flex flex-col gap-1.5">
                        <span class="text-[13px] font-medium text-muted">Şube</span>
                        <BaseSelect v-model="branchId" :options="branchOptions" />
                    </label>
                    <label class="flex flex-col gap-1.5">
                        <span class="text-[13px] font-medium text-muted">Rol</span>
                        <BaseSelect v-model="roleId" :options="roleOptions" />
                    </label>
                    <label class="flex flex-col gap-1.5">
                        <span class="text-[13px] font-medium text-muted">Durum</span>
                        <BaseSelect v-model="status" :options="statusOptions" />
                    </label>
                </div>
                <template #footer>
                    <BaseButton variant="ghost" @click="clearMobileFilters">Temizle</BaseButton>
                    <BaseButton @click="filterSheet = false">Uygula</BaseButton>
                </template>
            </BottomSheet>

            <!-- Liste -->
            <div class="overflow-hidden rounded-lg border border-default bg-raised">
                <DataTable
                    :columns="columns"
                    :rows="(rows as unknown as Record<string, unknown>[])"
                    :loading="loading"
                    caption="Personel listesi"
                >
                    <template #cell-name="{ row }">
                        <span class="flex flex-col">
                            <span class="font-medium text-body">{{ (row as unknown as StaffRow).name }}</span>
                            <span class="flex flex-wrap gap-x-2 text-xs text-subtle">
                                <span class="truncate">{{ (row as unknown as StaffRow).email }}</span>
                                <span v-if="(row as unknown as StaffRow).staff_code">Kod: {{ (row as unknown as StaffRow).staff_code }}</span>
                                <span v-if="(row as unknown as StaffRow).position">{{ (row as unknown as StaffRow).position }}</span>
                            </span>
                        </span>
                    </template>
                    <template #cell-branch="{ row }">
                        <span class="text-muted">{{ (row as unknown as StaffRow).branch?.name ?? '—' }}</span>
                    </template>
                    <template #cell-roles="{ row }">
                        <span class="flex flex-wrap gap-1">
                            <BaseBadge
                                v-for="role in (row as unknown as StaffRow).roles"
                                :key="role.id"
                                :variant="role.is_system ? 'primary' : 'neutral'"
                                no-icon
                            >
                                {{ role.name }}
                            </BaseBadge>
                            <BaseBadge v-if="((row as unknown as StaffRow).personal_overrides_count ?? 0) > 0" variant="info" no-icon>
                                {{ (row as unknown as StaffRow).personal_overrides_count }} istisna
                            </BaseBadge>
                        </span>
                    </template>
                    <template #cell-last_login="{ row }">
                        <span class="text-muted tabular-nums">{{ formatDate((row as unknown as StaffRow).last_login_at) }}</span>
                    </template>
                    <template #cell-is_active="{ row }">
                        <BaseSwitch
                            size="sm"
                            :model-value="(row as unknown as StaffRow).is_active"
                            :aria-label="`${(row as unknown as StaffRow).name} aktif/pasif`"
                            :disabled="!canManage || (row as unknown as StaffRow).id === actorId"
                            :busy="togglingId === (row as unknown as StaffRow).id"
                            @update:model-value="toggleActive(row as unknown as StaffRow, $event)"
                        />
                    </template>
                    <template #cell-actions="{ row }">
                        <BaseButton
                            v-if="canManage"
                            size="sm"
                            variant="ghost"
                            icon-only
                            :label="`${(row as unknown as StaffRow).name} düzenle`"
                            @click="openEdit(row as unknown as StaffRow)"
                        >
                            <AppIcon name="pencil" :size="15" />
                        </BaseButton>
                        <BaseDropdown v-if="canManage" menu-label="Personel işlemleri">
                            <template #trigger="{ toggle, ariaAttrs }">
                                <button
                                    type="button"
                                    v-bind="ariaAttrs"
                                    class="flex size-8 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                                    :aria-label="`${(row as unknown as StaffRow).name} diğer işlemler`"
                                    @click="toggle"
                                >
                                    <AppIcon name="dots-vertical" :size="16" />
                                </button>
                            </template>
                            <DropdownItem icon="users" @select="openOverrides(row as unknown as StaffRow)">Yetki istisnaları</DropdownItem>
                            <DropdownItem icon="label" @select="openPin(row as unknown as StaffRow)">
                                {{ (row as unknown as StaffRow).has_pin ? 'PIN sıfırla / kaldır' : 'PIN belirle' }}
                            </DropdownItem>
                            <DropdownItem icon="inbox" @select="sendResetLink(row as unknown as StaffRow)">Parola sıfırlama bağlantısı gönder</DropdownItem>
                            <DropdownItem v-if="canImpersonate(row as unknown as StaffRow)" icon="user" @select="impersonateTarget = row as unknown as StaffRow">
                                Test için giriş yap
                            </DropdownItem>
                            <DropdownItem
                                v-if="(row as unknown as StaffRow).is_active && (row as unknown as StaffRow).id !== actorId"
                                icon="logout"
                                danger
                                @select="terminateTarget = row as unknown as StaffRow"
                            >
                                İşten çıkar (pasife al)
                            </DropdownItem>
                            <DropdownItem v-if="!(row as unknown as StaffRow).is_active" icon="check" @select="reactivate(row as unknown as StaffRow)">
                                Yeniden aktifleştir
                            </DropdownItem>
                        </BaseDropdown>
                    </template>
                    <template #empty>
                        <EmptyState
                            icon="users"
                            title="Personel bulunamadı"
                            :description="q || branchId || roleId || status ? 'Filtrelerle eşleşen personel yok.' : 'İlk personel hesabını açın.'"
                        >
                            <template #action>
                                <BaseButton v-if="canManage" @click="openCreate">
                                    <AppIcon name="plus" :size="16" />
                                    Yeni Personel
                                </BaseButton>
                            </template>
                        </EmptyState>
                    </template>
                </DataTable>
            </div>

            <div class="flex items-center justify-between">
                <span class="text-xs text-subtle">Toplam {{ total }} personel</span>
                <BasePagination v-if="lastPage > 1" v-model:page="pageNo" :last-page="lastPage" />
            </div>
        </div>

        <!-- Çekmeceler / modal -->
        <StaffFormDrawer :open="formOpen" :meta="meta" :staff="selected" @close="formOpen = false" @saved="load" />
        <OverridesDrawer :open="overridesOpen" :meta="meta" :staff="selected" @close="overridesOpen = false" @saved="load" />
        <PinModal :open="pinOpen" :staff="selected" @close="pinOpen = false" @saved="load" />

        <BaseModal :open="terminateTarget !== null" title="İşten çıkarma" size="sm" @close="terminateTarget = null">
            <div class="flex flex-col gap-4">
                <p class="text-sm text-body">
                    <strong>{{ terminateTarget?.name }}</strong> pasife alınacak: giriş yapamaz, açık oturumları düşer.
                    Hesap ve geçmiş kayıtlar <strong>silinmez</strong>; dilediğinizde yeniden aktifleştirebilirsiniz.
                </p>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="terminateTarget = null">Vazgeç</BaseButton>
                    <BaseButton variant="danger" :loading="terminating" @click="terminate">İşten Çıkar</BaseButton>
                </div>
            </div>
        </BaseModal>

        <BaseModal :open="impersonateTarget !== null" title="Test için giriş" size="sm" @close="impersonateTarget = null">
            <div class="flex flex-col gap-4">
                <p class="text-sm text-body">
                    <strong>{{ impersonateTarget?.name }}</strong> personelinin oturumuna geçeceksiniz: onun gördüğü
                    ekranları ve yetkileri birebir test edersiniz. Üst tarafta kalıcı bir şerit çıkar; istediğiniz an
                    <strong>Yöneticiye dön</strong> ile kendi hesabınıza geri dönersiniz.
                </p>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="secondary" @click="impersonateTarget = null">Vazgeç</BaseButton>
                    <BaseButton :loading="impersonating" @click="impersonate">Bu kişi olarak gir</BaseButton>
                </div>
            </div>
        </BaseModal>
    </StaffShell>
</template>
