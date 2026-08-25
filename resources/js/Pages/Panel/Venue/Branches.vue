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

/* İşletme Vitrini (public QR menüsünde görünen bilgi kartı) */
const DAY_LABELS = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
const SOCIAL_FIELDS: { key: string; label: string; ph: string }[] = [
    { key: 'instagram', label: 'Instagram', ph: 'kullanici veya tam URL' },
    { key: 'facebook', label: 'Facebook', ph: 'sayfa veya tam URL' },
    { key: 'x', label: 'X (Twitter)', ph: 'kullanici' },
    { key: 'tiktok', label: 'TikTok', ph: 'kullanici' },
    { key: 'youtube', label: 'YouTube', ph: 'kanal veya @handle' },
    { key: 'whatsapp', label: 'WhatsApp', ph: '+9053...' },
    { key: 'website', label: 'Web sitesi', ph: 'https://...' },
];

type HourRow = { d: number; closed: boolean; open: string; close: string };
type ShowcaseForm = {
    wifi_ssid: string;
    wifi_password: string;
    maps_url: string;
    show_map: boolean;
    hoursEnabled: boolean;
    hours: HourRow[];
    social: Record<string, string>;
};

function emptyShowcase(): ShowcaseForm {
    return {
        wifi_ssid: '',
        wifi_password: '',
        maps_url: '',
        show_map: true,
        hoursEnabled: false,
        hours: Array.from({ length: 7 }, (_, d) => ({ d, closed: false, open: '09:00', close: '22:00' })),
        social: Object.fromEntries(SOCIAL_FIELDS.map((f) => [f.key, ''])),
    };
}

/* Kaydedilmiş showcase JSON'unu forma çevir (eksikleri varsayılana tamamla). */
function showcaseFromRow(raw: unknown): ShowcaseForm {
    const sc = emptyShowcase();
    if (!raw || typeof raw !== 'object') return sc;
    const r = raw as Record<string, unknown>;
    sc.wifi_ssid = typeof r.wifi_ssid === 'string' ? r.wifi_ssid : '';
    sc.wifi_password = typeof r.wifi_password === 'string' ? r.wifi_password : '';
    sc.maps_url = typeof r.maps_url === 'string' ? r.maps_url : '';
    sc.show_map = r.show_map !== false;
    if (Array.isArray(r.hours) && r.hours.length > 0) {
        sc.hoursEnabled = true;
        for (const h of r.hours as Record<string, unknown>[]) {
            const d = Number(h?.d);
            if (d >= 0 && d <= 6) {
                sc.hours[d] = {
                    d,
                    closed: h.closed === true,
                    open: typeof h.open === 'string' ? h.open : '',
                    close: typeof h.close === 'string' ? h.close : '',
                };
            }
        }
    }
    if (r.social && typeof r.social === 'object') {
        for (const f of SOCIAL_FIELDS) {
            const v = (r.social as Record<string, unknown>)[f.key];
            sc.social[f.key] = typeof v === 'string' ? v : '';
        }
    }
    return sc;
}

/* Formu API gövdesine çevir; her şey boşsa null (kart hiç görünmez). */
function showcaseToBody(sc: ShowcaseForm): Record<string, unknown> | null {
    const social: Record<string, string> = {};
    for (const f of SOCIAL_FIELDS) {
        const v = sc.social[f.key]?.trim();
        if (v) social[f.key] = v;
    }
    const out: Record<string, unknown> = {};
    if (sc.wifi_ssid.trim()) out.wifi_ssid = sc.wifi_ssid.trim();
    if (sc.wifi_password.trim()) out.wifi_password = sc.wifi_password.trim();
    if (sc.maps_url.trim()) out.maps_url = sc.maps_url.trim();
    out.show_map = sc.show_map;
    if (sc.hoursEnabled) {
        out.hours = sc.hours.map((h) => ({
            d: h.d,
            closed: h.closed,
            open: h.closed ? null : h.open || null,
            close: h.closed ? null : h.close || null,
        }));
    }
    if (Object.keys(social).length > 0) out.social = social;

    // Yalnız show_map (varsayılan) varsa "boş" say → null gönder.
    const meaningful = out.wifi_ssid || out.wifi_password || out.maps_url || out.hours || out.social;
    return meaningful ? out : null;
}

