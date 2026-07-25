<?php

/**
 * İzin kataloğu: "modül.işlem" anahtarları buradan seed edilir.
 * Roller sabit kodlanmaz; işletmeler bu katalogdan izin seçerek
 * kendi rollerini kurar (ADR / LEGACY §3.8 dersi).
 */
return [

    // Demo seed sahip parolası (yalnız seeder okur; rapor/log'a yazılmaz)
    'seed_owner_password' => env('SEED_OWNER_PASSWORD'),

    'modules' => [
        'catalog' => ['view', 'create', 'update', 'delete', 'change_price'],
        'orders' => ['view', 'create', 'update', 'delete', 'cancel', 'refund', 'discount', 'comp'],
        'payments' => ['take', 'refund'],
        'cash' => ['view', 'close'],
        'tables' => ['view', 'create', 'update', 'delete'],
        // Rezervasyon (Faz-9): view_sensitive = alerji notu gibi hassas
        // müşteri verisini görme (view'dan AYRI izin); manage = onay/iptal/
        // durum geçişleri + kapora takibi.
        'reservations' => ['view', 'create', 'update', 'delete', 'manage', 'view_sensitive'],
        'customers' => ['view', 'create', 'update', 'delete'],
        // Borçlar/Cari (Adisyon-Cari): view/create/update = cari kaydı
        // yönetimi; transfer = "adisyonu borca taşı" (garson da yapabilir,
        // para GİRİŞİ doğurmaz); collect = TAHSİLAT (para kaydı — hassas).
        'receivables' => ['view', 'create', 'update', 'transfer', 'collect'],
        'stock' => ['view', 'adjust'],
        // KDS (Faz-4): view = mutfak/bar ekranı (operasyon bilgisi, FİNANS YOK),
        // deliver = komi ekranı (teslim aldım / masaya götürdüm),
        // manage = istasyon tanımları + personel-istasyon ataması.
        'kds' => ['view', 'deliver', 'manage'],
        'reports' => ['view'],
        'staff' => ['view', 'manage'],
        'roles' => ['view', 'manage'],
        'branches' => ['view', 'manage'],
        'theme' => ['manage'],
        'integrations' => ['manage'],
        'settings' => ['view', 'manage'],
        // Kiosk (Faz-8): view = cihaz listesi + sağlık durumu (salt-okunur);
        // manage = cihaz ekle/kaldır, token yenile, uzaktan kilit/aç.
        'kiosk' => ['view', 'manage'],
        // Terminaller (§13): istasyon cihaz modu (kilitli Mutfak/Barista/Komi
        // terminalleri). view = cihaz listesi + sağlık; manage = ekle/kaldır,
        // token yenile, uzaktan kilit/aç (her cihaz gizli terminal kullanıcısı).
        'terminals' => ['view', 'manage'],
        'audit' => ['view'],
    ],

    'labels' => [
        'view' => 'Görüntüle',
        'create' => 'Oluştur',
        'update' => 'Güncelle',
        'delete' => 'Sil',
        'cancel' => 'İptal',
        'refund' => 'İade',
        'discount' => 'İndirim',
        'comp' => 'İkram',
        'change_price' => 'Fiyat değiştir',
        'take' => 'Ödeme al',
        'deliver' => 'Teslim / servis (komi)',
        'close' => 'Kasa kapat',
        'adjust' => 'Stok düzelt',
        'manage' => 'Yönet',
        'view_sensitive' => 'Hassas notları gör',
        'transfer' => 'Borca taşı',
        'collect' => 'Tahsilat al',
    ],

    // Yetki matrisi başlıkları (UI)
    'module_labels' => [
        'catalog' => 'Menü / Katalog',
        'orders' => 'Siparişler',
        'payments' => 'Ödemeler',
        'cash' => 'Kasa',
        'tables' => 'Masalar',
        'reservations' => 'Rezervasyonlar',
        'customers' => 'Müşteriler',
        'receivables' => 'Borçlar / Cari',
        'stock' => 'Stok',
        'kds' => 'Mutfak Ekranı (KDS)',
        'reports' => 'Raporlar',
        'staff' => 'Personel',
        'roles' => 'Roller & Yetkiler',
        'branches' => 'Şubeler',
        'theme' => 'Tema',
        'integrations' => 'Entegrasyonlar',
        'settings' => 'Ayarlar',
        'kiosk' => 'Kiosk',
        'terminals' => 'İstasyon Terminalleri',
        'audit' => 'Denetim Kaydı',
    ],

    /*
     * Tehlikeli izinler: matriste ayrı renk/ikonla işaretlenir ve kısa
     * açıklama gösterilir. Anahtar = izin, değer = neden riskli olduğu.
     */
    'dangerous' => [
        'orders.cancel' => 'Siparişi iptal eder; ciro kaydını etkiler.',
        'orders.refund' => 'Sipariş iadesi başlatır; para çıkışı doğurur.',
        'orders.discount' => 'Tutar üzerinde indirim uygular.',
        'orders.comp' => 'Ürünü ikram eder (bedelsiz).',
        'orders.delete' => 'Sipariş kaydını siler.',
        'payments.refund' => 'Alınmış ödemeyi iade eder; para çıkışı doğurur.',
        'cash.close' => 'Kasa oturumunu kapatır (Z raporu).',
        'catalog.change_price' => 'Satış fiyatlarını değiştirir.',
        'catalog.delete' => 'Ürün/kategori siler.',
        'stock.adjust' => 'Stok sayımlarını elle değiştirir.',
        'receivables.transfer' => 'Adisyonu ödenmemiş borca çevirir; masa boşalır ama tahsilat sonraya kalır.',
        'receivables.collect' => 'Cari tahsilat kaydı oluşturur; kasaya nakit/kart girişini temsil eder.',
        'reservations.delete' => 'Rezervasyon kaydını kalıcı siler.',
        'reservations.view_sensitive' => 'Alerji notu gibi hassas müşteri sağlık verisini görür.',
        'staff.manage' => 'Personel hesabı açar/kapatır, PIN sıfırlar.',
        'roles.manage' => 'Rol ve yetki setlerini değiştirir.',
        'audit.view' => 'Tüm denetim kayıtlarını görür.',
        'integrations.manage' => 'Dış sistem bağlantılarını yönetir.',
    ],

    /*
     * Rol şablonları: yeni işletme seed'i + "şablondan başlat" akışı.
     * Her şablon MANTIKLI VARSAYILAN settir; işletme sonradan özelleştirir.
     * 'all' → katalogtaki tüm izinler; 'except' bunlardan düşülür.
     */
    'templates' => [
        'sahip' => [
            'name' => 'Sahip',
            'description' => 'İşletme sahibi — tüm yetkiler.',
            'all' => true,
            'system' => true,
        ],
        'mudur' => [
            'name' => 'Müdür',
            'description' => 'Genel müdür — entegrasyonlar hariç tüm yetkiler.',
            'all' => true,
            'except' => ['integrations.manage'],
        ],
        'sube-muduru' => [
            'name' => 'Şube Müdürü',
            'description' => 'Operasyonun tamamı + raporlar; personel yönetimi sınırlı (rol/yetki tanımlayamaz).',
            'permissions' => [
                'catalog.view', 'catalog.create', 'catalog.update', 'catalog.delete', 'catalog.change_price',
                'orders.view', 'orders.create', 'orders.update', 'orders.cancel', 'orders.discount', 'orders.comp',
                'payments.take', 'cash.view', 'cash.close',
                'tables.view', 'tables.create', 'tables.update', 'tables.delete',
                'reservations.view', 'reservations.create', 'reservations.update',
                'reservations.delete', 'reservations.manage', 'reservations.view_sensitive',
                'customers.view', 'customers.create', 'customers.update',
                'receivables.view', 'receivables.create', 'receivables.update', 'receivables.transfer', 'receivables.collect',
                'stock.view', 'stock.adjust',
                'kds.view', 'kds.deliver', 'kds.manage',
                'reports.view',
                'staff.view', 'staff.manage',
                'roles.view',
                'branches.view',
                'settings.view',
                'kiosk.view', 'kiosk.manage',
                'terminals.view', 'terminals.manage',
            ],
        ],
        'garson' => [
            'name' => 'Garson',
            'description' => 'Sipariş alır ve günceller; nedenli ikram ve indirim uygulayabilir. Kasa, rapor ve personel kapalı.',
            'permissions' => [
                'catalog.view',
                'orders.view', 'orders.create', 'orders.update', 'orders.discount', 'orders.comp',
                'tables.view',
                'reservations.view', 'reservations.create', 'reservations.update',
                'customers.view',
                // Adisyonu borca taşıyabilir (masa boşalır); tahsilat YOK (kasiyer/yönetici işi).
                'receivables.view', 'receivables.transfer',
            ],
        ],
        'kasiyer' => [
            'name' => 'Kasiyer',
            'description' => 'Ödeme alır, kasa açar/kapatır. İade AYRI yetkidir ve varsayılan kapalıdır.',
            'permissions' => [
                'orders.view',
                'payments.take',
                'cash.view', 'cash.close',
                'tables.view',
                // Cari tahsilatı da kasiyer alır (aynı "ödeme alma" sorumluluğu).
                'receivables.view', 'receivables.collect',
            ],
        ],
        'mutfak' => [
            'name' => 'Mutfak',
            'description' => 'Yalnız mutfak ekranı (KDS) ve kendi istasyonu. Fiyat/ciro/rapor görmez.',
            'permissions' => ['kds.view'],
        ],
        'komi' => [
            'name' => 'Komi',
            'description' => 'Hazır siparişleri teslim alır ve masaya götürür.',
            'permissions' => ['kds.deliver', 'tables.view'],
        ],
    ],

    /*
     * Varsayılan açılış ekranları. Kullanıcı tercihi (users.default_screen)
     * boşsa sıra ile ilk İZİNLİ ekran seçilir (HomeScreen::resolve).
     * permission null → herkes görebilir; 'unless' izni varsa o ekran
     * otomatik seçimde ATLANIR (yönetici mutfağa düşmesin).
     */
    'screens' => [
        'orders' => ['label' => 'Siparişler', 'path' => '/panel/siparisler', 'permission' => 'orders.view'],
        'tables' => ['label' => 'Masalar', 'path' => '/panel/masalar', 'permission' => 'tables.view'],
        'cash' => ['label' => 'Kasa', 'path' => '/panel/kasa', 'permission' => 'payments.take'],
        'kds' => ['label' => 'Mutfak ekranı (KDS)', 'path' => '/panel/mutfak', 'permission' => 'kds.view'],
        'barista' => ['label' => 'Barista ekranı', 'path' => '/panel/barista', 'permission' => 'kds.view'],
        'runner' => ['label' => 'Komi ekranı', 'path' => '/panel/komi', 'permission' => 'kds.deliver'],
        'catalog' => ['label' => 'Menü yönetimi', 'path' => '/panel/menu', 'permission' => 'catalog.view'],
        'staff' => ['label' => 'Personel', 'path' => '/panel/personel', 'permission' => 'staff.view'],
        'dashboard' => ['label' => 'Panel (genel bakış)', 'path' => '/panel', 'permission' => null],
    ],

    /*
     * İçecek/bar ailesi istasyon anahtarları (config/kds.php builtin_stations).
     * Otomatik açılışta: kişinin atandığı istasyonların HEPSİ bu ailedeyse
     * Barista ekranına, aksi halde (yemek/karışık) Mutfak ekranına düşer.
     */
    'barista_stations' => ['barista', 'coffee', 'bar'],

];
