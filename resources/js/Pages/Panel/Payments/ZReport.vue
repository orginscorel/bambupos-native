<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { Head, usePage } from '@inertiajs/vue3';
import { ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import { fetchSessionReport, money, type SessionReport, type SessionRow } from './payments';

/**
 * Z RAPORU (kapalı oturum: dondurulmuş) / X RAPORU (açık: canlı).
 * Yazdırılabilir: tarayıcı yazdırması fiş görünümüne yakın sadeliktedir.
 */
const page = usePage();
const sessionId = Number((page.props as Record<string, unknown>).sessionId ?? 0);
const { danger } = useToast();

const session = ref<SessionRow | null>(null);
const report = ref<SessionReport | null>(null);
const loading = ref(true);

onMounted(async () => {
    try {
        const res = await fetchSessionReport(sessionId);
        session.value = res.session;
        report.value = res.report;
    } catch (e) {
        danger('Rapor yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
});

const dt = (iso: string | null) => (iso ? new Date(iso).toLocaleString('tr-TR') : '—');
const signed = (v: number) => `${v > 0 ? '+' : v < 0 ? '−' : ''}${money(Math.abs(v))}`;
const print = () => window.print();
</script>

<template>
    <Head :title="session ? `Z Raporu #${session.z_number}` : 'Z Raporu'" />
    <PanelShell title="Z Raporu" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">

        <p v-if="loading" class="p-6 text-center text-sm text-muted">Yükleniyor…</p>
        <EmptyState v-else-if="!report || !session" title="Rapor bulunamadı" icon="inbox" />

        <div v-else class="mx-auto flex w-full max-w-2xl flex-col gap-4 print:max-w-none">
            <div class="flex items-center justify-between gap-2 print:hidden">
                <BaseButton variant="secondary" size="sm" href="/panel/kasa/yonetim">← Kasa yönetimi</BaseButton>
                <BaseButton size="sm" @click="print">Yazdır</BaseButton>
            </div>

            <BaseCard>
                <div class="flex flex-col gap-4">
                    <header class="flex flex-wrap items-center justify-between gap-2 border-b border-default pb-3">
                        <div>
                            <h2 class="text-lg font-bold text-body">
                                {{ session.status === 'closed' ? 'Z RAPORU' : 'X RAPORU (ara — oturum açık)' }}
                                · #{{ session.z_number }}
                            </h2>
                            <p class="text-sm text-muted">{{ session.register_name ?? 'Kasa' }}</p>
                        </div>
                        <BaseBadge :variant="session.status === 'closed' ? 'neutral' : 'warning'" no-icon>
                            {{ session.status === 'closed' ? 'Kapalı (dondurulmuş)' : 'Açık (canlı)' }}
                        </BaseBadge>
                    </header>

                    <dl class="grid gap-1 text-sm">
                        <div class="flex justify-between"><dt class="text-muted">Açılış</dt><dd>{{ dt(session.opened_at) }} · {{ session.opened_by ?? '—' }}</dd></div>
                        <div class="flex justify-between"><dt class="text-muted">Kapanış</dt><dd>{{ dt(session.closed_at) }} · {{ session.closed_by ?? '—' }}</dd></div>
                    </dl>

                    <!-- Nakit mutabakatı -->
                    <section>
                        <h3 class="mb-1 text-sm font-semibold uppercase text-subtle">Nakit mutabakatı</h3>
                        <dl class="grid gap-1 text-sm">
                            <div class="flex justify-between"><dt class="text-muted">Açılış kasası</dt><dd class="tabular-nums">{{ money(report.opening_float_minor) }} ₺</dd></div>
                            <div class="flex justify-between"><dt class="text-muted">Beklenen nakit</dt><dd class="tabular-nums">{{ money(report.expected_cash_minor) }} ₺</dd></div>
                            <div class="flex justify-between"><dt class="text-muted">Sayılan nakit</dt><dd class="tabular-nums">{{ report.counted_cash_minor !== null ? money(report.counted_cash_minor) + ' ₺' : '—' }}</dd></div>
                            <div
                                class="flex justify-between font-semibold"
                                :class="(report.difference_minor ?? 0) === 0 ? 'text-success' : 'text-danger'"
                            >
                                <dt>Fark (sayılan − beklenen)</dt>
                                <dd class="tabular-nums">{{ report.difference_minor !== null ? signed(report.difference_minor) + ' ₺' : '—' }}</dd>
                            </div>
                        </dl>
                        <p v-if="session.closing_note" class="mt-1 text-xs text-muted">Not: {{ session.closing_note }}</p>
                    </section>

                    <!-- Yöntem kırılımı -->
                    <section>
                        <h3 class="mb-1 text-sm font-semibold uppercase text-subtle">Ödeme yöntemi kırılımı</h3>
                        <div class="overflow-x-auto">
                            <table class="w-full text-sm">
                                <thead>
                                    <tr class="border-b border-default text-left text-xs text-muted">
                                        <th class="py-1 font-medium">Yöntem</th>
                                        <th class="py-1 text-right font-medium">Adet</th>
                                        <th class="py-1 text-right font-medium">Tahsilat</th>
                                        <th class="py-1 text-right font-medium">İade</th>
                                        <th class="py-1 text-right font-medium">Net</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <tr v-for="m in report.by_method" :key="m.method" class="border-b border-default/50">
                                        <td class="py-1">{{ m.label }}</td>
                                        <td class="py-1 text-right tabular-nums">{{ m.count }}</td>
                                        <td class="py-1 text-right tabular-nums">{{ money(m.collected_minor) }}</td>
                                        <td class="py-1 text-right tabular-nums">{{ m.refunded_minor > 0 ? '−' + money(m.refunded_minor) : '—' }}</td>
                                        <td class="py-1 text-right font-semibold tabular-nums">{{ money(m.net_minor) }}</td>
                                    </tr>
                                    <tr v-if="report.by_method.length === 0">
                                        <td colspan="5" class="py-2 text-center text-muted">Bu oturumda ödeme yok</td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>
                    </section>

                    <!-- Toplamlar -->
                    <section>
                        <h3 class="mb-1 text-sm font-semibold uppercase text-subtle">Toplamlar</h3>
                        <dl class="grid gap-1 text-sm">
                            <div class="flex justify-between"><dt class="text-muted">Tahsilat ({{ report.payments_count }})</dt><dd class="tabular-nums">{{ money(report.payments_total_minor) }} ₺</dd></div>
                            <div class="flex justify-between"><dt class="text-muted">İade ({{ report.refunds_count }})</dt><dd class="tabular-nums">{{ report.refunds_total_minor > 0 ? '−' + money(report.refunds_total_minor) : '0,00' }} ₺</dd></div>
                            <div class="flex justify-between"><dt class="text-muted">İptal/void ({{ report.voids_count }})</dt><dd class="tabular-nums">{{ money(report.voids_total_minor) }} ₺</dd></div>
                            <div class="flex justify-between"><dt class="text-muted">Bahşiş</dt><dd class="tabular-nums">{{ money(report.tips_total_minor) }} ₺</dd></div>
                            <div class="flex justify-between"><dt class="text-muted">İndirim</dt><dd class="tabular-nums">{{ money(report.discounts_total_minor) }} ₺</dd></div>
                            <div class="flex justify-between"><dt class="text-muted">İkram</dt><dd class="tabular-nums">{{ money(report.comps_total_minor) }} ₺</dd></div>
                            <div class="flex justify-between"><dt class="text-muted">Servis bedeli</dt><dd class="tabular-nums">{{ money(report.service_charges_total_minor) }} ₺</dd></div>
                        </dl>
                    </section>

                    <!-- Hareket özeti -->
                    <section>
                        <h3 class="mb-1 text-sm font-semibold uppercase text-subtle">Kasa hareketleri</h3>
                        <dl class="grid gap-1 text-sm">
                            <div v-for="m in report.movements" :key="m.type" class="flex justify-between">
                                <dt class="text-muted">{{ m.label }} ({{ m.count }})</dt>
                                <dd class="tabular-nums">{{ m.direction === 'in' ? '+' : '−' }}{{ money(m.total_minor) }} ₺</dd>
                            </div>
                        </dl>
                    </section>
                </div>
            </BaseCard>
        </div>
        </div>
        </div>
    </PanelShell>
</template>
