<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import ShiftsShell from './components/ShiftsShell.vue';
import type { ClockDeviceRow, ShiftsMeta, ShiftSettings, StaffingRuleRow } from './types';
import { WEEKDAY_LABELS } from './types';
import { fmtDateTime } from './lib';

/**
 * /panel/mesai/ayarlar — mesai ayarları (yalnız staff.manage):
 * - süre/tolerans varsayılanları,
 * - KVKK konum takibi (VARSAYILAN KAPALI; açmak için politika metni zorunlu),
 * - yetkili giriş/çıkış cihazları (token bir kez gösterilir),
 * - minimum personel kuralları.
 */
const { success, danger } = useToast();

const meta = ref<ShiftsMeta | null>(null);
const loading = ref(true);
const saving = ref(false);
const errors = ref<Record<string, string>>({});

const settings = ref({
    standard_daily_min: '540',
    late_tolerance_min: '5',
    early_leave_tolerance_min: '5',
    default_break_min: '30',
    location_tracking_enabled: false,
    location_policy: '',
});

const devices = ref<ClockDeviceRow[]>([]);
const rules = ref<StaffingRuleRow[]>([]);

async function loadAll(): Promise<void> {
    loading.value = true;
    try {
        const [s, d, r, m] = await Promise.all([
            api<{ settings: ShiftSettings }>('/api/v1/shifts/settings'),
            api<{ devices: ClockDeviceRow[] }>('/api/v1/shifts/devices'),
            api<{ rules: StaffingRuleRow[] }>('/api/v1/shifts/staffing-rules'),
            api<ShiftsMeta>('/api/v1/shifts/meta'),
        ]);
        settings.value = {
            standard_daily_min: String(s.settings.standard_daily_min ?? 540),
            late_tolerance_min: String(s.settings.late_tolerance_min ?? 5),
            early_leave_tolerance_min: String(s.settings.early_leave_tolerance_min ?? 5),
            default_break_min: String(s.settings.default_break_min ?? 30),
            location_tracking_enabled: s.settings.location_tracking_enabled,
            location_policy: s.settings.location_policy ?? '',
        };
        devices.value = d.devices;
        rules.value = r.rules;
        meta.value = m;
    } catch (e) {
        if (e instanceof ApiError) danger('Ayarlar yüklenemedi', e.displayMessage);
    } finally {
        loading.value = false;
    }
}

onMounted(loadAll);

async function saveSettings(): Promise<void> {
    saving.value = true;
    errors.value = {};
    try {
        await api('/api/v1/shifts/settings', {
            method: 'PUT',
            body: {
                standard_daily_min: Number(settings.value.standard_daily_min),
                late_tolerance_min: Number(settings.value.late_tolerance_min),
                early_leave_tolerance_min: Number(settings.value.early_leave_tolerance_min),
                default_break_min: Number(settings.value.default_break_min),
                location_tracking_enabled: settings.value.location_tracking_enabled,
                location_policy: settings.value.location_policy || null,
            },
        });
        success('Ayarlar kaydedildi');
    } catch (e) {
        if (e instanceof ApiError) {
            errors.value = Object.fromEntries(Object.entries(e.errors).map(([k, v]) => [k, v[0]]));
            if (Object.keys(errors.value).length === 0) danger('Kaydedilemedi', e.displayMessage);
        }
    } finally {
        saving.value = false;
    }
}

/* ---- Cihazlar ---- */
const deviceName = ref('');
const deviceBranch = ref('');
const deviceSaving = ref(false);
const newToken = ref('');
const tokenModal = ref(false);

const branchOptions = computed(() => [
    { value: '', label: 'Şubeden bağımsız' },
    ...(meta.value?.branches ?? []).map((b) => ({ value: String(b.id), label: b.name })),
]);

async function addDevice(): Promise<void> {
    if (!deviceName.value.trim()) {
        danger('Cihaz adı gerekli');
        return;
    }
    deviceSaving.value = true;
    try {
        const result = await api<{ token: string }>('/api/v1/shifts/devices', {
            method: 'POST',
            body: { name: deviceName.value.trim(), branch_id: deviceBranch.value ? Number(deviceBranch.value) : null },
        });
        newToken.value = result.token;
        tokenModal.value = true;
        deviceName.value = '';
        deviceBranch.value = '';
        await loadAll();
    } catch (e) {
        if (e instanceof ApiError) danger('Cihaz eklenemedi', e.displayMessage);
    } finally {
        deviceSaving.value = false;
    }
}

async function removeDevice(row: ClockDeviceRow): Promise<void> {
    try {
        await api(`/api/v1/shifts/devices/${row.id}`, { method: 'DELETE' });
        success('Cihaz silindi');
        await loadAll();
    } catch (e) {
        if (e instanceof ApiError) danger('Silinemedi', e.displayMessage);
    }
}

