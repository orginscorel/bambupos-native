<?php

namespace App\Modules\Portal\Support;

use Illuminate\Http\Request;

/**
 * Personel Portalı host yardımcıları.
 *
 * Portal, aynı Laravel uygulamasının ayrı bir subdomain'de (config('portal.host'))
 * sunulan mobil-öncelikli yüzüdür. Host eşleşiyorsa portal rotaları/layout'u
 * devreye girer; aksi hâlde normal panel çalışır (DEĞİŞMEZ). DNS henüz yoksa
 * test/geliştirme için Host header ile erişilir.
 */
class Portal
{
    /** Yapılandırılmış portal host'u. */
    public static function host(): string
    {
        return (string) config('portal.host', 'personel.bogahostdeveloper.com.tr');
    }

    /** İstek portal host'undan mı geliyor? (Host header'a bakar → test edilebilir) */
    public static function isPortalHost(Request $request): bool
    {
        $host = self::host();

        return $host !== '' && strcasecmp($request->getHost(), $host) === 0;
    }

    /** Portal girişinde uzun ömürlü remember-me zorlanacak mı? */
    public static function forcesRemember(): bool
    {
        return (bool) config('portal.force_remember', true);
    }
}
