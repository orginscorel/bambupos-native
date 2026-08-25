<script setup lang="ts">
/**
 * İzinli Cihazlar (A3) — SENKRON görünüm.
 *
 * Gerçek Terminal + Kiosk cihazlarını (Terminaller/Kiosklar ekranlarındaki AYNI
 * cihazlar) hazır BAĞLANTI + KAREKOD + cihaz-kilidi durumuyla listeler. Artık
 * opak token elle girilmez: her cihazın kendi /terminal|/kiosk adresi + QR'ı
 * burada; o adresi İLK açan fiziksel cihaz (cihaz kilidi AÇIKSA) kilitlenir.
 * "Boşa düşür" / "Başka cihaza aktar" mevcut kilidi sıfırlar (sonraki açan bağlanır).
 */
import { onMounted, ref } from 'vue';
import { api } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import { usePermissions } from '@/composables/usePermissions';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';

interface Binding {
    id: number;
    bound: boolean;
    online: boolean;
    revoked: boolean;
    last_ip: string | null;
    last_seen_at: string | null;
}
interface DeviceRow {
    source: 'terminal' | 'kiosk';
    source_id: number;
    name: string;
    station: string | null;
    status: string;
    token: string;
    connect_url: string;
    qr: string;
    device_last_seen_at: string | null;
    binding: Binding | null;
}

const toast = useToast();
const { can } = usePermissions();
const canManage = can('devices.manage');
const loading = ref(true);
const lockEnabled = ref(false);
const lockToggling = ref(false);
const devices = ref<DeviceRow[]>([]);
const busy = ref<string | null>(null);
const qrModal = ref<DeviceRow | null>(null);

function rowKey(d: DeviceRow): string {
    return `${d.source}:${d.source_id}`;
}

async function load(): Promise<void> {
    loading.value = true;
    try {
        const res = await api<{ lock_enabled: boolean; devices: DeviceRow[] }>('/api/v1/devices/synced');
        lockEnabled.value = res.lock_enabled;
        devices.value = res.devices;
    } catch {
        toast.danger('Cihazlar yüklenemedi.');
    } finally {
        loading.value = false;
    }
}
onMounted(load);

function lockState(d: DeviceRow): { text: string; cls: string } {
    if (!lockEnabled.value) {
        return { text: 'Kilit kapalı', cls: 'text-subtle bg-inset' };
    }
    if (!d.binding || !d.binding.bound) {
        return { text: 'Cihaz bekleniyor', cls: 'text-warning bg-warning-soft' };
    }
    if (d.binding.revoked) {
        return { text: 'İzin kaldırıldı', cls: 'text-danger bg-danger-soft' };
    }
    return d.binding.online
        ? { text: 'Kilitli · çevrimiçi', cls: 'text-success bg-success-soft' }
        : { text: 'Kilitli · çevrimdışı', cls: 'text-subtle bg-inset' };
}

async function copy(url: string): Promise<void> {
    try {
        await navigator.clipboard.writeText(url);
        toast.success('Bağlantı panoya kopyalandı.');
    } catch {
        toast.danger('Kopyalanamadı — elle seçip kopyalayın.');
    }
}

async function act(d: DeviceRow, kind: 'release' | 'transfer'): Promise<void> {
    const label = kind === 'release' ? 'boşa düşürülsün' : 'başka cihaza aktarılsın';
    if (!confirm(`“${d.name}” bağlantısının cihaz kilidi ${label} mı? Mevcut kilitli cihaz düşer; bağlantıyı sonra açan yeni cihaz kilitlenir.`)) {
        return;
    }
    busy.value = rowKey(d);
    try {
        await api(`/api/v1/devices/${kind}-by-token`, {
            method: 'POST',
            body: { kind: d.source, token: d.token },
        });
        toast.success(kind === 'release' ? 'Kilit boşa düşürüldü.' : 'Başka cihaza aktarıldı.');
        await load();
    } catch (e: unknown) {
        toast.danger((e as { message?: string })?.message ?? 'İşlem başarısız.');
    } finally {
        busy.value = null;
    }
}

/**
 * §13 Faz 3: cihaz kilidi (device_lock) özelliğini bu ekrandan TEK TIKLA
 * aç/kapa. Eklentiler ekranıyla AYNI depoyu (tenant_features) kullanır —
 * yalnız buraya gitmeden erişilebilecek bir kısayoldur.
 */
