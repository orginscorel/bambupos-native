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
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import DropdownItem from '@/Components/ui/DropdownItem.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
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
            <!-- Araç çubuğu -->
            <div class="flex flex-wrap items-center gap-2">
                <SearchInput v-model="q" placeholder="Ad, e-posta, kod veya telefon ara" class="w-full sm:w-64" />
                <BaseSelect v-model="branchId" :options="branchOptions" size="sm" class="w-40" />
                <BaseSelect v-model="roleId" :options="roleOptions" size="sm" class="w-40" />
                <BaseSelect v-model="status" :options="statusOptions" size="sm" class="w-44" />
                <span class="grow" />
                <BaseButton v-if="canManage" @click="openCreate">
                    <AppIcon name="plus" :size="16" />
                    Yeni Personel
                </BaseButton>
            </div>

            <!-- Liste -->
            <div class="overflow-x-auto rounded-lg border border-default bg-raised">
                <table class="w-full min-w-[860px] text-sm">
                    <thead>
                        <tr class="border-b border-default text-left text-xs text-subtle uppercase">
                            <th class="px-3 py-2.5 font-medium">Personel</th>
                            <th class="px-3 py-2.5 font-medium">Şube</th>
                            <th class="px-3 py-2.5 font-medium">Roller</th>
                            <th class="px-3 py-2.5 font-medium">Son giriş</th>
                            <th class="px-3 py-2.5 font-medium">Aktif</th>
                            <th class="px-3 py-2.5 text-right font-medium">İşlemler</th>
                        </tr>
                    </thead>
                    <tbody v-if="loading">
                        <tr v-for="i in 5" :key="i" class="border-b border-default">
                            <td v-for="c in 6" :key="c" class="px-3 py-3"><BaseSkeleton class="h-5 w-full" /></td>
                        </tr>
                    </tbody>
                    <tbody v-else-if="rows.length > 0">
                        <tr v-for="row in rows" :key="row.id" class="border-b border-default last:border-0" :class="row.is_active ? '' : 'opacity-60'">
                            <td class="px-3 py-2.5">
                                <span class="flex flex-col">
                                    <span class="font-medium text-body">{{ row.name }}</span>
                                    <span class="flex flex-wrap gap-x-2 text-xs text-subtle">
                                        <span>{{ row.email }}</span>
                                        <span v-if="row.staff_code">Kod: {{ row.staff_code }}</span>
                                        <span v-if="row.position">{{ row.position }}</span>
                                    </span>
                                </span>
                            </td>
                            <td class="px-3 py-2.5 text-muted">{{ row.branch?.name ?? '—' }}</td>
                            <td class="px-3 py-2.5">
                                <span class="flex flex-wrap gap-1">
                                    <BaseBadge v-for="role in row.roles" :key="role.id" :variant="role.is_system ? 'primary' : 'neutral'" no-icon>
                                        {{ role.name }}
                                    </BaseBadge>
                                    <BaseBadge v-if="(row.personal_overrides_count ?? 0) > 0" variant="info" no-icon>
                                        {{ row.personal_overrides_count }} istisna
                                    </BaseBadge>
                                </span>
                            </td>
                            <td class="px-3 py-2.5 text-muted">{{ formatDate(row.last_login_at) }}</td>
                            <td class="px-3 py-2.5">
                                <BaseSwitch
                                    size="sm"
                                    :model-value="row.is_active"
                                    :aria-label="`${row.name} aktif/pasif`"
                                    :disabled="!canManage || row.id === actorId"
                                    :busy="togglingId === row.id"
                                    @update:model-value="toggleActive(row, $event)"
                                />
                            </td>
                            <td class="px-3 py-2.5">
                                <span class="flex items-center justify-end gap-1">
                                    <BaseButton
                                        v-if="canManage"
                                        size="sm"
                                        variant="ghost"
                                        icon-only
                                        :label="`${row.name} düzenle`"
                                        @click="openEdit(row)"
                                    >
                                        <AppIcon name="pencil" :size="15" />
                                    </BaseButton>
                                    <BaseDropdown v-if="canManage" menu-label="Personel işlemleri">
                                        <template #trigger="{ toggle, ariaAttrs }">
                                            <button
                                                type="button"
                                                v-bind="ariaAttrs"
                                                class="flex size-8 items-center justify-center rounded-md text-muted transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
                                                :aria-label="`${row.name} diğer işlemler`"
                                                @click="toggle"
                                            >
                                                <AppIcon name="dots-vertical" :size="16" />
                                            </button>
                                        </template>
                                        <DropdownItem icon="users" @select="openOverrides(row)">Yetki istisnaları</DropdownItem>
                                        <DropdownItem icon="label" @select="openPin(row)">
                                            {{ row.has_pin ? 'PIN sıfırla / kaldır' : 'PIN belirle' }}
                                        </DropdownItem>
                                        <DropdownItem icon="inbox" @select="sendResetLink(row)">Parola sıfırlama bağlantısı gönder</DropdownItem>
                                        <DropdownItem
                                            v-if="row.is_active && row.id !== actorId"
                                            icon="logout"
                                            danger
                                            @select="terminateTarget = row"
                                        >
                                            İşten çıkar (pasife al)
                                        </DropdownItem>
                                        <DropdownItem v-if="!row.is_active" icon="check" @select="reactivate(row)">
                                            Yeniden aktifleştir
                                        </DropdownItem>
                                    </BaseDropdown>
                                </span>
                            </td>
                        </tr>
                    </tbody>
                    <tbody v-else>
                        <tr>
                            <td colspan="6">
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
                            </td>
                        </tr>
                    </tbody>
                </table>
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
    </StaffShell>
</template>