async function copyToken(): Promise<void> {
    try {
        await navigator.clipboard.writeText(newToken.value);
        success('Token panoya kopyalandı');
    } catch {
        danger('Kopyalanamadı', 'Token metnini elle seçip kopyalayın.');
    }
}

/* ---- Min. personel kuralları ---- */
const ruleForm = ref({ branch_id: '', weekday: '', position: '', min_count: '2' });
const ruleSaving = ref(false);

const weekdayOptions = [
    { value: '', label: 'Her gün' },
    ...WEEKDAY_LABELS.map((label, i) => ({ value: String(i), label })),
];

async function addRule(): Promise<void> {
    if (!ruleForm.value.branch_id) {
        danger('Şube seçin');
        return;
    }
    ruleSaving.value = true;
    try {
        await api('/api/v1/shifts/staffing-rules', {
            method: 'POST',
            body: {
                branch_id: Number(ruleForm.value.branch_id),
                weekday: ruleForm.value.weekday === '' ? null : Number(ruleForm.value.weekday),
                position: ruleForm.value.position || null,
                min_count: Number(ruleForm.value.min_count || 1),
            },
        });
        success('Kural eklendi');
        ruleForm.value = { branch_id: '', weekday: '', position: '', min_count: '2' };
        await loadAll();
    } catch (e) {
        if (e instanceof ApiError) danger('Kural eklenemedi', e.displayMessage);
    } finally {
        ruleSaving.value = false;
    }
}

async function removeRule(row: StaffingRuleRow): Promise<void> {
    try {
        await api(`/api/v1/shifts/staffing-rules/${row.id}`, { method: 'DELETE' });
        success('Kural silindi');
        await loadAll();
    } catch (e) {
        if (e instanceof ApiError) danger('Silinemedi', e.displayMessage);
    }
}
</script>

