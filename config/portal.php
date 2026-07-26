<?php

/*
|--------------------------------------------------------------------------
| Personel Portalı (host-farkındalıklı self-servis)
|--------------------------------------------------------------------------
| Aynı Laravel uygulaması, ayrı bir subdomain'de mobil-öncelikli personel
| portalı sunar. İstek Host'u `host` ile eşleşiyorsa portal rotaları/layout'u
| devreye girer; aksi hâlde normal panel çalışır (DEĞİŞMEZ).
|
| DNS henüz yoksa test için Host header ile erişilebilir:
|   curl -H 'Host: personel.bogahostdeveloper.com.tr' https://.../mesaim
|
| Portal oturumu KALICIDIR (uzun ömürlü remember-me + idle-timeout yok).
| Oto-kapanma YALNIZ 3 durumda: pasife alınma, işten çıkarma (=pasif/silme),
| parola değişimi (AuthenticateSession).
*/

return [

    // Portal subdomain'i (PORTAL_HOST ile .env'den geçersiz kılınabilir).
    'host' => env('PORTAL_HOST', 'personel.bogahostdeveloper.com.tr'),

    // Portal girişinde uzun ömürlü "beni hatırla" (remember-me) zorlanır mı?
    // Laravel remember çerezi ~5 yıl (forever) ömürlüdür; bu bayrak yalnızca
    // portal host'undan yapılan girişte remember=true'yu garantiler (panel
    // host'unun davranışı DEĞİŞMEZ).
    'force_remember' => (bool) env('PORTAL_FORCE_REMEMBER', true),
];
