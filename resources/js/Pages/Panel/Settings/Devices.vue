<script setup lang="ts">
/**
 * CİHAZLAR — ÖKC, termal/fiş yazıcıları ve ağdaki cihazlar.
 *
 * Tarayıcı yerel ağı tarayamaz ve işletim sistemi yazıcılarını göremez; bu
 * yüzden keşif masaüstü uygulamasının native köprüsünde yapılır. Saf
 * tarayıcıda ekran bunu AÇIKÇA söyler ve sahte cihaz listelemez.
 *
 * Rol ataması bu CİHAZDA saklanır (sunucuda değil): aynı işletmenin iki
 * kasası farklı yazıcılara bağlıdır, sunucuda tutulsa biri diğerinin
 * yazıcısına basardı.
 */
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import SectionLabel from '@/Components/ui/SectionLabel.vue';
import {
    bridgeInfo,
    hasBridge,
    listOsPrinters,
    listSerialPorts,
    printToRole,
    probeDevice,
    savedDevices,
    saveDevices,
    scanNetwork,
    type BridgeDevice,
    type BridgeInfo,
    type SavedDevice,
} from '@/lib/deviceBridge';

const { success, danger, warning } = useToast();

const native = hasBridge();
const info = ref<BridgeInfo | null>(null);

const osPrinters = ref<BridgeDevice[]>([]);
const serialPorts = ref<BridgeDevice[]>([]);
const networkDevices = ref<BridgeDevice[]>([]);

const scanning = ref(false);
const loading = ref(false);
const testing = ref<string | null>(null);

const assigned = ref<SavedDevice[]>(savedDevices());

const roleOptions = [
    { value: '', label: 'Rol atama' },
    { value: 'receipt', label: 'Kasa fişi' },
    { value: 'kitchen', label: 'Mutfak fişi' },
    { value: 'okc', label: 'ÖKC (yazarkasa)' },
];

const roleLabel: Record<string, string> = {
    receipt: 'Kasa fişi',
    kitchen: 'Mutfak fişi',
    okc: 'ÖKC',
};

/** Tüm bulunan cihazlar tek listede (rol ataması için). */
const discovered = computed<BridgeDevice[]>(() => [
    ...osPrinters.value,
    ...networkDevices.value,
    ...serialPorts.value,
]);

function roleOf(address: string): string {
    return assigned.value.find((d) => d.address === address)?.role ?? '';
}

function setRole(dev: BridgeDevice, role: string): void {
    // Aynı rol tek cihaza aittir: yeni atama öncekini devre dışı bırakır,
    // aksi hâlde iki yazıcıya birden basardı.
    let list = assigned.value.filter((d) => d.address !== dev.address);
    if (role) {
        list = list.filter((d) => d.role !== role);
        list.push({ ...dev, role: role as SavedDevice['role'] });
    }
    assigned.value = list;
    saveDevices(list);
    success(role ? 'Rol atandı' : 'Rol kaldırıldı', role ? `${dev.name} → ${roleLabel[role]}` : dev.name);
}

