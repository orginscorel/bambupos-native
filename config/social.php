<?php

/*
|--------------------------------------------------------------------------
| Güven bandı (stats) + müşteri yorumları (testimonials)
|--------------------------------------------------------------------------
| ÖNEMLİ: Buradaki değerler DÜZENLENEBİLİR. Gerçek rakam/yorumlarınızı girin.
| Sahte/ödünç rakam veya sahte yorum KULLANMAYIN (yanıltıcı olur).
|
| - stats:  güven bandındaki 3 gösterge. 'num' bir rakam VEYA kısa etiket olabilir.
|           Gerçek "aktif işletme sayınız" varsa buraya girin.
| - businesses_count: gerçek işletme sayınız (örn. '250+'). Boşsa güven başlığı
|           rakamsız gösterilir (yanıltıcı bir sayı uydurulmaz).
| - testimonials: YALNIZCA gerçek müşteri yorumlarını ekleyin. Aşağıdakiler
|           tasarımı göstermek için ÖRNEK'tir; gerçeğiyle değiştirin veya boşaltın.
|           Dizi boşsa yorum bölümü otomatik GİZLENİR.
*/

return [

    // Gerçek işletme sayınız (ör. '250+'). Boş bırakılırsa başlık rakamsız gösterilir.
    'businesses_count' => '',

    // Güven bandı — varsayılanlar ürünün GERÇEK nitelikleridir (uydurma sayı değil).
    'stats' => [
        ['num' => 'Tek platform', 'label' => 'POS · QR menü · mutfak · stok · personel · rapor'],
        ['num' => 'Bulut + çevrimdışı', 'label' => 'yedekli altyapı; internet kesilse de satış sürer'],
        ['num' => '7/24', 'label' => 'destek talebi ve menü aktarım desteği'],
    ],

    /*
    | REFERANSLAR
    |--------------------------------------------------------------------------
    | 'references': GERÇEK müşteri/marka referansları. Her biri:
    |   ['name' => 'Marka Adı', 'sector' => 'Kafe', 'logo' => '/assets/site/refs/marka.png' (opsiyonel)]
    |   'logo' verilirse logo görseli, verilmezse marka adı + baş harf rozeti gösterilir.
    |   Dizi DOLUYSA "logo/isim duvarı" render edilir.
    |   Dizi BOŞSA (varsayılan) → uydurma marka gösterilmez; bunun yerine sistemin
    |   kullanıldığı DÜRÜST "işletme türleri" şeridi (reference_types) gösterilir.
    */
    'references_are_placeholder' => true,
    'references' => [
        // ['name' => 'Örnek Kafe', 'sector' => 'Kafe'],
    ],

    // Referans DUVARI boşken gösterilen dürüst "işletme türleri" (uydurma marka değil).
    'reference_types' => [
        ['label' => 'Kafe & Kahveci', 'icon' => 'coffee'],
        ['label' => 'Restoran', 'icon' => 'utensils'],
        ['label' => 'Nargile Salonu', 'icon' => 'flame'],
        ['label' => 'Bar & Pub', 'icon' => 'glass'],
        ['label' => 'Fast Food', 'icon' => 'burger'],
        ['label' => 'Otel & Sosyal Tesis', 'icon' => 'bed'],
        ['label' => 'Paket Servis', 'icon' => 'truck'],
        ['label' => 'Çok Şubeli Zincir', 'icon' => 'branch'],
    ],

    // ⚠️ ÖRNEK yorumlar — gerçek müşteri yorumlarıyla değiştirin (isim + işletme).
    // Gerçek yorum yoksa bu diziyi boş bırakın → bölüm gizlenir.
    'testimonials_are_placeholder' => true,
    'testimonials' => [
        ['quote' => 'Kurulum beklediğimizden hızlı oldu; menümüz aynı gün aktifti ve ekibimiz ilk günden rahatça kullandı.', 'name' => 'İşletme sahibi', 'business' => 'Örnek Kafe', 'sector' => 'Kafe'],
        ['quote' => 'Mutfak ekranı sayesinde sipariş karışıklığı bitti; masalar arası akış ve hesap bölme çok pratik.', 'name' => 'İşletme müdürü', 'business' => 'Örnek Restoran', 'sector' => 'Restoran'],
        ['quote' => 'Şubeler arası ciro ve stok takibini tek panelden görüyoruz; raporlar anlık geliyor.', 'name' => 'Zincir yöneticisi', 'business' => 'Örnek Zincir', 'sector' => 'Çok şubeli'],
    ],
];
