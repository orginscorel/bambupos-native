<script setup lang="ts">
/**
 * /panel/prim — Prim / Komisyon yönetimi. İki bölüm:
 *
 *  (a) Prim Şemaları — GET /api/v1/commission/schemes; ekle/düzenle/sil
 *      (POST/PUT/DELETE). basis'e göre farklı alanlar: satış yüzdesi
 *      (rate_bps = %×100), sipariş başına (per_order_minor), hedef primi
 *      (target_minor + bonus_minor). Yazma butonları `commission.manage`
 *      iznine bağlıdır (arayüz gizleme; asıl koruma backend).
 *  (b) Prim Raporu — dönem (from/to) seç → GET /api/v1/commission/report;
 *      personel bazında satış / sipariş / çalışma / prim / hedef tablosu +
 *      alt toplam. `commission.view` iznine bağlıdır.
 *
 * Para: *_minor → formatCurrencyMinor (₺). Süre: formatMinutes.
 */
import { computed, onMounted, reactive, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { usePermissions } from '@/composables/usePermissions';
import { useToast } from '@/composables/useToast';
import { formatCurrencyMinor, formatNumber } from '@/lib/format';
import { formatMinutes } from '@/types/portal';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';

type Basis = 'percent_sales' | 'per_order' | 'target_bonus';

interface SchemeDTO {
    id: number;
    name: string;
    basis: Basis;
    rate_bps: number;
    per_order_minor: number;
    target_minor: number;
    bonus_minor: number;
    position: string | null;
    is_active: boolean;
}

interface SchemesResponse {
    schemes: SchemeDTO[];
}

interface ReportRow {
    user: { id: number; name: string; position: string | null };
    sales_minor: number;
    order_count: number;
    worked_min: number;
    commission_minor: number;
    target_minor: number;
    target_met: boolean;
}

interface ReportResponse {
    rows: ReportRow[];
    totals: { sales_minor: number; commission_minor: number };
}

const { can } = usePermissions();
const { success, danger } = useToast();

const canView = computed(() => can('commission.view'));
const canManage = computed(() => can('commission.manage'));

const basisMeta: Record<Basis, { label: string; variant: 'primary' | 'success' | 'info' }> = {
    percent_sales: { label: 'Satış yüzdesi', variant: 'primary' },
    per_order: { label: 'Sipariş başına', variant: 'success' },
    target_bonus: { label: 'Hedef primi', variant: 'info' },
};

const basisOptions = [
    { value: 'percent_sales', label: 'Satış yüzdesi (%)' },
    { value: 'per_order', label: 'Sipariş başına (₺)' },
    { value: 'target_bonus', label: 'Hedef primi (₺)' },
];

/** basis'e göre şema kuralının kısa özeti (liste satırında). */
function schemeSummary(s: SchemeDTO): string {
    if (s.basis === 'percent_sales') return `Satışın %${formatNumber(s.rate_bps / 100)}`;
    if (s.basis === 'per_order') return `Sipariş başına ${formatCurrencyMinor(s.per_order_minor)}`;
    return `Hedef ${formatCurrencyMinor(s.target_minor)} → ${formatCurrencyMinor(s.bonus_minor)} prim`;
}

/* ============================ Prim Şemaları ============================ */
const schemesLoading = ref(true);
const schemes = ref<SchemeDTO[]>([]);

async function loadSchemes(): Promise<void> {
    schemesLoading.value = true;
    try {
        const res = await api<SchemesResponse>('/api/v1/commission/schemes');
        schemes.value = res.schemes ?? [];
    } catch (e) {
        danger('Şemalar yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        schemesLoading.value = false;
    }
}

/* ---- Şema oluştur / düzenle ---- */
const formOpen = ref(false);
const editingId = ref<number | null>(null);
const saving = ref(false);
const form = reactive({
    name: '',
    basis: 'percent_sales' as Basis,
    rate_pct: '', // % (rate_bps = %×100)
    per_order: '', // ₺ (per_order_minor = ₺×100)
    target: '', // ₺
    bonus: '', // ₺
    position: '',
    is_active: true,
});
const formErrors = reactive<Record<string, string>>({});

/** ₺ metnini minor'a çevirir (virgül/nokta toleranslı). */
function toMinor(v: string): number {
    const n = Number(v.replace(',', '.'));
    return Number.isFinite(n) ? Math.round(n * 100) : 0;
}

function resetForm(): void {
    form.name = '';
    form.basis = 'percent_sales';
    form.rate_pct = '';
    form.per_order = '';
    form.target = '';
    form.bonus = '';
    form.position = '';
    form.is_active = true;
    Object.keys(formErrors).forEach((k) => delete formErrors[k]);
}

function openCreate(): void {
    editingId.value = null;
    resetForm();
    formOpen.value = true;
}

function openEdit(s: SchemeDTO): void {
    editingId.value = s.id;
    Object.keys(formErrors).forEach((k) => delete formErrors[k]);
    form.name = s.name;
    form.basis = s.basis;
    form.rate_pct = s.rate_bps ? String(s.rate_bps / 100) : '';
    form.per_order = s.per_order_minor ? String(s.per_order_minor / 100) : '';
    form.target = s.target_minor ? String(s.target_minor / 100) : '';
    form.bonus = s.bonus_minor ? String(s.bonus_minor / 100) : '';
    form.position = s.position ?? '';
    form.is_active = s.is_active;
    formOpen.value = true;
}

async function save(): Promise<void> {
    saving.value = true;
    Object.keys(formErrors).forEach((k) => delete formErrors[k]);
    try {
        const body = {
            name: form.name,
            basis: form.basis,
            rate_bps: form.basis === 'percent_sales' ? Math.round(Number(form.rate_pct.replace(',', '.')) * 100) || 0 : 0,
            per_order_minor: form.basis === 'per_order' ? toMinor(form.per_order) : 0,
            target_minor: form.basis === 'target_bonus' ? toMinor(form.target) : 0,
            bonus_minor: form.basis === 'target_bonus' ? toMinor(form.bonus) : 0,
            position: form.position.trim() || null,
            is_active: form.is_active,
        };
        if (editingId.value === null) {
            await api('/api/v1/commission/schemes', { method: 'POST', body });
            success('Prim şeması eklendi');
        } else {
            await api(`/api/v1/commission/schemes/${editingId.value}`, { method: 'PUT', body });
            success('Prim şeması güncellendi');
        }
        formOpen.value = false;
        await loadSchemes();
    } catch (e) {
        if (e instanceof ApiError) {
            Object.entries(e.errors).forEach(([k, v]) => (formErrors[k] = v[0] ?? ''));
            if (!Object.keys(e.errors).length) danger(e.displayMessage);
        }
    } finally {
        saving.value = false;
    }
}

/* ---- Şema sil ---- */
const deleteTarget = ref<SchemeDTO | null>(null);
const deleting = ref(false);

async function remove(): Promise<void> {
    const s = deleteTarget.value;
    if (!s || deleting.value) return;
    deleting.value = true;
    try {
        await api(`/api/v1/commission/schemes/${s.id}`, { method: 'DELETE' });
        success('Prim şeması silindi');
        deleteTarget.value = null;
        await loadSchemes();
    } catch (e) {
        danger('Silinemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        deleting.value = false;
    }
}

/* ============================ Prim Raporu ============================ */
const reportLoading = ref(false);
const report = ref<ReportResponse | null>(null);

/** YYYY-MM-DD (yerel) — date input değeri. */
function isoDate(d: Date): string {
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

const now = new Date();
const range = reactive({
    from: isoDate(new Date(now.getFullYear(), now.getMonth(), 1)),
    to: isoDate(now),
});

function thisMonth(): void {
    const d = new Date();
    range.from = isoDate(new Date(d.getFullYear(), d.getMonth(), 1));
    range.to = isoDate(d);
    void loadReport();
}

async function loadReport(): Promise<void> {
    if (!canView.value) return;
    reportLoading.value = true;
    try {
        const q = new URLSearchParams({ from: range.from, to: range.to });
        report.value = await api<ReportResponse>(`/api/v1/commission/report?${q.toString()}`);
    } catch (e) {
        danger('Rapor yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
        report.value = null;
    } finally {
        reportLoading.value = false;
    }
}

onMounted(() => {
    if (!canView.value) return;
    void loadSchemes();
    void loadReport();
});
</script>

<template>
    <Head title="Prim / Komisyon" />
    <PanelShell title="Prim / Komisyon" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">

        <!-- Yetki yok -->
        <div v-if="!canView">
            <EmptyState
                icon="alert-circle"
                title="Erişim yok"
                description="Prim ve komisyon bilgilerini görüntülemek için yetkiniz bulunmuyor."
            />
        </div>

        <div v-else class="flex flex-col gap-8">
            <!-- ==================== (a) Prim Şemaları ==================== -->
            <section class="flex flex-col gap-4">
                <div class="flex flex-wrap items-center gap-2">
                    <div>
                        <h2 class="text-base font-semibold text-body">Prim Şemaları</h2>
                        <p class="text-sm text-muted">Personelin primini hesaplayan kuralları tanımlayın.</p>
                    </div>
                    <span class="grow" />
                    <BaseButton v-if="canManage" @click="openCreate">
                        <AppIcon name="plus" :size="16" />
                        Şema ekle
                    </BaseButton>
                </div>

                <!-- Yükleniyor -->
                <div v-if="schemesLoading" class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                    <BaseSkeleton v-for="i in 3" :key="i" class="h-32 w-full rounded-lg" />
                </div>

                <!-- Boş -->
                <EmptyState
                    v-else-if="schemes.length === 0"
                    icon="chart"
                    title="Henüz prim şeması yok"
                    :description="canManage ? 'İlk prim şemasını ekleyerek başlayın.' : 'Tanımlı prim şeması bulunmuyor.'"
                >
                    <template v-if="canManage" #action>
                        <BaseButton @click="openCreate">
                            <AppIcon name="plus" :size="16" />
                            Şema ekle
                        </BaseButton>
                    </template>
                </EmptyState>

                <!-- Şema kartları -->
                <div v-else class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                    <article
                        v-for="s in schemes"
                        :key="s.id"
                        class="flex flex-col gap-2 rounded-lg border border-default bg-raised p-4 shadow-(--shadow-card)"
                        :class="s.is_active ? '' : 'opacity-70'"
                    >
                        <div class="flex items-start justify-between gap-2">
                            <p class="text-sm font-semibold text-body">{{ s.name }}</p>
                            <BaseBadge :variant="basisMeta[s.basis].variant" no-icon class="shrink-0">
                                {{ basisMeta[s.basis].label }}
                            </BaseBadge>
                        </div>

                        <p class="text-sm text-muted">{{ schemeSummary(s) }}</p>

                        <div class="mt-1 flex flex-wrap items-center gap-2 text-xs text-muted">
                            <span class="inline-flex items-center gap-1">
                                <AppIcon name="user" :size="13" />
                                {{ s.position ? s.position : 'Tüm pozisyonlar' }}
                            </span>
                            <BaseBadge :variant="s.is_active ? 'success' : 'neutral'" no-icon>
                                {{ s.is_active ? 'Aktif' : 'Pasif' }}
                            </BaseBadge>
                        </div>

                        <div
                            v-if="canManage"
                            class="mt-2 flex items-center justify-end gap-1 border-t border-default pt-2"
                        >
                            <BaseButton size="sm" variant="ghost" icon-only :label="`${s.name} düzenle`" @click="openEdit(s)">
                                <AppIcon name="pencil" :size="15" />
                            </BaseButton>
                            <BaseButton size="sm" variant="ghost" icon-only :label="`${s.name} sil`" @click="deleteTarget = s">
                                <AppIcon name="trash" :size="15" />
                            </BaseButton>
                        </div>
                    </article>
                </div>
            </section>

            <!-- ==================== (b) Prim Raporu ==================== -->
            <section class="flex flex-col gap-4">
                <div>
                    <h2 class="text-base font-semibold text-body">Prim Raporu</h2>
                    <p class="text-sm text-muted">Seçili dönemde personel bazında satış ve hak edilen prim.</p>
                </div>

                <!-- Dönem seçici -->
                <div class="flex flex-wrap items-end gap-3 rounded-lg border border-default bg-surface-alt p-3">
                    <FormField label="Başlangıç" class="min-w-36 grow sm:grow-0">
                        <BaseInput v-model="range.from" type="date" />
                    </FormField>
                    <FormField label="Bitiş" class="min-w-36 grow sm:grow-0">
                        <BaseInput v-model="range.to" type="date" />
                    </FormField>
                    <div class="flex flex-wrap items-center gap-2">
                        <BaseButton :loading="reportLoading" @click="loadReport">
                            <AppIcon name="chart" :size="16" />
                            Getir
                        </BaseButton>
                        <BaseButton variant="secondary" @click="thisMonth">Bu ay</BaseButton>
                    </div>
                </div>

                <!-- Yükleniyor -->
                <div v-if="reportLoading" class="flex flex-col gap-2">
                    <BaseSkeleton v-for="i in 4" :key="i" class="h-12 w-full rounded-lg" />
                </div>

                <!-- Boş -->
                <EmptyState
                    v-else-if="!report || report.rows.length === 0"
                    icon="inbox"
                    title="Bu dönemde veri yok"
                    description="Farklı bir tarih aralığı seçmeyi deneyin."
                />

                <!-- Tablo -->
                <div v-else class="overflow-x-auto rounded-lg border border-default">
                    <table class="w-full min-w-[42rem] border-collapse text-sm">
                        <thead>
                            <tr class="border-b border-default bg-surface-alt text-left text-xs font-semibold uppercase tracking-wide text-subtle">
                                <th class="px-3 py-2.5">Personel</th>
                                <th class="px-3 py-2.5 text-right">Satış</th>
                                <th class="px-3 py-2.5 text-right">Sipariş</th>
                                <th class="px-3 py-2.5 text-right">Çalışma</th>
                                <th class="px-3 py-2.5 text-right">Prim</th>
                                <th class="px-3 py-2.5 text-right">Hedef / Durum</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="row in report.rows" :key="row.user.id" class="border-b border-default last:border-0">
                                <td class="px-3 py-2.5">
                                    <p class="font-medium text-body">{{ row.user.name }}</p>
                                    <p v-if="row.user.position" class="text-xs text-muted">{{ row.user.position }}</p>
                                </td>
                                <td class="px-3 py-2.5 text-right tabular-nums text-body">{{ formatCurrencyMinor(row.sales_minor) }}</td>
                                <td class="px-3 py-2.5 text-right tabular-nums text-muted">{{ formatNumber(row.order_count) }}</td>
                                <td class="px-3 py-2.5 text-right tabular-nums text-muted">{{ formatMinutes(row.worked_min) }}</td>
                                <td class="px-3 py-2.5 text-right font-semibold tabular-nums text-primary">{{ formatCurrencyMinor(row.commission_minor) }}</td>
                                <td class="px-3 py-2.5 text-right">
                                    <template v-if="row.target_minor > 0">
                                        <span class="tabular-nums text-muted">{{ formatCurrencyMinor(row.target_minor) }}</span>
                                        <BaseBadge :variant="row.target_met ? 'success' : 'neutral'" no-icon class="ml-2">
                                            {{ row.target_met ? 'Ulaştı' : 'Ulaşmadı' }}
                                        </BaseBadge>
                                    </template>
                                    <span v-else class="text-subtle">—</span>
                                </td>
                            </tr>
                        </tbody>
                        <tfoot>
                            <tr class="border-t-2 border-strong bg-surface-alt font-semibold text-body">
                                <td class="px-3 py-2.5">Toplam</td>
                                <td class="px-3 py-2.5 text-right tabular-nums">{{ formatCurrencyMinor(report.totals.sales_minor) }}</td>
                                <td class="px-3 py-2.5"></td>
                                <td class="px-3 py-2.5"></td>
                                <td class="px-3 py-2.5 text-right tabular-nums text-primary">{{ formatCurrencyMinor(report.totals.commission_minor) }}</td>
                                <td class="px-3 py-2.5"></td>
                            </tr>
                        </tfoot>
                    </table>
                </div>
            </section>
        </div>

        <!-- Şema oluştur / düzenle modalı -->
        <BaseModal
            :open="formOpen"
            :title="editingId === null ? 'Prim şeması ekle' : 'Prim şemasını düzenle'"
            @close="formOpen = false"
        >
            <div class="flex flex-col gap-4">
                <FormField label="Şema adı" :error="formErrors.name" required>
                    <BaseInput v-model="form.name" placeholder="Örn. Garson satış primi" />
                </FormField>

                <FormField label="Hesaplama türü" :error="formErrors.basis">
                    <BaseSelect v-model="form.basis" :options="basisOptions" />
                </FormField>

                <!-- Satış yüzdesi -->
                <FormField
                    v-if="form.basis === 'percent_sales'"
                    label="Satış yüzdesi (%)"
                    :error="formErrors.rate_bps"
                    hint="Kapanan satış tutarının bu yüzdesi prim olur."
                    required
                >
                    <BaseInput v-model="form.rate_pct" type="number" placeholder="Örn. 5" />
                </FormField>

                <!-- Sipariş başına -->
                <FormField
                    v-if="form.basis === 'per_order'"
                    label="Sipariş başına (₺)"
                    :error="formErrors.per_order_minor"
                    hint="Her kapanan sipariş için sabit prim tutarı."
                    required
                >
                    <BaseInput v-model="form.per_order" type="number" placeholder="Örn. 10" />
                </FormField>

                <!-- Hedef primi -->
                <div v-if="form.basis === 'target_bonus'" class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <FormField label="Hedef satış (₺)" :error="formErrors.target_minor" required>
                        <BaseInput v-model="form.target" type="number" placeholder="Örn. 20000" />
                    </FormField>
                    <FormField label="Prim (₺)" :error="formErrors.bonus_minor" hint="Hedefe ulaşınca ödenir." required>
                        <BaseInput v-model="form.bonus" type="number" placeholder="Örn. 1000" />
                    </FormField>
                </div>

                <FormField label="Pozisyon" :error="formErrors.position" hint="Boş bırakılırsa tüm pozisyonlara uygulanır.">
                    <BaseInput v-model="form.position" placeholder="Örn. Garson (opsiyonel)" />
                </FormField>

                <!-- Aktiflik -->
                <button
                    type="button"
                    role="switch"
                    :aria-checked="form.is_active"
                    class="flex min-h-11 w-full items-center justify-between gap-2 rounded-md border border-default px-3 py-2 text-left transition-colors duration-(--dur-fast) hover:bg-inset"
                    @click="form.is_active = !form.is_active"
                >
                    <span class="text-sm font-medium text-body">Aktif</span>
                    <span
                        class="relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors duration-(--dur-fast)"
                        :class="form.is_active ? 'bg-primary' : 'bg-inset'"
                    >
                        <span
                            class="inline-block size-5 rounded-full bg-white shadow transition-transform duration-(--dur-fast)"
                            :class="form.is_active ? 'translate-x-[1.375rem]' : 'translate-x-0.5'"
                        />
                    </span>
                </button>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="formOpen = false">Vazgeç</BaseButton>
                <BaseButton :loading="saving" @click="save">{{ editingId === null ? 'Ekle' : 'Kaydet' }}</BaseButton>
            </template>
        </BaseModal>

        <!-- Şema sil onayı -->
        <BaseModal :open="deleteTarget !== null" title="Prim şemasını sil" size="sm" @close="deleteTarget = null">
            <p class="text-sm text-body">
                <strong>{{ deleteTarget?.name }}</strong> şeması kalıcı olarak silinecek. Bu işlem geri alınamaz.
            </p>
            <template #footer>
                <BaseButton variant="secondary" @click="deleteTarget = null">Vazgeç</BaseButton>
                <BaseButton variant="danger" :loading="deleting" @click="remove">Sil</BaseButton>
            </template>
        </BaseModal>
        </div>
        </div>
    </PanelShell>
</template>
