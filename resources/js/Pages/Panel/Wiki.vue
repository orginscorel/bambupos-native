<script setup lang="ts">
import { Head } from '@inertiajs/vue3';
import PanelShell from '@/Components/panel/PanelShell.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import AppIcon from '@/Components/ui/AppIcon.vue';

/**
 * Panel > Nasıl Çalışır (statik anlatım sayfası — canlı veri YOK).
 *
 * Amaç: kasa↔sipariş↔masa↔adisyon↔cari ilişkisini ve Ciro/Tahsilat/
 * Açık masa/Açık borç ayrımını (2026-07-23 düzeltmesi) TEK ekranda,
 * herkesin anlayacağı dille anlatmak. İzin gerektirmez (herhangi bir
 * işletmeye özel veri taşımaz) — /panel/surum-notlari ile aynı desen.
 */

interface FlowStep {
    key: string;
    icon: string;
    variant: 'neutral' | 'primary' | 'success' | 'warning' | 'danger' | 'info';
    title: string;
    detail: string;
}

const openStep: FlowStep = {
    key: 'open',
    icon: 'orders',
    variant: 'primary',
    title: 'Adisyon açılır',
    detail: 'Masanın o anki TEK açık adisyonu. Aynı masada ikinci bir açık adisyon AÇILAMAZ.',
};

const payBranch: FlowStep[] = [
    { key: 'pay', icon: 'cart', variant: 'success', title: 'Ödeme alınır (Kasa)', detail: 'Nakit / kart / diğer yöntem — payments tablosuna işlenir.' },
    { key: 'paid', icon: 'check-circle', variant: 'success', title: 'Durum: ödendi', detail: 'Adisyon KAPANIR. Tutar Tahsilat + Ciro\'ya yazılır.' },
];

const debtBranch: FlowStep[] = [
    { key: 'debt', icon: 'inbox', variant: 'warning', title: '"Borca taşı" (Cari seç)', detail: 'Var olan ya da yeni bir cari (müşteri hesabı) seçilir.' },
    { key: 'transferred', icon: 'inbox', variant: 'warning', title: 'Durum: borca taşındı', detail: 'Adisyon KAPANIR. Tutar carinin bakiyesine (Açık borç) yazılır.' },
];
</script>

