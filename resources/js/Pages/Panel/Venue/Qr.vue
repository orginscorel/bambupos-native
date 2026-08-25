<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseCheckbox from '@/Components/ui/BaseCheckbox.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import DataTable, { type TableColumn } from '@/Components/ui/DataTable.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import VenueNav from './VenueNav.vue';
import { fetchAreas, fetchBranches, uploadFile, type AreaRow, type BranchRow, type Paginated, type TableRow } from './venue';

const { success, danger } = useToast();

/* ================= Şablon ayarları ================= */
interface QrSettings {
    header_text: string | null;
    description: string | null;
    color: string;
    bg_color: string;
    frame: string;
    show_table_no: boolean;
    has_logo: boolean;
}

const settings = ref<QrSettings | null>(null);
const settingsBusy = ref(false);
const settingsErrors = ref<Record<string, string>>({});

async function loadSettings(): Promise<void> {
    const res = await api<{ settings: QrSettings }>('/api/v1/venue/qr/settings');
    settings.value = res.settings;
}

async function saveSettings(): Promise<void> {
    if (!settings.value || settingsBusy.value) return;
    settingsBusy.value = true;
    settingsErrors.value = {};
    try {
        const res = await api<{ settings: QrSettings }>('/api/v1/venue/qr/settings', {
            method: 'PUT',
            body: {
                header_text: settings.value.header_text || null,
                description: settings.value.description || null,
                color: settings.value.color,
                bg_color: settings.value.bg_color,
                frame: settings.value.frame,
                show_table_no: settings.value.show_table_no,
            },
        });
        settings.value = res.settings;
        success('Şablon kaydedildi', 'QR kartları yeni şablonla üretilecek.');
        bumpPreview();
    } catch (e) {
        if (e instanceof ApiError) {
            for (const [k, v] of Object.entries(e.errors)) settingsErrors.value[k] = v[0];
            if (Object.keys(settingsErrors.value).length === 0) danger('Kaydedilemedi', e.displayMessage);
        } else {
            danger('Kaydedilemedi', 'Beklenmeyen bir hata oluştu.');
        }
    } finally {
        settingsBusy.value = false;
    }
}

const logoInput = ref<HTMLInputElement | null>(null);
const logoBusy = ref(false);

async function onLogoChosen(event: Event): Promise<void> {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file || logoBusy.value) return;
    logoBusy.value = true;
    try {
        const res = await uploadFile<{ settings: QrSettings }>('/api/v1/venue/qr/logo', 'logo', file);
        settings.value = res.settings;
        success('Logo yüklendi', 'QR kartlarının ortasına eklenecek.');
        bumpPreview();
    } catch (e) {
        danger('Logo yüklenemedi', e instanceof Error ? e.message : 'Beklenmeyen bir hata oluştu.');
    } finally {
        logoBusy.value = false;
        if (logoInput.value) logoInput.value.value = '';
    }
}

