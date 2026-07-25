<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { authFromPage } from '@/types/auth';
import { formatCurrencyMinor, formatLongDate, formatNumber } from '@/lib/format';
import PanelShell from '@/Components/panel/PanelShell.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';

interface Summary {
    orders: number;
    revenue_minor: number;
    products: number;
    customers: number;
    tables: number;
}

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));
const canViewReports = computed(() => auth.value?.permissions.includes('reports.view') ?? false);

const today = formatLongDate(new Date());

const loading = ref(false);
const loadError = ref('');
const summary = ref<Summary | null>(null);

onMounted(async () => {
    if (!canViewReports.value) return;
    loading.value = true;
    try {
        summary.value = await api<Summary>('/api/v1/reports/summary');
    } catch (e) {
        loadError.value = e instanceof ApiError ? e.displayMessage : 'Özet yüklenemedi.';
    } finally {
        loading.value = false;
    }
});

const cards = computed(() => {
    const s = summary.value;
    if (s === null) return [];
    return [
        { key: 'orders', label: 'Toplam sipariş', value: formatNumber(s.orders), icon: 'orders' },
        { key: 'revenue', label: 'Toplam ciro', value: formatCurrencyMinor(s.revenue_minor), icon: 'chart' },
        { key: 'products', label: 'Menüdeki ürün', value: formatNumber(s.products), icon: 'utensils' },
        { key: 'tables', label: 'Masa', value: formatNumber(s.tables), icon: 'qr-code' },
        { key: 'customers', label: 'Müşteri', value: formatNumber(s.customers), icon: 'users' },
    ];
});

/** Hiç veri yok mu? (yeni işletme) */
const isFresh = computed(() => {
    const s = summary.value;
    return s !== null && s.orders === 0 && s.products === 0 && s.tables === 0 && s.customers === 0;
});
</script>

<template>
    <Head title="Panel" />

    <PanelShell title="Panel">
        <div class="flex flex-col gap-5">
            <!-- Karşılama -->
            <div>
                <h2 class="text-xl font-semibold text-body">
                    Merhaba{{ auth?.user.first_name ? `, ${auth.user.first_name}` : '' }}
                </h2>
                <p class="mt-0.5 text-sm text-muted">{{ today }}</p>
            </div>

            <!-- Özet kartları -->
            <template v-if="canViewReports">
                <div v-if="loading" class="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-5">
                    <div
                        v-for="n in 5"
                        :key="n"
                        class="flex flex-col gap-3 rounded-lg border border-default bg-raised p-4 shadow-card"
                    >
                        <BaseSkeleton size-class="h-4 w-24" />
                        <BaseSkeleton size-class="h-7 w-16" />
                    </div>
                </div>

                <div
                    v-else-if="loadError"
                    class="flex items-start gap-2.5 rounded-md border border-danger-border bg-danger-soft px-3 py-2.5 text-sm text-danger"
                    role="alert"
                >
                    <AppIcon name="alert-circle" :size="17" class="mt-0.5" />
                    <p>{{ loadError }}</p>
                </div>

                <div v-else-if="summary" class="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-5">
                    <div
                        v-for="card in cards"
                        :key="card.key"
                        class="flex flex-col gap-2 rounded-lg border border-default bg-raised p-4 shadow-card"
                    >
                        <div class="flex items-center gap-2 text-muted">
                            <AppIcon :name="card.icon" :size="16" />
                            <span class="text-xs font-medium">{{ card.label }}</span>
                        </div>
                        <span class="text-2xl font-semibold text-body">{{ card.value }}</span>
                    </div>
                </div>
            </template>

            <!-- Yeni işletme: dürüst boş durum, uydurma sayı yok -->
            <BaseCard v-if="isFresh" flush>
                <EmptyState
                    icon="inbox"
                    title="Henüz veri yok"
                    description="İşletmeniz yeni kurulmuş görünüyor. Menü, masa ve siparişler eklendikçe özet burada görünecek."
                />
            </BaseCard>

            <!-- Bugünkü hareketler -->
            <BaseCard v-if="canViewReports && summary && !isFresh" title="Son hareketler" flush>
                <EmptyState
                    icon="orders"
                    title="Bugün henüz hareket yok"
                    description="Yeni siparişler geldiğinde burada listelenecek."
                />
            </BaseCard>

            <!-- Rapor izni olmayan roller için dürüst mesaj -->
            <BaseCard v-if="!canViewReports" flush>
                <EmptyState
                    icon="chart"
                    title="Özet raporlarına erişiminiz yok"
                    description="Bu alan için 'Raporlar: Görüntüle' yetkisi gerekir. Gerekliyse işletme sahibinizle iletişime geçin."
                />
            </BaseCard>
        </div>
    </PanelShell>
</template>
