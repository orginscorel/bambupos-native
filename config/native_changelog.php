<?php

/**
 * Native (mobil/masaüstü) uygulama sürüm notları — Sürüm-Changelog ajanı.
 *
 * DÜRÜSTLÜK KURALI: QR Menü'nün şu an bir native (mobil/masaüstü) uygulaması
 * YOK — yalnız web panel ve tarayıcı tabanlı müşteri menüsü var. Bu dosyaya
 * sahte bir sürüm numarası veya "yayınlandı" durumu YAZILMAZ. Native
 * uygulama geliştirilip yayına alındığında `status` => 'released' olur,
 * `current_version` ve `entries` gerçek verilerle doldurulur. Yapı, diğer
 * bogahost sistemleriyle (finans/dcim/chat/task/muh) aynı desendedir —
 * ORTAK dosya biçimi; qrmenu'de henüz içerik yoktur.
 */
return [

    /** 'not_released' | 'released' */
    'status' => 'not_released',

    'current_version' => null,
    'released_at' => null,

    /** Hedeflenen ilk yayın sürümü — henüz kesinleşmedi, taahhüt değildir. */
    'planned_version' => '1.0.0',

    /** Yayınlanmış sürüm yokken kullanıcıya gösterilecek dürüst durum metni. */
    'status_message' => 'QR Menü native (mobil/masaüstü) uygulaması henüz yayınlanmadı. '
        .'Şu an QR Menü, tarayıcı üzerinden panel ve müşteri menüsü olarak sunuluyor. '
        .'Native uygulama planlandığında ilk sürüm notları burada yayınlanacak.',

    'entries' => [],

];
