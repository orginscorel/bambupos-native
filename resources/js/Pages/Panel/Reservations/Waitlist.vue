<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import FormField from '@/Components/ui/FormField.vue';
import ReservationsNav from './ReservationsNav.vue';
import { type WaitlistRow } from './reservations';

/**
 * Bekleme listesi: sıradaki müşteriler + tahmini bekleme süresi.
 * "Çağır" müşteri-geldi bildirimidir (masanız hazır); "Masaya al" kapatır.
 */
const page = usePage();
const { success, danger } = useToast();

const auth = computed(() => (page.props as Record<string, unknown>).auth as {
    permissions?: string[];
    activeBranchId?: number | null;
} | null);

const permissions = computed<string[]>(() => auth.value?.permissions ?? []);
const branchId = computed<number | null>(() => auth.value?.activeBranchId ?? null);
const canCreate = computed(() => permissions.value.includes('reservations.create'));
const canUpdate = computed(() => permissions.value.includes('reservations.update'));

const loading = ref(true);
const rows = ref<WaitlistRow[]>([]);
const openCount = ref(0);

async function load(): Promise<void> {
    loading.value = true;
    try {
        const res = await api<{ waitlist: WaitlistRow[]; open_count: number }>('/api/v1/reservations/waitlist');
        rows.value = res.waitlist;
        openCount.value = res.open_count;
    } catch (e) {
        danger('Bekleme listesi yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

/* ---- Yeni girdi ---- */
const form = ref({ customer_name: '', customer_phone: '', party_size: '2', quoted_wait_minutes: '', note: '' });
const formBusy = ref(false);
const errors = ref<Record<string, string>>({});

async function add(): Promise<void> {
    if (!branchId.value) return;
    formBusy.value = true;
    errors.value = {};
    try {
        await api('/api/v1/reservations/waitlist', {
            method: 'POST',
            body: {
                branch_id: branchId.value,
                customer_name: form.value.customer_name,
                customer_phone: form.value.customer_phone || null,
                party_size: Number(form.value.party_size),
                quoted_wait_minutes: form.value.quoted_wait_minutes ? Number(form.value.quoted_wait_minutes) : null,
                note: form.value.note || null,
            },
        });
        success('Bekleme listesine eklendi');
        form.value = { customer_name: '', customer_phone: '', party_size: '2', quoted_wait_minutes: '', note: '' };
        void load();
    } catch (e) {
        if (e instanceof ApiError) {
            for (const [field, msgs] of Object.entries(e.errors)) errors.value[field] = msgs[0] ?? '';
            danger('Eklenemedi', e.displayMessage);
        }
    } finally {
        formBusy.value = false;
    }
}

/* ---- Durum ---- */
const busyId = ref<number | null>(null);

async function setStatus(row: WaitlistRow, status: string): Promise<void> {
    busyId.value = row.id;
    try {
        await api(`/api/v1/reservations/waitlist/${row.id}/status`, { method: 'POST', body: { status } });
        success(
            status === 'notified'
                ? 'Müşteri çağrıldı (masanız hazır bildirimi)'
                : status === 'seated'
                    ? 'Müşteri masaya alındı'
                    : 'Durum güncellendi',
        );
        void load();
    } catch (e) {
        danger('Güncellenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen bir hata oluştu.');
    } finally {
        busyId.value = null;
    }
}

function waitingFor(row: WaitlistRow): string {
    if (!row.waiting_since) return '';
    const mins = Math.max(0, Math.round((Date.now() - new Date(row.waiting_since).getTime()) / 60000));
    return `${mins} dk önce yazıldı`;
}
</script>

<template>
    <Head title="Bekleme Listesi" />
    <PanelShell title="Bekleme Listesi">
        <ReservationsNav active="waitlist" />

        <div class="flex flex-col gap-4">
            <!-- Yeni girdi -->
            <BaseCard v-if="canCreate" title="Listeye ekle">
                <form class="flex flex-wrap items-end gap-3" @submit.prevent="add">
                    <div class="w-full sm:w-56">
                        <FormField label="Müşteri adı" required :error="errors.customer_name">
                            <BaseInput v-model="form.customer_name" placeholder="Ad Soyad" :invalid="!!errors.customer_name" />
                        </FormField>
                    </div>
                    <div class="w-40">
                        <FormField label="Telefon" :error="errors.customer_phone">
                            <BaseInput v-model="form.customer_phone" inputmode="tel" placeholder="05xx…" />
                        </FormField>
                    </div>
                    <div class="w-24">
                        <FormField label="Kişi" required :error="errors.party_size">
                            <BaseInput v-model="form.party_size" type="number" inputmode="numeric" />
                        </FormField>
                    </div>
                    <div class="w-32">
                        <FormField label="Tahmin (dk)" hint="Boş = otomatik" :error="errors.quoted_wait_minutes">
                            <BaseInput v-model="form.quoted_wait_minutes" type="number" inputmode="numeric" placeholder="ör. 20" />
                        </FormField>
                    </div>
                    <div class="w-full sm:w-64">
                        <FormField label="Not">
                            <BaseInput v-model="form.note" placeholder="ör. bebek arabası var" />
                        </FormField>
                    </div>
                    <BaseButton type="submit" :loading="formBusy" :disabled="!form.customer_name.trim()">
                        <AppIcon name="plus" :size="16" />
                        Ekle
                    </BaseButton>
                </form>
            </BaseCard>

            <!-- Liste -->
            <BaseCard flush>
                <template #header>
                    <h2 class="text-sm font-semibold text-body">Sıradakiler</h2>
                </template>
                <template #actions>
                    <BaseBadge variant="warning">{{ openCount }} bekleyen</BaseBadge>
                </template>

                <div v-if="loading" class="p-8 text-center text-sm text-muted">Yükleniyor…</div>
                <EmptyState
                    v-else-if="rows.length === 0"
                    title="Bekleyen yok"
                    description="Doluluk arttığında müşterileri buraya ekleyip sırayla masaya alabilirsiniz."
                    icon="inbox"
                />
                <ul v-else class="flex flex-col">
                    <li
                        v-for="row in rows"
                        :key="row.id"
                        class="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-default px-4 py-3 last:border-b-0"
                    >
                        <span
                            class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm font-semibold"
                            :class="row.position ? 'bg-primary-soft text-primary' : 'bg-inset text-muted'"
                        >
                            {{ row.position ?? '—' }}
                        </span>

                        <div class="min-w-0 grow">
                            <div class="flex flex-wrap items-center gap-2">
                                <span class="font-medium text-body">{{ row.customer_name }}</span>
                                <span class="text-sm text-muted">{{ row.party_size }} kişi</span>
                                <BaseBadge :variant="row.status_variant">
                                    <AppIcon :name="row.status_icon" :size="12" />
                                    {{ row.status_label }}
                                </BaseBadge>
                                <span v-if="row.estimated_wait_minutes !== null" class="text-sm text-muted">
                                    ~{{ row.estimated_wait_minutes }} dk bekleme
                                </span>
                            </div>
                            <div class="mt-0.5 flex flex-wrap gap-x-3 text-xs text-muted">
                                <span v-if="row.customer_phone">{{ row.customer_phone }}</span>
                                <span>{{ waitingFor(row) }}</span>
                                <span v-if="row.note" class="italic">“{{ row.note }}”</span>
                            </div>
                        </div>

                        <div v-if="canUpdate" class="flex items-center gap-1">
                            <BaseButton
                                v-if="row.status === 'waiting'"
                                size="sm"
                                variant="secondary"
                                :loading="busyId === row.id"
                                @click="setStatus(row, 'notified')"
                            >
                                <AppIcon name="bell" :size="14" />
                                Çağır
                            </BaseButton>
                            <BaseButton
                                v-if="row.status === 'waiting' || row.status === 'notified'"
                                size="sm"
                                :loading="busyId === row.id"
                                @click="setStatus(row, 'seated')"
                            >
                                <AppIcon name="users" :size="14" />
                                Masaya al
                            </BaseButton>
                            <BaseButton
                                v-if="row.status === 'notified'"
                                size="sm"
                                variant="ghost"
                                :loading="busyId === row.id"
                                @click="setStatus(row, 'expired')"
                            >
                                Gelmedi
                            </BaseButton>
                            <BaseButton
                                v-if="row.status === 'waiting'"
                                size="sm"
                                variant="ghost"
                                :loading="busyId === row.id"
                                @click="setStatus(row, 'cancelled')"
                            >
                                Vazgeçti
                            </BaseButton>
                        </div>
                    </li>
                </ul>
            </BaseCard>
        </div>
    </PanelShell>
</template>
