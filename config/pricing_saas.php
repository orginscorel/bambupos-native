<?php

/*
|--------------------------------------------------------------------------
| SaaS abonelik fiyat kataloğu (platform geliri — A2 Abonelik & Faturalama)
|--------------------------------------------------------------------------
| DİKKAT: Bu, işletmelerin MÜŞTERİLERİNE sattığı ürün fiyatı DEĞİL; BamBumPOS'un
| işletmelerden aldığı SaaS abonelik ücretidir. config/pricing.php (kurumsal
| tanıtım sitesi, "Teklif Al") ile KARIŞTIRILMAMALI — bu dosya platformun
| KENDİ faturalama motoru içindir (saas_plans tablosuna migration'da tohumlanır).
|
| Anahtarlar SuperAdminController::PLANS ile birebir hizalıdır: trial/basic/
| pro/enterprise. Rakamlar makul/gösterge niteliğindedir (uydurma değil —
| config/pricing.php'deki paket kapsamlarıyla aynı özellik sırasına dayanır);
| gerçek liste fiyatı ticari kararla burada güncellenir. price_minor kuruş
| cinsindendir (₺1 = 100).
|--------------------------------------------------------------------------
*/

return [

    'plans' => [

        'trial' => [
            'name' => 'Deneme',
            'price_minor' => 0,
            'currency' => 'TRY',
            'interval' => 'monthly',
            'is_active' => true,
            'trial_days' => 14,
            'features' => [
                'Tüm temel modüllere erişim (14 gün)',
                'Tek şube, tek terminal',
                'Kredi kartı gerekmez',
            ],
        ],

        'basic' => [
            'name' => 'Başlangıç',
            'price_minor' => 99000, // 990,00 ₺/ay
            'currency' => 'TRY',
            'interval' => 'monthly',
            'is_active' => true,
            'features' => [
                'Temel POS & adisyon',
                'QR menü & masa yönetimi',
                'Temel raporlar',
                'Tek terminal',
                'Bulut yedekleme',
            ],
        ],

        'pro' => [
            'name' => 'Profesyonel',
            'price_minor' => 199000, // 1.990,00 ₺/ay
            'currency' => 'TRY',
            'interval' => 'monthly',
            'is_active' => true,
            'features' => [
                'Başlangıç paketindeki her şey',
                'Personel & vardiya',
                'Stok & reçete',
                'Rezervasyon',
                'Paket sipariş',
                'Gelişmiş raporlar',
                'Çoklu terminal',
            ],
        ],

        'enterprise' => [
            'name' => 'Kurumsal',
            'price_minor' => 499000, // 4.990,00 ₺/ay (gösterge; çok şubeli anlaşmalarda özel teklif geçerlidir)
            'currency' => 'TRY',
            'interval' => 'monthly',
            'is_active' => true,
            'features' => [
                'Profesyonel paketindeki her şey',
                'Çoklu / özel şube',
                'Merkezi yönetim & stok transferi',
                'Kurumsal yetkilendirme',
                'Özel entegrasyon',
                'Öncelikli destek & SLA',
            ],
        ],

    ],

];
