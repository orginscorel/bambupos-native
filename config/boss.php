<?php

/*
|--------------------------------------------------------------------------
| Patron Paneli (host-farkındalıklı — AYRI SİSTEM)
|--------------------------------------------------------------------------
| Aynı Laravel uygulaması, ayrı bir subdomain'de (patron.*) executive Patron
| Paneli'ni sunar — personel portalı (personel.*) deseninin birebir eşi. İstek
| Host'u `host` ile eşleşiyorsa Patron Paneli kökte (/) açılır; aksi hâlde
| normal panel/portal çalışır (DEĞİŞMEZ).
|
| DNS henüz yoksa test için Host header ile erişilebilir:
|   curl -H 'Host: patron.bogahostdeveloper.com.tr' https://.../
|
| Kurulum (DNS + SSL) personel portalıyla aynı: cPanel subdomain → aynı docroot
| + LiteSpeed/acme SAN sertifikası.
*/

return [

    // Patron subdomain'i (BOSS_HOST ile .env'den geçersiz kılınabilir).
    'host' => env('BOSS_HOST', 'patron.bogahostdeveloper.com.tr'),

    // Patron girişinde uzun ömürlü "beni hatırla" (personel portalı gibi).
    'force_remember' => (bool) env('BOSS_FORCE_REMEMBER', true),
];
