<script setup lang="ts">
import { computed, toRef } from 'vue';
import { formatCurrencyMinor, formatNumber } from '@/lib/format';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import ExportButtons from '../components/ExportButtons.vue';
import StatTile from '../components/StatTile.vue';
import { useReport, type ReceivablesReport, type ReconciliationSummary, type ReportFilterState } from '../reports';

/**
 * POS / nakit / sistem mutabakatı: "kasada ne olmalı, ne var, POS ne
 * diyor" tek ekranda. Ödeme defteri (payments, TEK DOĞRULUK KAYNAĞI)
 * nakit/POS/diğer olarak kırılır ve sistemin adisyon defteriyle
 * (bu aralıkta KAPANAN adisyonların paid_minor toplamı) kıyaslanır.
 * Kasa sayımı varsa (Payments > kasa oturumları) beklenen/sayılan nakit
 * farkı da ayrıca gösterilir. Kasa Z raporunun YERİNE GEÇMEZ.
 */
const props = defineProps<{ filters: ReportFilterState }>();
const filters = toRef(props, 'filters');

const r = useReport<ReconciliationSummary>('finance-reconciliation', filters);
const receivables = useReport<ReceivablesReport>('ops-open-receivables', filters);
const d = computed(() => r.data.value);

const hasPayments = computed(() => (d.value?.payments_total_minor ?? 0) > 0 || (d.value?.orders_closed_count ?? 0) > 0);

/** Tahsil edilen + açık cari ≈ sistemin kayıtlı satışı (yalnız cari modülü aktifse anlamlı). */
const grandTotalMinor = computed(() => {
    if (d.value === null) return null;
    const rec = receivables.data.value;
    if (!rec?.available || rec.total_minor === null) return null;
    return d.value.payments_total_minor + rec.total_minor;
});

const diffIsZero = computed(() => (d.value?.difference_minor ?? 0) === 0);
const cashDiffIsZero = computed(() => (d.value?.cash_sessions_difference_minor ?? 0) === 0);
</script>

