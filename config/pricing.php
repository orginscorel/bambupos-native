<?php

/*
|--------------------------------------------------------------------------
| Fiyatlandırma içeriği — paketler, karşılaştırma tablosu, ek modüller, SSS
|--------------------------------------------------------------------------
| Fiyatlar "Teklif Al" modunda (net rakam yerine). P7'de CMS'e taşınabilir.
| icon anahtarları: App\Modules\Marketing\Support\Icons.
*/

return [

    'plans' => [
        [
            'name' => 'Başlangıç', 'for' => 'Küçük kafe ve hızlı servis işletmeleri',
            'price' => 'Teklif Al', 'popular' => false,
            'features' => ['Temel POS & adisyon', 'QR menü & masa yönetimi', 'Temel raporlar', 'Tek terminal', 'Bulut yedekleme'],
            'cta' => 'Teklif Al',
        ],
        [
            'name' => 'Profesyonel', 'for' => 'Büyüyen restoran ve kafeler',
            'price' => 'Teklif Al', 'popular' => true,
            'features' => ['Başlangıç’taki her şey', 'Personel & vardiya', 'Stok & reçete', 'Rezervasyon', 'Paket sipariş', 'Gelişmiş raporlar', 'Çoklu terminal'],
            'cta' => 'Demo Talep Et',
        ],
        [
            'name' => 'Kurumsal', 'for' => 'Çok şubeli ve zincir işletmeler',
            'price' => 'Teklif Al', 'popular' => false,
            'features' => ['Profesyonel’deki her şey', 'Çoklu / özel şube', 'Merkezi yönetim & stok transferi', 'Kurumsal yetkilendirme', 'Özel entegrasyon', 'Öncelikli destek & SLA'],
            'cta' => 'Satışla Görüş',
        ],
    ],

    // Karşılaştırma tablosu: her satır bir özellik, 3 pakette durumu (true / 'metin' / false)
    'compare' => [
        ['g' => 'Satış & Sipariş', 'rows' => [
            ['Masa & adisyon yönetimi', true, true, true],
            ['QR menü & self sipariş', true, true, true],
            ['Mobil POS / garson uygulaması', true, true, true],
            ['Self servis kiosk', false, 'Ek modül', 'Ek modül'],
            ['Hesap bölme & ikram', true, true, true],
        ]],
        ['g' => 'Mutfak & Hazırlık', 'rows' => [
            ['Mutfak ekranı (KDS)', true, true, true],
            ['Barista / nargile ekranı', false, true, true],
            ['Reçete & maliyet', false, true, true],
        ]],
        ['g' => 'İşletme Yönetimi', 'rows' => [
            ['Temel raporlar', true, true, true],
            ['Gelişmiş & saatlik raporlar', false, true, true],
            ['Personel & vardiya', false, true, true],
            ['Stok & tedarikçi', false, true, true],
            ['Rezervasyon', false, true, true],
            ['Müşteri & sadakat', false, 'Ek modül', true],
        ]],
        ['g' => 'Çoklu Şube & Kurumsal', 'rows' => [
            ['Şube sayısı', 'Tek', 'Sınırlı', 'Sınırsız / özel'],
            ['Merkezi menü & fiyat', false, false, true],
            ['Şubeler arası stok transferi', false, false, true],
            ['Özel entegrasyon', false, false, true],
            ['SLA & öncelikli destek', false, false, true],
        ]],
    ],

    'addons' => [
        ['kiosk', 'Self Servis Kiosk', 'Dokunmatik self sipariş ekranı'],
        ['flame', 'Nargile Ekranı', 'Nargile hazırlık kulvarı ve köz takibi'],
        ['truck', 'Kurye & Paket', 'Kurye atama ve teslimat yönetimi'],
        ['tag', 'Sadakat & Kampanya', 'Puan, sadakat ve kampanya modülü'],
        ['plug', 'Özel Entegrasyon', 'Markaya özel entegrasyon geliştirme'],
        ['phone', 'Markaya Özel Uygulama', 'İşletmenize özel mobil sipariş uygulaması'],
    ],

    'faq' => [
        ['Fiyatlar neden belirtilmiyor?', 'İşletmenizin ölçeği, şube ve terminal sayısı ile ihtiyacınız olan modüllere göre size özel teklif hazırlıyoruz. Demo talebiyle net fiyatınızı hızla iletiriz.'],
        ['Kurulum ücreti var mı?', 'Kurulum ücreti yoktur; menü aktarımında ekibimiz size destek olur.'],
        ['İstemediğim modülleri ödemez miyim?', 'Evet. Nargile, kiosk, kurye, sadakat gibi modüller eklentidir; yalnız kullandığınız modüller paketinize dahil edilir.'],
        ['Taahhüt gerekiyor mu?', 'Deneme süresi için taahhüt gerekmez; uzun dönem planlarında avantajlı fiyat sunulur.'],
        ['Aylık mı yıllık mı ödenir?', 'Aylık veya yıllık ödeme seçilebilir; yıllık ödemede indirim uygulanır.'],
    ],
];
