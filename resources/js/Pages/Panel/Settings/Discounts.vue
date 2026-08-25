<script setup lang="ts">
/**
 * HAZIR İNDİRİM TANIMLARI (ayarlar).
 *
 * Tekrar eden indirimler (şehit/gazi yakını, kamu personeli, öğrenci…) burada
 * bir kez tanımlanır; kasa ve sepet tek dokunuşla uygular. Gerekçe tanımın
 * adından geldiği için raporlarda GRUPLANABİLİR — serbest metinle bu mümkün
 * değildi ("kamu", "kamu personeli", "memur" ayrı ayrı görünüyordu).
 */
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
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
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import type { DiscountPresetRow } from '@/Components/panel/OrderDiscountDialog.vue';

const { success, danger } = useToast();

/** Kuruş → "1.234,56". */
function money(minor: number): string {
    return (minor / 100).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

const presets = ref<DiscountPresetRow[]>([]);
const loading = ref(true);
const busy = ref(false);

async function load(): Promise<void> {
    loading.value = true;
    try {
        // all=1 → pasif tanımlar da listelenir (yönetim ekranı).
        const res = await api<{ presets: DiscountPresetRow[] }>('/api/v1/discount-presets?all=1');
        presets.value = res.presets;
    } catch (e) {
        danger('Tanımlar yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/* ---- Form (ekle / düzenle) ---- */
const modalOpen = ref(false);
const editing = ref<DiscountPresetRow | null>(null);
const fName = ref('');
const fType = ref<'percent' | 'amount'>('percent');
const fValue = ref('');
const fNote = ref('');
const fRequiresApproval = ref(false);
const fActive = ref(true);

const title = computed(() => (editing.value ? 'İndirim tanımını düzenle' : 'Yeni indirim tanımı'));

function openCreate(): void {
    editing.value = null;
    fName.value = '';
    fType.value = 'percent';
    fValue.value = '';
    fNote.value = '';
    fRequiresApproval.value = false;
    fActive.value = true;
    modalOpen.value = true;
}

function openEdit(p: DiscountPresetRow): void {
    editing.value = p;
    fName.value = p.name;
    fType.value = p.type;
    fValue.value = p.type === 'percent'
        ? String(p.value_percent ?? '').replace('.', ',')
        : ((p.value_minor ?? 0) / 100).toLocaleString('tr-TR', { minimumFractionDigits: 2 });
    fNote.value = p.note ?? '';
    fRequiresApproval.value = p.requires_approval;
    fActive.value = p.is_active;
    modalOpen.value = true;
}

/** Yüzde → sayı, sabit tutar → kuruş. */
function parsedValue(): number | null {
    const raw = fValue.value.replace(/\s/g, '').replace(/\./g, '').replace(',', '.');
    const n = Number(raw);
    if (!Number.isFinite(n) || n <= 0) return null;
    return fType.value === 'percent' ? n : Math.round(n * 100);
}

async function save(): Promise<void> {
    if (busy.value) return;
    const value = parsedValue();
    if (fName.value.trim().length < 2) {
        danger('Ad gerekli', 'En az 2 karakterlik bir ad yazın.');
        return;
    }
    if (value === null || (fType.value === 'percent' && value > 100)) {
        danger('Değer geçersiz', fType.value === 'percent' ? 'Yüzde 0 ile 100 arasında olmalı.' : 'Sıfırdan büyük bir tutar girin.');
        return;
    }

    busy.value = true;
    try {
        const body = {
            name: fName.value.trim(),
            type: fType.value,
            value_percent: fType.value === 'percent' ? value : null,
            value_minor: fType.value === 'amount' ? value : null,
            note: fNote.value.trim() || null,
            requires_approval: fRequiresApproval.value,
            is_active: fActive.value,
        };
        if (editing.value) {
            await api(`/api/v1/discount-presets/${editing.value.id}`, { method: 'PUT', body });
            success('Tanım güncellendi', body.name);
        } else {
            await api('/api/v1/discount-presets', { method: 'POST', body });
            success('Tanım eklendi', body.name);
        }
        modalOpen.value = false;
        await load();
    } catch (e) {
        danger('Kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        busy.value = false;
    }
}

/* ---- Aylık kullanım dökümü ---- */
interface MonthStat {
    month: string;
    used_count: number;
    used_minor: number;
}
const statsPreset = ref<DiscountPresetRow | null>(null);
const statsMonths = ref<MonthStat[]>([]);
const statsBusy = ref<number | null>(null);

async function openStats(p: DiscountPresetRow): Promise<void> {
    if (statsBusy.value !== null) return;
    statsBusy.value = p.id;
    try {
        const res = await api<{ months: MonthStat[] }>(`/api/v1/discount-presets/${p.id}/stats`);
        statsMonths.value = res.months;
        statsPreset.value = p;
    } catch (e) {
        danger('Döküm alınamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        statsBusy.value = null;
    }
}

/** "2026-08" → "Ağustos 2026". */
function monthLabel(ym: string): string {
    const [y, m] = ym.split('-').map(Number);
    return new Date(y, (m ?? 1) - 1, 1).toLocaleDateString('tr-TR', { month: 'long', year: 'numeric' });
}

/** Aylık çubuk genişliği — en yüksek aya oranla. */
function monthBar(minor: number): string {
    const max = Math.max(...statsMonths.value.map((x) => x.used_minor), 1);
    return `${Math.max(2, Math.round((minor / max) * 100))}%`;
}

/* ---- Silme (onaylı) ---- */
const deleteTarget = ref<DiscountPresetRow | null>(null);

async function confirmDelete(): Promise<void> {
    if (!deleteTarget.value || busy.value) return;
    busy.value = true;
    try {
        await api(`/api/v1/discount-presets/${deleteTarget.value.id}`, { method: 'DELETE' });
        success('Tanım silindi', deleteTarget.value.name);
        deleteTarget.value = null;
        await load();
    } catch (e) {
        danger('Silinemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        busy.value = false;
    }
}
</script>

<template>
    <Head title="İndirim tanımları" />
    <PanelShell title="İndirim tanımları" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1080px] flex-col gap-3">

        <BaseCard>
            <template #header>
                <div class="flex w-full flex-wrap items-center justify-between gap-2">
                    <div class="min-w-0">
                        <h2 class="text-sm font-semibold text-body">Hazır indirimler</h2>
                        <p class="text-xs text-muted">
                            Kasa ve adisyon ekranında tek dokunuşla uygulanır; gerekçe tanımın adı olur.
                        </p>
                    </div>
                    <BaseButton @click="openCreate">
                        <AppIcon name="plus" :size="16" /> Yeni tanım
                    </BaseButton>
                </div>
            </template>

            <p v-if="loading" class="py-8 text-center text-sm text-muted">Yükleniyor…</p>
            <EmptyState
                v-else-if="presets.length === 0"
                title="Tanımlı indirim yok"
                description="Örnek: “Şehit/Gazi yakını %20”, “Kamu personeli %10”, “Öğrenci %15”."
                icon="tag"
            />
            <ul v-else class="divide-y divide-default">
                <li v-for="p in presets" :key="p.id" class="flex flex-wrap items-center gap-3 py-3">
                    <span class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-primary-soft text-primary">
                        <AppIcon name="tag" :size="18" />
                    </span>
                    <div class="min-w-0 grow">
                        <p class="flex flex-wrap items-center gap-2">
                            <span class="truncate font-semibold text-body">{{ p.name }}</span>
                            <span class="rounded-full bg-primary-soft px-2 py-0.5 text-xs font-bold text-primary">{{ p.value_label }}</span>
                            <BaseBadge v-if="!p.is_active" variant="neutral" no-icon>Pasif</BaseBadge>
                            <BaseBadge v-if="p.requires_approval" variant="warning" no-icon>
                                <AppIcon name="alert-triangle" :size="11" /> Yönetici onayı ister
                            </BaseBadge>
                        </p>
                        <p v-if="p.note" class="truncate text-xs text-muted">{{ p.note }}</p>
                    </div>
                    <!-- KULLANIM: kaç kez uygulandı ve ne kadar indirim yaptı.
                         Bir tanımın işe yarayıp yaramadığı ancak buradan görülür;
                         hiç kullanılmayan tanım menüyü şişirir, çok kullanılan
                         tanım ciroyu ölçülebilir biçimde etkiler. -->
                    <div class="flex shrink-0 items-center gap-3 text-center">
                        <div class="min-w-16">
                            <p class="text-[10.5px] font-semibold uppercase tracking-wide text-subtle">Bu ay</p>
                            <p class="text-sm font-bold tabular-nums text-body">{{ p.month_count ?? 0 }}</p>
                            <p class="text-[11px] tabular-nums text-muted">{{ money(p.month_minor ?? 0) }} ₺</p>
                        </div>
                        <div class="min-w-16 border-s border-default ps-3">
                            <p class="text-[10.5px] font-semibold uppercase tracking-wide text-subtle">Toplam</p>
                            <p class="text-sm font-bold tabular-nums text-body">{{ p.used_count ?? 0 }}</p>
                            <p class="text-[11px] tabular-nums text-muted">{{ money(p.used_minor ?? 0) }} ₺</p>
                        </div>
                    </div>

                    <div class="flex shrink-0 items-center gap-1.5">
                        <BaseButton variant="ghost" size="sm" :loading="statsBusy === p.id" @click="openStats(p)">
                            <AppIcon name="chart" :size="14" /> Aylık
                        </BaseButton>
                        <BaseButton variant="secondary" size="sm" @click="openEdit(p)">
                            <AppIcon name="pencil" :size="14" /> Düzenle
                        </BaseButton>
                        <BaseButton variant="ghost" size="sm" class="!text-danger" @click="deleteTarget = p">
                            <AppIcon name="trash" :size="14" /> Sil
                        </BaseButton>
                    </div>
                </li>
            </ul>
        </BaseCard>
        </div>
        </div>
    </PanelShell>

    <!-- Ekle / düzenle -->
    <BaseModal :open="modalOpen" :title="title" size="md" @close="modalOpen = false">
        <div class="flex flex-col gap-3">
            <FormField label="Tanım adı" hint="Fişte ve raporda bu ad görünür" required>
                <BaseInput v-model="fName" placeholder="ör. Şehit/Gazi yakını" />
            </FormField>
            <div class="grid gap-3 sm:grid-cols-2">
                <FormField label="Tür">
                    <BaseSelect
                        :model-value="fType"
                        :options="[
                            { value: 'percent', label: 'Yüzde (%)' },
                            { value: 'amount', label: 'Sabit tutar (₺)' },
                        ]"
                        @update:model-value="(v: string) => (fType = v as 'percent' | 'amount')"
                    />
                </FormField>
                <FormField :label="fType === 'percent' ? 'Yüzde' : 'Tutar (₺)'" required>
                    <BaseInput v-model="fValue" inputmode="decimal" :placeholder="fType === 'percent' ? 'ör. 20' : 'ör. 25,00'" />
                </FormField>
            </div>
            <FormField label="Açıklama" hint="Personele kısa hatırlatma (isteğe bağlı)">
                <BaseInput v-model="fNote" placeholder="ör. kimlik ibrazı ile" />
            </FormField>

            <label class="flex items-start gap-3 rounded-lg border border-default p-3">
                <BaseSwitch v-model="fRequiresApproval" />
                <span class="min-w-0 text-sm">
                    <span class="font-medium text-body">Yönetici onayı (PIN) istesin</span>
                    <span class="block text-xs text-muted">
                        Kapalıyken tanım önceden onaylı sayılır ve %10 eşiği aranmaz — tanımı zaten
                        indirim yetkilisi yapmıştır. Açıkken her uygulamada PIN sorulur.
                    </span>
                </span>
            </label>

            <label class="flex items-center gap-3 rounded-lg border border-default p-3">
                <BaseSwitch v-model="fActive" />
                <span class="text-sm font-medium text-body">Aktif (kasa ve sepette görünür)</span>
            </label>
        </div>
        <template #footer>
            <BaseButton variant="secondary" @click="modalOpen = false">Vazgeç</BaseButton>
            <BaseButton :loading="busy" @click="save">Kaydet</BaseButton>
        </template>
    </BaseModal>

    <!-- Aylık kullanım dökümü -->
    <BaseModal :open="statsPreset !== null" :title="`${statsPreset?.name ?? ''} — aylık kullanım`" size="md" @close="statsPreset = null">
        <p v-if="statsMonths.length === 0" class="py-6 text-center text-sm text-muted">
            Bu tanım son 12 ayda hiç kullanılmamış.
        </p>
        <ul v-else class="flex flex-col gap-1.5">
            <li v-for="m in statsMonths" :key="m.month" class="flex items-center gap-3">
                <span class="w-24 shrink-0 text-sm font-medium text-body">{{ monthLabel(m.month) }}</span>
                <span class="h-2 grow overflow-hidden rounded-full bg-inset">
                    <span class="block h-full rounded-full bg-primary" :style="{ width: monthBar(m.used_minor) }" />
                </span>
                <span class="w-14 shrink-0 text-end text-sm font-bold tabular-nums text-body">{{ m.used_count }}×</span>
                <span class="w-24 shrink-0 text-end text-sm font-semibold tabular-nums text-muted">{{ money(m.used_minor) }} ₺</span>
            </li>
        </ul>
        <template #footer>
            <BaseButton variant="secondary" @click="statsPreset = null">Kapat</BaseButton>
        </template>
    </BaseModal>

    <!-- Silme onayı -->
    <BaseModal :open="deleteTarget !== null" title="Tanımı sil" size="sm" @close="deleteTarget = null">
        <p class="text-sm text-muted">
            <span class="font-medium text-body">{{ deleteTarget?.name }}</span> tanımı silinecek.
            Daha önce uygulanmış indirimler etkilenmez (gerekçe metni adisyonda kalır).
        </p>
        <template #footer>
            <BaseButton variant="secondary" @click="deleteTarget = null">Vazgeç</BaseButton>
            <BaseButton variant="danger" :loading="busy" @click="confirmDelete">Sil</BaseButton>
        </template>
    </BaseModal>
</template>
