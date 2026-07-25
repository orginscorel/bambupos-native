<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { authFromPage } from '@/types/auth';
import { formatCurrencyMinor, formatLongDate, formatNumber } from '@/lib/format';
import PanelShell from '@/Components/panel/PanelShell.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseSkeleton from '@/Components/ui/BaseSkeleton.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';
import StatTile from './Reports/components/StatTile.vue';
import ChartLine from './Reports/components/ChartLine.vue';
import ChartStackedBar from './Reports/components/ChartStackedBar.vue';
import { pctChange, shortDay, type DayPoint, type PeriodTotals } from './Reports/reports';

/**
 * Panel açılışı — ROL BAZLI (prompt §20): sunucu, kullanıcının izinlerine
 * göre bölüm döndürür (DashboardService). Sahip ciro+kıyas+ödeme kırılımı;
 * şube müdürü operasyon+kasa; garson yalnız operasyon görür. İzinsiz bölüm
 * yanıtta yoktur, ekran da onu hiç çizmez.
 *
 * Veri yoksa DÜRÜST boş durum: uydurma sayı/grafik yasak.
 */

interface DashboardSections {
    today?: {
        date: string;
        current: PeriodTotals;
        yesterday: PeriodTotals;
        last_week: PeriodTotals;
        cancelled: { orders: number; total_minor: number };
        collected_minor: number;
        open_table_minor: number;
        open_table_orders: number;
    };
    trend?: { days: DayPoint[] };
    payment_mix?: {
        total_minor: number;
        tips_minor: number;
        rows: { method: string; label: string; count: number; amount_minor: number }[];
    };
    open_orders?: {
        open_total: number;
        pending_approval: number;
        in_kitchen: number;
        awaiting_payment: number;
        delayed: number;
        delayed_threshold_minutes: number;
    };
    service_requests?: { open: number; rows: { id: number; label: string; table: string | null; age_minutes: number }[] };
    occupancy?: { tables: number; occupied: number; rate: number | null };
    cash?: {
        open_sessions: {
            id: number;
            z_number: number;
            register: string;
            opened_by: string | null;
            opened_at: string;
            expected_cash_minor: number;
        }[];
    };
    adjustments?: {
        cancelled_orders: number;
        cancelled_minor: number;
        discount_minor: number;
        comp_minor: number;
    };
}

const page = usePage();
const auth = computed(() => authFromPage(page.props as Record<string, unknown>));
const today = formatLongDate(new Date());

const loading = ref(true);
const loadError = ref('');
const sections = ref<DashboardSections | null>(null);

let timer: ReturnType<typeof setTimeout> | null = null;

async function load(initial = false): Promise<void> {
    if (initial) loading.value = true;
    try {
        const res = await api<{ sections: DashboardSections }>('/api/v1/reports/dashboard');
        sections.value = res.sections;
        loadError.value = '';
    } catch (e) {
        if (initial) loadError.value = e instanceof ApiError ? e.displayMessage : 'Panel verisi yüklenemedi.';
    } finally {
        loading.value = false;
    }
    // Operasyonel sayılar (açık sipariş, çağrılar, doluluk) 60 sn'de bir tazelenir.
    timer = setTimeout(() => void load(false), 60000);
}

onMounted(() => void load(true));
onUnmounted(() => {
    if (timer !== null) clearTimeout(timer);
});

/* ---- türetimler ---- */
const s = computed(() => sections.value);

