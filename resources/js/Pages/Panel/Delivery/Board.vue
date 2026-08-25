<script setup lang="ts">
/**
 * /panel/teslimat — Teslimat (paket/kurye) panosu.
 *
 * Paket siparişlerin teslimatlarını durum sütunlarında gösterir
 * (Bekliyor / Atandı / Yolda / Teslim / Başarısız). Her kartta müşteri
 * adı/telefon, adres, tutar ve durum rozeti. Yazma aksiyonları (kurye ata,
 * durum güncelle) `delivery.manage`; sayfa `delivery.view` iznine bağlıdır
 * (arayüz gizleme — asıl koruma backend policy'de, ADR-004).
 */
import { computed, onMounted, reactive, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { formatCurrencyMinor } from '@/lib/format';
import { usePermissions } from '@/composables/usePermissions';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseModal from '@/Components/ui/BaseModal.vue';
import BaseSelect from '@/Components/ui/BaseSelect.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';

type DeliveryStatus = 'pending' | 'assigned' | 'on_the_way' | 'delivered' | 'failed';

interface CourierOption {
    id: number;
    name: string;
}

interface DeliveryDTO {
    id: number;
    order_id: number;
    order: {
        id: number;
        number?: number | string | null;
        customer_name: string | null;
        customer_phone: string | null;
        total_minor: number;
        service_type: string;
    };
    address: string | null;
    note: string | null;
    status: DeliveryStatus;
    status_label: string | null;
    fee_minor: number;
    courier: { id: number; name: string } | null;
    assigned_at: string | null;
    delivered_at: string | null;
    created_at: string | null;
}

interface DeliveriesResponse {
    deliveries: DeliveryDTO[];
    couriers: CourierOption[];
}

const { can } = usePermissions();
const { success, danger } = useToast();

const canView = computed(() => can('delivery.view'));
const canManage = computed(() => can('delivery.manage'));

const loading = ref(true);
const deliveries = ref<DeliveryDTO[]>([]);
const couriers = ref<CourierOption[]>([]);

const statusMeta: Record<DeliveryStatus, { label: string; variant: 'neutral' | 'info' | 'primary' | 'success' | 'danger' }> = {
    pending: { label: 'Bekliyor', variant: 'neutral' },
    assigned: { label: 'Atandı', variant: 'info' },
    on_the_way: { label: 'Yolda', variant: 'primary' },
    delivered: { label: 'Teslim', variant: 'success' },
    failed: { label: 'Başarısız', variant: 'danger' },
};

const columns: { status: DeliveryStatus }[] = [
    { status: 'pending' },
    { status: 'assigned' },
    { status: 'on_the_way' },
    { status: 'delivered' },
    { status: 'failed' },
];

const statusOptions = columns.map((c) => ({ value: c.status, label: statusMeta[c.status].label }));

const courierOptions = computed(() => [
    { value: '', label: 'Kurye seçin', disabled: true },
    ...couriers.value.map((c) => ({ value: String(c.id), label: c.name })),
]);

const dtFmt = new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
const dt = (iso: string | null): string => (iso ? dtFmt.format(new Date(iso)) : '');

function statusLabel(d: DeliveryDTO): string {
    return d.status_label ?? statusMeta[d.status]?.label ?? d.status;
}

function byStatus(status: DeliveryStatus): DeliveryDTO[] {
    return deliveries.value.filter((d) => d.status === status);
}

async function load(): Promise<void> {
    loading.value = true;
    try {
        const res = await api<DeliveriesResponse>('/api/v1/deliveries');
        deliveries.value = res.deliveries ?? [];
        couriers.value = res.couriers ?? [];
    } catch (e) {
        danger('Teslimatlar yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
}

onMounted(() => {
    if (canView.value) void load();
    else loading.value = false;
});

/* ---- Yönet modalı (kurye ata + durum güncelle) ---- */
const manageTarget = ref<DeliveryDTO | null>(null);
const savingAssign = ref(false);
const savingStatus = ref(false);
const form = reactive({ courier_id: '', status: 'pending' as DeliveryStatus });

function openManage(d: DeliveryDTO): void {
    manageTarget.value = d;
    form.courier_id = d.courier ? String(d.courier.id) : '';
    form.status = d.status;
}

function closeManage(): void {
    manageTarget.value = null;
}

async function assignCourier(): Promise<void> {
    const target = manageTarget.value;
    if (!target || savingAssign.value || !form.courier_id) return;
    savingAssign.value = true;
    try {
        const res = await api<{ delivery: DeliveryDTO }>(`/api/v1/deliveries/${target.order_id}/assign`, {
            method: 'POST',
            body: { courier_id: Number(form.courier_id) },
        });
        applyUpdate(res.delivery);
        success('Kurye atandı');
        closeManage();
    } catch (e) {
        danger('Kurye atanamadı', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        savingAssign.value = false;
    }
}

async function updateStatus(): Promise<void> {
    const target = manageTarget.value;
    if (!target || savingStatus.value) return;
    savingStatus.value = true;
    try {
        const res = await api<{ delivery: DeliveryDTO }>(`/api/v1/deliveries/${target.order_id}/status`, {
            method: 'POST',
            body: { status: form.status },
        });
        applyUpdate(res.delivery);
        success('Durum güncellendi');
        closeManage();
    } catch (e) {
        danger('Durum güncellenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        savingStatus.value = false;
    }
}

/** Sunucudan dönen güncel DTO'yu listeye yansıt (order_id benzersiz). */
function applyUpdate(updated: DeliveryDTO): void {
    const idx = deliveries.value.findIndex((d) => d.order_id === updated.order_id);
    if (idx >= 0) deliveries.value.splice(idx, 1, updated);
    else deliveries.value.push(updated);
}
</script>

<template>
    <Head title="Teslimat" />
    <PanelShell title="Teslimat" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">

        <!-- Yetki yok -->
        <div v-if="!canView">
            <EmptyState
                icon="alert-circle"
                title="Erişim yok"
                description="Teslimat panosunu görüntülemek için yetkiniz bulunmuyor."
            />
        </div>

        <div v-else class="flex flex-col gap-4">
            <!-- Araç çubuğu -->
            <div class="flex flex-wrap items-center gap-2">
                <p class="text-sm text-muted">Paket siparişlerin teslimatını takip edin ve kurye atayın.</p>
                <span class="grow" />
                <BaseButton variant="secondary" size="sm" :loading="loading" @click="load">
                    <AppIcon name="package" :size="16" />
                    Yenile
                </BaseButton>
            </div>

            <!-- Yükleniyor -->
            <div v-if="loading" class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-5">
                <BaseSkeleton v-for="i in 5" :key="i" class="h-40 w-full rounded-lg" />
            </div>

            <!-- Boş -->
            <EmptyState
                v-else-if="deliveries.length === 0"
                icon="package"
                title="Teslimat yok"
                description="Paket siparişi geldiğinde burada listelenir."
            />

            <!-- Durum sütunları -->
            <div v-else class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-5">
                <section
                    v-for="col in columns"
                    :key="col.status"
                    class="flex flex-col gap-3 rounded-lg border border-default bg-surface-alt p-3"
                >
                    <div class="flex items-center justify-between px-1">
                        <h2 class="text-sm font-semibold text-body">{{ statusMeta[col.status].label }}</h2>
                        <span class="rounded-full bg-inset px-2 py-0.5 text-xs font-medium text-muted">
                            {{ byStatus(col.status).length }}
                        </span>
                    </div>

                    <p v-if="byStatus(col.status).length === 0" class="px-1 py-4 text-center text-xs text-subtle">
                        Kayıt yok
                    </p>

                    <article
                        v-for="d in byStatus(col.status)"
                        :key="d.id"
                        class="rounded-lg border border-default bg-raised p-3 shadow-(--shadow-card)"
                        :class="d.status === 'delivered' ? 'opacity-70' : ''"
                    >
                        <div class="flex items-start justify-between gap-2">
                            <p class="text-sm font-semibold text-body">
                                {{ d.order.customer_name || 'Müşteri' }}
                            </p>
                            <BaseBadge :variant="statusMeta[d.status].variant" class="shrink-0">
                                {{ statusLabel(d) }}
                            </BaseBadge>
                        </div>

                        <div class="mt-2 flex flex-col gap-1 text-xs text-muted">
                            <a
                                v-if="d.order.customer_phone"
                                :href="`tel:${d.order.customer_phone}`"
                                class="inline-flex items-center gap-1 hover:text-body"
                            >
                                <AppIcon name="user" :size="13" />
                                {{ d.order.customer_phone }}
                            </a>
                            <span v-if="d.address" class="inline-flex items-start gap-1">
                                <AppIcon name="store" :size="13" class="mt-0.5" />
                                <span class="line-clamp-2">{{ d.address }}</span>
                            </span>
                            <span v-if="d.note" class="inline-flex items-start gap-1 text-subtle">
                                <AppIcon name="info" :size="13" class="mt-0.5" />
                                <span class="line-clamp-2">{{ d.note }}</span>
                            </span>
                        </div>

                        <div class="mt-2.5 flex items-center justify-between gap-2">
                            <span class="text-sm font-bold text-body">{{ formatCurrencyMinor(d.order.total_minor) }}</span>
                            <span v-if="d.fee_minor > 0" class="text-xs text-muted">
                                +{{ formatCurrencyMinor(d.fee_minor) }} teslimat
                            </span>
                        </div>

                        <div class="mt-2 flex flex-col gap-1 text-xs text-muted">
                            <span v-if="d.courier" class="inline-flex items-center gap-1">
                                <AppIcon name="user" :size="13" />
                                {{ d.courier.name }}
                            </span>
                            <span v-if="d.delivered_at" class="inline-flex items-center gap-1">
                                <AppIcon name="check-circle" :size="13" />
                                {{ dt(d.delivered_at) }}
                            </span>
                        </div>

                        <div v-if="canManage" class="mt-3 flex items-center justify-end border-t border-default pt-2">
                            <BaseButton size="sm" variant="ghost" @click="openManage(d)">
                                <AppIcon name="settings" :size="15" />
                                Yönet
                            </BaseButton>
                        </div>
                    </article>
                </section>
            </div>
        </div>

        <!-- Yönet modalı: kurye ata + durum güncelle -->
        <BaseModal
            :open="manageTarget !== null"
            :title="manageTarget ? (manageTarget.order.customer_name || 'Teslimat') : 'Teslimat'"
            @close="closeManage"
        >
            <div v-if="manageTarget" class="flex flex-col gap-4">
                <div class="rounded-lg bg-inset px-3 py-2 text-xs text-muted">
                    <span v-if="manageTarget.address" class="block">{{ manageTarget.address }}</span>
                    <span class="font-semibold text-body">{{ formatCurrencyMinor(manageTarget.order.total_minor) }}</span>
                </div>

                <FormField label="Kurye">
                    <div class="flex items-end gap-2">
                        <BaseSelect v-model="form.courier_id" :options="courierOptions" class="flex-1" />
                        <BaseButton :loading="savingAssign" :disabled="!form.courier_id" @click="assignCourier">Ata</BaseButton>
                    </div>
                </FormField>

                <FormField label="Durum">
                    <div class="flex items-end gap-2">
                        <BaseSelect v-model="form.status" :options="statusOptions" class="flex-1" />
                        <BaseButton variant="secondary" :loading="savingStatus" @click="updateStatus">Güncelle</BaseButton>
                    </div>
                </FormField>
            </div>
            <template #footer>
                <BaseButton variant="secondary" @click="closeManage">Kapat</BaseButton>
            </template>
        </BaseModal>
        </div>
        </div>
    </PanelShell>
</template>