async function removeLogo(): Promise<void> {
    if (logoBusy.value) return;
    logoBusy.value = true;
    try {
        const res = await api<{ settings: QrSettings }>('/api/v1/venue/qr/logo', { method: 'DELETE' });
        settings.value = res.settings;
        success('Logo kaldırıldı', 'Kartlar logosuz üretilecek.');
        bumpPreview();
    } catch (e) {
        danger('Logo kaldırılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        logoBusy.value = false;
    }
}

/* ================= Şube / masa listesi ================= */
const branches = ref<BranchRow[]>([]);
const areas = ref<AreaRow[]>([]);
const branchId = ref('');
const areaId = ref('');
const tables = ref<TableRow[]>([]);
const loadingTables = ref(false);

const branchOptions = computed(() => branches.value.map((b) => ({ value: String(b.id), label: b.name })));
const areaOptions = computed(() =>
    areas.value
        .filter((a) => String(a.branch_id) === branchId.value)
        .map((a) => ({ value: String(a.id), label: a.name })),
);

async function loadTables(): Promise<void> {
    if (!branchId.value) {
        tables.value = [];
        return;
    }
    loadingTables.value = true;
    try {
        const params = new URLSearchParams({ branch_id: branchId.value, active: '1', per_page: '200' });
        if (areaId.value) params.set('area_id', areaId.value);
        const res = await api<{ tables: Paginated<TableRow> }>(`/api/v1/venue/tables?${params}`);
        tables.value = res.tables.data;
    } catch (e) {
        danger('Masalar yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loadingTables.value = false;
    }
}

watch(branchId, () => {
    areaId.value = '';
    bumpPreview();
    void loadTables();
});
watch(areaId, () => void loadTables());

onMounted(async () => {
    try {
        await loadSettings();
        [branches.value, areas.value] = await Promise.all([fetchBranches(), fetchAreas(null)]);
        branchId.value = String(branches.value[0]?.id ?? '');
    } catch (e) {
        danger('Sayfa yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    }
});

/* ================= Önizleme ================= */
const previewVersion = ref(0);

function bumpPreview(): void {
    previewVersion.value++;
}

// CANLI önizleme: URL güncel (kaydedilmemiş) şablon değerlerini taşır (?preview=1).
// settings değişince computed yeniden hesaplanır → <img> src değişir → anında yenilenir.
const previewUrl = computed(() => {
    const first = tables.value[0];
    const base = first
        ? `/api/v1/venue/tables/${first.id}/qr-image`
        : branchId.value
            ? `/api/v1/venue/branches/${branchId.value}/qr-image`
            : '';
    if (!base) return '';
    const p = new URLSearchParams({ preview: '1', v: String(previewVersion.value) });
    const s = settings.value;
    if (s) {
        p.set('color', s.color);
        p.set('bg_color', s.bg_color);
        p.set('frame', s.frame);
        p.set('header', s.header_text ?? '');
        p.set('description', s.description ?? '');
    }
    return `${base}?${p.toString()}`;
});

/* ================= İndirme / rotasyon ================= */
function downloadTable(row: TableRow, format: 'png' | 'svg'): void {
    window.location.href = `/api/v1/venue/tables/${row.id}/qr-image?format=${format}&download=1`;
}

function downloadBranch(format: 'png' | 'svg'): void {
    if (!branchId.value) return;
    window.location.href = `/api/v1/venue/branches/${branchId.value}/qr-image?format=${format}&download=1`;
}

function downloadSheet(includeGeneral: boolean): void {
    if (!branchId.value) return;
    const params = new URLSearchParams({ branch_id: branchId.value });
    if (areaId.value) params.set('area_id', areaId.value);
    if (includeGeneral) params.set('include_general', '1');
    window.location.href = `/api/v1/venue/qr/sheet?${params}`;
}

const rotatingRow = ref<TableRow | null>(null);
const rotateAllOpen = ref(false);
const rotateBranchOpen = ref(false);
const rotateBusy = ref(false);

async function rotateOne(): Promise<void> {
    const row = rotatingRow.value;
    if (!row) return;
    rotatingRow.value = null;
    try {
        await api(`/api/v1/venue/tables/${row.id}/qr-rotate`, { method: 'POST' });
        success('QR yenilendi', `${row.name} masasının eski QR kodu geçersiz. Yeni kartı yazdırın.`);
        bumpPreview();
        await loadTables();
    } catch (e) {
        danger('QR yenilenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    }
}

async function rotateAll(): Promise<void> {
    if (rotateBusy.value || !branchId.value) return;
    rotateBusy.value = true;
    try {
        const body: Record<string, unknown> = { branch_id: Number(branchId.value) };
        if (areaId.value) body.area_id = Number(areaId.value);
        const res = await api<{ rotated: number }>('/api/v1/venue/qr/rotate-bulk', { method: 'POST', body });
        success('Toplu QR yenileme tamam', `${res.rotated} masanın eski QR kodu geçersiz kılındı. A4 PDF ile yeni kartları yazdırın.`);
        rotateAllOpen.value = false;
        bumpPreview();
        await loadTables();
    } catch (e) {
        danger('Toplu yenileme başarısız', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        rotateBusy.value = false;
    }
}

async function rotateBranchToken(): Promise<void> {
    if (rotateBusy.value || !branchId.value) return;
    rotateBusy.value = true;
    try {
        await api(`/api/v1/venue/branches/${branchId.value}/qr-rotate`, { method: 'POST' });
        success('Genel menü QR yenilendi', 'Eski genel menü kodu geçersiz kılındı.');
        rotateBranchOpen.value = false;
        bumpPreview();
    } catch (e) {
        danger('Yenilenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        rotateBusy.value = false;
    }
}

const columns: TableColumn[] = [
    { key: 'number', label: 'No', widthClass: 'w-16' },
    { key: 'name', label: 'Masa' },
    { key: 'area_name', label: 'Alan' },
    { key: 'qr_rotated_at', label: 'Son yenileme' },
    { key: 'actions', label: 'QR işlemleri', align: 'right' },
];
</script>

<template>
    <Head title="QR Yönetimi" />
    <!-- TAM KAPLAMA: mekân gezinmesi SABİT şeritte; içerik kendi içinde kayar. -->
    <PanelShell title="QR Yönetimi" flush canvas>
        <div class="shrink-0 border-b border-default bg-raised px-4 py-2.5 sm:px-6">
            <VenueNav />
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">
            <div class="grid gap-4 lg:grid-cols-3">
                <!-- Şablon -->
                <div class="lg:col-span-2">
                    <BaseCard title="QR kart şablonu">
                        <div v-if="!settings" class="flex flex-col gap-3">
                            <BaseSkeleton size-class="h-10 w-full" />
                            <BaseSkeleton size-class="h-10 w-full" />
                        </div>
                        <form v-else class="flex flex-col gap-4" @submit.prevent="saveSettings">
                            <div class="grid gap-3 sm:grid-cols-2">
                                <FormField label="Başlık" :error="settingsErrors.header_text" hint="Boş bırakılırsa işletme adı kullanılır">
                                    <BaseInput :model-value="settings.header_text ?? ''" placeholder="İşletme adı" @update:model-value="(v: string) => (settings!.header_text = v)" />
                                </FormField>
                                <FormField label="Açıklama" :error="settingsErrors.description">
                                    <BaseInput :model-value="settings.description ?? ''" placeholder="Menü için QR kodu okutun" @update:model-value="(v: string) => (settings!.description = v)" />
                                </FormField>
                            </div>
                            <div class="grid gap-3 sm:grid-cols-3">
                                <FormField label="Desen rengi" :error="settingsErrors.color">
                                    <div class="flex items-center gap-2">
                                        <input v-model="settings.color" type="color" class="h-10 w-12 cursor-pointer rounded-md border border-strong bg-raised" aria-label="Desen rengi seç" />
                                        <BaseInput v-model="settings.color" size="sm" />
                                    </div>
                                </FormField>
                                <FormField label="Arka plan" :error="settingsErrors.bg_color">
                                    <div class="flex items-center gap-2">
                                        <input v-model="settings.bg_color" type="color" class="h-10 w-12 cursor-pointer rounded-md border border-strong bg-raised" aria-label="Arka plan rengi seç" />
                                        <BaseInput v-model="settings.bg_color" size="sm" />
                                    </div>
                                </FormField>
                                <FormField label="Çerçeve" :error="settingsErrors.frame">
                                    <BaseSelect
                                        v-model="settings.frame"
                                        :options="[
                                            { value: 'none', label: 'Çerçevesiz' },
                                            { value: 'simple', label: 'Düz çerçeve' },
                                            { value: 'rounded', label: 'Çift çizgi' },
                                        ]"
                                    />
                                </FormField>
                            </div>
                            <BaseCheckbox v-model="settings.show_table_no" label="Masa numarasını kartta göster" />
                            <div class="flex flex-wrap items-center gap-2">
                                <input ref="logoInput" type="file" accept="image/png,image/jpeg,image/webp" class="hidden" @change="onLogoChosen" />
                                <BaseButton variant="secondary" :loading="logoBusy" @click="logoInput?.click()">
                                    <AppIcon name="plus" :size="15" />
                                    {{ settings.has_logo ? 'Logoyu değiştir' : 'Logo yükle' }}
                                </BaseButton>
                                <BaseButton v-if="settings.has_logo" variant="ghost" :loading="logoBusy" @click="removeLogo">
                                    <AppIcon name="trash" :size="15" />
                                    Logoyu kaldır
                                </BaseButton>
                                <span class="text-xs text-muted">PNG/JPG/WebP, en fazla 2&nbsp;MB; sunucuda işlenir, dışarı gönderilmez.</span>
                            </div>
                            <div class="flex justify-end">
                                <BaseButton type="submit" :loading="settingsBusy">Şablonu kaydet</BaseButton>
                            </div>
                        </form>
                    </BaseCard>
                </div>

                <!-- Önizleme -->
                <BaseCard title="Önizleme">
                    <div class="flex flex-col items-center gap-3">
                        <img
                            v-if="previewUrl"
                            :src="previewUrl"
                            alt="QR kart önizlemesi"
                            class="w-full max-w-64 rounded-md border border-default"
                        />
                        <EmptyState v-else title="Önizleme yok" description="Önce bir şube seçin." icon="qr-code" />
                        <p class="text-center text-xs text-muted">Önizleme ilk masanın (yoksa genel menünün) gerçek kartıdır.</p>
                    </div>
                </BaseCard>
            </div>

            <!-- Kapsam + toplu çıktı -->
            <BaseCard>
                <div class="flex flex-wrap items-end gap-3">
                    <div class="w-full sm:w-56">
                        <FormField label="Şube">
                            <BaseSelect v-model="branchId" :options="branchOptions" placeholder="Şube seçin" />
                        </FormField>
                    </div>
                    <div class="w-full sm:w-56">
                        <FormField label="Alan (isteğe bağlı)">
                            <BaseSelect v-model="areaId" :options="areaOptions" placeholder="Tüm alanlar" />
                        </FormField>
                    </div>
                    <div class="flex flex-wrap gap-2">
                        <BaseButton :disabled="!branchId || tables.length === 0" @click="downloadSheet(false)">
                            <AppIcon name="qr-code" :size="15" />
                            A4 PDF indir {{ areaId ? '(alan)' : '(şube)' }}
                        </BaseButton>
                        <BaseButton variant="secondary" :disabled="!branchId" @click="downloadSheet(true)">
                            A4 PDF + genel menü
                        </BaseButton>
                        <BaseButton variant="secondary" :disabled="!branchId" @click="downloadBranch('png')">Genel menü PNG</BaseButton>
                        <BaseButton variant="secondary" :disabled="!branchId" @click="downloadBranch('svg')">Genel menü SVG</BaseButton>
                        <BaseButton variant="danger" :disabled="!branchId || tables.length === 0" @click="rotateAllOpen = true">
                            <AppIcon name="alert-triangle" :size="15" />
                            Tümünün QR'ını yenile
                        </BaseButton>
                        <BaseButton variant="ghost" :disabled="!branchId" @click="rotateBranchOpen = true">Genel menü QR'ını yenile</BaseButton>
                    </div>
                </div>
            </BaseCard>

            <!-- Masa bazlı QR listesi -->
            <BaseCard flush title="Masa QR kodları">
                <DataTable :columns="columns" :rows="tables" :loading="loadingTables" caption="Masa QR listesi" empty-title="Masa yok" empty-description="Seçilen kapsamda aktif masa bulunamadı.">
                    <template #cell-number="{ row }">
                        <span class="font-mono text-sm">{{ (row as unknown as TableRow).number ?? '—' }}</span>
                    </template>
                    <template #cell-name="{ row }">
                        <span class="font-medium">{{ (row as unknown as TableRow).name }}</span>
                    </template>
                    <template #cell-area_name="{ row }">
                        <span v-if="(row as unknown as TableRow).area_name">{{ (row as unknown as TableRow).area_name }}</span>
                        <span v-else class="text-subtle">—</span>
                    </template>
                    <template #cell-qr_rotated_at="{ row }">
                        <span v-if="(row as unknown as TableRow).qr_rotated_at" class="text-xs text-muted">
                            {{ new Date((row as unknown as TableRow).qr_rotated_at as string).toLocaleString('tr-TR') }}
                        </span>
                        <span v-else class="text-xs text-subtle">İlk kod</span>
                    </template>
                    <template #cell-actions="{ row }">
                        <div class="flex items-center justify-end gap-1">
                            <BaseButton size="sm" variant="secondary" @click="downloadTable(row as unknown as TableRow, 'png')">PNG</BaseButton>
                            <BaseButton size="sm" variant="secondary" @click="downloadTable(row as unknown as TableRow, 'svg')">SVG</BaseButton>
                            <BaseButton size="sm" variant="ghost" icon-only label="QR kodunu yenile" @click="rotatingRow = row as unknown as TableRow">
                                <AppIcon name="alert-triangle" :size="15" />
                            </BaseButton>
                        </div>
                    </template>
                </DataTable>
            </BaseCard>
        </div>

        <!-- Onaylar -->
        <BaseModal :open="rotatingRow !== null" title="QR kodunu yenile" size="sm" @close="rotatingRow = null">
            <p class="text-sm text-muted">
                <strong>{{ rotatingRow?.name }}</strong> masasının QR kodu yenilenecek; basılı eski kod <strong>anında geçersiz</strong> olacak.
            </p>
            <template #footer>
                <BaseButton variant="secondary" @click="rotatingRow = null">Vazgeç</BaseButton>
                <BaseButton variant="danger" @click="rotateOne">Yenile</BaseButton>
            </template>
        </BaseModal>

        <BaseModal :open="rotateAllOpen" title="Toplu QR yenileme" size="sm" @close="rotateAllOpen = false">
            <p class="text-sm text-muted">
                Seçilen kapsamdaki <strong>{{ tables.length }}</strong> masanın QR kodu yenilenecek; masalardaki tüm basılı
                kodlar <strong>anında geçersiz</strong> olacak. Ardından A4 PDF'i indirip yeni kartları yazdırın.
            </p>
            <template #footer>
                <BaseButton variant="secondary" @click="rotateAllOpen = false">Vazgeç</BaseButton>
                <BaseButton variant="danger" :loading="rotateBusy" @click="rotateAll">Tümünü yenile</BaseButton>
            </template>
        </BaseModal>

        <BaseModal :open="rotateBranchOpen" title="Genel menü QR'ını yenile" size="sm" @close="rotateBranchOpen = false">
            <p class="text-sm text-muted">Şubenin genel menü (masasız) QR kodu yenilenecek; basılı eski kod geçersiz olacak.</p>
            <template #footer>
                <BaseButton variant="secondary" @click="rotateBranchOpen = false">Vazgeç</BaseButton>
                <BaseButton variant="danger" :loading="rotateBusy" @click="rotateBranchToken">Yenile</BaseButton>
            </template>
        </BaseModal>
        </div>
    </PanelShell>
</template>
