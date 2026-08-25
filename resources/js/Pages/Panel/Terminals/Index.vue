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
import { usePermissions } from '@/composables/usePermissions';
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

/** §13 Faz 3: panelden lisanslı terminal kurulumu — kullanım göstergesi. */
interface LicenseDto {
    limit: number | null;
    used: number;
    remaining: number | null;
    unlimited: boolean;
}

/** /api/v1/devices/synced satırı (yalnız İHTİYACIMIZ olan alanlar). */
interface SyncedBinding {
    bound: boolean;
    online: boolean;
    revoked: boolean;
}
interface SyncedRow {
    source: 'terminal' | 'kiosk';
    source_id: number;
    binding: SyncedBinding | null;
}

const toast = useToast();
const { can } = usePermissions();
const canManage = can('terminals.manage');
const canManageDeviceLock = can('devices.manage');

const loading = ref(true);
const devices = ref<DeviceDto[]>([]);
const branches = ref<BranchDto[]>([]);
const stationOptions = ref<StationOption[]>([]);
const busyId = ref<number | null>(null);
const license = ref<LicenseDto>({ limit: null, used: 0, remaining: null, unlimited: true });

// Fiziksel cihaz kilidi köprüsü (İzinli Cihazlar ekranıyla ORTAK durum).
const lockEnabled = ref(false);
const lockToggling = ref(false);
const bindingByTerminalId = ref<Record<number, SyncedBinding | null>>({});

/* ---------- Liste ---------- */

async function load(): Promise<void> {
    try {
        const res = await api<{ devices: DeviceDto[]; branches: BranchDto[]; stations: StationOption[]; license: LicenseDto }>(
            '/api/v1/terminals/devices',
        );
        devices.value = res.devices;
        branches.value = res.branches;
        stationOptions.value = res.stations;
        license.value = res.license;
    } catch (e) {
        toast.danger(e instanceof ApiError ? e.displayMessage : 'Cihazlar yüklenemedi.');
    } finally {
        loading.value = false;
    }
    await loadDeviceLockBridge();
}

/**
 * İzinli Cihazlar (A3) ile köprü: aynı senkron ucu kullanır, yalnız cihaz
 * kilidi AÇIK/KAPALI durumunu + bu ekrandaki her terminalin fiziksel
 * bağlanma durumunu okur. devices.view izni yoksa sessizce atlanır — bu
 * ekranın asıl işlevi bozulmaz (bonus bir gösterge).
 */
async function loadDeviceLockBridge(): Promise<void> {
    try {
        const res = await api<{ lock_enabled: boolean; devices: SyncedRow[] }>('/api/v1/devices/synced');
        lockEnabled.value = res.lock_enabled;
        const map: Record<number, SyncedBinding | null> = {};
        res.devices.filter((r) => r.source === 'terminal').forEach((r) => (map[r.source_id] = r.binding));
        bindingByTerminalId.value = map;
    } catch {
        /* devices.view yoksa ya da başka bir sebeple: köprü göstergesi gizlenir, sayfa çalışmaya devam eder. */
    }
}

async function toggleDeviceLock(): Promise<void> {
    lockToggling.value = true;
    try {
        const res = await api<{ enabled: boolean }>('/api/v1/devices/lock-feature', {
            method: 'POST',
            body: { enabled: !lockEnabled.value },
        });
        lockEnabled.value = res.enabled;
        toast.success(res.enabled ? 'Cihaz kilidi açıldı.' : 'Cihaz kilidi kapatıldı.');
    } catch (e) {
        toast.danger(e instanceof ApiError ? e.displayMessage : 'İşlem yapılamadı.');
    } finally {
        lockToggling.value = false;
    }
}

function physicalLockLabel(d: DeviceDto): { text: string; cls: string } {
    if (!lockEnabled.value) {
        return { text: 'Cihaz kilidi kapalı', cls: 'text-subtle bg-inset' };
    }
    const b = bindingByTerminalId.value[d.id];
    if (!b || !b.bound) {
        return { text: 'Fiziksel cihaz bekleniyor', cls: 'text-warning bg-warning-soft' };
    }
    if (b.revoked) {
        return { text: 'Fiziksel cihaz izni iptal edildi', cls: 'text-danger bg-danger-soft' };
    }
    return b.online
        ? { text: 'Fiziksel cihaza kilitli · çevrimiçi', cls: 'text-success bg-success-soft' }
        : { text: 'Fiziksel cihaza kilitli', cls: 'text-subtle bg-inset' };
}

onMounted(load);