<template>
    <Head title="Nasıl Çalışır" />

    <PanelShell title="Nasıl Çalışır">
        <div class="mx-auto flex w-full max-w-5xl flex-col gap-8">
            <div class="flex flex-col gap-2">
                <h1 class="text-2xl font-semibold text-body">Kasa · Sipariş · Masa · Adisyon · Cari nasıl bağlanır?</h1>
                <p class="max-w-3xl text-[15px] leading-relaxed text-muted">
                    Bu sayfa canlı veri taşımaz — yalnızca sistemin temel kurallarını ve para akışının nereden
                    nereye gittiğini anlatır. Raporlardaki rakamların ne anlama geldiğini (Ciro, Tahsilat, Açık
                    masa, Açık borç) burada netleştirebilirsiniz.
                </p>
            </div>

            <!-- ---- Temel kavramlar ---- -->
            <BaseCard title="Temel kavramlar">
                <dl class="grid grid-cols-1 gap-5 p-1 sm:grid-cols-2">
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-inset text-muted">
                            <AppIcon name="qr-code" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Masa</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Fiziksel masa/QR. Bir masanın <strong class="text-body">en fazla bir</strong> açık
                                adisyonu olabilir — "masa dolu mu" sorusunun cevabı, o masada açık adisyon olup
                                olmadığıdır.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
                            <AppIcon name="orders" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Adisyon (Sipariş)</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Bir oturuma ait kalemlerin tamamı. Açılışta <BaseBadge variant="primary" no-icon>açık</BaseBadge>
                                durumdadır; ödendiğinde ya da borca taşındığında <strong class="text-body">kapanır</strong> ve
                                masa boşalır.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-success-soft text-success">
                            <AppIcon name="cart" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Kasa / Ödeme</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Gerçek para giriş noktası. Her ödeme <code class="rounded bg-inset px-1 py-0.5 text-xs">payments</code>
                                kaydına yazılır — <strong class="text-body">Tahsilat</strong> rakamı SADECE buradan
                                gelir, adisyon tutarından yeniden hesaplanmaz.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-warning-soft text-warning">
                            <AppIcon name="inbox" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Cari (Borç hesabı)</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Ödeme o an alınamayan adisyonlar bir cariye "borca taşınır". Cari bakiyesi
                                (<code class="rounded bg-inset px-1 py-0.5 text-xs">receivables.balance_minor</code>)
                                <strong class="text-body">Açık borç</strong>u temsil eder; sonradan tahsil edilince
                                bakiye azalır ve o tutar Tahsilat'a eklenir.
                            </dd>
                        </div>
                    </div>
                </dl>
            </BaseCard>

            <!-- ---- Kroki: bir adisyonun yolculuğu ---- -->
            <BaseCard title="Kroki: bir adisyonun açılıştan kapanışa yolculuğu">
                <div class="flex flex-col items-center gap-1 p-2">
                    <!-- Masa boş -->
                    <div class="flex w-full max-w-xs items-center justify-center gap-2 rounded-lg border border-default bg-inset px-4 py-2.5 text-sm font-medium text-muted">
                        <AppIcon name="store" :size="16" />
                        Masa (boş)
                    </div>
                    <div class="flex flex-col items-center py-1 text-subtle">
                        <span class="text-xs">sipariş alınır / QR'dan gönderilir</span>
                        <AppIcon name="chevron-down" :size="16" />
                    </div>

                    <!-- Adisyon açılır -->
                    <div class="flex w-full max-w-xs flex-col items-center gap-1 rounded-lg border border-primary-soft-border bg-primary-soft px-4 py-3 text-center">
                        <span class="flex items-center gap-1.5 text-sm font-semibold text-primary">
                            <AppIcon name="orders" :size="16" />
                            {{ openStep.title }}
                        </span>
                        <span class="text-xs leading-relaxed text-muted">{{ openStep.detail }}</span>
                    </div>

                    <div class="flex flex-col items-center py-1 text-subtle">
                        <span class="text-xs">hesap istenir → biri seçilir</span>
                        <AppIcon name="chevron-down" :size="16" />
                    </div>

                    <!-- İki dal: Ödeme vs Borca taşı -->
                    <div class="grid w-full grid-cols-1 gap-6 sm:grid-cols-2">
                        <div class="flex flex-col items-center gap-1">
                            <div
                                v-for="(step, i) in payBranch"
                                :key="step.key"
                                class="flex w-full flex-col items-center gap-3"
                            >
                                <div
                                    class="flex w-full flex-col items-center gap-1 rounded-lg border bg-success-soft px-4 py-3 text-center border-success-border"
                                >
                                    <span class="flex items-center gap-1.5 text-sm font-semibold text-success">
                                        <AppIcon :name="step.icon" :size="16" />
                                        {{ step.title }}
                                    </span>
                                    <span class="text-xs leading-relaxed text-muted">{{ step.detail }}</span>
                                </div>
                                <AppIcon v-if="i < payBranch.length - 1" name="chevron-down" :size="16" class="text-subtle" />
                            </div>
                        </div>

                        <div class="flex flex-col items-center gap-1">
                            <div
                                v-for="(step, i) in debtBranch"
                                :key="step.key"
                                class="flex w-full flex-col items-center gap-3"
                            >
                                <div
                                    class="flex w-full flex-col items-center gap-1 rounded-lg border bg-warning-soft px-4 py-3 text-center border-warning-border"
                                >
                                    <span class="flex items-center gap-1.5 text-sm font-semibold text-warning">
                                        <AppIcon :name="step.icon" :size="16" />
                                        {{ step.title }}
                                    </span>
                                    <span class="text-xs leading-relaxed text-muted">{{ step.detail }}</span>
                                </div>
                                <AppIcon v-if="i < debtBranch.length - 1" name="chevron-down" :size="16" class="text-subtle" />
                            </div>
                        </div>
                    </div>

                    <div class="flex flex-col items-center py-1 text-subtle">
                        <AppIcon name="chevron-down" :size="16" />
                    </div>

                    <!-- Birleşim: Adisyon kapanır -->
                    <div class="flex w-full max-w-xs flex-col items-center gap-1 rounded-lg border border-default bg-raised px-4 py-3 text-center shadow-card">
                        <span class="flex items-center gap-1.5 text-sm font-semibold text-body">
                            <AppIcon name="check-circle" :size="16" />
                            Adisyon KAPANIR
                        </span>
                        <span class="text-xs leading-relaxed text-muted">Her iki yolda da geçerli — masa artık meşgul değil.</span>
                    </div>

                    <div class="py-1"><AppIcon name="chevron-down" :size="16" class="text-subtle" /></div>

                    <div class="flex w-full max-w-xs items-center justify-center gap-2 rounded-lg border border-default bg-inset px-4 py-2.5 text-sm font-medium text-muted">
                        <AppIcon name="store" :size="16" />
                        Masa BOŞALIR — yeni adisyon açılabilir
                    </div>
                </div>

                <div class="mt-5 flex items-start gap-2.5 rounded-md border border-info-border bg-info-soft px-3 py-2.5 text-sm text-info">
                    <AppIcon name="info" :size="16" class="mt-0.5 shrink-0" />
                    <p class="leading-relaxed">
                        Açık borç sonradan (kısmen ya da tamamen) tahsil edilirse, o tutar Cari ekranından
                        <strong>Tahsilat</strong>'a eklenir ve cari bakiyesi (Açık borç) o kadar azalır. Ciro
                        DEĞİŞMEZ — yalnızca tutarın hangi "kovada" (Tahsilat mı Açık borç mu) durduğu değişir.
                    </p>
                </div>
            </BaseCard>

            <!-- ---- Ciro/Tahsilat/Açık masa/Açık borç ayrımı ---- -->
            <BaseCard title="Raporlardaki 4 rakam — hangisi ne demek?">
                <div class="grid grid-cols-1 gap-3 p-1 sm:grid-cols-2 xl:grid-cols-4">
                    <div class="rounded-lg border border-default bg-raised p-4">
                        <BaseBadge variant="primary" no-icon>Ciro</BaseBadge>
                        <p class="mt-2 text-sm leading-relaxed text-muted">
                            YALNIZ <strong class="text-body">kapanan</strong> adisyonlar (ödendi + borca taşındı).
                            İptal ve iade Ciro'ya sayılmaz. Henüz açık olan adisyonlar da sayılmaz.
                        </p>
                    </div>
                    <div class="rounded-lg border border-success-border bg-success-soft p-4">
                        <BaseBadge variant="success" no-icon>Tahsilat</BaseBadge>
                        <p class="mt-2 text-sm leading-relaxed text-body">
                            Kasaya gerçekten giren para (<code class="rounded bg-inset px-1 py-0.5 text-xs">payments</code>
                            kaydı). Borca taşınan tutar, tahsil edilene kadar burada DEĞİLDİR.
                        </p>
                    </div>
                    <div class="rounded-lg border border-warning-border bg-warning-soft p-4">
                        <BaseBadge variant="warning" no-icon>Açık borç</BaseBadge>
                        <p class="mt-2 text-sm leading-relaxed text-body">
                            Cari hesapların GÜNCEL bakiye toplamı. "Borca taşı" ile kapanmış ama henüz tahsil
                            edilmemiş tutarlar burada birikir.
                        </p>
                    </div>
                    <div class="rounded-lg border border-default bg-inset p-4">
                        <BaseBadge variant="neutral" no-icon>Açık masa tutarı</BaseBadge>
                        <p class="mt-2 text-sm leading-relaxed text-muted">
                            ANLIK: henüz kapanmamış (ödenmemiş/borca yazılmamış) adisyonların toplamı. Ciro
                            DEĞİLDİR — sipariş iptal olabilir, tutar değişebilir.
                        </p>
                    </div>
                </div>

                <div class="mt-4 rounded-lg border border-default bg-raised p-4">
                    <p class="text-sm font-semibold text-body">Denklem</p>
                    <p class="mt-1 font-mono text-sm text-muted">Ciro = Tahsilat + Açık borç <span class="text-subtle">(o dönem kapanan adisyonlar için)</span></p>
                    <p class="mt-3 text-xs leading-relaxed text-subtle">
                        Örnek: bir adisyon 500 ₺ ise ve müşteri 350 ₺ nakit ödeyip kalan 150 ₺'yi cariye
                        yazdırdıysa: Ciro = 500 ₺, Tahsilat = 350 ₺, Açık borç = 150 ₺. Cari sonradan 150 ₺
                        öderse: Tahsilat 500 ₺'ye çıkar, Açık borç 0'a iner — Ciro hep 500 ₺ kalır.
                    </p>
                </div>
            </BaseCard>

            <!-- ---- Kurallar ---- -->
            <BaseCard title="Aklınızda kalsın">
                <ul class="flex flex-col divide-y divide-default">
                    <li class="flex items-start gap-3 py-3">
                        <AppIcon name="check-circle" :size="16" class="mt-0.5 shrink-0 text-success" />
                        <span class="text-sm leading-relaxed text-body">
                            Bir masada aynı anda <strong>tek</strong> açık adisyon olur — ikinci bir sipariş,
                            var olan açık adisyona kalem olarak eklenir.
                        </span>
                    </li>
                    <li class="flex items-start gap-3 py-3">
                        <AppIcon name="check-circle" :size="16" class="mt-0.5 shrink-0 text-success" />
                        <span class="text-sm leading-relaxed text-body">
                            Bir adisyon yalnız iki şekilde kapanır: <strong>tam ödenerek</strong> ya da
                            <strong>cariye borç yazılarak</strong>. İkisi de masayı boşaltır.
                        </span>
                    </li>
                    <li class="flex items-start gap-3 py-3">
                        <AppIcon name="check-circle" :size="16" class="mt-0.5 shrink-0 text-success" />
                        <span class="text-sm leading-relaxed text-body">
                            İptal edilen ya da iade edilen adisyonlar Ciro'nun DIŞINDADIR — raporlarda ayrı
                            satırda görünürler, gizlenmezler.
                        </span>
                    </li>
                    <li class="flex items-start gap-3 py-3">
                        <AppIcon name="check-circle" :size="16" class="mt-0.5 shrink-0 text-success" />
                        <span class="text-sm leading-relaxed text-body">
                            Hiçbir hareket yoksa (yeni işletme, demo hesap) Ciro dürüstçe <strong>₺0</strong>
                            görünür — henüz kapanmış satış yoksa uydurma bir rakam gösterilmez.
                        </span>
                    </li>
                </ul>
            </BaseCard>
        </div>
    </PanelShell>
</template>