const kpis = computed(() => {
    const t = s.value?.today;
    if (!t) return [];
    const list = [
        {
            label: 'Bugünkü ciro (kapanan)',
            value: formatCurrencyMinor(t.current.revenue_minor),
            delta: pctChange(t.current.revenue_minor, t.yesterday.revenue_minor),
            deltaLabel: 'düne göre',
            hint: t.last_week.revenue_minor > 0 ? `geçen hafta bugün: ${formatCurrencyMinor(t.last_week.revenue_minor)}` : 'Yalnız ödenen/borca taşınan adisyonlar',
        },
        {
            label: 'Bugünkü tahsilat',
            value: formatCurrencyMinor(t.collected_minor),
            delta: null,
            deltaLabel: '',
            hint: 'Kasaya giren gerçek para (payments)',
        },
        {
            label: 'Açık masa tutarı',
            value: formatCurrencyMinor(t.open_table_minor),
            delta: null,
            deltaLabel: '',
            hint: t.open_table_orders > 0 ? `${formatNumber(t.open_table_orders)} açık adisyon — Ciro değil (anlık)` : 'Şu an açık adisyon yok',
        },
        {
            label: 'Bugünkü sipariş',
            value: formatNumber(t.current.orders),
            delta: pctChange(t.current.orders, t.yesterday.orders),
            deltaLabel: 'düne göre',
            hint: '',
        },
        {
            label: 'Ortalama sepet',
            value: t.current.orders > 0 ? formatCurrencyMinor(t.current.avg_basket_minor) : '—',
            delta: t.current.orders > 0 ? pctChange(t.current.avg_basket_minor, t.yesterday.avg_basket_minor) : null,
            deltaLabel: 'düne göre',
            hint: t.current.orders === 0 ? 'Bugün kapanan (ödenen) satış yok' : '',
        },
    ];

    const occ = s.value?.occupancy;
    if (occ) {
        list.push({
            label: 'Masa doluluğu',
            value: occ.rate !== null ? `%${occ.rate.toFixed(0)}` : '—',
            delta: null,
            deltaLabel: '',
            hint: `${formatNumber(occ.occupied)} / ${formatNumber(occ.tables)} masa dolu`,
        });
    }

    return list;
});

const trendPoints = computed(() =>
    (s.value?.trend?.days ?? []).map((d) => ({ label: shortDay(d.date), title: d.date, value: d.revenue_minor })),
);
const trendHasData = computed(() => trendPoints.value.some((p) => p.value > 0));

const paymentSegments = computed(() => {
    const rows = s.value?.payment_mix?.rows ?? [];
    const head = rows.slice(0, 4).map((r, i) => ({
        label: r.label,
        value: r.amount_minor,
        colorIndex: i,
        hint: `${formatNumber(r.count)} işlem`,
    }));
    const tail = rows.slice(4);
    if (tail.length > 0) {
        head.push({
            label: 'Diğer',
            value: tail.reduce((sum, r) => sum + r.amount_minor, 0),
            colorIndex: 4,
            hint: `${tail.length} yöntem`,
        });
    }
    return head;
});

/** Hiç bölüm dönmedi mi? (ör. yalnız KDS izinli personel) */
const noSections = computed(
    () => sections.value !== null && Object.keys(sections.value).length === 0,
);

/** Kiracı taze mi? (rapor izni var ama hiç hareket yok) */
const isFresh = computed(() => {
    const t = s.value?.today;
    if (!t) return false;
    return (
        t.current.orders === 0 &&
        t.yesterday.orders === 0 &&
        !trendHasData.value &&
        (s.value?.open_orders?.open_total ?? 0) === 0
    );
});
</script>