const form = ref({ name: '', code: '', address: '', phone: '', timezone: 'Europe/Istanbul', is_active: true });
const showcase = ref<ShowcaseForm>(emptyShowcase());
const formErrors = ref<Record<string, string>>({});
const formBusy = ref(false);

function openCreate(): void {
    editing.value = null;
    formErrors.value = {};
    form.value = { name: '', code: '', address: '', phone: '', timezone: 'Europe/Istanbul', is_active: true };
    showcase.value = emptyShowcase();
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
    showcase.value = showcaseFromRow((row as unknown as { showcase?: unknown }).showcase);
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
        showcase: showcaseToBody(showcase.value),
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
    <!-- TAM KAPLAMA: mekân gezinmesi SABİT şeritte; içerik kendi içinde kayar. -->
    <PanelShell title="Şubeler" flush canvas>
        <div class="shrink-0 border-b border-default bg-raised px-4 py-2.5 sm:px-6">
            <VenueNav />
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">
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

                <!-- ============ İşletme Vitrini ============ -->
                <div class="mt-2 border-t border-default pt-4">
                    <div class="flex items-center gap-2">
                        <AppIcon name="qr-code" class="size-4 text-primary" />
                        <h3 class="text-sm font-semibold">İşletme Vitrini</h3>
                    </div>
                    <p class="mt-1 text-xs text-muted">Müşteri QR menüsünde görünen bilgi kartı: WiFi, çalışma saatleri, konum ve sosyal medya. Boş bıraktığınız alanlar gösterilmez.</p>

                    <!-- WiFi -->
                    <div class="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
                        <FormField label="WiFi ağ adı (SSID)" :error="formErrors['showcase.wifi_ssid']">
                            <BaseInput v-model="showcase.wifi_ssid" placeholder="ör. Cafe_Misafir" />
                        </FormField>
                        <FormField label="WiFi şifresi" :error="formErrors['showcase.wifi_password']">
                            <BaseInput v-model="showcase.wifi_password" placeholder="Müşteri tek dokunuşla kopyalar" />
                        </FormField>
                    </div>

                    <!-- Konum -->
                    <FormField label="Harita / konum bağlantısı" class="mt-1" :error="formErrors['showcase.maps_url']" hint="Boş bırakılırsa adresten Google Haritalar linki otomatik üretilir">
                        <BaseInput v-model="showcase.maps_url" placeholder="https://maps.google.com/..." inputmode="url" />
                    </FormField>
                    <BaseSwitch v-model="showcase.show_map" class="mt-2" label="Yol tarifi bağlantısını göster" description="Menüde konum/harita satırı görünsün" />

                    <!-- Çalışma saatleri -->
                    <BaseSwitch v-model="showcase.hoursEnabled" class="mt-3" label="Çalışma saatlerini göster" description="Haftalık açılış/kapanış saatleri; müşteri 'şu an açık/kapalı' görür" />
                    <div v-if="showcase.hoursEnabled" class="mt-2 flex flex-col gap-1.5 rounded-lg border border-app bg-subtle p-2">
                        <div v-for="row in showcase.hours" :key="row.d" class="flex items-center gap-2">
                            <span class="w-20 shrink-0 text-xs font-medium">{{ DAY_LABELS[row.d] }}</span>
                            <template v-if="!row.closed">
                                <BaseInput v-model="row.open" type="time" class="!py-1 text-sm" />
                                <span class="text-xs text-muted">–</span>
                                <BaseInput v-model="row.close" type="time" class="!py-1 text-sm" />
                            </template>
                            <span v-else class="flex-1 text-xs text-muted">Kapalı</span>
                            <label class="ml-auto flex shrink-0 items-center gap-1 text-xs text-muted">
                                <input v-model="row.closed" type="checkbox" class="size-3.5 accent-current" />
                                Kapalı
                            </label>
                        </div>
                    </div>

                    <!-- Sosyal medya -->
                    <div class="mt-4">
                        <span class="text-xs font-medium text-muted">Sosyal medya</span>
                        <div class="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2">
                            <FormField v-for="f in SOCIAL_FIELDS" :key="f.key" :label="f.label" :error="formErrors[`showcase.social.${f.key}`]">
                                <BaseInput v-model="showcase.social[f.key]" :placeholder="f.ph" />
                            </FormField>
                        </div>
                    </div>
                </div>

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
        </div>
    </PanelShell>
</template>