<template>
    <div class="flex flex-col gap-4">
        <p v-if="r.error.value" class="text-sm text-danger">{{ r.error.value }}</p>

        <div class="flex items-center justify-between">
            <p class="text-xs text-subtle">
                Seçilen aralık: <span class="font-medium text-muted">{{ filters.from }} – {{ filters.to }}</span>
            </p>
            <ExportButtons report="finance-reconciliation" :filters="filters" />
        </div>

        <EmptyState
            v-if="d && !hasPayments"
            icon="cart"
            title="Bu aralıkta tahsilat yok"
            description="Kasadan ödeme alındıkça nakit/POS/sistem kıyaslaması burada oluşur."
        />

        <template v-else-if="d">
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
                <StatTile label="Nakit (kasada olmalı)" :value="formatCurrencyMinor(d.cash_minor)" :hint="`${formatNumber(d.cash_count)} işlem`" />
                <StatTile label="POS / Kart" :value="formatCurrencyMinor(d.pos_minor)" :hint="`${formatNumber(d.pos_count)} işlem`" />
                <StatTile
                    label="Diğer (yemek kartı/havale/QR/online…)"
                    :value="formatCurrencyMinor(d.other_minor)"
                    :hint="`${formatNumber(d.other_count)} işlem`"
                />
            </div>

            <BaseCard title="Ödeme defteri vs sistem adisyon toplamı" flush>
                <div class="grid grid-cols-1 divide-y divide-default sm:grid-cols-3 sm:divide-x sm:divide-y-0">
                    <div class="px-4 py-3">
                        <p class="text-xs text-muted">Ödeme defteri toplamı (nakit + POS + diğer)</p>
                        <p class="mt-1 text-xl font-semibold text-body">{{ formatCurrencyMinor(d.payments_total_minor) }}</p>
                    </div>
                    <div class="px-4 py-3">
                        <p class="text-xs text-muted">Sistemdeki adisyon toplamı (kapanan {{ formatNumber(d.orders_closed_count) }} adisyon)</p>
                        <p class="mt-1 text-xl font-semibold text-body">{{ formatCurrencyMinor(d.orders_paid_minor) }}</p>
                    </div>
                    <div class="px-4 py-3">
                        <p class="text-xs text-muted">Fark</p>
                        <p class="mt-1 flex items-center gap-2 text-xl font-semibold" :class="diffIsZero ? 'text-body' : 'text-danger'">
                            {{ formatCurrencyMinor(Math.abs(d.difference_minor)) }}
                            <BaseBadge :variant="diffIsZero ? 'success' : 'danger'">
                                {{ diffIsZero ? 'Tutuyor' : d.difference_minor > 0 ? 'Defter fazla' : 'Sistem fazla' }}
                            </BaseBadge>
                        </p>
                    </div>
                </div>
                <p class="border-t border-default px-4 py-2 text-xs text-subtle">
                    Ödeme defteri ödeme ANINA (paid_at), sistem toplamı adisyonun KAPANIŞ anına (closed_at) göre
                    hesaplanır — dönem sınırına denk gelen birkaç kuruşluk fark beklenebilir. Büyük/sürekli fark
                    gerçek bir tutarsızlığa işaret eder. Yöntem bazında tam kırılım: Finans &gt; Ödeme yöntemleri.
                </p>
            </BaseCard>

            <BaseCard title="Kasa sayımı: beklenen vs sayılan nakit" flush>
                <template v-if="d.has_cash_sessions">
                    <div class="grid grid-cols-1 divide-y divide-default sm:grid-cols-3 sm:divide-x sm:divide-y-0">
                        <div class="px-4 py-3">
                            <p class="text-xs text-muted">Beklenen nakit ({{ formatNumber(d.cash_sessions_closed_count) }} kapanan oturum)</p>
                            <p class="mt-1 text-xl font-semibold text-body">{{ formatCurrencyMinor(d.cash_sessions_expected_minor) }}</p>
                        </div>
                        <div class="px-4 py-3">
                            <p class="text-xs text-muted">Sayılan nakit</p>
                            <p class="mt-1 text-xl font-semibold text-body">{{ formatCurrencyMinor(d.cash_sessions_counted_minor) }}</p>
                        </div>
                        <div class="px-4 py-3">
                            <p class="text-xs text-muted">Kasa farkı</p>
                            <p class="mt-1 flex items-center gap-2 text-xl font-semibold" :class="cashDiffIsZero ? 'text-body' : 'text-danger'">
                                {{ formatCurrencyMinor(Math.abs(d.cash_sessions_difference_minor)) }}
                                <BaseBadge :variant="cashDiffIsZero ? 'success' : 'danger'">
                                    {{ cashDiffIsZero ? 'Tutuyor' : d.cash_sessions_difference_minor > 0 ? 'Fazla çıktı' : 'Eksik çıktı' }}
                                </BaseBadge>
                            </p>
                        </div>
                    </div>
                    <p class="border-t border-default px-4 py-2 text-xs text-subtle">
                        Oturum bazında ayrıntı (Z no, açan, açılış/kapanış): Finans &gt; Kasa oturumları.
                    </p>
                </template>
                <EmptyState
                    v-else
                    icon="cart"
                    title="Bu aralıkta kapanmış (Z alınmış) kasa oturumu yok"
                    description="Kasa açılıp Z ile kapatıldığında beklenen/sayılan nakit farkı burada görünür."
                />
            </BaseCard>

            <BaseCard title="Tahsil edilen + açık cari = tam tablo" flush>
                <template v-if="receivables.data.value?.available">
                    <div class="grid grid-cols-1 divide-y divide-default sm:grid-cols-3 sm:divide-x sm:divide-y-0">
                        <div class="px-4 py-3">
                            <p class="text-xs text-muted">Tahsil edilen (ödeme defteri)</p>
                            <p class="mt-1 text-xl font-semibold text-body">{{ formatCurrencyMinor(d.payments_total_minor) }}</p>
                        </div>
                        <div class="px-4 py-3">
                            <p class="text-xs text-muted">Açık cari bakiyesi (güncel, {{ formatNumber(receivables.data.value.count) }} hesap)</p>
                            <p class="mt-1 text-xl font-semibold text-body">
                                {{ formatCurrencyMinor(receivables.data.value.total_minor ?? 0) }}
                            </p>
                        </div>
                        <div class="px-4 py-3">
                            <p class="text-xs text-muted">Toplam (tahsil + açık cari)</p>
                            <p class="mt-1 text-xl font-semibold text-body">
                                {{ grandTotalMinor !== null ? formatCurrencyMinor(grandTotalMinor) : '—' }}
                            </p>
                        </div>
                    </div>
                    <p class="border-t border-default px-4 py-2 text-xs text-subtle">
                        Açık cari bakiyesi GÜNCEL toplamdır (dönemsel değil, cariye özgü); bu yüzden toplam yalnız
                        yaklaşık bir "tam tablo" göstergesidir, birebir dönem cirosuyla eşleşmesi beklenmez.
                    </p>
                </template>
                <EmptyState
                    v-else
                    icon="user"
                    title="Cari modülü henüz aktif değil"
                    description="Cari hesap (borç takibi) modülü tamamlanınca tahsil edilen + açık cari toplamı burada görünecek."
                />
            </BaseCard>
        </template>
    </div>
</template>