async function toggleDeviceLock(): Promise<void> {
    lockToggling.value = true;
    try {
        const res = await api<{ enabled: boolean }>('/api/v1/devices/lock-feature', {
            method: 'POST',
            body: { enabled: !lockEnabled.value },
        });
        lockEnabled.value = res.enabled;
        toast.success(res.enabled ? 'Cihaz kilidi açıldı; bağlantılar artık ilk açan cihaza kilitlenir.' : 'Cihaz kilidi kapatıldı.');
    } catch (e: unknown) {
        toast.danger((e as { message?: string })?.message ?? 'İşlem başarısız.');
    } finally {
        lockToggling.value = false;
    }
}

/** İptal et (izni tamamen kaldır) / yeniden etkinleştir — kilitli cihaz erişimini derhal keser. */
async function revokeOrReactivate(d: DeviceRow, action: 'revoke' | 'reactivate'): Promise<void> {
    if (!d.binding) return;
    if (action === 'revoke' && !confirm(`“${d.name}” bağlı cihazın erişimi TAMAMEN iptal edilsin mi? Cihaz bu bağlantıyı bir daha kullanamaz.`)) {
        return;
    }
    busy.value = rowKey(d);
    try {
        await api(`/api/v1/devices/${d.binding.id}/${action}`, { method: 'POST' });
        toast.success(action === 'revoke' ? 'Cihaz izni iptal edildi.' : 'Cihaz izni yeniden etkinleştirildi.');
        await load();
    } catch (e: unknown) {
        toast.danger((e as { message?: string })?.message ?? 'İşlem başarısız.');
    } finally {
        busy.value = null;
    }
}
</script>

