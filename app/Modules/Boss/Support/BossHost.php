<?php

namespace App\Modules\Boss\Support;

use Illuminate\Http\Request;

/**
 * Patron Paneli host yardımcıları (personel `Portal` deseninin eşi).
 *
 * Patron Paneli, aynı Laravel uygulamasının ayrı bir subdomain'de
 * (config('boss.host')) sunulan executive yüzüdür. Host eşleşiyorsa Patron
 * Paneli kökte (/) açılır; aksi hâlde normal panel/portal çalışır (DEĞİŞMEZ).
 * DNS henüz yoksa test/geliştirme için Host header ile erişilir.
 */
class BossHost
{
    /** Yapılandırılmış patron host'u. */
    public static function host(): string
    {
        return (string) config('boss.host', 'patron.bogahostdeveloper.com.tr');
    }

    /** İstek patron host'undan mı geliyor? (Host header'a bakar → test edilebilir) */
    public static function isBossHost(Request $request): bool
    {
        $host = self::host();

        return $host !== '' && strcasecmp($request->getHost(), $host) === 0;
    }

    /** Patron girişinde uzun ömürlü remember-me zorlanacak mı? */
    public static function forcesRemember(): bool
    {
        return (bool) config('boss.force_remember', true);
    }
}