<template>
    <Head title="Panel" />

    <PanelShell title="Panel">
        <div class="flex flex-col gap-4">
            <!-- Karşılama -->
            <div class="flex flex-wrap items-end justify-between gap-2">
                <div>
                    <h2 class="text-xl font-semibold text-body">
                        Merhaba{{ auth?.user.first_name ? `, ${auth.user.first_name}` : '' }}
                    </h2>
                    <p class="mt-0.5 text-sm text-muted">{{ today }}</p>
                </div>
                <BaseButton
                    v-if="s?.today"
                    variant="ghost"
                    size="sm"
                    href="/panel/raporlar"
                >
                    <AppIcon name="chart" :size="15" />
                    Tüm raporlar
                </BaseButton>
            </div>

            <!-- Yükleniyor -->
            <div v-if="loading" class="grid grid-cols-2 gap-3 xl:grid-cols-4">
                <div v-for="n in 4" :key="n" class="flex flex-col gap-3 rounded-lg border border-default bg-raised p-4 shadow-card">
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

            <template v-else-if="sections">
                <!-- Rolünde panel bölümü olmayanlar (ör. mutfak): dürüst yönlendirme -->
                <BaseCard v-if="noSections" flush>
                    <EmptyState
                        icon="dashboard"
                        title="Bu ekranda size özel bölüm yok"
                        description="Rolünüz operasyon ekranlarını kullanıyor. Soldaki menüden çalışma ekranınıza (Mutfak, Komi, Siparişler…) geçebilirsiniz."
                    />
                </BaseCard>

                <!-- KPI satırı (reports.view) -->
                <div v-if="kpis.length > 0" class="grid grid-cols-2 gap-3" :class="kpis.length >= 4 ? 'xl:grid-cols-4' : 'xl:grid-cols-3'">
                    <StatTile
                        v-for="k in kpis"
                        :key="k.label"
                        :label="k.label"
                        :value="k.value"
                        :delta="k.delta"
                        :delta-label="k.deltaLabel"
                        :hint="k.hint"
                    />
                </div>

                <!-- Yeni işletme: dürüst boş durum -->
                <BaseCard v-if="isFresh" flush>
                    <EmptyState
                        icon="inbox"
                        title="Henüz hareket yok"
                        description="Siparişler gelmeye başlayınca bugünkü ciro, eğilim ve operasyon durumu burada görünecek."
                    />
                </BaseCard>

                <template v-else>
                    <!-- Operasyon durumu (orders.view) -->
                    <div v-if="s?.open_orders" class="grid gap-4 xl:grid-cols-3">
                        <BaseCard title="Açık adisyonlar" class="xl:col-span-2">
                            <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
                                <div class="flex flex-col gap-1">
                                    <span class="text-2xl font-semibold text-body">{{ formatNumber(s.open_orders.open_total) }}</span>
                                    <span class="text-xs text-muted">Toplam açık</span>
                                </div>
                                <div class="flex flex-col gap-1">
                                    <span class="text-2xl font-semibold text-body">{{ formatNumber(s.open_orders.pending_approval) }}</span>
                                    <span class="text-xs text-muted">Onay bekleyen</span>
                                </div>
                                <div class="flex flex-col gap-1">
                                    <span class="text-2xl font-semibold text-body">{{ formatNumber(s.open_orders.in_kitchen) }}</span>
                                    <span class="text-xs text-muted">Mutfakta</span>
                                </div>
                                <div class="flex flex-col gap-1">
                                    <span
                                        class="text-2xl font-semibold"
                                        :class="s.open_orders.delayed > 0 ? 'text-danger' : 'text-body'"
                                    >
                                        {{ formatNumber(s.open_orders.delayed) }}
                                    </span>
                                    <span class="text-xs text-muted">
                                        Geciken (&gt;{{ s.open_orders.delayed_threshold_minutes }} dk)
                                    </span>
                                </div>
                            </div>
                            <div class="mt-3 border-t border-default pt-3">
                                <BaseButton variant="secondary" size="sm" href="/panel/siparisler">Sipariş panosuna git</BaseButton>
                            </div>
                        </BaseCard>

                        <!-- Servis çağrıları -->
                        <BaseCard v-if="s.service_requests" flush>
                            <template #header>
                                <h2 class="text-sm font-semibold text-body">
                                    Servis çağrıları
                                    <BaseBadge v-if="s.service_requests.open > 0" variant="warning" class="ml-1">
                                        {{ s.service_requests.open }} açık
                                    </BaseBadge>
                                </h2>
                            </template>
                            <ul v-if="s.service_requests.rows.length > 0" class="divide-y divide-default">
                                <li v-for="r in s.service_requests.rows" :key="r.id" class="flex items-center justify-between gap-2 px-4 py-2.5 text-sm">
                                    <span class="text-body">{{ r.label }}</span>
                                    <span class="text-xs whitespace-nowrap text-muted">
                                        {{ r.table ?? '—' }} · {{ r.age_minutes }} dk
                                    </span>
                                </li>
                            </ul>
                            <EmptyState v-else icon="bell" title="Açık çağrı yok" description="Masalardan gelen çağrılar burada görünür." />
                        </BaseCard>
                    </div>

                    <!-- Ciro eğilimi + ödeme kırılımı (reports.view) -->
                    <div v-if="s?.trend || s?.payment_mix" class="grid gap-4 xl:grid-cols-2">
                        <BaseCard v-if="s?.trend" title="Son 14 gün ciro">
                            <ChartLine
                                v-if="trendHasData"
                                :points="trendPoints"
                                money
                                label="Son 14 günün günlük ciro eğilimi"
                            />
                            <EmptyState
                                v-else
                                icon="chart"
                                title="Henüz ciro verisi yok"
                                description="Satış gerçekleştikçe 14 günlük eğilim burada çizilir."
                            />
                        </BaseCard>

                        <BaseCard v-if="s?.payment_mix" title="Bugünkü tahsilat (yöntem kırılımı)">
                            <template v-if="s.payment_mix.total_minor > 0">
                                <p class="mb-2 text-2xl font-semibold text-body">
                                    {{ formatCurrencyMinor(s.payment_mix.total_minor) }}
                                    <span v-if="s.payment_mix.tips_minor > 0" class="text-sm font-normal text-muted">
                                        + {{ formatCurrencyMinor(s.payment_mix.tips_minor) }} bahşiş
                                    </span>
                                </p>
                                <ChartStackedBar
                                    :segments="paymentSegments"
                                    money
                                    label="Bugünkü tahsilatın ödeme yöntemine göre payı"
                                />
                            </template>
                            <EmptyState
                                v-else
                                icon="cart"
                                title="Bugün henüz tahsilat yok"
                                description="Kasadan ödeme alındığında yöntem kırılımı burada görünür."
                            />
                        </BaseCard>
                    </div>

                    <!-- Kasa + iptal/ikram -->
                    <div v-if="s?.cash || s?.adjustments" class="grid gap-4 xl:grid-cols-2">
                        <BaseCard v-if="s?.cash" title="Kasa durumu" flush>
                            <ul v-if="s.cash.open_sessions.length > 0" class="divide-y divide-default">
                                <li
                                    v-for="sess in s.cash.open_sessions"
                                    :key="sess.id"
                                    class="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5 text-sm"
                                >
                                    <div>
                                        <span class="font-medium text-body">{{ sess.register }}</span>
                                        <span class="ml-1 text-xs text-muted">Z#{{ sess.z_number }}</span>
                                        <span v-if="sess.opened_by" class="ml-1 text-xs text-subtle">· {{ sess.opened_by }}</span>
                                    </div>
                                    <div class="text-right">
                                        <span class="font-semibold text-body">{{ formatCurrencyMinor(sess.expected_cash_minor) }}</span>
                                        <span class="ml-1 text-xs text-muted">çekmecede (beklenen)</span>
                                    </div>
                                </li>
                            </ul>
                            <EmptyState
                                v-else
                                icon="cart"
                                title="Açık kasa oturumu yok"
                                description="Kasa açıldığında oturum ve beklenen nakit burada izlenir."
                            />
                        </BaseCard>

                        <BaseCard v-if="s?.adjustments" title="Bugün: iptal / indirim / ikram">
                            <dl class="grid grid-cols-3 gap-3 text-center">
                                <div>
                                    <dt class="text-xs text-muted">İptal</dt>
                                    <dd class="mt-1 text-lg font-semibold text-body">
                                        {{ formatNumber(s.adjustments.cancelled_orders) }}
                                    </dd>
                                    <dd class="text-xs text-subtle">{{ formatCurrencyMinor(s.adjustments.cancelled_minor) }}</dd>
                                </div>
                                <div>
                                    <dt class="text-xs text-muted">İndirim</dt>
                                    <dd class="mt-1 text-lg font-semibold text-body">
                                        {{ formatCurrencyMinor(s.adjustments.discount_minor) }}
                                    </dd>
                                </div>
                                <div>
                                    <dt class="text-xs text-muted">İkram</dt>
                                    <dd class="mt-1 text-lg font-semibold text-body">
                                        {{ formatCurrencyMinor(s.adjustments.comp_minor) }}
                                    </dd>
                                </div>
                            </dl>
                            <p v-if="s.today && s.today.cancelled.orders > 0" class="mt-3 border-t border-default pt-2 text-xs text-warning">
                                Bugün {{ s.today.cancelled.orders }} adisyon iptal edildi
                                ({{ formatCurrencyMinor(s.today.cancelled.total_minor) }}) — nedenleri Raporlar &gt; Operasyon'da.
                            </p>
                        </BaseCard>
                    </div>
                </template>
            </template>
        </div>
    </PanelShell>
</template>
