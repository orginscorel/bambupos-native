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
    orderElapsed,
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

/* Masadaki tüm açık adisyonların aktif kalem + servis edilen toplamı (#4). */
function tableItems(t: BoardTable): number {
    return t.orders.reduce((n, o) => n + o.items_count, 0);
}
function tableServed(t: BoardTable): number {
    return t.orders.reduce((n, o) => n + o.served_count, 0);
}

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

/* ================= Kat / alan gruplaması + masa görsel yardımcıları =================
   Yalnız görünüm (davranış değişmez): masalar aynı alan (+ kat) başlığı altında
   toplanır; kart rengi doluluğu kodlar (açık adisyon = dolu = danger, boş = success). */
interface TableGroup {
    key: string;
    area: string | null;
    floor: string | null;
    tables: BoardTable[];
}

const groupedTables = computed<TableGroup[]>(() => {
    const groups = new Map<string, TableGroup>();
    for (const t of filteredTables.value) {
        const key = `${t.floor_name ?? ''}||${t.area_name ?? ''}`;
        let g = groups.get(key);
        if (!g) {
            g = { key, area: t.area_name, floor: t.floor_name, tables: [] };
            groups.set(key, g);
        }
        g.tables.push(t);
    }
    return [...groups.values()];
});

/** Masada açık adisyon var mı → kart rengi (dolu = danger, boş = success). */
function tableOccupied(t: BoardTable): boolean {
    return t.orders.length > 0;
}
/** Bir gruptaki dolu masa sayısı (başlık özeti). */
function occupiedCount(list: BoardTable[]): number {
    return list.reduce((n, t) => n + (t.orders.length > 0 ? 1 : 0), 0);
}
/** Masadaki tüm açık adisyonların kalan (ödenecek) toplamı — kuruş. */
function tableTotal(t: BoardTable): number {
    return t.orders.reduce((n, o) => n + o.remaining_minor, 0);
}
/** Kısmi teslim ilerleme çubuğu için yüzde (servis edilen / toplam kalem). */
function servedPct(t: BoardTable): string {
    const items = tableItems(t);
    if (items <= 0) return '0%';
    return `${Math.round((tableServed(t) / items) * 100)}%`;
}
/** Masadaki ödeme özeti — yalnız anlamlı olduğunda rozet çıkar (ödendi / kısmi). */
function tablePayment(t: BoardTable): 'paid' | 'partial' | null {
    if (t.orders.length === 0) return null;
    if (t.orders.every((o) => o.payment_state === 'paid')) return 'paid';
    if (t.orders.some((o) => o.payment_state !== 'unpaid')) return 'partial';
    return null;
}

/* ================= Masa aç / adisyona git =================
   Kişi sayısı AÇILIŞTA SORULMAZ (kullanıcı talebi): masaya tıklayınca boşsa
   direkt adisyon açılır ve içine girilir; tek adisyon varsa ona girilir; birden
   çok adisyon varsa seçtirilir. Misafir adedi opsiyonel — adisyon detayından
   sonradan eklenebilir (backend guest_count nullable). */
const openTable = ref<BoardTable | null>(null);
const openBusy = ref(false);

/* Rezervasyon ↔ walk-in çakışma onayı (§8): boş görünen masaya adisyon
   açılırken masanın yaklaşan/aktif rezervasyonu varsa backend 409 +
   requires_confirmation döndürür; personel onaylarsa confirm=true ile açılır. */
interface ReservationConflict {
    message: string;
    table: BoardTable;
    reservation?: { customer_name?: string; reserved_time?: string; party_size?: number; status_label?: string };
}
const reservationConflict = ref<ReservationConflict | null>(null);

function onTableClick(table: BoardTable): void {
    if (table.orders.length === 1) {
        router.visit(`/panel/siparisler/${table.orders[0].id}`);
        return;
    }
    if (table.orders.length === 0) {
        void createOrder(table); // boş masa → doğrudan adisyon aç + içine gir
        return;
    }
    // Birden çok açık adisyon → hangisine gireceğini seçtir.
    openTable.value = table;
    busyModal = true;
}

function closeTableModal(): void {
    openTable.value = null;
    busyModal = false;
}

