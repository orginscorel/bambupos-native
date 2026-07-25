<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { formatDateTime } from '@/lib/format';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import InventoryNav from './components/InventoryNav.vue';
import {
    fetchItems, fetchWarehouses, metaFromProps,
    type CountData, type ItemRow, type WarehouseRow,
} from './inventory';

/**
 * SAYIM (§17): KÖR SAYIM — sayan kişi beklenen miktarı GÖRMEZ; miktarlar
 * gönderilince beklenen anlık stok snapshot'lanır ve fark çıkar. Onay
 * (stock.adjust) farkları count_adjust olarak deftere işler.
 */
const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

const counts = ref<CountData[]>([]);
const warehouses = ref<WarehouseRow[]>([]);
const items = ref<ItemRow[]>([]);
const loading = ref(true);
const busy = ref(false);

const active = ref<CountData | null>(null);
const countedInput = ref<Record<number, string>>({});

async function load(): Promise<void> {
    loading.value = true;
    try {
        [warehouses.value, items.value] = await Promise.all([fetchWarehouses(), fetchItems()]);
        counts.value = (await api<{ counts: CountData[] }>('/api/v1/inventory/counts')).counts;
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/* ---- Yeni sayım ---- */
const newOpen = ref(false);
const newForm = ref({ warehouse_id: '', note: '' });

async function createCount(): Promise<void> {
    if (busy.value) return;
    busy.value = true;
    try {
        const res = await api<{ count: CountData }>('/api/v1/inventory/counts', {
            method: 'POST',
            body: { warehouse_id: Number(newForm.value.warehouse_id), note: newForm.value.note || null },
        });
        newOpen.value = false;
        success('Sayım açıldı', 'Kör sayım: beklenen miktarlar gönderene kadar gizli.');
        await load();
        await openCount(res.count.id);
    } catch (e) {
        danger('Açılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}

async function openCount(id: number): Promise<void> {
    try {
        const res = await api<{ count: CountData }>(`/api/v1/inventory/counts/${id}`);
        active.value = res.count;
        countedInput.value = {};
        for (const line of res.count.lines ?? []) {
            if (line.counted_qty !== null) countedInput.value[line.item_id] = line.counted_qty;
        }
    } catch (e) {
        danger('Açılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    }
}

/** Depodaki aktif kalemler (sayılacak liste) — beklenen miktar GÖSTERİLMEZ. */
const countableItems = computed(() => {
    if (!active.value) return [];
    return items.value.filter((i) => i.is_active);
});

async function saveLines(): Promise<void> {
    if (!active.value || busy.value) return;
    busy.value = true;
    try {
        const lines = Object.entries(countedInput.value)
            .filter(([, v]) => v !== '')
            .map(([itemId, v]) => ({ item_id: Number(itemId), counted_qty: v }));

        if (!lines.length) {
            danger('Satır yok', 'En az bir kalem için sayım girin.');
            return;
        }

        await api(`/api/v1/inventory/counts/${active.value.id}/lines`, { method: 'PUT', body: { lines } });
        success('Sayım kaydedildi', `${lines.length} satır.`);
        await openCount(active.value.id);
    } catch (e) {
        danger('Kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}

async function act(action: 'submit' | 'approve' | 'cancel'): Promise<void> {
    if (!active.value || busy.value) return;
    busy.value = true;
    try {
        await api(`/api/v1/inventory/counts/${active.value.id}/${action}`, { method: 'POST' });
        success(
            action === 'submit' ? 'Sayım gönderildi' : action === 'approve' ? 'Sayım onaylandı' : 'Sayım iptal edildi',
            action === 'submit' ? 'Farklar aşağıda; onayla deftere işlensin.' : action === 'approve' ? 'Farklar deftere count_adjust olarak işlendi.' : '',
        );
        await openCount(active.value.id);
        counts.value = (await api<{ counts: CountData[] }>('/api/v1/inventory/counts')).counts;
    } catch (e) {
        danger('İşlenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        busy.value = false;
    }
}

const statusLabel = (s: string): string =>
    s === 'draft' ? 'Taslak' : s === 'submitted' ? 'Gönderildi' : s === 'approved' ? 'Onaylandı' : 'İptal';
const statusVariant = (s: string): 'neutral' | 'info' | 'success' | 'danger' =>
    s === 'draft' ? 'neutral' : s === 'submitted' ? 'info' : s === 'approved' ? 'success' : 'danger';

const warehouseOptions = computed(() => warehouses.value.filter((w) => w.is_active).map((w) => ({ value: String(w.id), label: w.name })));
</script>

<template>
    <Head title="Stok Sayımı" />
    <PanelShell title="Stok">
        <InventoryNav active="counts" />

        <div class="grid gap-4 lg:grid-cols-[320px_1fr]">
            <!-- Sol: sayım listesi -->
            <div class="flex flex-col gap-3">
                <BaseButton block @click="newOpen = true"><AppIcon name="plus" :size="14" /> Yeni sayım</BaseButton>
                <BaseCard flush>
                    <div class="max-h-[65vh] overflow-y-auto">
                        <button
                            v-for="c in counts"
                            :key="c.id"
                            type="button"
                            class="flex w-full flex-col gap-0.5 border-b border-default px-3 py-2 text-left text-sm hover:bg-surface-alt"
                            :class="active?.id === c.id ? 'bg-surface-alt' : ''"
                            @click="openCount(c.id)"
                        >
                            <span class="flex items-center justify-between">
                                <span class="font-medium">#{{ c.id }} · {{ c.warehouse_name }}</span>
                                <BaseBadge :variant="statusVariant(c.status)" no-icon>{{ statusLabel(c.status) }}</BaseBadge>
                            </span>
                            <span class="text-xs text-subtle">{{ c.created_at ? formatDateTime(c.created_at) : '' }} · {{ c.line_count ?? 0 }} satır</span>
                        </button>
                        <EmptyState v-if="!counts.length && !loading" title="Sayım yok" description="Kör sayım başlatın: personel beklenen stoğu görmeden sayar." />
                    </div>
                </BaseCard>
            </div>

            <!-- Sağ: aktif sayım -->
            <BaseCard v-if="!active" flush>
                <EmptyState icon="check-circle" title="Sayım seçin" description="Soldan bir sayım seçin ya da yeni sayım başlatın." />
            </BaseCard>

            <BaseCard v-else :title="`Sayım #${active.id} — ${active.warehouse_name ?? ''}`">
                <div class="flex flex-col gap-3">
                    <div class="flex flex-wrap items-center gap-2 text-sm">
                        <BaseBadge :variant="statusVariant(active.status)">{{ statusLabel(active.status) }}</BaseBadge>
                        <BaseBadge v-if="active.is_blind && active.status === 'draft'" variant="info">Kör sayım — beklenen gizli</BaseBadge>
                        <span v-if="active.note" class="text-muted">{{ active.note }}</span>
                    </div>

                    <!-- TASLAK: giriş -->
                    <template v-if="active.status === 'draft'">
                        <div class="w-full overflow-x-auto overscroll-x-contain">
                            <table class="w-full min-w-max border-collapse text-sm" aria-label="Sayım girişi">
                                <thead>
                                    <tr class="border-b border-default bg-surface-alt text-xs font-semibold tracking-wide text-muted uppercase">
                                        <th class="px-3 py-2 text-left">Kalem</th>
                                        <th class="px-3 py-2 text-left">Birim</th>
                                        <th class="w-40 px-3 py-2 text-right">Sayılan</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <tr v-for="i in countableItems" :key="i.id" class="border-b border-default">
                                        <td class="px-3 py-1.5">{{ i.name }}</td>
                                        <td class="px-3 py-1.5 text-muted">{{ i.base_unit }}</td>
                                        <td class="px-3 py-1.5">
                                            <BaseInput v-model="countedInput[i.id]" size="sm" inputmode="decimal" placeholder="—" />
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>
                        <div class="flex flex-wrap justify-end gap-2 border-t border-default pt-3">
                            <BaseButton variant="secondary" :loading="busy" @click="act('cancel')">İptal et</BaseButton>
                            <BaseButton variant="secondary" :loading="busy" @click="saveLines">Kaydet</BaseButton>
                            <BaseButton :loading="busy" @click="saveLines().then(() => act('submit'))">Kaydet ve gönder</BaseButton>
                        </div>
                    </template>

                    <!-- GÖNDERİLDİ / ONAYLANDI: fark dökümü -->
                    <template v-else>
                        <div class="w-full overflow-x-auto overscroll-x-contain">
                            <table class="w-full min-w-max border-collapse text-sm" aria-label="Sayım farkları">
                                <thead>
                                    <tr class="border-b border-default bg-surface-alt text-xs font-semibold tracking-wide text-muted uppercase">
                                        <th class="px-3 py-2 text-left">Kalem</th>
                                        <th class="px-3 py-2 text-right">Beklenen</th>
                                        <th class="px-3 py-2 text-right">Sayılan</th>
                                        <th class="px-3 py-2 text-right">Fark</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <tr v-for="l in active.lines" :key="l.item_id" class="border-b border-default" :class="(l.diff_milli ?? 0) !== 0 ? 'bg-warning-soft/30' : ''">
                                        <td class="px-3 py-2">{{ l.item_name }}</td>
                                        <td class="px-3 py-2 text-right tabular-nums text-muted">{{ l.expected_qty ?? '—' }} {{ l.unit }}</td>
                                        <td class="px-3 py-2 text-right tabular-nums">{{ l.counted_qty ?? '—' }} {{ l.unit }}</td>
                                        <td class="px-3 py-2 text-right font-medium tabular-nums" :class="(l.diff_milli ?? 0) < 0 ? 'text-danger' : (l.diff_milli ?? 0) > 0 ? 'text-success' : 'text-muted'">
                                            {{ (l.diff_milli ?? 0) > 0 ? '+' : '' }}{{ l.diff_qty ?? '0' }}
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>
                        <div v-if="active.status === 'submitted'" class="flex flex-wrap justify-end gap-2 border-t border-default pt-3">
                            <BaseButton variant="secondary" :loading="busy" @click="act('cancel')">İptal et</BaseButton>
                            <BaseButton v-if="meta.canAdjust" :loading="busy" @click="act('approve')">Onayla — farkları deftere işle</BaseButton>
                            <span v-else class="self-center text-xs text-subtle">Onay stok düzeltme yetkisi ister.</span>
                        </div>
                    </template>
                </div>
            </BaseCard>
        </div>

        <!-- Yeni sayım -->
        <BaseModal :open="newOpen" title="Yeni sayım" @close="newOpen = false">
            <form class="flex flex-col gap-3" @submit.prevent="createCount">
                <FormField label="Depo" required>
                    <BaseSelect v-model="newForm.warehouse_id" :options="warehouseOptions" placeholder="Seçin…" />
                </FormField>
                <FormField label="Not"><BaseInput v-model="newForm.note" placeholder="ör. Ay sonu sayımı" /></FormField>
                <p class="rounded-md bg-inset px-3 py-2 text-xs text-muted">
                    Kör sayım: sayan kişi sistemdeki beklenen miktarı görmez; gönderdikten sonra fark ortaya çıkar.
                </p>
                <div class="flex justify-end gap-2 pt-1">
                    <BaseButton variant="secondary" @click="newOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="busy" :disabled="!newForm.warehouse_id">Başlat</BaseButton>
                </div>
            </form>
        </BaseModal>
    </PanelShell>
</template>