const atLicenseLimit = computed(() => !license.value.unlimited && (license.value.remaining ?? 0) <= 0);
const licenseText = computed(() => {
    if (license.value.unlimited) return 'Sınırsız terminal lisansı';
    return `${license.value.used} / ${license.value.limit} terminal lisansı kullanıldı`;
});

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
    if (atLicenseLimit.value) {
        toast.danger(`Terminal lisans limitiniz doldu (${license.value.used}/${license.value.limit}). Yükseltme için destek ekibiyle iletişime geçin.`);
        return;
    }
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
            license.value = {
                ...license.value,
                used: license.value.used + 1,
                remaining: license.value.unlimited ? null : Math.max(0, (license.value.remaining ?? 1) - 1),
            };
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
        license.value = {
            ...license.value,
            used: Math.max(0, license.value.used - 1),
            remaining: license.value.unlimited ? null : (license.value.remaining ?? 0) + 1,
        };
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
    <PanelShell title="İstasyon Terminalleri" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1080px] flex-col gap-3">

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
                <BaseButton
                    v-if="canManage"
                    :disabled="atLicenseLimit"
                    :title="atLicenseLimit ? 'Terminal lisans limitiniz doldu' : ''"
                    @click="openCreate"
                >
                    <AppIcon name="plus" :size="16" />
                    Terminal ekle
                </BaseButton>
            </div>

            <!-- §13 Faz 3: terminal lisans göstergesi -->
            <div
                v-if="!loading"
                class="flex flex-wrap items-center justify-between gap-3 rounded-xl border px-4 py-3 text-sm"
                :class="atLicenseLimit ? 'border-danger bg-danger-soft text-danger' : 'border-default bg-inset text-body'"
            >
                <div class="flex items-center gap-2">
                    <AppIcon :name="atLicenseLimit ? 'alert-triangle' : 'tablet'" :size="16" />
                    <span class="font-semibold">{{ licenseText }}</span>
                </div>
                <div v-if="!license.unlimited" class="h-1.5 w-32 overflow-hidden rounded-full bg-black/10">
                    <div
                        class="h-full rounded-full"
                        :class="atLicenseLimit ? 'bg-danger' : 'bg-primary'"
                        :style="{ width: Math.min(100, (license.used / Math.max(1, license.limit ?? 1)) * 100) + '%' }"
                    />
                </div>
                <span v-if="atLicenseLimit" class="text-xs">Yükseltme için destek ekibiyle iletişime geçin.</span>
            </div>

            <!-- §13 Faz 3: Terminaller ↔ İzinli Cihazlar köprüsü — cihaz kilidi durumu + tek-tık aç/kapa -->
            <div
                v-if="!loading"
                class="flex flex-wrap items-center gap-2 rounded-xl border px-4 py-3 text-sm"
                :class="lockEnabled ? 'border-success bg-success-soft text-success' : 'border-warning bg-warning-soft text-warning'"
            >
                <AppIcon :name="lockEnabled ? 'check-circle' : 'alert-triangle'" :size="18" />
                <span v-if="lockEnabled" class="font-semibold">Cihaz kilidi AÇIK — her terminal bağlantısı ilk açan fiziksel cihaza kilitlenir.</span>
                <span v-else class="font-semibold">Cihaz kilidi KAPALI — herkes bu terminal adreslerini açabilir, fiziksel cihaza kilitlenmez.</span>
                <div class="ml-auto flex items-center gap-2">
                    <BaseButton v-if="canManageDeviceLock" size="sm" variant="secondary" :loading="lockToggling" @click="toggleDeviceLock">
                        {{ lockEnabled ? 'Kilidi kapat' : 'Kilidi aç' }}
                    </BaseButton>
                    <a href="/panel/izinli-cihazlar" class="font-semibold text-primary hover:underline">İzinli Cihazlar →</a>
                </div>
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

                    <!-- §13 Faz 3: fiziksel cihaz kilidi durumu (İzinli Cihazlar ile ortak) -->
                    <div class="flex flex-wrap items-center gap-2">
                        <span class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold" :class="physicalLockLabel(d).cls">
                            <span class="size-1.5 rounded-full bg-current" />
                            {{ physicalLockLabel(d).text }}
                        </span>
                        <a href="/panel/izinli-cihazlar" class="text-xs font-semibold text-primary hover:underline">
                            İzinli Cihazlar'da yönet →
                        </a>
                    </div>

                    <div v-if="canManage" class="flex flex-wrap gap-2">
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
        </div>
        </div>
    </PanelShell>
</template>
