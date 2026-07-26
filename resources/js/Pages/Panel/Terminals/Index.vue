<script setup lang="ts">
/**
 * İstasyon terminal yönetimi (§13, Faz A).
 *
 * terminals.manage yetkisiyle: cihaz ekle/düzenle/kaldır, token yenile
 * (eski adres ANINDA 410), uzaktan kilitle/aç, sağlık durumu (son kalp
 * atışı), şube ve istasyon (Mutfak/Barista/Komi). Her cihaz GİZLİ bir
 * terminal kullanıcısı üretir; cihazda açılacak /terminal/{token} adresi +
 * QR gösterilir (kiosk cihaz-yönetim deseni).
 */
import { computed, onMounted, reactive, ref } from 'vue';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';

type Station = 'kitchen' | 'barista' | 'komi' | 'kasa' | 'order_entry';

interface DeviceDto {
    id: number;
    name: string;
    station: Station;
    station_label: string;
    branch_id: number;
    branch_name: string | null;
    status: 'active' | 'inactive';
    url: string;
    qr: string;
    online: boolean;
    last_seen_at: string | null;
    last_ip: string | null;
    locked_at: string | null;
    token_rotated_at: string | null;
    created_at: string | null;
}

interface BranchDto {
    id: number;
    name: string;
}

interface StationOption {
    value: string;
    label: string;
}

const toast = useToast();

const loading = ref(true);
const devices = ref<DeviceDto[]>([]);
const branches = ref<BranchDto[]>([]);
const stationOptions = ref<StationOption[]>([]);
const busyId = ref<number | null>(null);

/* ---------- Liste ---------- */