<template>
    <Head title="Mesai Ayarları" />
    <ShiftsShell title="Mesai Ayarları">
        <BaseSkeleton v-if="loading" class="h-64 w-full" />

        <div v-else class="grid grid-cols-1 gap-4 xl:grid-cols-2">
            <!-- Genel + KVKK -->
            <BaseCard title="Genel ayarlar">
                <div class="flex flex-col gap-3">
                    <div class="grid grid-cols-2 gap-3">
                        <FormField
                            label="Standart gün (dk)"
                            :error="errors.standard_daily_min"
                            hint="Vardiyasız günlerde fazla mesai eşiği"
                        >
                            <BaseInput v-model="settings.standard_daily_min" type="number" inputmode="numeric" />
                        </FormField>
                        <FormField label="Varsayılan mola (dk)" :error="errors.default_break_min">
                            <BaseInput v-model="settings.default_break_min" type="number" inputmode="numeric" />
                        </FormField>
                        <FormField label="Geç kalma toleransı (dk)" :error="errors.late_tolerance_min">
                            <BaseInput v-model="settings.late_tolerance_min" type="number" inputmode="numeric" />
                        </FormField>
                        <FormField label="Erken çıkış toleransı (dk)" :error="errors.early_leave_tolerance_min">
                            <BaseInput v-model="settings.early_leave_tolerance_min" type="number" inputmode="numeric" />
                        </FormField>
                    </div>

                    <div class="rounded-md border border-default bg-inset p-3">
                        <div class="flex items-center justify-between gap-2">
                            <div>
                                <p class="text-sm font-semibold text-body">Konum doğrulaması (KVKK)</p>
                                <p class="mt-0.5 text-xs text-muted">
                                    Varsayılan olarak <strong>kapalıdır</strong> ve hiçbir zaman zorunlu değildir.
                                    Açılırsa bile konum yalnız <strong>açık rıza veren</strong> personelde kaydedilir.
                                </p>
                            </div>
                            <BaseSwitch v-model="settings.location_tracking_enabled" label="Konum doğrulaması" />
                        </div>
                        <FormField
                            v-if="settings.location_tracking_enabled"
                            class="mt-2"
                            label="Aydınlatma / politika metni"
                            :error="errors.location_policy"
                            required
                            hint="Personele rıza ekranında gösterilir; boş bırakılamaz"
                        >
                            <textarea
                                v-model="settings.location_policy"
                                rows="3"
                                class="w-full rounded-md border border-strong bg-raised p-2 text-sm text-body placeholder:text-subtle focus:ring-2 focus:ring-ring-brand focus:outline-none"
                                placeholder="Konum verisinin hangi amaçla, ne kadar süreyle işlendiğini açıklayın…"
                            />
                        </FormField>
                    </div>

                    <div class="flex justify-end">
                        <BaseButton :loading="saving" @click="saveSettings">Kaydet</BaseButton>
                    </div>
                </div>
            </BaseCard>

            <div class="flex flex-col gap-4">
                <!-- Yetkili cihazlar -->
                <BaseCard title="Yetkili giriş/çıkış cihazları">
                    <div class="flex flex-col gap-3">
                        <p class="text-xs text-muted">
                            Kiosk/tablet gibi cihazlar oturum açmadan, cihaz token'ı + personel PIN'iyle giriş/çıkış
                            alabilir (NFC/QR okuyucular ileride aynı yapıyı kullanır).
                        </p>
                        <div class="flex flex-wrap items-end gap-2">
                            <BaseInput v-model="deviceName" placeholder="Cihaz adı (ör. Mutfak Tableti)" size="sm" class="w-52" />
                            <BaseSelect v-model="deviceBranch" :options="branchOptions" size="sm" class="w-44" />
                            <BaseButton size="sm" :loading="deviceSaving" @click="addDevice">Cihaz Ekle</BaseButton>
                        </div>
                        <EmptyState v-if="devices.length === 0" title="Kayıtlı cihaz yok" />
                        <ul v-else class="flex flex-col gap-1">
                            <li
                                v-for="row in devices"
                                :key="row.id"
                                class="flex items-center justify-between gap-2 rounded-md border border-default px-3 py-2 text-sm"
                            >
                                <div>
                                    <p class="font-medium text-body">{{ row.name }}</p>
                                    <p class="text-xs text-muted">
                                        {{ row.branch?.name ?? 'Şubeden bağımsız' }}
                                        <template v-if="row.last_seen_at"> · Son kullanım: {{ fmtDateTime(row.last_seen_at) }}</template>
                                    </p>
                                </div>
                                <div class="flex items-center gap-2">
                                    <BaseBadge :variant="row.is_active ? 'success' : 'neutral'" no-icon>
                                        {{ row.is_active ? 'Aktif' : 'Pasif' }}
                                    </BaseBadge>
                                    <BaseButton size="sm" variant="ghost" @click="removeDevice(row)">Sil</BaseButton>
                                </div>
                            </li>
                        </ul>
                    </div>
                </BaseCard>

                <!-- Min. personel kuralları -->
                <BaseCard title="Minimum personel kuralları">
                    <div class="flex flex-col gap-3">
                        <p class="text-xs text-muted">
                            Takvimde, kuralın altında kalan günler için uyarı gösterilir (şube + gün + pozisyon bazında).
                        </p>
                        <div class="flex flex-wrap items-end gap-2">
                            <BaseSelect v-model="ruleForm.branch_id" :options="branchOptions.slice(1)" placeholder="Şube" size="sm" class="w-36" />
                            <BaseSelect v-model="ruleForm.weekday" :options="weekdayOptions" size="sm" class="w-28" />
                            <BaseInput v-model="ruleForm.position" placeholder="Pozisyon (ops.)" size="sm" class="w-36" />
                            <BaseInput v-model="ruleForm.min_count" type="number" inputmode="numeric" size="sm" class="w-20" />
                            <BaseButton size="sm" :loading="ruleSaving" @click="addRule">Ekle</BaseButton>
                        </div>
                        <EmptyState v-if="rules.length === 0" title="Kural yok" />
                        <ul v-else class="flex flex-col gap-1">
                            <li
                                v-for="row in rules"
                                :key="row.id"
                                class="flex items-center justify-between gap-2 rounded-md border border-default px-3 py-2 text-sm"
                            >
                                <span class="text-body">
                                    {{ row.branch?.name ?? '—' }} ·
                                    {{ row.weekday === null ? 'Her gün' : WEEKDAY_LABELS[row.weekday] }}
                                    <template v-if="row.position"> · {{ row.position }}</template>
                                    → en az <strong>{{ row.min_count }}</strong> kişi
                                </span>
                                <BaseButton size="sm" variant="ghost" @click="removeRule(row)">Sil</BaseButton>
                            </li>
                        </ul>
                    </div>
                </BaseCard>
            </div>
        </div>

        <!-- Token gösterimi (yalnız bir kez) -->
        <BaseModal :open="tokenModal" title="Cihaz Token'ı" size="sm" :dismissable="false" @close="tokenModal = false">
            <div class="flex flex-col gap-3 text-sm">
                <p class="text-muted">
                    Bu token yalnız <strong>bir kez</strong> gösterilir; cihaza kaydedin. Kaybolursa cihazı silip
                    yeniden ekleyin.
                </p>
                <code class="rounded-md bg-inset p-3 font-mono text-xs break-all text-body">{{ newToken }}</code>
                <p class="text-xs text-subtle">
                    Cihaz, isteklerini <code>X-Device-Token</code> başlığıyla <code>/api/v1/shifts/device-clock</code>
                    ucuna gönderir.
                </p>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="copyToken">Kopyala</BaseButton>
                <BaseButton @click="tokenModal = false; newToken = ''">Kaydettim, kapat</BaseButton>
            </template>
        </BaseModal>
    </ShiftsShell>
</template>
