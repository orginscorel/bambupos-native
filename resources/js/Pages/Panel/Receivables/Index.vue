<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import { usePermissions } from '@/composables/usePermissions';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseDrawer from '@/Components/ui/BaseDrawer.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BasePagination from '@/Components/ui/BasePagination.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSwitch from '@/Components/ui/BaseSwitch.vue';
import DataTable, { type TableColumn } from '@/Components/ui/DataTable.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import {
    money,
    type Paginated,
    type ReceivableDebtOrderRow,
    type ReceivableRow,
    type ReceivableTransactionRow,
} from './receivables';

const { success, danger } = useToast();
const { can } = usePermissions();

/* ================= Liste ================= */
const rows = ref<ReceivableRow[]>([]);
const loading = ref(true);
const q = ref('');
const onlyDebtors = ref(true);
const pageNo = ref(1);
const lastPage = ref(1);
const total = ref(0);

async function load(): Promise<void> {
    loading.value = true;
    try {
        const params = new URLSearchParams();
        if (q.value) params.set('q', q.value);
        if (onlyDebtors.value) params.set('only_debtors', '1');
        params.set('page', String(pageNo.value));

        const res = await api<{ receivables: Paginated<ReceivableRow> }>(`/api/v1/receivables?${params}`);
        rows.value = res.receivables.data;
        lastPage.value = res.receivables.last_page;
        total.value = res.receivables.total;
    } catch (e) {
        danger('Cari listesi yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);
watch([q, onlyDebtors], () => {
    pageNo.value = 1;
    void load();
});
watch(pageNo, load);

const columns: TableColumn[] = [
    { key: 'name', label: 'Cari' },
    { key: 'balance_minor', label: 'Bakiye (borç)', align: 'right' },
    { key: 'open_debt_orders_count', label: 'Taşınmış adisyon', align: 'center' },
    { key: 'is_active', label: 'Durum' },
    { key: 'actions', label: 'İşlemler', align: 'right' },
];

/* ================= Oluştur / düzenle ================= */
const drawerOpen = ref(false);
const editing = ref<ReceivableRow | null>(null);
const form = ref({ name: '', phone: '', email: '', note: '' });
const formErrors = ref<Record<string, string>>({});
const formBusy = ref(false);

function openCreate(): void {
    editing.value = null;
    formErrors.value = {};
    form.value = { name: '', phone: '', email: '', note: '' };
    drawerOpen.value = true;
}

function openEdit(row: ReceivableRow): void {
    editing.value = row;
    formErrors.value = {};
    form.value = { name: row.name, phone: row.phone ?? '', email: row.email ?? '', note: row.note ?? '' };
    drawerOpen.value = true;
}

async function submit(): Promise<void> {
    if (formBusy.value) return;
    formBusy.value = true;
    formErrors.value = {};

    const body = {
        name: form.value.name,
        phone: form.value.phone || null,
        email: form.value.email || null,
        note: form.value.note || null,
    };

    try {
        if (editing.value === null) {
            await api('/api/v1/receivables', { method: 'POST', body });
            success('Cari oluşturuldu', `${form.value.name} eklendi.`);
        } else {
            await api(`/api/v1/receivables/${editing.value.id}`, { method: 'PUT', body });
            success('Cari güncellendi', `${form.value.name} kaydedildi.`);
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

async function togglePassive(row: ReceivableRow): Promise<void> {
    try {
        await api(`/api/v1/receivables/${row.id}`, { method: 'PUT', body: { is_active: !row.is_active } });
        success(row.is_active ? 'Cari pasife alındı' : 'Cari aktifleştirildi', row.name);
        await load();
    } catch (e) {
        danger('Güncellenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    }
}

/* ================= Detay: geçmiş + taşınmış adisyonlar ================= */
const detail = ref<ReceivableRow | null>(null);
const detailTransactions = ref<ReceivableTransactionRow[]>([]);
const detailOrders = ref<ReceivableDebtOrderRow[]>([]);

/** Açık ziyaret kartları (kalem dökümü görünenler). */
const expandedOrders = ref<Set<number>>(new Set());
function toggleOrder(id: number): void {
    const next = new Set(expandedOrders.value);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    expandedOrders.value = next;
}

/** Ziyaretlerin borç toplamı (başlıktaki bağlam). */
const detailOrdersTotal = computed(() =>
    detailOrders.value.reduce((n, o) => n + (o.debt_amount_minor ?? o.total_minor), 0),
);

/** "24 Ağustos 2026, Pazartesi · 19:42" — ziyaretin ne zaman olduğu. */
function visitDate(o: ReceivableDebtOrderRow): string {
    const iso = o.closed_at ?? o.created_at ?? null;
    if (!iso) return `Adisyon #${o.id}`;
    const d = new Date(iso);
    return `${d.toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric', weekday: 'long' })} · ${d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })}`;
}

/** O ziyarette alınan toplam ürün adedi (kalem sayısı değil). */
function visitQty(o: ReceivableDebtOrderRow): number {
    return (o.items ?? []).reduce((n, i) => n + i.qty, 0);
}
const detailLoading = ref(false);

async function openDetail(row: ReceivableRow): Promise<void> {
    detail.value = row;
    detailLoading.value = true;
    try {
        const res = await api<{ receivable: ReceivableRow; transactions: ReceivableTransactionRow[]; debt_orders: ReceivableDebtOrderRow[] }>(
            `/api/v1/receivables/${row.id}`,
        );
        detail.value = res.receivable;
        detailTransactions.value = res.transactions;
        detailOrders.value = res.debt_orders;
        // Yeni cari açıldığında önceki carinin açık kartları taşınmasın.
        expandedOrders.value = new Set();
    } catch (e) {
        danger('Cari detayı yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        detailLoading.value = false;
    }
}

function closeDetail(): void {
    detail.value = null;
    detailTransactions.value = [];
    detailOrders.value = [];
}

const transactionTypeLabel: Record<string, string> = {
    debt_transfer: 'Adisyon borcu',
    payment: 'Tahsilat',
    adjustment: 'Düzeltme',
};

/* ================= Tahsilat ================= */
const collectModal = ref(false);
const collectAmount = ref('');
const collectMethod = ref('cash');
const collectNote = ref('');
const collectBusy = ref(false);

function openCollect(): void {
    collectAmount.value = '';
    collectMethod.value = 'cash';
    collectNote.value = '';
    collectModal.value = true;
}

function parseAmountMinor(text: string): number {
    const normalized = text.replace(/\s/g, '').replace(/\./g, '').replace(',', '.');
    const value = Number(normalized);
    return Number.isFinite(value) ? Math.round(value * 100) : 0;
}

async function submitCollect(): Promise<void> {
    const target = detail.value;
    if (!target || collectBusy.value) return;

    const amount = parseAmountMinor(collectAmount.value);
    if (amount <= 0) {
        danger('Tutar geçersiz', 'Pozitif bir tutar girin.');
        return;
    }

    collectBusy.value = true;
    try {
        await api(`/api/v1/receivables/${target.id}/collect`, {
            method: 'POST',
            body: { amount_minor: amount, method: collectMethod.value, note: collectNote.value || null },
        });
        success('Tahsilat kaydedildi', `${money(amount)} ₺ alındı.`);
        collectModal.value = false;
        await Promise.all([load(), openDetail(target)]);
    } catch (e) {
        danger('Tahsilat kaydedilemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        collectBusy.value = false;
    }
}
</script>

<template>
    <Head title="Borçlar" />
    <!-- TAM KAPLAMA: cari listesi ekranı doldurur, kendi içinde kayar. -->
    <PanelShell title="Borçlar" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">
            <BaseCard flush>
                <template #header>
                    <h2 class="text-sm font-semibold text-body">Cari hesaplar</h2>
                </template>
                <template #actions>
                    <BaseButton size="sm" @click="openCreate">
                        <AppIcon name="plus" :size="15" />
                        Yeni cari
                    </BaseButton>
                </template>

                <div class="flex flex-wrap items-center gap-3 border-b border-default px-4 py-3">
                    <SearchInput v-model="q" placeholder="Ad, telefon, e-posta ara…" class="max-w-xs" />
                    <BaseSwitch v-model="onlyDebtors" label="Yalnız borçlular" />
                    <span class="ml-auto text-xs text-muted">{{ total }} cari</span>
                </div>

                <DataTable
                    :columns="columns"
                    :rows="(rows as unknown as Record<string, unknown>[])"
                    :loading="loading"
                    caption="Cari listesi"
                    empty-title="Cari yok"
                    empty-description="Bir adisyonu borca taşıdığınızda ya da elle cari eklediğinizde burada görünür."
                >
                    <template #cell-name="{ row }">
                        <button type="button" class="text-left font-medium text-body hover:underline" @click="openDetail(row as unknown as ReceivableRow)">
                            {{ (row as unknown as ReceivableRow).name }}
                        </button>
                        <div class="text-xs text-muted">{{ (row as unknown as ReceivableRow).phone ?? '—' }}</div>
                    </template>
                    <template #cell-balance_minor="{ row }">
                        <span :class="(row as unknown as ReceivableRow).balance_minor > 0 ? 'font-semibold text-danger' : 'text-muted'">
                            {{ money((row as unknown as ReceivableRow).balance_minor) }} ₺
                        </span>
                    </template>
                    <template #cell-open_debt_orders_count="{ row }">
                        {{ (row as unknown as ReceivableRow).open_debt_orders_count }}
                    </template>
                    <template #cell-is_active="{ row }">
                        <BaseBadge v-if="(row as unknown as ReceivableRow).is_active" variant="success">Aktif</BaseBadge>
                        <BaseBadge v-else variant="neutral" no-icon>
                            <AppIcon name="x" :size="12" />
                            Pasif
                        </BaseBadge>
                    </template>
                    <template #cell-actions="{ row }">
                        <div class="flex items-center justify-end gap-1">
                            <BaseButton size="sm" variant="ghost" @click="openDetail(row as unknown as ReceivableRow)">Detay</BaseButton>
                            <BaseButton size="sm" variant="ghost" icon-only label="Cariyi düzenle" @click="openEdit(row as unknown as ReceivableRow)">
                                <AppIcon name="pencil" :size="16" />
                            </BaseButton>
                            <BaseButton
                                size="sm"
                                variant="ghost"
                                icon-only
                                :label="(row as unknown as ReceivableRow).is_active ? 'Pasife al' : 'Aktifleştir'"
                                @click="togglePassive(row as unknown as ReceivableRow)"
                            >
                                <AppIcon :name="(row as unknown as ReceivableRow).is_active ? 'x-circle' : 'check-circle'" :size="16" />
                            </BaseButton>
                        </div>
                    </template>
                </DataTable>

                <div v-if="lastPage > 1" class="flex justify-center border-t border-default p-3">
                    <BasePagination v-model:page="pageNo" :last-page="lastPage" />
                </div>
            </BaseCard>
        </div>

        <!-- Oluştur / düzenle -->
        <BaseDrawer :open="drawerOpen" :title="editing ? 'Cariyi düzenle' : 'Yeni cari'" @close="drawerOpen = false">
            <form class="flex flex-col gap-4" @submit.prevent="submit">
                <FormField label="Ad" required :error="formErrors.name">
                    <BaseInput v-model="form.name" placeholder="ör. Ahmet Bey / Şirket adı" />
                </FormField>
                <FormField label="Telefon" :error="formErrors.phone">
                    <BaseInput v-model="form.phone" inputmode="tel" />
                </FormField>
                <FormField label="E-posta" :error="formErrors.email">
                    <BaseInput v-model="form.email" type="email" />
                </FormField>
                <FormField label="Not" :error="formErrors.note">
                    <BaseInput v-model="form.note" placeholder="ör. Komşu esnaf, düzenli müşteri…" />
                </FormField>
                <div class="flex justify-end gap-2 pt-2">
                    <BaseButton variant="secondary" @click="drawerOpen = false">Vazgeç</BaseButton>
                    <BaseButton type="submit" :loading="formBusy">{{ editing ? 'Kaydet' : 'Oluştur' }}</BaseButton>
                </div>
            </form>
        </BaseDrawer>

        <!-- Detay: bakiye + geçmiş + taşınmış adisyonlar -->
        <BaseDrawer :open="detail !== null" :title="detail?.name ?? ''" width-class="sm:max-w-lg" @close="closeDetail">
            <div v-if="detail" class="flex flex-col gap-5">
                <div class="flex items-center justify-between rounded-lg bg-inset p-4">
                    <div>
                        <p class="text-xs text-muted">Güncel bakiye (borç)</p>
                        <p class="text-2xl font-semibold" :class="detail.balance_minor > 0 ? 'text-danger' : 'text-success'">
                            {{ money(detail.balance_minor) }} ₺
                        </p>
                    </div>
                    <!-- Tahsilat KASADA alınır: para kasa oturumuna, nakit kasa
                         defterine ve Z raporuna oradan düşer. Buradaki hızlı
                         modal korunur (küçük düzeltmeler için), ama birincil yol
                         kasa ekranıdır. -->
                    <div class="flex flex-col items-end gap-1.5">
                        <BaseButton
                            v-if="can('receivables.collect')"
                            :disabled="detail.balance_minor <= 0"
                            href="/panel/kasa?sekme=borclar"
                        >
                            <AppIcon name="cart" :size="15" />
                            Kasada tahsil et
                        </BaseButton>
                        <button
                            v-if="can('receivables.collect') && detail.balance_minor > 0"
                            type="button"
                            class="text-xs font-medium text-muted underline transition hover:text-body"
                            @click="openCollect"
                        >
                            Kasaya gitmeden hızlı kaydet
                        </button>
                    </div>
                </div>

                <!-- ZİYARET DÖKÜMÜ: her borç kaydı, o günün sipariş özeti.
                     Önceden yalnız "#124 · Masa 3 — 250,00 ₺" yazıyordu; her gün
                     gelen bir müşteride borcun neden o kadar olduğu izlenemiyor,
                     itiraz halinde savunulamıyordu. Artık tarih + saat + nerede
                     + kaç kalem + ne alındığı tek tek görünür. -->
                <div>
                    <div class="flex items-center justify-between gap-2 pb-2">
                        <h3 class="text-sm font-semibold text-body">Ziyaretler ve harcamalar</h3>
                        <span v-if="detailOrders.length" class="text-xs font-semibold text-muted tabular-nums">
                            {{ detailOrders.length }} kayıt · {{ money(detailOrdersTotal) }} ₺
                        </span>
                    </div>

                    <EmptyState
                        v-if="!detailLoading && detailOrders.length === 0"
                        title="Kayıt yok"
                        description="Bu cariye taşınmış adisyon yok."
                    />
                    <ul v-else class="flex flex-col gap-2">
                        <li v-for="o in detailOrders" :key="o.id" class="overflow-hidden rounded-lg border border-default">
                            <!-- Ziyaret başlığı: tarih · saat · yer · tutar -->
                            <button
                                type="button"
                                class="flex w-full items-center gap-2 bg-inset/50 px-3 py-2 text-left transition hover:bg-inset"
                                :aria-expanded="expandedOrders.has(o.id)"
                                @click="toggleOrder(o.id)"
                            >
                                <AppIcon
                                    :name="expandedOrders.has(o.id) ? 'chevron-down' : 'chevron-right'"
                                    :size="15"
                                    class="shrink-0 text-subtle"
                                />
                                <span class="min-w-0 grow">
                                    <span class="block truncate text-sm font-semibold text-body">
                                        {{ visitDate(o) }}
                                    </span>
                                    <span class="block truncate text-xs text-muted">
                                        #{{ o.id }} · {{ o.table_name ?? o.channel_label ?? '—' }}
                                        <template v-if="o.items?.length"> · {{ visitQty(o) }} ürün</template>
                                    </span>
                                </span>
                                <span class="shrink-0 text-sm font-bold tabular-nums text-danger">
                                    {{ money(o.debt_amount_minor ?? o.total_minor) }} ₺
                                </span>
                            </button>

                            <!-- Kalem dökümü: ne yenmiş / ne içilmiş -->
                            <div v-if="expandedOrders.has(o.id)" class="border-t border-default">
                                <p v-if="!o.items || o.items.length === 0" class="px-3 py-2 text-xs text-muted">
                                    Bu adisyonun kalem dökümü yok.
                                </p>
                                <ul v-else class="divide-y divide-default">
                                    <li v-for="it in o.items" :key="it.id" class="flex items-center gap-2 px-3 py-1.5 text-sm">
                                        <span class="min-w-7 shrink-0 rounded bg-inset px-1.5 py-0.5 text-center text-xs font-bold tabular-nums text-body">
                                            {{ it.qty }}×
                                        </span>
                                        <span class="min-w-0 grow truncate text-body">
                                            {{ it.name }}
                                            <span v-if="it.variant_name" class="text-xs text-muted">({{ it.variant_name }})</span>
                                            <span v-if="it.is_comp" class="text-xs font-medium text-info"> · ikram</span>
                                        </span>
                                        <span
                                            class="shrink-0 text-xs font-semibold tabular-nums"
                                            :class="it.is_comp ? 'text-subtle line-through' : 'text-muted'"
                                        >
                                            {{ money(it.line_total_minor) }} ₺
                                        </span>
                                    </li>
                                </ul>
                            </div>
                        </li>
                    </ul>
                </div>

                <div>
                    <h3 class="pb-2 text-sm font-semibold text-body">Hareket geçmişi</h3>
                    <EmptyState v-if="!detailLoading && detailTransactions.length === 0" title="Hareket yok" description="Henüz borç/tahsilat kaydı yok." />
                    <ul v-else class="flex flex-col gap-1.5">
                        <li v-for="t in detailTransactions" :key="t.id" class="flex items-center justify-between rounded-md border border-default px-3 py-2 text-sm">
                            <div class="flex flex-col">
                                <span class="font-medium">{{ transactionTypeLabel[t.type] ?? t.type }}</span>
                                <span class="text-xs text-muted">{{ t.performed_by ?? '—' }} · {{ t.note ?? '' }}</span>
                            </div>
                            <span :class="t.amount_minor > 0 ? 'text-danger' : 'text-success'">
                                {{ t.amount_minor > 0 ? '+' : '' }}{{ money(t.amount_minor) }} ₺
                            </span>
                        </li>
                    </ul>
                </div>
            </div>
        </BaseDrawer>

        <!-- Tahsilat -->
        <BaseModal :open="collectModal" title="Tahsilat al" size="sm" @close="collectModal = false">
            <div class="flex flex-col gap-3">
                <p v-if="detail" class="text-sm text-muted">Kalan borç: <strong>{{ money(detail.balance_minor) }} ₺</strong></p>
                <FormField label="Tutar (₺)" required>
                    <BaseInput v-model="collectAmount" inputmode="decimal" placeholder="ör. 150,00" />
                </FormField>
                <FormField label="Yöntem" required>
                    <BaseSelect
                        v-model="collectMethod"
                        :options="[
                            { value: 'cash', label: 'Nakit' },
                            { value: 'card', label: 'Kart' },
                            { value: 'transfer', label: 'Havale/EFT' },
                            { value: 'other', label: 'Diğer' },
                        ]"
                    />
                </FormField>
                <FormField label="Not">
                    <BaseInput v-model="collectNote" />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="collectModal = false">Vazgeç</BaseButton>
                <BaseButton :loading="collectBusy" @click="submitCollect">Tahsil et</BaseButton>
            </template>
        </BaseModal>
        </div>
    </PanelShell>
</template>