async function load(): Promise<void> {
    try {
        const res = await api<{ devices: DeviceDto[]; branches: BranchDto[]; stations: StationOption[] }>(
            '/api/v1/terminals/devices',
        );
        devices.value = res.devices;
        branches.value = res.branches;
        stationOptions.value = res.stations;
    } catch (e) {
        toast.danger(e instanceof ApiError ? e.displayMessage : 'Cihazlar yüklenemedi.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

const branchOptions = computed(() => branches.value.map((b) => ({ value: String(b.id), label: b.name })));

function healthLabel(d: DeviceDto): { variant: 'success' | 'warning' | 'neutral'; text: string } {
    if (d.status === 'inactive') return { variant: 'warning', text: 'Kilitli' };
    if (d.online) return { variant: 'success', text: 'Çevrimiçi' };
    return { variant: 'neutral', text: d.last_seen_at ? 'Çevrimdışı' : 'Hiç bağlanmadı' };
}

function lastSeenText(d: DeviceDto): string {
    if (!d.last_seen_at) return '—';
    return new Date(d.last_seen_at).toLocaleString('tr-TR');
}

/* ---------- Form (ekle / düzenle) ---------- */

const formOpen = ref(false);
const editing = ref<DeviceDto | null>(null);
const saving = ref(false);
const form = reactive({ name: '', branch_id: '', station: 'kitchen' });
const formErrors = reactive<{ [k: string]: string }>({});

function openCreate(): void {
    editing.value = null;
    form.name = '';
    form.branch_id = branches.value.length === 1 ? String(branches.value[0].id) : '';
    form.station = 'kitchen';
    clearErrors();
    formOpen.value = true;
}

function openEdit(d: DeviceDto): void {
    editing.value = d;
    form.name = d.name;
    form.branch_id = String(d.branch_id);
    form.station = d.station;
    clearErrors();
    formOpen.value = true;
}

function clearErrors(): void {
    Object.keys(formErrors).forEach((k) => delete formErrors[k]);
}

async function save(): Promise<void> {
    saving.value = true;
    clearErrors();
    try {
        const body = {
            name: form.name,
            branch_id: Number(form.branch_id || 0),
            station: form.station,
        };
        if (editing.value) {
            const res = await api<{ device: DeviceDto }>(`/api/v1/terminals/devices/${editing.value.id}`, { method: 'PUT', body });
            devices.value = devices.value.map((d) => (d.id === res.device.id ? res.device : d));
            toast.success('Terminal güncellendi.');
        } else {
            const res = await api<{ device: DeviceDto }>('/api/v1/terminals/devices', { method: 'POST', body });
            devices.value = [...devices.value, res.device].sort((a, b) => a.name.localeCompare(b.name, 'tr'));
            toast.success('Terminal eklendi. Adresi cihaza girin.');
            showDevice.value = res.device;
            urlModalTitle.value = 'Yeni terminal adresi';
            urlModalOpen.value = true;
        }
        formOpen.value = false;
    } catch (e) {
        if (e instanceof ApiError) {
            Object.entries(e.errors).forEach(([k, v]) => (formErrors[k] = v[0] ?? ''));
            toast.danger(e.displayMessage);
        } else {
            toast.danger('Kaydedilemedi.');
        }
    } finally {
        saving.value = false;
    }
}

/* ---------- Token yenileme / adres+QR göster ---------- */

const rotateTarget = ref<DeviceDto | null>(null);
const urlModalOpen = ref(false);
const urlModalTitle = ref('Terminal adresi');
const showDevice = ref<DeviceDto | null>(null);

function openUrl(d: DeviceDto): void {
    showDevice.value = d;
    urlModalTitle.value = 'Terminal adresi';
    urlModalOpen.value = true;
}

async function rotateConfirmed(): Promise<void> {
    const d = rotateTarget.value;
    if (!d) return;
    busyId.value = d.id;
    try {
        const res = await api<{ device: DeviceDto }>(`/api/v1/terminals/devices/${d.id}/rotate-token`, { method: 'POST' });
        devices.value = devices.value.map((x) => (x.id === res.device.id ? res.device : x));
        rotateTarget.value = null;
        showDevice.value = res.device;
        urlModalTitle.value = 'Yeni terminal adresi (eski adres geçersiz)';
        urlModalOpen.value = true;
        toast.success('Token yenilendi; eski adres artık geçersiz.');
    } catch (e) {
        toast.danger(e instanceof ApiError ? e.displayMessage : 'Token yenilenemedi.');
    } finally {
        busyId.value = null;
    }
}

async function copyUrl(url: string): Promise<void> {
    try {
        await navigator.clipboard.writeText(url);
        toast.success('Adres panoya kopyalandı.');
    } catch {
        toast.danger('Kopyalanamadı — adresi elle seçip kopyalayın.');
    }
}

/* ---------- Kilit / sil ---------- */

async function toggleLock(d: DeviceDto): Promise<void> {
    busyId.value = d.id;
    try {
        const action = d.status === 'inactive' ? 'unlock' : 'lock';
        const res = await api<{ device: DeviceDto }>(`/api/v1/terminals/devices/${d.id}/${action}`, { method: 'POST' });
        devices.value = devices.value.map((x) => (x.id === res.device.id ? res.device : x));
        toast.success(action === 'lock' ? 'Terminal kilitlendi; cihaz kilit ekranına düşecek.' : 'Kilit açıldı.');
    } catch (e) {
        toast.danger(e instanceof ApiError ? e.displayMessage : 'İşlem yapılamadı.');
    } finally {
        busyId.value = null;
    }
}

const deleteTarget = ref<DeviceDto | null>(null);
const deleting = ref(false);

async function deleteConfirmed(): Promise<void> {
    const d = deleteTarget.value;
    if (!d) return;
    deleting.value = true;
    try {
        await api(`/api/v1/terminals/devices/${d.id}`, { method: 'DELETE' });
        devices.value = devices.value.filter((x) => x.id !== d.id);
        toast.success('Terminal kaldırıldı; adresi artık çalışmaz.');
        deleteTarget.value = null;
    } catch (e) {
        toast.danger(e instanceof ApiError ? e.displayMessage : 'Silinemedi.');
    } finally {
        deleting.value = false;
    }
}
</script>

<template>
    <PanelShell title="İstasyon Terminalleri">
        <div class="mx-auto flex w-full max-w-5xl flex-col gap-5">

            <div class="flex items-center justify-between gap-3">
                <p class="text-sm text-muted">
                    Mutfak / Barista / Komi (mutfak ekranları, para görmez) ve Kasa / Sipariş Girişi
                    (para görebilir) için cihaza-bağlı, tam-ekran, KİLİTLİ terminaller. Her cihaz
                    yalnız kendi istasyon ekranını gösterir (personel tüm paneli görmez) ve yalnız
                    kendi adresiyle (opak token) çalışır; token yenilenince eski adres anında
                    geçersiz olur. Kasa/Sipariş terminalinde hassas işlemler (ödeme, iptal, iade,
                    ikram) personel PIN'i ister ve o kişiye kaydedilir.
                </p>
                <BaseButton @click="openCreate">
                    <AppIcon name="plus" :size="16" />
                    Terminal ekle
                </BaseButton>
            </div>

            <template v-if="loading">
                <BaseCard><BaseSkeleton class="h-40" /></BaseCard>
            </template>

            <EmptyState
                v-else-if="devices.length === 0"
                icon="tablet"
                title="Henüz terminal cihazı yok"
                description="Cihaz ekleyin; oluşan adresi (veya QR'ı) istasyon cihazının tarayıcısında tam ekran açın."
            />

            <BaseCard v-else v-for="d in devices" :key="d.id">
                <div class="flex flex-col gap-3">
                    <div class="flex flex-wrap items-center justify-between gap-3">
                        <div class="flex items-center gap-3">
                            <span class="flex h-10 w-10 items-center justify-center rounded-lg bg-inset">
                                <AppIcon name="tablet" :size="20" />
                            </span>
                            <div>
                                <h3 class="font-semibold text-body">{{ d.name }}</h3>
                                <p class="text-sm text-muted">
                                    {{ d.branch_name ?? 'Şube #' + d.branch_id }} ·
                                    <span class="font-medium text-body">{{ d.station_label }}</span> terminali
                                </p>
                            </div>
                        </div>
                        <div class="flex items-center gap-2">
                            <BaseBadge :variant="healthLabel(d).variant">{{ healthLabel(d).text }}</BaseBadge>
                        </div>
                    </div>

                    <div class="flex flex-wrap items-center gap-2 rounded-md bg-inset px-3 py-2">
                        <code class="min-w-0 flex-1 truncate text-xs text-muted" :title="d.url">{{ d.url }}</code>
                        <BaseButton size="sm" variant="ghost" @click="openUrl(d)">Adres & QR</BaseButton>
                        <BaseButton size="sm" variant="ghost" @click="copyUrl(d.url)">Kopyala</BaseButton>
                    </div>

                    <p class="text-xs text-muted">
                        Son görülme: {{ lastSeenText(d) }}<span v-if="d.last_ip"> · IP: {{ d.last_ip }}</span>
                        <span v-if="d.token_rotated_at"> · Token yenilendi: {{ new Date(d.token_rotated_at).toLocaleString('tr-TR') }}</span>
                    </p>

                    <div class="flex flex-wrap gap-2">
                        <BaseButton size="sm" variant="secondary" :disabled="busyId === d.id" @click="openEdit(d)">
                            <AppIcon name="pencil" :size="14" /> Düzenle
                        </BaseButton>
                        <BaseButton size="sm" variant="secondary" :disabled="busyId === d.id" @click="toggleLock(d)">
                            {{ d.status === 'inactive' ? 'Kilidi aç' : 'Uzaktan kilitle' }}
                        </BaseButton>
                        <BaseButton size="sm" variant="secondary" :disabled="busyId === d.id" @click="rotateTarget = d">
                            Token yenile
                        </BaseButton>
                        <BaseButton size="sm" variant="danger" :disabled="busyId === d.id" @click="deleteTarget = d">
                            <AppIcon name="trash" :size="14" /> Kaldır
                        </BaseButton>
                    </div>
                </div>
            </BaseCard>
        </div>

        <!-- Ekle / düzenle -->
        <BaseModal :open="formOpen" :title="editing ? 'Terminali düzenle' : 'İstasyon terminali ekle'" @close="formOpen = false">
            <div class="flex flex-col gap-4">
                <FormField label="Cihaz adı" required :error="formErrors.name">
                    <BaseInput v-model="form.name" placeholder="Örn. Mutfak Terminal 1" maxlength="100" />
                </FormField>
                <FormField label="Şube" required :error="formErrors.branch_id">
                    <BaseSelect v-model="form.branch_id" :options="branchOptions" placeholder="Şube seçin" />
                </FormField>
                <FormField
                    label="İstasyon"
                    :error="formErrors.station"
                    hint="Cihaz yalnız bu istasyon ekranına kilitlenir. Mutfak/Barista hazırlık kuyruğunu, Komi hazır kalemleri görür (para görmez). Kasa ödeme ekranını, Sipariş Girişi adisyonları açar (para görebilir; hassas işlemler personel PIN'i ister)."
                >
                    <BaseSelect v-model="form.station" :options="stationOptions" />
                </FormField>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="ghost" @click="formOpen = false">Vazgeç</BaseButton>
                    <BaseButton :loading="saving" @click="save">{{ editing ? 'Kaydet' : 'Ekle' }}</BaseButton>
                </div>
            </div>
        </BaseModal>

        <!-- Token yenileme onayı -->
        <BaseModal :open="rotateTarget !== null" title="Token yenilensin mi?" size="sm" @close="rotateTarget = null">
            <div class="flex flex-col gap-4">
                <p class="text-sm text-body">
                    <strong>{{ rotateTarget?.name }}</strong> için yeni bir adres üretilecek.
                    Eski adres <strong>anında geçersiz</strong> olur (cihaz 410 sayfası görür) ve
                    yeni adresi cihaza yeniden girmeniz gerekir.
                </p>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="ghost" @click="rotateTarget = null">Vazgeç</BaseButton>
                    <BaseButton variant="danger" :loading="busyId === rotateTarget?.id" @click="rotateConfirmed">Yenile</BaseButton>
                </div>
            </div>
        </BaseModal>

        <!-- Adres + QR göster -->
        <BaseModal :open="urlModalOpen" :title="urlModalTitle" @close="urlModalOpen = false">
            <div class="flex flex-col gap-4">
                <p class="text-sm text-muted">Bu adresi istasyon cihazının tarayıcısında tam ekran açın ya da QR'ı okutun:</p>
                <div v-if="showDevice" class="flex justify-center">
                    <img
                        :src="showDevice.qr"
                        alt="Terminal QR"
                        class="h-52 w-52 rounded-lg border border-default bg-white p-2"
                    />
                </div>
                <div class="flex items-center gap-2 rounded-md bg-inset px-3 py-2">
                    <code class="min-w-0 flex-1 break-all text-xs">{{ showDevice?.url }}</code>
                    <BaseButton size="sm" variant="ghost" @click="showDevice && copyUrl(showDevice.url)">Kopyala</BaseButton>
                </div>
                <div class="flex justify-end">
                    <BaseButton @click="urlModalOpen = false">Tamam</BaseButton>
                </div>
            </div>
        </BaseModal>

        <!-- Silme onayı -->
        <BaseModal :open="deleteTarget !== null" title="Terminal kaldırılsın mı?" size="sm" @close="deleteTarget = null">
            <div class="flex flex-col gap-4">
                <p class="text-sm text-body">
                    <strong>{{ deleteTarget?.name }}</strong> ve ona bağlı gizli terminal hesabı kaldırılacak;
                    adresi bir daha çalışmaz. Geçmiş siparişler silinmez.
                </p>
                <div class="flex justify-end gap-2">
                    <BaseButton variant="ghost" @click="deleteTarget = null">Vazgeç</BaseButton>
                    <BaseButton variant="danger" :loading="deleting" @click="deleteConfirmed">Kaldır</BaseButton>
                </div>
            </div>
        </BaseModal>
    </PanelShell>
</template>
