<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import InventoryNav from './components/InventoryNav.vue';
import { fetchSuppliers, metaFromProps, money, type SupplierRow } from './inventory';

/** TEDARİKÇİLER (§17.6): kart yönetimi + kalem fiyat geçmişi. */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

const suppliers = ref<SupplierRow[]>([]);
const loading = ref(true);

async function load(): Promise<void> {
    loading.value = true;
    try {
        suppliers.value = await fetchSuppliers();
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/* ---- Kart formu ---- */
const formOpen = ref(false);
const busy = ref(false);
const editing = ref<SupplierRow | null>(null);
const formErrors = ref<Record<string, string[]>>({});
const blank = () => ({ name: '', contact_name: '', phone: '', email: '', tax_no: '', address: '', payment_term_days: '0', note: '', is_active: true });
const form = ref(blank());

function openCreate(): void {
    editing.value = null;
    form.value = blank();
    formErrors.value = {};
    formOpen.value = true;
}

function openEdit(s: SupplierRow): void {
    editing.value = s;
    form.value = {
        name: s.name, contact_name: s.contact_name ?? '', phone: s.phone ?? '', email: s.email ?? '',
        tax_no: s.tax_no ?? '', address: s.address ?? '', payment_term_days: String(s.payment_term_days),
        note: s.note ?? '', is_active: s.is_active,
    };
    formErrors.value = {};
    formOpen.value = true;
}

async function submit(): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    formErrors.value = {};
    try {
        const body = { ...form.value, payment_term_days: Number(form.value.payment_term_days) || 0 };
        if (editing.value) {
            await api(`/api/v1/inventory/suppliers/${editing.value.id}`, { method: 'PUT', body });
        } else {
            await api('/api/v1/inventory/suppliers', { method: 'POST', body });
        }
        success('Kaydedildi', '');
        formOpen.value = false;
        await load();
    } catch (e) {
        if (e instanceof ApiError) {
            formErrors.value = e.errors;
            danger('Kaydedilemedi', e.displayMessage);
        }
    } finally {
        busy.value = false;
    }
}

/* ---- Fiyat geçmişi ---- */
const pricesOpen = ref(false);
const pricesFor = ref<SupplierRow | null>(null);
const prices = ref<{ item_name: string | null; unit: string | null; unit_price_minor: number; recorded_at: string | null }[]>([]);

async function openPrices(s: SupplierRow): Promise<void> {
    pricesFor.value = s;
    prices.value = [];
    pricesOpen.value = true;
    try {
        prices.value = (await api<{ prices: typeof prices.value }>(`/api/v1/inventory/suppliers/${s.id}/prices`)).prices;
    } catch {
        /* sessiz */
    }
}

const err = (f: string): string => formErrors.value[f]?.[0] ?? '';
</script>

<template>
    <Head title="Tedarikçiler" />
    <PanelShell title="Stok" flush canvas>
        <div class="shrink-0 border-b border-default bg-raised px-4 py-2.5 sm:px-6">
            <InventoryNav active="suppliers" />
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">
        <div class="mb-3 flex items-center justify-between">
            <p class="text-sm text-muted">Mal kabulünde alış fiyatı otomatik geçmişe yazılır.</p>
            <BaseButton v-if="meta.canAdjust" size="sm" @click="openCreate">
                <AppIcon name="plus" :size="14" /> Tedarikçi ekle
            </BaseButton>
        </div>

        <BaseCard flush>
            <div class="w-full overflow-x-auto overscroll-x-contain">
                <table class="w-full min-w-max border-collapse text-sm" aria-label="Tedarikçiler">
                    <thead>
                        <tr class="border-b border-default bg-surface-alt text-xs font-semibold tracking-wide text-muted uppercase">
                            <th class="px-4 py-2.5 text-left">Ad</th>
                            <th class="px-4 py-2.5 text-left">İletişim</th>
                            <th class="px-4 py-2.5 text-left">Vergi no</th>
                            <th class="px-4 py-2.5 text-right">Vade</th>
                            <th class="px-4 py-2.5 text-left">Durum</th>
                            <th class="px-4 py-2.5 text-right">İşlem</th>
                        </tr>
                    </thead>
                    <tbody v-if="!loading && suppliers.length">
                        <tr v-for="s in suppliers" :key="s.id" class="border-b border-default">
                            <td class="px-4 py-2 font-medium">{{ s.name }}</td>
                            <td class="px-4 py-2 text-muted">
                                <span v-if="s.contact_name">{{ s.contact_name }}</span>
                                <span v-if="s.phone" class="text-subtle"> · {{ s.phone }}</span>
                            </td>
                            <td class="px-4 py-2 text-muted">{{ s.tax_no ?? '—' }}</td>
                            <td class="px-4 py-2 text-right tabular-nums text-muted">{{ s.payment_term_days }} gün</td>
                            <td class="px-4 py-2">
                                <BaseBadge :variant="s.is_active ? 'success' : 'neutral'" no-icon>{{ s.is_active ? 'Aktif' : 'Pasif' }}</BaseBadge>
                            </td>
                            <td class="px-4 py-2 text-right">
                                <span class="flex justify-end gap-1.5">
                                    <BaseButton size="sm" variant="ghost" @click="openPrices(s)">Fiyatlar</BaseButton>
                                    <BaseButton v-if="meta.canAdjust" size="sm" variant="secondary" @click="openEdit(s)">Düzenle</BaseButton>
                                </span>
                            </td>
                        </tr>
                    </tbody>
                </table>
                <div v-if="loading" class="p-6 text-center text-sm text-muted">Yükleniyor…</div>
                <EmptyState v-else-if="!suppliers.length" title="Tedarikçi yok" description="Satın alma ve mal kabul için önce tedarikçi ekleyin." />
            </div>
        </BaseCard>

        <!-- Kart formu -->
        <BaseModal :open="formOpen" :title="editing ? 'Tedarikçiyi düzenle' : 'Yeni tedarikçi'" @close="formOpen = false">
            <form class="flex flex-col gap-3" @submit.prevent="submit">
                <FormField label="Ad" required :error="err('name')"><BaseInput v-model="form.name" /></FormField>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="İlgili kişi" :error="err('contact_name')"><BaseInput v-model="form.contact_name" /></FormField>
                    <FormField label="Telefon" :error="err('phone')"><BaseInput v-model="form.phone" /></FormField>
                </div>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="E-posta" :error="err('email')"><BaseInput v-model="form.email" type="email" /></FormField>
                    <FormField label="Vergi no" :error="err('tax_no')"><BaseInput v-model="form.tax_no" /></FormField>
                </div>
                <div class="grid grid-cols-2 gap-3">
                    <FormField label="Vade (gün)" :error="err('payment_term_days')"><BaseInput v-model="form.payment_term_days" inputmode="numeric" /></FormField>
                    <FormField label="Adres" :error="err('address')"><BaseInput v-model="form.address" /></FormField>
                </div>
                <FormField label="Not" :error="err('note')"><BaseInput v-model="form.note" /></FormField>
                <label class="flex items-center gap-2 text-sm"><input v-model="form.is_active" type="checkbox" class="rounded" /> Aktif</label>
                <div class="flex justify-end gap-2 pt-1">
                    <BaseButton variant="secondary" @click="formOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="busy">Kaydet</BaseButton>
                </div>
            </form>
        </BaseModal>

        <!-- Fiyat geçmişi -->
        <BaseModal :open="pricesOpen" :title="`${pricesFor?.name ?? ''} — fiyat geçmişi`" @close="pricesOpen = false">
            <div v-if="prices.length" class="max-h-96 overflow-y-auto">
                <table class="w-full text-sm">
                    <thead>
                        <tr class="border-b border-default text-xs text-muted uppercase">
                            <th class="py-2 text-left">Kalem</th>
                            <th class="py-2 text-right">Birim fiyat</th>
                            <th class="py-2 text-right">Tarih</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr v-for="(p, i) in prices" :key="i" class="border-b border-default">
                            <td class="py-1.5">{{ p.item_name }} <span class="text-subtle">/ {{ p.unit }}</span></td>
                            <td class="py-1.5 text-right tabular-nums">{{ money(p.unit_price_minor) }}</td>
                            <td class="py-1.5 text-right text-muted">{{ p.recorded_at ? new Date(p.recorded_at).toLocaleDateString('tr-TR') : '—' }}</td>
                        </tr>
                    </tbody>
                </table>
            </div>
            <p v-else class="py-6 text-center text-sm text-muted">Bu tedarikçiden henüz mal kabul yapılmadı.</p>
        </BaseModal>
        </div>
        </div>
    </PanelShell>
</template>