async function createOrder(table: BoardTable, confirm = false): Promise<void> {
    if (openBusy.value) return;
    openBusy.value = true;
    try {
        const res = await api<{ order: OrderSummary }>('/api/v1/orders', {
            method: 'POST',
            body: {
                branch_id: branchId.value ? Number(branchId.value) : branches.value[0]?.id,
                channel: 'table',
                table_id: table.id,
                guest_count: null,
                confirm,
            },
        });
        success('Adisyon açıldı', `${table.name} için yeni adisyon oluşturuldu.`);
        reservationConflict.value = null;
        closeTableModal();
        router.visit(`/panel/siparisler/${res.order.id}`);
    } catch (e) {
        // Rezervasyon çakışması: onay iste (adisyon henüz açılmadı).
        if (e instanceof ApiError && e.status === 409 && e.data?.requires_confirmation) {
            const r = e.data.reservation as ReservationConflict['reservation'];
            reservationConflict.value = {
                message: typeof e.data.message === 'string' ? e.data.message : 'Bu masa rezerve — yine de açılsın mı?',
                table,
                reservation: r,
            };
            busyModal = true;
            return;
        }
        danger('Adisyon açılamadı', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        openBusy.value = false;
    }
}

function cancelReservationConflict(): void {
    reservationConflict.value = null;
    busyModal = false;
}

async function confirmReservationConflict(): Promise<void> {
    const pending = reservationConflict.value;
    if (!pending) return;
    reservationConflict.value = null;
    busyModal = false;
    await createOrder(pending.table, true);
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
    <PanelShell title="Siparişler" immersive>
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
                            <span class="text-sm text-muted">{{ o.items_count }} kalem</span>
                            <span class="whitespace-nowrap text-sm font-semibold tabular-nums text-body">{{ o.total_display }} ₺</span>
                            <span class="text-xs text-subtle">{{ orderElapsed(o) }} önce</span>
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

            <!-- Masa panosu: kat/alan gruplu, büyük dokunmatik kartlar. Kart rengi
                 doluluğu kodlar (dolu = kırmızı şerit, boş = yeşil). Durum rozeti
                 (3'lü) yalnız görüntüdür — buradan durum ilerletilmez. -->
            <template v-if="filteredTables.length > 0">
                <section v-for="g in groupedTables" :key="g.key" class="flex flex-col gap-3">
                    <!-- Grup başlığı: alan/kat + doluluk özeti (renk anahtarı) -->
                    <div class="flex flex-wrap items-center gap-x-3 gap-y-1 px-0.5">
                        <span class="flex h-8 w-8 items-center justify-center rounded-lg bg-primary-soft text-primary">
                            <AppIcon name="utensils" :size="16" />
                        </span>
                        <h2 class="text-base font-bold text-body">{{ g.area ?? g.floor ?? 'Masalar' }}</h2>
                        <span v-if="g.area && g.floor" class="text-xs font-medium text-subtle">· {{ g.floor }}</span>
                        <span class="ml-auto flex items-center gap-3 text-xs font-semibold">
                            <span class="flex items-center gap-1.5 text-danger">
                                <span class="h-2 w-2 rounded-full bg-danger"></span>{{ occupiedCount(g.tables) }} dolu
                            </span>
                            <span class="flex items-center gap-1.5 text-success">
                                <span class="h-2 w-2 rounded-full bg-success"></span>{{ g.tables.length - occupiedCount(g.tables) }} boş
                            </span>
                        </span>
                    </div>

                    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 sm:gap-4 lg:grid-cols-3 xl:grid-cols-4">
                        <button
                            v-for="t in g.tables"
                            :key="t.id"
                            type="button"
                            class="group relative flex min-h-40 flex-col gap-3 overflow-hidden rounded-2xl border p-4 text-left shadow-sm transition-all duration-150 hover:-translate-y-0.5 hover:shadow-lg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                            :class="tableOccupied(t) ? 'border-danger-border bg-raised' : 'border-success-border bg-success-soft'"
                            :aria-label="`${t.name} — ${t.status_label}`"
                            @click="onTableClick(t)"
                        >
                            <!-- Başlık: masa adı (büyük) + Dolu/Boş rozeti + numara çipi -->
                            <div class="flex items-start justify-between gap-2">
                                <div class="min-w-0">
                                    <p class="truncate text-lg font-bold leading-tight text-body">{{ t.name }}</p>
                                    <p class="mt-0.5 flex items-center gap-1.5 text-xs text-muted">
                                        <span v-if="t.area_name" class="truncate">{{ t.area_name }}</span>
                                        <span class="inline-flex items-center gap-1 whitespace-nowrap">
                                            <AppIcon name="users" :size="11" />{{ t.capacity }}
                                        </span>
                                    </p>
                                </div>
                                <div class="flex shrink-0 items-center gap-1.5">
                                    <span
                                        class="rounded-full px-2 py-0.5 text-xs font-bold text-white"
                                        :class="tableOccupied(t) ? 'bg-danger' : 'bg-success'"
                                    >{{ tableOccupied(t) ? 'Dolu' : 'Boş' }}</span>
                                    <span
                                        v-if="t.number !== null"
                                        class="rounded-lg bg-inset px-2 py-0.5 font-mono text-xs font-semibold text-subtle"
                                    >{{ t.number }}</span>
                                </div>
                            </div>

                            <!-- Dolu: büyük tutar + kalem/süre + servis ilerlemesi + durum/ödeme -->
                            <template v-if="tableOccupied(t)">
                                <div class="mt-auto flex flex-col gap-2">
                                    <div>
                                        <p class="flex items-baseline gap-1 leading-none">
                                            <span class="text-2xl font-extrabold tabular-nums text-body">{{ money(tableTotal(t)) }}</span>
                                            <span class="text-base font-bold text-muted">₺</span>
                                        </p>
                                        <p class="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-subtle">
                                            <span class="font-medium text-muted">{{ tableItems(t) }} kalem</span>
                                            <span aria-hidden="true">·</span>
                                            <span>{{ orderElapsed(t.orders[0]) }}</span>
                                            <span v-if="t.orders.length > 1" class="rounded bg-inset px-1.5 py-0.5 font-medium text-muted">{{ t.orders.length }} adisyon</span>
                                        </p>
                                    </div>

                                    <!-- Kısmi teslim ilerleme çubuğu (#4) -->
                                    <div v-if="tableItems(t) > 0 && tableServed(t) < tableItems(t)">
                                        <div class="mb-1 flex items-center justify-between text-[11px] font-medium text-subtle">
                                            <span>Servis</span>
                                            <span class="tabular-nums">{{ tableServed(t) }}/{{ tableItems(t) }}</span>
                                        </div>
                                        <div class="h-1.5 w-full overflow-hidden rounded-full bg-inset">
                                            <div class="h-full rounded-full bg-success transition-all" :style="{ width: servedPct(t) }"></div>
                                        </div>
                                    </div>

                                    <div class="flex flex-wrap items-center gap-1.5">
                                        <BaseBadge :variant="t.status_variant" no-icon>
                                            <AppIcon :name="t.status_icon" :size="12" />
                                            {{ t.status_label }}
                                        </BaseBadge>
                                        <BaseBadge v-if="tablePayment(t)" :variant="tablePayment(t) === 'paid' ? 'success' : 'warning'" no-icon>
                                            <AppIcon :name="tablePayment(t) === 'paid' ? 'check-circle' : 'cart'" :size="12" />
                                            {{ tablePayment(t) === 'paid' ? 'Ödendi' : 'Kısmi' }}
                                        </BaseBadge>
                                    </div>
                                </div>
                            </template>

                            <!-- Boş: yeşil davet, dokun → doğrudan adisyon aç -->
                            <template v-else>
                                <div class="flex flex-1 flex-col items-center justify-center gap-2 py-2 text-center">
                                    <span class="flex h-11 w-11 items-center justify-center rounded-full bg-success text-invert shadow-sm transition-transform group-hover:scale-105">
                                        <AppIcon name="plus" :size="22" />
                                    </span>
                                    <span class="text-xs font-semibold text-success">Boş · adisyon aç</span>
                                </div>
                            </template>
                        </button>
                    </div>
                </section>
            </template>
            <BaseCard v-else-if="!loading">
                <EmptyState title="Masa bulunamadı" description="Filtreleri değiştirin ya da Masalar sayfasından masa oluşturun." icon="qr-code" />
            </BaseCard>

            <!-- Masasız kanal siparişleri: paket / gel-al / kiosk — şık kart ızgarası -->
            <BaseCard v-if="board.channel_orders.length > 0">
                <template #header>
                    <div class="flex items-center gap-2">
                        <AppIcon name="package" :size="18" class="text-primary" />
                        <h2 class="text-sm font-semibold text-body">Paket / Gel-Al / Kiosk siparişleri</h2>
                        <span class="rounded-full bg-inset px-2 py-0.5 text-xs font-semibold text-muted">{{ board.channel_orders.length }}</span>
                    </div>
                </template>
                <div class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
                    <button
                        v-for="o in board.channel_orders"
                        :key="o.id"
                        type="button"
                        class="group flex flex-col gap-3 rounded-2xl border border-default bg-raised p-4 text-left shadow-sm transition-all duration-150 hover:-translate-y-0.5 hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                        @click="router.visit(`/panel/siparisler/${o.id}`)"
                    >
                        <div class="flex items-start justify-between gap-2">
                            <div class="flex flex-wrap items-center gap-1.5">
                                <!-- Kaynak (nereden: Garson/Kiosk/QR) — tek etiket, ServiceType ile çakışmaz (#3) -->
                                <BaseBadge :variant="o.source_variant" no-icon>
                                    <AppIcon :name="o.source_icon" :size="12" />
                                    {{ o.source_label }}
                                </BaseBadge>
                                <!-- Servis tipi (nasıl: Masada/Gel-al/Paket) -->
                                <BaseBadge :variant="o.service_type_variant" no-icon>
                                    <AppIcon :name="o.service_type_icon" :size="12" />
                                    {{ o.service_type_label }}
                                </BaseBadge>
                            </div>
                            <span class="shrink-0 font-mono text-xs font-semibold text-subtle">#{{ o.id }}</span>
                        </div>

                        <div class="flex items-end justify-between gap-2">
                            <div class="min-w-0">
                                <p v-if="o.customer_name" class="truncate text-sm font-semibold text-body">{{ o.customer_name }}</p>
                                <p class="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-subtle">
                                    <span class="font-medium text-muted">{{ o.items_count }} kalem</span>
                                    <span aria-hidden="true">·</span>
                                    <span>{{ orderElapsed(o) }}</span>
                                </p>
                            </div>
                            <p class="flex shrink-0 items-baseline gap-1 leading-none">
                                <span class="text-xl font-extrabold tabular-nums text-body">{{ o.total_display }}</span>
                                <span class="text-sm font-bold text-muted">₺</span>
                            </p>
                        </div>

                        <div class="flex flex-wrap items-center gap-1.5 border-t border-default pt-2.5">
                            <BaseBadge :variant="o.status_variant" no-icon>
                                <AppIcon :name="o.status_icon" :size="12" />
                                {{ o.status_label }}
                            </BaseBadge>
                            <BaseBadge :variant="o.payment_state === 'paid' ? 'success' : o.payment_state === 'partial' ? 'warning' : 'neutral'" no-icon>
                                <AppIcon :name="o.payment_state === 'paid' ? 'check-circle' : 'cart'" :size="12" />
                                {{ o.payment_label }}
                            </BaseBadge>
                            <!-- Kısmi teslim ilerlemesi (#4): komi kalemleri tek tek teslim eder -->
                            <span v-if="o.items_count > 0 && o.served_count < o.items_count" class="ml-auto text-xs font-medium text-subtle">
                                {{ o.served_count }}/{{ o.items_count }} servis
                            </span>
                        </div>
                    </button>
                </div>
            </BaseCard>
        </div>

        <!-- Masa modalı: yalnız birden çok açık adisyon varsa çıkar — hangisine
             gireceğini seçtirir ya da yeni adisyon açtırır. Kişi sayısı SORULMAZ. -->
        <BaseModal :open="openTable !== null" :title="openTable?.name ?? 'Masa'" size="sm" @close="closeTableModal">
            <div v-if="openTable && openTable.orders.length > 0" class="flex flex-col gap-2">
                <p class="text-xs font-medium text-muted">Bu masadaki açık adisyonlar</p>
                <button
                    v-for="o in openTable.orders"
                    :key="o.id"
                    type="button"
                    class="flex items-center justify-between rounded-lg border border-default p-3 text-left hover:bg-inset"
                    @click="busyModal = false; router.visit(`/panel/siparisler/${o.id}`)"
                >
                    <span class="font-medium">Adisyon #{{ o.id }}</span>
                    <span class="text-sm text-muted">{{ o.items_count }} kalem · <span class="whitespace-nowrap tabular-nums">{{ o.total_display }} ₺</span></span>
                </button>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeTableModal">Vazgeç</BaseButton>
                <BaseButton :loading="openBusy" @click="openTable && createOrder(openTable)">
                    <AppIcon name="plus" :size="14" />
                    Yeni adisyon aç
                </BaseButton>
            </template>
        </BaseModal>

        <!-- Rezervasyon ↔ walk-in çakışma onayı (§8): masanın yaklaşan/aktif
             rezervasyonu varsa personel açılışı açıkça onaylar. -->
        <BaseModal
            :open="reservationConflict !== null"
            title="Masa rezerve"
            size="sm"
            @close="cancelReservationConflict"
        >
            <div class="flex flex-col gap-3">
                <div class="flex items-start gap-2 text-sm">
                    <AppIcon name="alert-triangle" :size="18" class="mt-0.5 shrink-0 text-warning" />
                    <p>{{ reservationConflict?.message }}</p>
                </div>
                <div
                    v-if="reservationConflict?.reservation"
                    class="rounded-lg border border-default p-3 text-sm"
                >
                    <p class="font-medium">{{ reservationConflict.reservation.customer_name }}</p>
                    <p class="text-muted">
                        {{ reservationConflict.reservation.reserved_time }}
                        · {{ reservationConflict.reservation.party_size }} kişi
                        <template v-if="reservationConflict.reservation.status_label">
                            · {{ reservationConflict.reservation.status_label }}
                        </template>
                    </p>
                </div>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="cancelReservationConflict">Vazgeç</BaseButton>
                <BaseButton variant="danger" :loading="openBusy" @click="confirmReservationConflict">
                    Yine de aç
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