<template>
    <PanelShell title="İzinli Cihazlar" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1080px] flex-col gap-3">

        <div class="mx-auto flex w-full max-w-5xl flex-col gap-5 p-4 sm:p-6">
            <!-- Başlık + açıklama -->
            <header class="flex flex-col gap-1">
                <h1 class="text-xl font-bold text-body">İzinli Cihazlar</h1>
                <p class="max-w-2xl text-sm text-muted">
                    Terminal ve kiosk ekranlarınız burada. Her cihazın bağlantısını (veya karekodunu)
                    o cihazda açın; cihaz kilidi açıkken bağlantıyı <strong>ilk açan cihaz kilitlenir</strong>,
                    aynı bağlantı başka cihazda açılmaz. Cihaz değiştirmek için “Boşa düşür” ya da “Aktar” kullanın.
                </p>
            </header>

            <!-- Cihaz kilidi durumu + tek-tık aç/kapa (§13 Faz 3) -->
            <div
                v-if="!loading"
                class="flex flex-wrap items-center gap-3 rounded-xl border px-4 py-3 text-sm"
                :class="lockEnabled ? 'border-success bg-success-soft text-success' : 'border-warning bg-warning-soft text-warning'"
            >
                <AppIcon :name="lockEnabled ? 'check-circle' : 'alert-triangle'" :size="18" />
                <div class="flex-1">
                    <span v-if="lockEnabled" class="font-semibold">Cihaz kilidi AÇIK — bağlantılar ilk açan fiziksel cihaza kilitlenir.</span>
                    <template v-else>
                        <span class="font-semibold">Cihaz kilidi KAPALI — herkes bu terminal/kiosk adreslerini açabilir,</span>
                        <span class="text-body"> hiçbir bağlantı belirli bir cihaza kilitlenmez (varsayılan durum).</span>
                    </template>
                </div>
                <BaseButton v-if="canManage" size="sm" variant="secondary" :loading="lockToggling" @click="toggleDeviceLock">
                    {{ lockEnabled ? 'Kilidi kapat' : 'Kilidi aç' }}
                </BaseButton>
            </div>

            <!-- Yeni cihaz nereden? -->
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-muted">
                <AppIcon name="alert-circle" :size="15" />
                <span>Yeni terminal/kiosk eklemek için:</span>
                <a href="/panel/terminaller" class="font-semibold text-primary hover:underline">Terminaller</a>
                <span>·</span>
                <a href="/panel/kiosklar" class="font-semibold text-primary hover:underline">Kiosklar</a>
            </div>

            <!-- Yükleniyor -->
            <div v-if="loading" class="grid gap-3 sm:grid-cols-2">
                <BaseSkeleton v-for="i in 4" :key="i" class="h-40" />
            </div>

            <!-- Boş -->
            <EmptyState
                v-else-if="devices.length === 0"
                icon="qr-code"
                title="Kayıtlı terminal/kiosk yok"
                description="Terminaller veya Kiosklar ekranından bir cihaz ekleyin; burada bağlantısı + karekodu + kilit durumu görünür."
            />

            <!-- Cihaz listesi -->
            <div v-else class="grid gap-4 sm:grid-cols-2">
                <BaseCard v-for="d in devices" :key="rowKey(d)" class="flex flex-col gap-3 p-4">
                    <div class="flex items-start justify-between gap-3">
                        <div class="min-w-0">
                            <div class="flex flex-wrap items-center gap-2">
                                <span
                                    class="inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide"
                                    :class="d.source === 'terminal' ? 'bg-primary-soft text-primary' : 'bg-inset text-muted'"
                                >
                                    {{ d.source === 'terminal' ? 'Terminal' : 'Kiosk' }}
                                </span>
                                <span v-if="d.station" class="text-xs text-muted">{{ d.station }}</span>
                            </div>
                            <p class="mt-1 truncate text-base font-bold text-body" :title="d.name">{{ d.name }}</p>
                        </div>
                        <!-- QR küçük önizleme (tıkla büyüt) -->
                        <button
                            type="button"
                            class="shrink-0 rounded-lg border border-default bg-white p-1 transition hover:border-primary"
                            title="Karekodu büyüt"
                            @click="qrModal = d"
                        >
                            <img :src="d.qr" alt="Bağlantı karekodu" class="size-14" />
                        </button>
                    </div>

                    <!-- Kilit durumu -->
                    <div class="flex flex-wrap items-center gap-2">
                        <span class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold" :class="lockState(d).cls">
                            <span class="size-1.5 rounded-full bg-current" />
                            {{ lockState(d).text }}
                        </span>
                        <span v-if="d.binding?.bound && d.binding?.last_ip" class="text-[11px] text-subtle">
                            {{ d.binding.last_ip }}
                        </span>
                    </div>

                    <!-- Bağlantı + kopyala -->
                    <div class="flex items-center gap-2 rounded-lg bg-inset px-3 py-2">
                        <code class="min-w-0 flex-1 truncate text-xs text-body" :title="d.connect_url">{{ d.connect_url }}</code>
                        <BaseButton size="sm" variant="ghost" @click="copy(d.connect_url)">Kopyala</BaseButton>
                    </div>

                    <!-- Aksiyonlar (devices.manage — salt-görüntüleme kullanıcı bu bölümü görmez) -->
                    <div v-if="canManage" class="mt-auto flex flex-wrap gap-2">
                        <BaseButton
                            size="sm"
                            variant="secondary"
                            :disabled="!d.binding?.bound || busy === rowKey(d)"
                            :loading="busy === rowKey(d)"
                            @click="act(d, 'release')"
                        >
                            Boşa düşür
                        </BaseButton>
                        <BaseButton
                            size="sm"
                            variant="ghost"
                            :disabled="!d.binding?.bound || busy === rowKey(d)"
                            @click="act(d, 'transfer')"
                        >
                            <AppIcon name="refresh-cw" :size="14" /> Aktar
                        </BaseButton>
                        <BaseButton
                            v-if="d.binding && !d.binding.revoked"
                            size="sm"
                            variant="danger"
                            :disabled="busy === rowKey(d)"
                            @click="revokeOrReactivate(d, 'revoke')"
                        >
                            İptal et
                        </BaseButton>
                        <BaseButton
                            v-if="d.binding && d.binding.revoked"
                            size="sm"
                            variant="secondary"
                            :disabled="busy === rowKey(d)"
                            @click="revokeOrReactivate(d, 'reactivate')"
                        >
                            Yeniden etkinleştir
                        </BaseButton>
                    </div>
                </BaseCard>
            </div>
        </div>

        <!-- QR büyüt modalı -->
        <BaseModal :open="qrModal !== null" title="Bağlantı karekodu" @close="qrModal = null">
            <div v-if="qrModal" class="flex flex-col items-center gap-3 p-2 text-center">
                <p class="text-sm font-semibold text-body">{{ qrModal.name }}</p>
                <img :src="qrModal.qr" alt="Bağlantı karekodu" class="size-56 rounded-lg border border-default bg-white p-2" />
                <p class="text-xs text-muted">Bu karekodu cihazın kamerasıyla okutun; ekran o cihaza kilitlenir.</p>
                <code class="max-w-full truncate text-[11px] text-subtle">{{ qrModal.connect_url }}</code>
                <BaseButton size="sm" variant="secondary" @click="copy(qrModal.connect_url)">Bağlantıyı kopyala</BaseButton>
            </div>
        </BaseModal>
        </div>
        </div>
    </PanelShell>
</template>
