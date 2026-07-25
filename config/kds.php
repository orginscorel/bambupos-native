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
    // İKİ ANA İSTASYON önce gelir (§12 — kullanıcı ayrımı net olsun):
    //   kitchen → MUTFAK (tüm yemekler)  ·  barista → BARİSTA (kahve/çay/içecek/bar)
    // Mutfakta kimse içecek yapmaz; içecekler Barista'ya düşer. Alttakiler
    // "genişletilebilir" örnekleridir (Tatlı/Izgara vb.) — işletme dilerse
    // ürünleri bunlara da atayabilir; demo yalnız Mutfak/Barista/Nargile kullanır.
    // NOT: 'kitchen' Faz-2'den beri mutfak anahtarıdır — key SABİT kalır
    // (ürün/kalem yönlendirmesi bozulmasın), yalnız etiket "Mutfak" oldu.
    'builtin_stations' => [
        ['key' => 'kitchen', 'name' => 'Mutfak', 'icon' => 'flame'],
        ['key' => 'barista', 'name' => 'Barista', 'icon' => 'coffee'],
        ['key' => 'grill', 'name' => 'Izgara', 'icon' => 'flame'],
        ['key' => 'dessert', 'name' => 'Tatlı', 'icon' => 'cake'],
        ['key' => 'cold_kitchen', 'name' => 'Soğuk Mutfak', 'icon' => 'snowflake'],
        ['key' => 'oven', 'name' => 'Fırın', 'icon' => 'oven'],
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
