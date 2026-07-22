<?php

/**
 * KDS modülü (Faz-4): mutfak/bar/komi ekranları.
 *
 * İstasyon modeli: aşağıdaki YERLEŞİK istasyonlar her kiracıda hazırdır;
 * işletme kds_stations tablosuna KENDİ istasyonlarını ekler (StationRegistry
 * ikisini birleştirir). Ürün → istasyon yönlendirmesi Catalog'daki
 * products.station anahtarıyla yapılır (satış anında order_items.station'a
 * snapshot'lanır — Orders Faz-3).
 */
return [

    // Yerleşik istasyonlar (key ürün kartındaki `station` değeriyle eşleşir).
    // 'kitchen' Faz-2'den beri "mutfak" olarak kullanılıyor → Sıcak Mutfak.
    'builtin_stations' => [
        ['key' => 'kitchen', 'name' => 'Sıcak Mutfak', 'icon' => 'flame'],
        ['key' => 'cold_kitchen', 'name' => 'Soğuk Mutfak', 'icon' => 'snowflake'],
        ['key' => 'grill', 'name' => 'Izgara', 'icon' => 'flame'],
        ['key' => 'oven', 'name' => 'Fırın', 'icon' => 'oven'],
        ['key' => 'dessert', 'name' => 'Tatlı', 'icon' => 'cake'],
        ['key' => 'coffee', 'name' => 'Kahve', 'icon' => 'coffee'],
        ['key' => 'bar', 'name' => 'Bar', 'icon' => 'glass'],
        ['key' => 'hookah', 'name' => 'Nargile', 'icon' => 'smoke'],
        ['key' => 'packaging', 'name' => 'Paketleme', 'icon' => 'package'],
    ],

    // İstasyonu boş ürünlerin düştüğü sanal kova (ekranda "İstasyonsuz").
    'unassigned_key' => '_none',

    // SLA: hedef süre ürünün prep_minutes'ı; yoksa bu varsayılan (dk).
    'default_prep_minutes' => 15,

    // Bekleme süresi hedefe ulaşınca UYARI, late_ratio × hedefte GECİKMİŞ.
    // Renk + ikon + süre metni birlikte gösterilir (yalnız renk değil).
    'late_ratio' => 1.5,

    // Ekran polling aralığı (sn) — ADR-006: 3–5 sn, cursor'lı, boşta 204.
    'poll_interval_seconds' => 4,

];
