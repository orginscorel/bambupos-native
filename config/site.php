<?php

/*
|--------------------------------------------------------------------------
| BamBumPOS Kurumsal Web Sitesi — merkezi site yapılandırması
|--------------------------------------------------------------------------
| Mega menü, footer bilgi mimarisi, iletişim/sosyal, duyuru bandı ve SEO
| varsayılanları. P1 aşamasında statik kaynak; P7'de CMS (SiteSetting +
| Navigation) tablolarına taşınacak — yapı o geçişe uygun tutuldu.
| Metinler TR; i18n P7'de PageTranslation ile eklenecek.
*/

return [

    'brand' => [
        'name' => 'BamBumPOS',
        'tagline' => 'Hepsi Bir Arada İşletme Yönetim Sistemi',
        'infra' => 'bogahost.com altyapı güvencesi',
    ],

    // Üst duyuru bandı — panelden aç/kapa (P7). enabled=false ise gösterilmez.
    'announcement' => [
        'enabled' => true,
        'text' => '14 gün ücretsiz deneme · Kurulum ücreti yok · Ücretsiz menü aktarım desteği',
        'cta_label' => 'Demo Talep Et',
        'cta_url' => '/#demo',
    ],

    'contact' => [
        'phone' => '+90 850 000 00 00',
        'phone_raw' => '+908500000000',
        'whatsapp' => '+908500000000',
        'email' => 'satis@bambumpos.com',
        'support_email' => 'destek@bambumpos.com',
        'address' => 'Türkiye',
        'hours' => 'Hafta içi 09:00–18:00',
    ],

    'social' => [
        'instagram' => '', 'linkedin' => '', 'youtube' => '', 'x' => '', 'facebook' => '',
    ],

    // Global header mega menü. Her kategori: label + (columns | link).
    // route = uygulanacak URL (P3'te sayfalar üretilecek).
    'mega' => [
        [
            'label' => 'POS Sistemleri',
            'columns' => [[
                'heading' => 'Sektöre özel POS',
                'items' => [
                    ['t' => 'Kafe POS Sistemi', 'u' => '/kafe-pos-sistemi', 'd' => 'Kafe ve kahveciler için'],
                    ['t' => 'Restoran POS Sistemi', 'u' => '/restoran-pos-sistemi', 'd' => 'A la carte ve masalı servis'],
                    ['t' => 'Nargile Salonu POS', 'u' => '/nargile-salonu-pos-sistemi', 'd' => 'Nargile hazırlık akışıyla'],
                    ['t' => 'Bar & Pub POS Sistemi', 'u' => '/bar-pub-pos-sistemi', 'd' => 'Hızlı bar servisi'],
                ],
            ], [
                'heading' => 'Daha fazla sektör',
                'items' => [
                    ['t' => 'Fast Food POS Sistemi', 'u' => '/fast-food-pos-sistemi', 'd' => 'Hızlı servis & sayaç'],
                    ['t' => 'Otel & Sosyal Tesis', 'u' => '/otel-pos-sistemi', 'd' => 'Oda & tesis entegrasyonu'],
                    ['t' => 'Paket Servis POS', 'u' => '/paket-servis-pos-sistemi', 'd' => 'Telefon & online sipariş'],
                    ['t' => 'Çok Şubeli Zincir', 'u' => '/cok-subeli-restoran-yonetimi', 'd' => 'Merkezi yönetim'],
                ],
            ]],
            'feature' => ['t' => 'Sektörünüzü seçin', 'd' => 'İşletme tipinize göre hazır kurulum ve menü aktarımı.', 'u' => '/#demo', 'cta' => 'Ücretsiz demo'],
        ],
        [
            'label' => 'Sipariş Çözümleri',
            'columns' => [[
                'heading' => 'Sipariş kanalları',
                'items' => [
                    ['t' => 'Mobil POS', 'u' => '/mobil-pos', 'd' => 'Elde satış & adisyon'],
                    ['t' => 'QR Menü & Sipariş', 'u' => '/qr-menu', 'd' => 'Masadan self sipariş'],
                    ['t' => 'Online Sipariş', 'u' => '/online-siparis', 'd' => 'Web sipariş sayfası'],
                    ['t' => 'Self Servis Kiosk', 'u' => '/self-servis-kiosk', 'd' => 'Dokunmatik kiosk'],
                    ['t' => 'Garson Uygulaması', 'u' => '/garson-uygulamasi', 'd' => 'El terminali'],
                ],
            ], [
                'heading' => 'Hazırlık & teslimat',
                'items' => [
                    ['t' => 'Mutfak Ekranı (KDS)', 'u' => '/mutfak-ekran-sistemi', 'd' => 'Sipariş istasyonları'],
                    ['t' => 'Barista Ekranı', 'u' => '/barista-ekrani', 'd' => 'İçecek hazırlık'],
                    ['t' => 'Nargile Hazırlık Ekranı', 'u' => '/nargile-hazirlik-ekrani', 'd' => 'Nargile kulvarı'],
                    ['t' => 'Paket Sipariş Yönetimi', 'u' => '/paket-siparis-yonetimi', 'd' => 'Paket akışı'],
                    ['t' => 'Kurye Yönetimi', 'u' => '/kurye-yonetimi', 'd' => 'Atama & takip'],
                ],
            ]],
        ],
        [
            'label' => 'İşletme Çözümleri',
            'columns' => [[
                'heading' => 'Operasyon',
                'items' => [
                    ['t' => 'Personel & Vardiya', 'u' => '/personel-yonetimi', 'd' => 'Vardiya, mola, prim'],
                    ['t' => 'Depo & Stok', 'u' => '/stok-yonetimi', 'd' => 'Kritik stok & fire'],
                    ['t' => 'Üretim & Reçete', 'u' => '/uretim-recete', 'd' => 'Maliyet & reçete'],
                    ['t' => 'Ön Muhasebe', 'u' => '/on-muhasebe', 'd' => 'Gelir-gider takibi'],
                    ['t' => 'Tedarikçi Yönetimi', 'u' => '/tedarikci-yonetimi', 'd' => 'Alım & bakiye'],
                ],
            ], [
                'heading' => 'Yönetim & büyüme',
                'items' => [
                    ['t' => 'Akıllı Raporlar', 'u' => '/satis-raporlari', 'd' => 'Canlı dashboard'],
                    ['t' => 'Çoklu Şube Yönetimi', 'u' => '/coklu-sube-yonetimi', 'd' => 'Merkezi kontrol'],
                    ['t' => 'Rezervasyon Yönetimi', 'u' => '/rezervasyon-yonetimi', 'd' => 'Masa & takvim'],
                    ['t' => 'Müşteri & Sadakat', 'u' => '/musteri-sadakat', 'd' => 'Puan & CRM'],
                    ['t' => 'Kampanya Yönetimi', 'u' => '/kampanya-yonetimi', 'd' => 'İndirim & fırsat'],
                ],
            ]],
        ],
        [
            'label' => 'Entegrasyonlar',
            'columns' => [[
                'heading' => 'Ödeme & cihaz',
                'items' => [
                    ['t' => 'Ödeme Entegrasyonları', 'u' => '/entegrasyonlar?k=odeme', 'd' => 'Sanal POS & ödeme'],
                    ['t' => 'Yazarkasa & ÖKC', 'u' => '/entegrasyonlar?k=okc', 'd' => 'YN-POS & ÖKC'],
                    ['t' => 'Donanım Entegrasyonları', 'u' => '/entegrasyonlar?k=donanim', 'd' => 'Yazıcı, çekmece, terazi'],
                ],
            ], [
                'heading' => 'Platform & servis',
                'items' => [
                    ['t' => 'Paket Sipariş Platformları', 'u' => '/entegrasyonlar?k=paket', 'd' => 'Online sipariş kanalları'],
                    ['t' => 'Muhasebe Entegrasyonları', 'u' => '/entegrasyonlar?k=muhasebe', 'd' => 'e-Fatura & muhasebe'],
                    ['t' => 'API & Webhook', 'u' => '/entegrasyonlar?k=api', 'd' => 'Geliştirici erişimi'],
                    ['t' => 'Tüm Entegrasyonlar', 'u' => '/entegrasyonlar', 'd' => 'Kataloğu görüntüle'],
                ],
            ]],
        ],
        [
            'label' => 'Kurumsal',
            'columns' => [[
                'heading' => 'Şirket',
                'items' => [
                    ['t' => 'Hakkımızda', 'u' => '/hakkimizda', 'd' => 'Marka hikâyemiz'],
                    ['t' => 'Neden BamBumPOS', 'u' => '/neden-bambumpos', 'd' => 'Farkımız'],
                    ['t' => 'Güvenlik & Altyapı', 'u' => '/guvenlik-altyapi', 'd' => 'Veri güvenliği'],
                    ['t' => 'Referanslar', 'u' => '/referanslar', 'd' => 'Müşteri hikâyeleri'],
                ],
            ], [
                'heading' => 'İletişim & kaynak',
                'items' => [
                    ['t' => 'İş Ortaklığı', 'u' => '/is-ortakligi', 'd' => 'Bayilik & ortaklık'],
                    ['t' => 'Kariyer', 'u' => '/kariyer', 'd' => 'Bize katılın'],
                    ['t' => 'Blog', 'u' => '/blog', 'd' => 'İçerik merkezi'],
                    ['t' => 'İletişim', 'u' => '/iletisim', 'd' => 'Bize ulaşın'],
                    ['t' => 'Destek Merkezi', 'u' => '/destek', 'd' => 'Yardım & dokümanlar'],
                ],
            ]],
        ],
        ['label' => 'Fiyatlandırma', 'link' => '/fiyatlandirma'],
    ],

    // Footer bilgi mimarisi
    'footer' => [
        ['h' => 'POS Sistemleri', 'items' => [
            ['t' => 'Kafe POS', 'u' => '/kafe-pos-sistemi'], ['t' => 'Restoran POS', 'u' => '/restoran-pos-sistemi'],
            ['t' => 'Nargile Salonu', 'u' => '/nargile-salonu-pos-sistemi'], ['t' => 'Bar & Pub', 'u' => '/bar-pub-pos-sistemi'],
            ['t' => 'Fast Food', 'u' => '/fast-food-pos-sistemi'], ['t' => 'Otel & Sosyal Tesis', 'u' => '/otel-pos-sistemi'],
        ]],
        ['h' => 'Sipariş Çözümleri', 'items' => [
            ['t' => 'QR Menü', 'u' => '/qr-menu'], ['t' => 'Mobil POS', 'u' => '/mobil-pos'],
            ['t' => 'Self Servis Kiosk', 'u' => '/self-servis-kiosk'], ['t' => 'Mutfak Ekranı', 'u' => '/mutfak-ekran-sistemi'],
            ['t' => 'Garson Uygulaması', 'u' => '/garson-uygulamasi'], ['t' => 'Kurye Yönetimi', 'u' => '/kurye-yonetimi'],
        ]],
        ['h' => 'İşletme Çözümleri', 'items' => [
            ['t' => 'Personel & Vardiya', 'u' => '/personel-yonetimi'], ['t' => 'Depo & Stok', 'u' => '/stok-yonetimi'],
            ['t' => 'Akıllı Raporlar', 'u' => '/satis-raporlari'], ['t' => 'Çoklu Şube', 'u' => '/coklu-sube-yonetimi'],
            ['t' => 'Rezervasyon', 'u' => '/rezervasyon-yonetimi'], ['t' => 'Müşteri & Sadakat', 'u' => '/musteri-sadakat'],
        ]],
        ['h' => 'Kurumsal', 'items' => [
            ['t' => 'Hakkımızda', 'u' => '/hakkimizda'], ['t' => 'Neden BamBumPOS', 'u' => '/neden-bambumpos'],
            ['t' => 'Fiyatlandırma', 'u' => '/fiyatlandirma'], ['t' => 'Entegrasyonlar', 'u' => '/entegrasyonlar'],
            ['t' => 'Blog', 'u' => '/blog'], ['t' => 'İletişim', 'u' => '/iletisim'],
        ]],
        ['h' => 'Destek & Yasal', 'items' => [
            ['t' => 'Destek Merkezi', 'u' => '/destek'], ['t' => 'Güvenlik & Altyapı', 'u' => '/guvenlik-altyapi'],
            ['t' => 'Gizlilik Politikası', 'u' => '/gizlilik-politikasi'], ['t' => 'KVKK Aydınlatma', 'u' => '/kvkk'],
            ['t' => 'Çerez Politikası', 'u' => '/cerez-politikasi'], ['t' => 'Kullanım Koşulları', 'u' => '/kullanim-kosullari'],
        ]],
    ],

    // SEO varsayılanları (per-sayfa @section ile ezilir)
    'seo' => [
        'title_suffix' => ' · BamBumPOS',
        'default_title' => 'BamBumPOS — Restoran & Kafe için Hepsi Bir Arada POS ve İşletme Yönetim Sistemi',
        'default_description' => 'BamBumPOS ile siparişten mutfağa, kasadan stoğa, personelden raporlamaya kadar tüm işletmenizi tek platformdan yönetin. Bulut tabanlı POS, QR menü ve işletme yönetim sistemi.',
        'og_image' => '/assets/site/og-default.png',
        'locale' => 'tr_TR',
    ],
];
