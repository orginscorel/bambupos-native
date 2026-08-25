<script setup lang="ts">
/**
 * Portal "Teslimatlarım" — kuryenin kendine atanan aktif teslimatları.
 *
 * Mobil-öncelikli p-card listesi: her kartta müşteri, adres, tutar, durum;
 * "Yola çıktım" (on_the_way) ve "Teslim ettim" (delivered) aksiyon butonları
 * (≥44px). Portal görsel kimliği (p-card / p-tile-* — app.css .portal-root).
 * Erişim `delivery.deliver` iznine sahip kullanıcıya açıktır (backend zorlar).
 */
import { computed, onMounted, ref } from 'vue';
import { api, ApiError } from '@/lib/http';
import { formatCurrencyMinor } from '@/lib/format';
import { useToast } from '@/composables/useToast';
import PortalLayout from '@/Layouts/PortalLayout.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';

type DeliveryStatus = 'pending' | 'assigned' | 'on_the_way' | 'delivered' | 'failed';

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
}

const { success, danger } = useToast();

const loading = ref(true);
const busyId = ref<number | null>(null);
const deliveries = ref<DeliveryDTO[]>([]);

const statusMeta: Record<DeliveryStatus, { label: string; fg: string; bg: string }> = {
    pending: { label: 'Bekliyor', fg: 'var(--color-muted)', bg: 'var(--color-inset)' },
    assigned: { label: 'Atandı', fg: 'var(--p-sky)', bg: 'var(--p-sky-soft)' },
    on_the_way: { label: 'Yolda', fg: 'var(--p-indigo)', bg: 'var(--p-indigo-soft)' },
    delivered: { label: 'Teslim', fg: 'var(--p-emerald)', bg: 'var(--p-emerald-soft)' },
    failed: { label: 'Başarısız', fg: 'var(--p-rose)', bg: 'var(--p-rose-soft)' },
};

function statusLabel(d: DeliveryDTO): string {
    return d.status_label ?? statusMeta[d.status]?.label ?? d.status;
}

async function load(): Promise<void> {
    loading.value = true;
    try {
        const res = await api<DeliveriesResponse>('/api/v1/portal/deliveries');
        deliveries.value = res.deliveries ?? [];
    } catch (e) {
        danger('Teslimatlar yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        loading.value = false;
    }
}

onMounted(() => void load());

async function setStatus(d: DeliveryDTO, status: 'on_the_way' | 'delivered'): Promise<void> {
    if (busyId.value !== null) return;
    busyId.value = d.id;
    try {
        const res = await api<{ delivery: DeliveryDTO }>(`/api/v1/portal/deliveries/${d.id}/status`, {
            method: 'POST',
            body: { status },
        });
        const idx = deliveries.value.findIndex((x) => x.id === d.id);
        if (idx >= 0) deliveries.value.splice(idx, 1, res.delivery);
        success(status === 'delivered' ? 'Teslim edildi 🎉' : 'Yola çıkıldı');
    } catch (e) {
        danger('İşlem tamamlanamadı', e instanceof ApiError ? e.displayMessage : 'Lütfen tekrar deneyin.');
    } finally {
        busyId.value = null;
    }
}

const heading = 'Teslimatlarım';
const activeCount = computed(() => deliveries.value.filter((d) => d.status !== 'delivered' && d.status !== 'failed').length);
const subtitle = computed(() => (activeCount.value ? `${activeCount.value} aktif teslimat` : 'Atanmış teslimat yok'));
</script>

<template>
    <PortalLayout title="Teslimatlarım" active="deliveries" :heading="heading" :subtitle="subtitle">
        <!-- Yükleniyor -->
        <div v-if="loading" class="flex flex-col gap-3">
            <div v-for="i in 3" :key="i" class="p-card h-32 animate-pulse p-4" />
        </div>

        <!-- Boş durum -->
        <div v-else-if="deliveries.length === 0" class="p-card flex flex-col items-center gap-3 px-4 py-12 text-center">
            <span class="flex size-14 items-center justify-center rounded-full bg-(--p-emerald-soft) text-(--p-emerald)">
                <AppIcon name="package" :size="26" />
            </span>
            <p class="text-sm font-medium text-muted">Atanmış teslimat yok</p>
        </div>

        <!-- Teslimat kartları -->
        <div v-else class="flex flex-col gap-3">
            <article v-for="d in deliveries" :key="d.id" class="p-card p-4">
                <div class="flex items-start justify-between gap-2">
                    <div class="min-w-0 flex-1">
                        <p class="truncate text-base font-bold text-body">{{ d.order.customer_name || 'Müşteri' }}</p>
                        <a
                            v-if="d.order.customer_phone"
                            :href="`tel:${d.order.customer_phone}`"
                            class="mt-0.5 inline-flex items-center gap-1 text-sm font-medium text-(--p-indigo)"
                        >
                            <AppIcon name="user" :size="14" />
                            {{ d.order.customer_phone }}
                        </a>
                    </div>
                    <span
                        class="shrink-0 rounded-full px-2.5 py-1 text-xs font-bold"
                        :style="{ color: statusMeta[d.status].fg, background: statusMeta[d.status].bg }"
                    >
                        {{ statusLabel(d) }}
                    </span>
                </div>

                <div v-if="d.address" class="mt-3 flex items-start gap-2 rounded-xl bg-(--color-inset) px-3 py-2.5">
                    <AppIcon name="store" :size="16" class="mt-0.5 shrink-0 text-muted" />
                    <span class="text-sm text-body">{{ d.address }}</span>
                </div>
                <p v-if="d.note" class="mt-2 flex items-start gap-2 px-1 text-xs text-muted">
                    <AppIcon name="info" :size="14" class="mt-0.5 shrink-0" />
                    {{ d.note }}
                </p>

                <div class="mt-3 flex items-center justify-between gap-2">
                    <span class="text-lg font-extrabold text-body">{{ formatCurrencyMinor(d.order.total_minor) }}</span>
                    <span v-if="d.fee_minor > 0" class="text-xs font-medium text-muted">
                        +{{ formatCurrencyMinor(d.fee_minor) }} teslimat
                    </span>
                </div>

                <!-- Aksiyonlar -->
                <div
                    v-if="d.status === 'assigned' || d.status === 'on_the_way'"
                    class="mt-4 grid gap-2"
                    :class="d.status === 'assigned' ? 'grid-cols-2' : 'grid-cols-1'"
                >
                    <button
                        v-if="d.status === 'assigned'"
                        type="button"
                        class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl bg-(--p-indigo-soft) px-4 text-sm font-semibold text-(--p-indigo) transition active:scale-[0.98] disabled:opacity-55"
                        :disabled="busyId !== null"
                        @click="setStatus(d, 'on_the_way')"
                    >
                        <AppIcon name="cart" :size="18" />
                        Yola çıktım
                    </button>
                    <button
                        type="button"
                        class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl bg-(--p-emerald) px-4 text-sm font-semibold text-white transition active:scale-[0.98] disabled:opacity-55"
                        :disabled="busyId !== null"
                        @click="setStatus(d, 'delivered')"
                    >
                        <AppIcon name="check" :size="18" />
                        Teslim ettim
                    </button>
                </div>
            </article>
        </div>
    </PortalLayout>
</template>
