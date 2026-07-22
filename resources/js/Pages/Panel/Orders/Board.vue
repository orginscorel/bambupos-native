<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { Head, router, usePage } from '@inertiajs/vue3';
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
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import SearchInput from '@/Components/ui/SearchInput.vue';
import {
    elapsed,
    fetchBoard,
    fetchBranches,
    metaFromProps,
    money,
    type BoardData,
    type BoardTable,
    type BranchRow,
    type OrderSummary,
    type ServiceRequestRow,
} from './orders';

const page = usePage();
const meta = metaFromProps(page.props as Record<string, unknown>);
const { success, danger } = useToast();

/* ================= Veri + polling (ADR-006: 5 sn) ================= */
const loading = ref(true);
const board = ref<BoardData>({ tables: [], channel_orders: [], pending_approval: [], service_requests: [] });
const branches = ref<BranchRow[]>([]);
const branchId = ref('');
const q = ref('');
const areaFilter = ref('');
const statusFilter = ref('');

let timer: ReturnType<typeof setInterval> | null = null;
let busyModal = false;

async function load(silent = false): Promise<void> {
    if (!silent) loading.value = true;
    try {
        board.value = await fetchBoard(branchId.value ? Number(branchId.value) : null);
    } catch (e) {
        if (!silent) danger('Pano yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

onMounted(async () => {
    try {
        branches.value = await fetchBranches();
    } catch {
        /* şube filtresi boş kalır */
    }
    await load();
    timer = setInterval(() => {
        if (!busyModal) void load(true);
    }, 5000);
});

onBeforeUnmount(() => {
    if (timer) clearInterval(timer);
});

const branchOptions = computed(() => branches.value.map((b) => ({ value: String(b.id), label: b.name })));

const areaOptions = computed(() => {
    const names = new Set<string>();
    board.value.tables.forEach((t) => {
        if (t.area_name) names.add(t.area_name);
    });
    return [...names].map((n) => ({ value: n, label: n }));
});

const statusOptions = computed(() => meta.tableStatuses.map((s) => ({ value: s.value, label: s.label })));

const filteredTables = computed(() =>
    board.value.tables.filter((t) => {
        if (areaFilter.value && t.area_name !== areaFilter.value) return false;
        if (statusFilter.value && t.status !== statusFilter.value) return false;
        if (q.value) {
            const needle = q.value.toLocaleLowerCase('tr-TR');
            const hay = `${t.name} ${t.number ?? ''} ${t.area_name ?? ''}`.toLocaleLowerCase('tr-TR');
            if (!hay.includes(needle)) return false;
        }
        return true;
    }),
);

/* ================= Masa aç / adisyona git ================= */
const openTable = ref<BoardTable | null>(null);
const guestCount = ref('2');
const openBusy = ref(false);

function onTableClick(table: BoardTable): void {
    if (table.orders.length === 1) {
        router.visit(`/panel/siparisler/${table.orders[0].id}`);
        return;
    }
    // Birden çok adisyon → seçtir; hiç yoksa masa aç.
    openTable.value = table;
    guestCount.value = String(Math.min(table.capacity, 2));
    busyModal = true;
}

function closeTableModal(): void {
    openTable.value = null;
    busyModal = false;
}

async function createOrder(): Promise<void> {
    const table = openTable.value;
    if (!table || openBusy.value) return;
    openBusy.value = true;
    try {
        const res = await api<{ order: OrderSummary }>('/api/v1/orders', {
            method: 'POST',
            body: {
                branch_id: branchId.value ? Number(branchId.value) : branches.value[0]?.id,
                channel: 'table',
                table_id: table.id,
                guest_count: Number(guestCount.value) || null,
            },
        });
        success('Adisyon açıldı', `${table.name} için yeni adisyon oluşturuldu.`);
        closeTableModal();
        router.visit(`/panel/siparisler/${res.order.id}`);
    } catch (e) {
        danger('Adisyon açılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        openBusy.value = false;
    }
}

/* ================= Masasız kanal siparişi (paket / gel-al / kiosk) ================= */
const channelModal = ref(false);
const channelForm = ref({ channel: 'package', customer_name: '', customer_phone: '', note: '' });
const channelBusy = ref(false);

const channelOptions = computed(() =>
    meta.channels.filter((c) => c.value !== 'table' && c.value !== 'qr').map((c) => ({ value: c.value, label: c.label })),
);

function openChannelModal(): void {
    channelForm.value = { channel: 'package', customer_name: '', customer_phone: '', note: '' };
    channelModal.value = true;
    busyModal = true;
}

function closeChannelModal(): void {
    channelModal.value = false;
    busyModal = false;
}

async function createChannelOrder(): Promise<void> {
    if (channelBusy.value) return;
    channelBusy.value = true;
    try {
        const res = await api<{ order: OrderSummary }>('/api/v1/orders', {
            method: 'POST',
            body: {
                branch_id: branchId.value ? Number(branchId.value) : branches.value[0]?.id,
                channel: channelForm.value.channel,
                customer_name: channelForm.value.customer_name || null,
                customer_phone: channelForm.value.customer_phone || null,
                note: channelForm.value.note || null,
            },
        });
        success('Sipariş açıldı', 'Ürünleri ekleyebilirsiniz.');
        closeChannelModal();
        router.visit(`/panel/siparisler/${res.order.id}`);
    } catch (e) {
        danger('Sipariş açılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        channelBusy.value = false;
    }
}

/* ================= Servis talepleri ================= */
const resolvingRequest = ref<number | null>(null);

async function resolveRequest(sr: ServiceRequestRow): Promise<void> {
    if (resolvingRequest.value !== null) return;
    resolvingRequest.value = sr.id;
    try {
        await api(`/api/v1/orders/service-requests/${sr.id}/done`, { method: 'POST' });
        success('Talep kapatıldı', `${sr.table_name ?? 'Masa'} — ${sr.kind_label}`);
        await load(true);
    } catch (e) {
        danger('Kapatılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        resolvingRequest.value = null;
    }
}

/* ================= QR onayı ================= */
const approving = ref<number | null>(null);

async function approveOrder(order: OrderSummary): Promise<void> {
    if (approving.value !== null) return;
    approving.value = order.id;
    try {
        await api(`/api/v1/orders/${order.id}/approve`, { method: 'POST' });
        success('Sipariş onaylandı', `${order.table_name ?? 'Masa'} siparişi mutfağa düşebilir.`);
        await load(true);
    } catch (e) {
        danger('Onaylanamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        approving.value = null;
    }
}
</script>

<template>
    <Head title="Siparişler" />
    <PanelShell title="Siparişler">
        <div class="flex flex-col gap-4">
            <!-- Açık servis talepleri (garson çağır / hesap iste / su iste) -->
            <BaseCard v-if="board.service_requests.length > 0">
                <div class="flex items-center gap-2 pb-2">
                    <AppIcon name="bell" :size="18" class="text-danger" />
                    <h2 class="text-sm font-semibold text-body">Servis talepleri ({{ board.service_requests.length }})</h2>
                </div>
                <div class="flex flex-col gap-2">
                    <div
                        v-for="sr in board.service_requests"
                        :key="sr.id"
                        class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-default p-3"
                    >
                        <div class="flex items-center gap-2">
                            <BaseBadge variant="warning" no-icon>
                                <AppIcon :name="sr.kind_icon" :size="12" />
                                {{ sr.kind_label }}
                            </BaseBadge>
                            <span class="font-medium">{{ sr.table_name ?? 'Masa' }}</span>
                            <span class="text-sm text-muted">{{ elapsed(sr.created_at) }} önce</span>
                        </div>
                        <BaseButton size="sm" variant="secondary" :loading="resolvingRequest === sr.id" @click="resolveRequest(sr)">
                            <AppIcon name="check" :size="14" />
                            İlgilenildi
                        </BaseButton>
                    </div>
                </div>
            </BaseCard>

            <!-- Onay bekleyen QR siparişleri -->
            <BaseCard v-if="board.pending_approval.length > 0">
                <div class="flex items-center gap-2 pb-2">
                    <AppIcon name="bell" :size="18" class="text-warning" />
                    <h2 class="text-sm font-semibold text-body">Onay bekleyen QR siparişleri ({{ board.pending_approval.length }})</h2>
                </div>
                <div class="flex flex-col gap-2">
                    <div
                        v-for="o in board.pending_approval"
                        :key="o.id"
                        class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-default p-3"
                    >
                        <div class="flex items-center gap-3">
                            <BaseBadge :variant="o.status_variant" no-icon>
                                <AppIcon :name="o.status_icon" :size="12" />
                                {{ o.status_label }}
                            </BaseBadge>
                            <span class="font-medium">{{ o.table_name ?? o.channel_label }}</span>
                            <span class="text-sm text-muted">{{ o.items_count }} kalem · {{ o.total_display }} ₺ · {{ elapsed(o.created_at) }}</span>
                        </div>
                        <div class="flex gap-2">
                            <BaseButton size="sm" variant="secondary" @click="router.visit(`/panel/siparisler/${o.id}`)">İncele</BaseButton>
                            <BaseButton size="sm" :loading="approving === o.id" @click="approveOrder(o)">
                                <AppIcon name="check" :size="14" />
                                Onayla
                            </BaseButton>
                        </div>
                    </div>
                </div>
            </BaseCard>

            <!-- Filtreler -->
            <BaseCard>
                <div class="flex flex-wrap items-end gap-3">
                    <div class="w-full sm:w-44">
                        <FormField label="Şube">
                            <BaseSelect v-model="branchId" :options="branchOptions" placeholder="Tümü" size="sm" @update:model-value="() => load()" />
                        </FormField>
                    </div>
                    <div class="w-full sm:w-40">
                        <FormField label="Alan">
                            <BaseSelect v-model="areaFilter" :options="areaOptions" placeholder="Tümü" size="sm" />
                        </FormField>
                    </div>
                    <div class="w-full sm:w-44">
                        <FormField label="Masa durumu">
                            <BaseSelect v-model="statusFilter" :options="statusOptions" placeholder="Tümü" size="sm" />
                        </FormField>
                    </div>
                    <div class="w-full grow sm:w-52">
                        <FormField label="Ara">
                            <SearchInput v-model="q" placeholder="Masa adı veya no…" />
                        </FormField>
                    </div>
                    <BaseButton variant="secondary" @click="openChannelModal">
                        <AppIcon name="cart" :size="16" />
                        Paket / Gel-Al / Kiosk
                    </BaseButton>
                </div>
            </BaseCard>

            <!-- Masa ızgarası: büyük dokunma hedefleri, durum = renk + ikon + metin -->
            <div v-if="filteredTables.length > 0" class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
                <button
                    v-for="t in filteredTables"
                    :key="t.id"
                    type="button"
                    class="flex min-h-32 flex-col justify-between rounded-xl border border-default bg-surface p-3 text-left shadow-sm transition-shadow hover:shadow-md focus-visible:outline-2"
                    :aria-label="`${t.name} — ${t.status_label}`"
                    @click="onTableClick(t)"
                >
                    <div class="flex items-start justify-between gap-2">
                        <div>
                            <p class="text-base font-semibold text-body">{{ t.name }}</p>
                            <p class="text-xs text-muted">
                                <template v-if="t.area_name">{{ t.area_name }}<template v-if="t.floor_name"> · {{ t.floor_name }}</template> · </template>
                                <AppIcon name="users" :size="11" class="inline" /> {{ t.capacity }}
                            </p>
                        </div>
                        <span class="font-mono text-sm text-subtle">{{ t.number ?? '' }}</span>
                    </div>
                    <div class="flex flex-col gap-1.5">
                        <div v-if="t.orders.length > 0" class="text-sm font-medium text-body">
                            {{ t.orders.reduce((n, o) => n + o.items_count, 0) }} kalem ·
                            {{ money(t.orders.reduce((n, o) => n + o.remaining_minor, 0)) }} ₺
                            <span class="text-xs text-muted">· {{ elapsed(t.orders[0].created_at) }}</span>
                        </div>
                        <BaseBadge :variant="t.status_variant" no-icon>
                            <AppIcon :name="t.status_icon" :size="12" />
                            {{ t.status_label }}
                        </BaseBadge>
                    </div>
                </button>
            </div>
            <BaseCard v-else-if="!loading">
                <EmptyState title="Masa bulunamadı" description="Filtreleri değiştirin ya da Masalar sayfasından masa oluşturun." icon="qr-code" />
            </BaseCard>

            <!-- Masasız kanal siparişleri -->
            <BaseCard v-if="board.channel_orders.length > 0">
                <h2 class="pb-2 text-sm font-semibold text-body">Paket / Gel-Al / Kiosk siparişleri</h2>
                <div class="flex flex-col gap-2">
                    <button
                        v-for="o in board.channel_orders"
                        :key="o.id"
                        type="button"
                        class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-default p-3 text-left transition-colors hover:bg-inset"
                        @click="router.visit(`/panel/siparisler/${o.id}`)"
                    >
                        <div class="flex flex-wrap items-center gap-2">
                            <BaseBadge :variant="o.channel_variant" no-icon>
                                <AppIcon :name="o.channel_icon" :size="12" />
                                {{ o.channel_label }}
                            </BaseBadge>
                            <span class="font-medium">#{{ o.id }}</span>
                            <span v-if="o.customer_name" class="text-sm text-muted">{{ o.customer_name }}</span>
                        </div>
                        <div class="flex items-center gap-3">
                            <span class="text-sm text-muted">{{ o.items_count }} kalem · {{ o.total_display }} ₺ · {{ elapsed(o.created_at) }}</span>
                            <BaseBadge :variant="o.status_variant" no-icon>
                                <AppIcon :name="o.status_icon" :size="12" />
                                {{ o.status_label }}
                            </BaseBadge>
                        </div>
                    </button>
                </div>
            </BaseCard>
        </div>

        <!-- Masa modalı: adisyon seç ya da yeni aç -->
        <BaseModal :open="openTable !== null" :title="openTable?.name ?? 'Masa'" size="sm" @close="closeTableModal">
            <div v-if="openTable && openTable.orders.length > 0" class="flex flex-col gap-2 pb-3">
                <p class="text-xs font-medium text-muted">Bu masadaki açık adisyonlar</p>
                <button
                    v-for="o in openTable.orders"
                    :key="o.id"
                    type="button"
                    class="flex items-center justify-between rounded-lg border border-default p-3 text-left hover:bg-inset"
                    @click="busyModal = false; router.visit(`/panel/siparisler/${o.id}`)"
                >
                    <span class="font-medium">Adisyon #{{ o.id }}</span>
                    <span class="text-sm text-muted">{{ o.items_count }} kalem · {{ o.total_display }} ₺</span>
                </button>
            </div>
            <FormField label="Kişi sayısı" hint="Yeni adisyon için">
                <BaseInput v-model="guestCount" inputmode="numeric" />
            </FormField>
            <template #footer>
                <BaseButton variant="secondary" @click="closeTableModal">Vazgeç</BaseButton>
                <BaseButton :loading="openBusy" @click="createOrder">
                    <AppIcon name="plus" :size="14" />
                    Yeni adisyon aç
                </BaseButton>
            </template>
        </BaseModal>

        <!-- Masasız kanal siparişi -->
        <BaseModal :open="channelModal" title="Paket / Gel-Al / Kiosk siparişi" size="sm" @close="closeChannelModal">
            <div class="flex flex-col gap-3">
                <FormField label="Kanal" required>
                    <BaseSelect v-model="channelForm.channel" :options="channelOptions" />
                </FormField>
                <FormField label="Müşteri adı">
                    <BaseInput v-model="channelForm.customer_name" placeholder="ör. Ayşe Yılmaz" />
                </FormField>
                <FormField label="Telefon">
                    <BaseInput v-model="channelForm.customer_phone" inputmode="tel" placeholder="05xx…" />
                </FormField>
                <FormField label="Not">
                    <BaseInput v-model="channelForm.note" placeholder="ör. Zili çalma" />
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeChannelModal">Vazgeç</BaseButton>
                <BaseButton :loading="channelBusy" @click="createChannelOrder">Siparişi aç</BaseButton>
            </template>
        </BaseModal>
    </PanelShell>
</template>