async function loadLocal(): Promise<void> {
    if (!native) return;
    loading.value = true;
    try {
        info.value = await bridgeInfo();
        osPrinters.value = await listOsPrinters();
        serialPorts.value = await listSerialPorts();
    } catch (e) {
        danger('Cihazlar okunamadı', e instanceof Error ? e.message : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

async function runScan(): Promise<void> {
    if (!native || scanning.value) return;
    scanning.value = true;
    networkDevices.value = [];
    try {
        const found = await scanNetwork();
        networkDevices.value = found;
        if (found.length === 0) {
            warning('Ağda cihaz bulunamadı', 'Yazıcı açık ve aynı ağda mı? Kablosuz ağ ayrımı olabilir.');
        } else {
            success(`${found.length} cihaz bulundu`, 'Role atayıp test fişi basabilirsiniz.');
        }
    } catch (e) {
        danger('Tarama başarısız', e instanceof Error ? e.message : 'Beklenmeyen hata.');
    } finally {
        scanning.value = false;
    }
}

async function testConnection(dev: BridgeDevice): Promise<void> {
    if (dev.kind !== 'network' || testing.value) return;
    testing.value = dev.address;
    try {
        const [host, port] = dev.address.split(':');
        const ok = await probeDevice(host, Number(port));
        if (ok) success('Bağlantı var', dev.address);
        else danger('Bağlanılamadı', dev.address);
    } finally {
        testing.value = null;
    }
}

/** ESC/POS test fişi — cihazın gerçekten yazdırdığını kanıtlar. */
async function testPrint(role: SavedDevice['role']): Promise<void> {
    const ESC = 0x1b;
    const GS = 0x1d;
    const text = 'BamBumPOS test fisi\nCihaz baglantisi calisiyor.\n\n';
    const bytes: number[] = [
        ESC, 0x40,           // yazıcıyı sıfırla
        ESC, 0x61, 0x01,     // ortala
        ...Array.from(text, (c) => c.charCodeAt(0) & 0xff),
        0x0a, 0x0a, 0x0a,
        GS, 0x56, 0x00,      // kağıt kes
    ];
    try {
        const res = await printToRole(role, bytes);
        success('Test fişi gönderildi', res);
    } catch (e) {
        danger('Gönderilemedi', e instanceof Error ? e.message : 'Beklenmeyen hata.');
    }
}

onMounted(loadLocal);
</script>

<template>
    <Head title="Cihazlar" />
    <PanelShell title="Cihazlar" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1080px] flex-col gap-3">

            <!-- Köprü durumu: native mod mu, tarayıcı mı -->
            <div
                class="flex flex-wrap items-center gap-3 rounded-lg border p-3"
                :class="native ? 'border-success-border bg-success-soft' : 'border-warning-border bg-warning-soft'"
            >
                <AppIcon :name="native ? 'check-circle' : 'alert-triangle'" :size="20" :class="native ? 'text-success' : 'text-warning'" />
                <div class="min-w-0 grow">
                    <p class="font-semibold" :class="native ? 'text-success' : 'text-warning'">
                        {{ native ? 'Masaüstü uygulaması — cihaz erişimi açık' : 'Tarayıcıda çalışıyorsunuz' }}
                    </p>
                    <p class="text-xs text-muted">
                        <template v-if="native">
                            {{ info?.os }}/{{ info?.arch }} · köprü v{{ info?.version }}
                            <template v-if="info?.local_ip"> · yerel IP {{ info.local_ip }}</template>
                        </template>
                        <template v-else>
                            Ağ taraması, ÖKC ve işletim sistemi yazıcıları yalnız
                            <strong>BamBumPOS masaüstü uygulamasında</strong> kullanılabilir —
                            tarayıcılar yerel ağa erişemez.
                        </template>
                    </p>
                </div>
                <BaseButton v-if="!native" variant="secondary" size="sm" href="/native">
                    <AppIcon name="arrow-right" :size="15" /> Uygulamayı indir
                </BaseButton>
            </div>

            <!-- Atanmış roller -->
            <SectionLabel label="Atanmış cihazlar" icon="printer" />
            <BaseCard flush>
                <EmptyState
                    v-if="assigned.length === 0"
                    title="Henüz rol atanmadı"
                    description="Aşağıdan bir cihaz bulup “Kasa fişi”, “Mutfak fişi” ya da “ÖKC” rolü verin."
                    icon="printer"
                />
                <ul v-else class="divide-y divide-default">
                    <li v-for="d in assigned" :key="d.address" class="flex flex-wrap items-center gap-3 p-3">
                        <BaseBadge variant="primary" no-icon>{{ roleLabel[d.role] }}</BaseBadge>
                        <span class="min-w-0 grow">
                            <span class="block truncate font-medium text-body">{{ d.name }}</span>
                            <span class="block truncate text-xs text-muted">{{ d.address }}</span>
                        </span>
                        <BaseButton variant="secondary" size="sm" @click="testPrint(d.role)">
                            <AppIcon name="printer" :size="14" /> Test fişi
                        </BaseButton>
                    </li>
                </ul>
            </BaseCard>

            <!-- Keşif -->
            <SectionLabel label="Cihaz bul" icon="plug" />
            <BaseCard>
                <div class="flex flex-wrap items-center gap-2">
                    <BaseButton :disabled="!native || loading" :loading="loading" variant="secondary" @click="loadLocal">
                        <AppIcon name="refresh-cw" :size="15" /> Bilgisayardakileri tara
                    </BaseButton>
                    <BaseButton :disabled="!native || scanning" :loading="scanning" @click="runScan">
                        <AppIcon name="globe" :size="15" /> Ağı tara (9100 · 631 · 515)
                    </BaseButton>
                    <span v-if="scanning" class="text-xs text-muted">254 adres taranıyor…</span>
                </div>
                <p class="mt-2 text-xs text-muted">
                    Ağ taraması bu bilgisayarın bulunduğu /24 ağını dener. Yazıcılar 9100 (RAW/ESC-POS),
                    631 (IPP) veya 515 (LPD) portunu dinler; ÖKC cihazları çoğunlukla 9100 kullanır.
                </p>
            </BaseCard>

            <BaseCard v-if="discovered.length > 0" flush title="Bulunan cihazlar">
                <ul class="divide-y divide-default">
                    <li v-for="d in discovered" :key="d.kind + d.address" class="flex flex-wrap items-center gap-3 p-3">
                        <span
                            class="flex size-9 shrink-0 items-center justify-center rounded-lg"
                            :class="d.kind === 'network' ? 'bg-info-soft text-info' : d.kind === 'serial' ? 'bg-warning-soft text-warning' : 'bg-primary-soft text-primary'"
                        >
                            <AppIcon :name="d.kind === 'network' ? 'globe' : d.kind === 'serial' ? 'plug' : 'printer'" :size="17" />
                        </span>
                        <span class="min-w-0 grow">
                            <span class="block truncate font-medium text-body">{{ d.name }}</span>
                            <span class="block truncate text-xs text-muted">{{ d.detail ?? d.address }}</span>
                        </span>
                        <BaseButton
                            v-if="d.kind === 'network'"
                            variant="ghost"
                            size="sm"
                            :loading="testing === d.address"
                            @click="testConnection(d)"
                        >
                            Bağlantıyı sına
                        </BaseButton>
                        <div class="w-40 shrink-0">
                            <BaseSelect
                                :model-value="roleOf(d.address)"
                                :options="roleOptions"
                                size="sm"
                                @update:model-value="(v: string) => setRole(d, v)"
                            />
                        </div>
                    </li>
                </ul>
            </BaseCard>
        </div>
        </div>
    </PanelShell>
</template>
