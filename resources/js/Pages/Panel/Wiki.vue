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

/**
 * Sipariş yaşam döngüsü (2026-07-25): durum yalnız istasyonda ilerler.
 * Hazırlanıyor → Garson & Komi bekliyor → Servis edildi.
 */
const lifecycle: FlowStep[] = [
    { key: 'created', icon: 'orders', variant: 'primary', title: 'Sipariş açılır', detail: 'Masadan, kiosktan ya da QR menüden gelir. Aynı masaya gelen yeni sipariş, o masanın açık adisyonuna kalem olarak eklenir.' },
    { key: 'preparing', icon: 'chef-hat', variant: 'warning', title: 'Hazırlanıyor', detail: 'Kalemler istasyonlara düşer: yemek → Mutfak, kahve/içecek → Barista. Her istasyon yalnız kendi kalemini görür.' },
    { key: 'waiting', icon: 'bell', variant: 'info', title: 'Garson & Komi bekliyor', detail: 'İstasyon kalemi bitirince "hazır" olur; komi kalemi teslim almak için bekler.' },
    { key: 'served', icon: 'check-circle', variant: 'success', title: 'Servis edildi', detail: 'Komi kalemi masaya teslim edince tamamlanır. Durum yalnızca ilgili istasyonda ilerler.' },
];

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

    <PanelShell title="Nasıl Çalışır" flush canvas>
        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1080px] flex-col gap-3">

        <div class="mx-auto flex w-full max-w-5xl flex-col gap-8">
            <div class="flex flex-col gap-2">
                <h1 class="text-2xl font-semibold text-body">Sipariş · Mutfak · Kasa · Masa · Cari nasıl bağlanır?</h1>
                <p class="max-w-3xl text-[15px] leading-relaxed text-muted">
                    Bu sayfa canlı veri taşımaz — yalnızca sistemin temel kurallarını, bir siparişin açılıştan
                    servise yolculuğunu ve para akışının nereden nereye gittiğini anlatır. Raporlardaki rakamların
                    ne anlama geldiğini (Ciro, Tahsilat, Açık masa, Açık borç) burada netleştirebilirsiniz.
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

            <!-- ---- Sipariş yaşam döngüsü ---- -->
            <BaseCard title="Sipariş yaşam döngüsü — açılıştan servise">
                <p class="mb-5 max-w-3xl px-1 text-sm leading-relaxed text-muted">
                    Bir sipariş nereden gelirse gelsin (masa, kiosk ya da QR) aynı akışa girer. <strong class="text-body">Durum
                    yalnızca ilgili istasyonda ilerler</strong> — Siparişler ekranı bu durumu yalnızca <em>görüntüler</em>,
                    kasa ise ödeme/iptal işler.
                </p>
                <div class="grid grid-cols-1 gap-3 p-1 sm:grid-cols-2 xl:grid-cols-4">
                    <template v-for="(step, i) in lifecycle" :key="step.key">
                        <div class="flex flex-col gap-2 rounded-lg border border-default bg-raised p-4">
                            <span class="flex size-8 items-center justify-center rounded-full"
                                :class="{
                                    'bg-primary-soft text-primary': step.variant === 'primary',
                                    'bg-warning-soft text-warning': step.variant === 'warning',
                                    'bg-info-soft text-info': step.variant === 'info',
                                    'bg-success-soft text-success': step.variant === 'success',
                                }">
                                <AppIcon :name="step.icon" :size="16" />
                            </span>
                            <div class="flex items-center gap-2">
                                <span class="text-xs font-mono text-subtle">{{ i + 1 }}</span>
                                <span class="text-sm font-semibold text-body">{{ step.title }}</span>
                            </div>
                            <span class="text-xs leading-relaxed text-muted">{{ step.detail }}</span>
                        </div>
                    </template>
                </div>
                <div class="mt-4 flex items-start gap-2.5 rounded-md border border-info-border bg-info-soft px-3 py-2.5 text-sm text-info">
                    <AppIcon name="info" :size="16" class="mt-0.5 shrink-0" />
                    <p class="leading-relaxed">
                        "Garson &amp; Komi bekliyor" adımı, kalemin hazır olduğu ama henüz masaya gitmediği andır.
                        Komi teslim edene kadar sipariş bu durumda bekler — böylece hiçbir hazır tabak/bardak
                        istasyonda unutulmaz.
                    </p>
                </div>
            </BaseCard>

            <!-- ---- İstasyonlar: Mutfak vs Barista ---- -->
            <BaseCard title="İstasyonlar — Mutfak, Barista ve Komi">
                <div class="grid grid-cols-1 gap-3 p-1 sm:grid-cols-3">
                    <div class="flex flex-col gap-2 rounded-lg border border-default bg-raised p-4">
                        <span class="flex items-center gap-2 text-sm font-semibold text-body">
                            <span class="flex size-8 items-center justify-center rounded-full bg-warning-soft text-warning">
                                <AppIcon name="chef-hat" :size="16" />
                            </span>
                            Mutfak
                        </span>
                        <p class="text-sm leading-relaxed text-muted">
                            Yemek kalemleri buraya düşer. Mutfak ekranı yalnızca <strong class="text-body">kendi</strong>
                            kalemlerini gösterir — kahve/içecek görünmez.
                        </p>
                    </div>
                    <div class="flex flex-col gap-2 rounded-lg border border-default bg-raised p-4">
                        <span class="flex items-center gap-2 text-sm font-semibold text-body">
                            <span class="flex size-8 items-center justify-center rounded-full bg-primary-soft text-primary">
                                <AppIcon name="coffee" :size="16" />
                            </span>
                            Barista
                        </span>
                        <p class="text-sm leading-relaxed text-muted">
                            Kahve, içecek ve bar ürünleri buraya düşer. Her ürün, kataloğunda seçilen istasyona göre
                            otomatik yönlenir. Mutfakta kimse içecek hazırlamaz.
                        </p>
                    </div>
                    <div class="flex flex-col gap-2 rounded-lg border border-default bg-raised p-4">
                        <span class="flex items-center gap-2 text-sm font-semibold text-body">
                            <span class="flex size-8 items-center justify-center rounded-full bg-success-soft text-success">
                                <AppIcon name="users" :size="16" />
                            </span>
                            Komi (servis)
                        </span>
                        <p class="text-sm leading-relaxed text-muted">
                            Komi <strong class="text-body">tüm istasyonların</strong> hazır kalemlerini tek ekranda görür,
                            toplar ve masaya götürür. İstasyon farkı komiyi bölmez.
                        </p>
                    </div>
                </div>
                <div class="mt-4 flex items-start gap-2.5 rounded-md border border-default bg-inset px-3 py-2.5 text-sm text-muted">
                    <AppIcon name="info" :size="16" class="mt-0.5 shrink-0 text-subtle" />
                    <p class="leading-relaxed">
                        Süzme <strong class="text-body">kalem düzeyindedir</strong>: bir masada hem yemek hem kahve
                        varsa, yemek Mutfak'ta, kahve Barista'da görünür — aynı adisyon iki istasyona bölünür,
                        müşteri tek hesap alır. Mutfak/Barista/Komi ekranları <strong class="text-body">para görmez</strong>.
                    </p>
                </div>
                <div class="mt-2.5 flex items-start gap-2.5 rounded-md border border-default bg-inset px-3 py-2.5 text-sm text-muted">
                    <AppIcon name="nargile" :size="16" class="mt-0.5 shrink-0 text-subtle" />
                    <p class="leading-relaxed">
                        <strong class="text-body">Nargile</strong> eklentisi açıksa dördüncü bir kulvar eklenir:
                        Nargile istasyonuna atanan ürünler Mutfak yerine ayrı <strong class="text-body">Nargile
                        ekranına</strong> düşer ve nargileci kendi terminalinden yönetir. Eklenti kapalıyken bu
                        ürünler Mutfak kulvarında kalır (Ayarlar › Eklentiler).
                    </p>
                </div>
            </BaseCard>

            <!-- ---- Terminal: cihaza kilitli istasyonlar ---- -->
            <BaseCard title="Terminal — cihaza kilitli istasyonlar">
                <p class="mb-5 max-w-3xl px-1 text-sm leading-relaxed text-muted">
                    Mutfak/Barista/Komi ekranları ile Kasa ve Sipariş Girişi, isterseniz birer <strong class="text-body">terminal</strong>
                    olarak kurulur: cihaz artık tam ekran yalnızca kendi istasyonunu gösterir, panelin geri kalanını görmez.
                </p>
                <dl class="grid grid-cols-1 gap-5 p-1 sm:grid-cols-2">
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
                            <AppIcon name="monitor" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Lisanslı kurulum</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Ayarlar › Terminaller'den ("Terminal ekle") şube ve istasyon seçilir; sistem işletmenin
                                terminal lisans hakkına göre (ör. "3 / 5 terminal lisansı kullanıldı" ya da sınırsız)
                                benzersiz bir adres/QR üretir. Bu adres cihazın tarayıcısında tam ekran açılır ya da QR
                                okutulur — cihaz o an o istasyona kilitlenir.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-inset text-muted">
                            <AppIcon name="tablet" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Oto-kilit</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Cihaz kendi adresiyle otomatik oturum açar; personel şifre girmez ve yalnızca kendi
                                istasyon ekranını görür. Yönetici istediği an cihazı uzaktan kilitleyebilir ya da
                                adresini yenileyip eskisini anında geçersiz kılabilir.
                            </dd>
                        </div>
                    </div>
                </dl>
                <div class="mt-4 flex items-start gap-2.5 rounded-md border border-default bg-inset px-3 py-2.5 text-sm text-muted">
                    <AppIcon name="info" :size="16" class="mt-0.5 shrink-0 text-subtle" />
                    <p class="leading-relaxed">
                        Mutfak/Barista/Komi terminalleri <strong class="text-body">para görmez</strong>. Kasa ve Sipariş
                        Girişi terminalleri para görür; bu ikisinde ödeme alma, iptal, iade/void ve ikram gibi hassas
                        işlemler personel <strong class="text-body">PIN</strong>'i ister ve o kişiye kaydedilir (normal
                        panel oturumunda PIN istenmez).
                    </p>
                </div>
            </BaseCard>

            <!-- ---- Kiosk & QR: müşteri kanalları ---- -->
            <BaseCard title="Kiosk & QR — müşteri kanalları">
                <div class="grid grid-cols-1 gap-5 p-1 sm:grid-cols-2">
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
                            <AppIcon name="store" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Kiosk (self-servis cihaz)</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Müşteri, cihazdaki dokunmatik ekrandan ürün görselleriyle kendi siparişini verir ve
                                bağlı <strong class="text-body">POS/ödeme sağlayıcısı</strong> üzerinden ödemesini yapar.
                                Sipariş <strong class="text-body">Siparişler panosuna ve mutfağa</strong> düşer; kartta
                                ödeme durumu görünür.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-inset text-muted">
                            <AppIcon name="qr-code" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">QR menü</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Müşteri masadaki QR'ı okutup sipariş gönderir; sipariş o masanın açık adisyonuna eklenir.
                            </dd>
                        </div>
                    </div>
                </div>
                <div class="mt-4 flex items-start gap-2.5 rounded-md border border-info-border bg-info-soft px-3 py-2.5 text-sm text-info">
                    <AppIcon name="info" :size="16" class="mt-0.5 shrink-0" />
                    <p class="leading-relaxed">
                        Hangi kanaldan gelirse gelsin sipariş <strong>aynı yaşam döngüsüne</strong> girer: Hazırlanıyor →
                        Garson &amp; Komi bekliyor → Servis edildi. Kanal farkı yalnızca siparişin nasıl başladığını değiştirir.
                    </p>
                </div>
            </BaseCard>

            <!-- ---- Eklentiler & entegrasyonlar ---- -->
            <BaseCard title="Eklentiler & entegrasyonlar">
                <div class="grid grid-cols-1 gap-5 p-1 sm:grid-cols-2">
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
                            <AppIcon name="wallet" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">POS / yazarkasa / ÖKC entegratörü</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Markadan bağımsız bir entegratör: kasadaki, terminaldeki ve kiosktaki ödemeler
                                seçtiğiniz sağlayıcıya (banka POS, ÖKC/yazarkasa, ödeme kuruluşu) yönlenir.
                                Ayarlar › Entegrasyonlar'dan sağlayıcı seçilip yapılandırılır; kurulmadıysa
                                sistem sahte "tahsil edildi" göstermez.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-warning-soft text-warning">
                            <AppIcon name="nargile" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Nargile</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Nargile mekânları için ayrı hazırlık ekranı + nargileci terminali. Açıkken Nargile
                                istasyonuna atanan ürünler kendi kulvarına düşer.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-inset text-muted">
                            <AppIcon name="plug" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Şarjmatik</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Açıkken müşteri QR menüden "Şarjmatik İste" der; talep personele bildirim olarak düşer.
                                Kapalıyken buton hiç görünmez.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-inset text-muted">
                            <AppIcon name="settings" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Tema & marka</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Ayarlar › Tema'dan marka rengi, vurgu rengi, yazı tipi ve açık/koyu mod; Ayarlar ›
                                İşletme / Marka'dan işletme adı ve logo. QR menü ve panel bu ayarlara uyar.
                            </dd>
                        </div>
                    </div>
                </div>
                <div class="mt-4 flex items-start gap-2.5 rounded-md border border-default bg-inset px-3 py-2.5 text-sm text-muted">
                    <AppIcon name="info" :size="16" class="mt-0.5 shrink-0 text-subtle" />
                    <p class="leading-relaxed">
                        Eklentiler <strong class="text-body">Ayarlar › Eklentiler</strong> ekranından tek tıkla
                        açılıp kapatılır. Kapalı bir eklentinin ekranları, butonları ve uçları tamamen gizlenir —
                        işletme yalnızca kullandığı özellikleri görür.
                    </p>
                </div>
            </BaseCard>

            <!-- ---- Depo / Stok ---- -->
            <BaseCard title="Depo — reçeteyle otomatik stok">
                <div class="grid grid-cols-1 gap-5 p-1 sm:grid-cols-2">
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-inset text-muted">
                            <AppIcon name="package" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Otomatik düşüm</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Bir kalem servis edilince, ürünün reçetesindeki hammaddeler tanımlı gramaj kadar
                                depodan <strong class="text-body">otomatik düşer</strong> — "kola verildi" → kola stoğu 1 azalır.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-warning-soft text-warning">
                            <AppIcon name="inbox" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">İptal → iade</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Bir kalem iptal/iade edilince stok geri eklenir ve <strong class="text-body">sebep
                                zorunlu</strong> olarak kaydedilir. Her hareket değişmez bir defterde (kim, ne kadar,
                                neden, ne zaman) izlenir; gün/ay raporuyla giriş–çıkış–kalan mutabakatı yapılır.
                            </dd>
                        </div>
                    </div>
                </div>
            </BaseCard>

            <!-- ---- Kroki: bir adisyonun yolculuğu ---- -->
            <BaseCard title="Kasada kapanış: bir adisyonun ödeme/borç yolculuğu">
                <p class="mb-4 max-w-3xl px-1 text-sm leading-relaxed text-muted">
                    Kasa, masanın açık adisyonunu görür; kalemleri <strong class="text-body">doğrular, düzeltir ya da
                    ikram</strong> edebilir. Ödemeyi nakit, kart ya da <strong class="text-body">bölerek (split)</strong>
                    alır, para üstünü hesaplar — ödeme tamamlanınca adisyon kapanır ve tutar Tahsilat'a yazılır.
                </p>
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
                <div class="mt-4 flex items-start gap-2.5 rounded-md border border-default bg-inset px-3 py-2.5 text-sm text-muted">
                    <AppIcon name="info" :size="16" class="mt-0.5 shrink-0 text-subtle" />
                    <p class="leading-relaxed">
                        Bu 4 rakamın yanında <strong class="text-body">Raporlar</strong> (<code class="rounded bg-inset px-1 py-0.5 text-xs">/panel/raporlar</code>)
                        ekranında satış (günlük/saatlik, kategori, ürün, masa, kanal), finans (KDV dağılımı, ödeme
                        yöntemleri, kasa oturumları, POS/nakit mutabakatı), ürün kârlılığı, operasyon (gün sonu,
                        geciken siparişler, istasyon hazırlama süreleri, komi teslim SLA, iptal/ikram nedenleri,
                        QR/Kiosk kullanımı) ve personel performansı raporları da bulunur.
                    </p>
                </div>
            </BaseCard>

            <!-- ---- Roller: kim neyi görür ---- -->
            <BaseCard title="Roller — kim neyi görür?">
                <p class="mb-5 max-w-3xl px-1 text-sm leading-relaxed text-muted">
                    Yetkiler role göre değişir; her rol yalnızca işine gerektiği kadarını görür.
                </p>
                <dl class="grid grid-cols-1 gap-5 p-1 sm:grid-cols-2">
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-primary-soft text-primary">
                            <AppIcon name="users" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Sahip & Müdür</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Tüm ekranlara erişir (kasa, raporlar, ayarlar, personel/rol yönetimi dahil). Şube
                                Müdürü aynı operasyon ve rapor yetkilerine sahiptir; yalnızca rol/yetki tanımlaması
                                onun dışındadır.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-inset text-muted">
                            <AppIcon name="orders" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Garson</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Sipariş alır, masa/adisyon işler, rezervasyona bakar — kasayı ve raporları göremez.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-success-soft text-success">
                            <AppIcon name="wallet" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Kasiyer</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Yalnızca ödeme/kasa işlemlerini yapar; iade gibi ek yetkiler ayrıca açılabilir.
                            </dd>
                        </div>
                    </div>
                    <div class="flex gap-3">
                        <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-warning-soft text-warning">
                            <AppIcon name="chef-hat" :size="16" />
                        </span>
                        <div>
                            <dt class="text-sm font-semibold text-body">Mutfak / Komi / Kurye / Depo Sorumlusu</dt>
                            <dd class="mt-0.5 text-sm leading-relaxed text-muted">
                                Her biri yalnızca kendi ekranını görür: istasyon (KDS) ekranı, teslim kuyruğu,
                                kurye/teslimat listesi ya da depo/stok ekranı — panelin geri kalanı gizlidir.
                            </dd>
                        </div>
                    </div>
                </dl>
                <div class="mt-4 flex items-start gap-2.5 rounded-md border border-default bg-inset px-3 py-2.5 text-sm text-muted">
                    <AppIcon name="gauge" :size="16" class="mt-0.5 shrink-0 text-subtle" />
                    <p class="leading-relaxed">
                        <strong class="text-body">Patron Paneli</strong> bu panelin bir sekmesi değildir — ayrı bir
                        alt alan adından (patron.*) girilen, bağımsız bir yönetici kontrol panelidir; işletme
                        sahibine ciro/performans/kasa/stok özetini gösterir.
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
        </div>
        </div>
    </PanelShell>
</template>
