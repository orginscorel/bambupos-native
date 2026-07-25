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
        'customers' => ['view', 'create', 'update', 'delete'],
        'stock' => ['view', 'adjust'],
        'reports' => ['view'],
        'staff' => ['view', 'manage'],
        'roles' => ['view', 'manage'],
        'branches' => ['view', 'manage'],
        'theme' => ['manage'],
        'integrations' => ['manage'],
        'settings' => ['view', 'manage'],
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
        'close' => 'Kasa kapat',
        'adjust' => 'Stok düzelt',
        'manage' => 'Yönet',
    ],

];
