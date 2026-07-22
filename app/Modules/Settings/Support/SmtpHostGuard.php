<?php

namespace App\Modules\Settings\Support;

/**
 * SSRF önlemi: platform-dışı işletmelerin SMTP hedefi olarak iç ağ /
 * ayrılmış adresleri kullanmasını engeller. (Test düğmesi gerçek TCP
 * bağlantısı kurar; bu sınıf onu iç ağ tarayıcısına dönüştürmeyi önler.)
 */
class SmtpHostGuard
{
    /** Adres iç ağa/ayrılmış aralığa çözülüyorsa TRUE döner. */
    public static function isForbidden(string $host): bool
    {
        $host = trim($host, "[] \t");

        if ($host === '' || strcasecmp($host, 'localhost') === 0) {
            return true;
        }

        // Doğrudan IP yazılmışsa
        if (filter_var($host, FILTER_VALIDATE_IP) !== false) {
            return self::isPrivateIp($host);
        }

        // Alan adı: A/AAAA kayıtlarının TAMAMI denetlenir (rebinding'e karşı
        // en azından kayıt düzeyinde savunma; ek olarak hız sınırı da var).
        $ips = [];

        $records = @dns_get_record($host, DNS_A | DNS_AAAA) ?: [];
        foreach ($records as $record) {
            if (isset($record['ip'])) {
                $ips[] = $record['ip'];
            }
            if (isset($record['ipv6'])) {
                $ips[] = $record['ipv6'];
            }
        }

        if ($ips === []) {
            // Çözülemeyen ad: bağlantı zaten kurulamaz; test dürüstçe
            // "sunucuya ulaşılamadı" der. Engellemeye gerek yok.
            return false;
        }

        foreach ($ips as $ip) {
            if (self::isPrivateIp($ip)) {
                return true;
            }
        }

        return false;
    }

    private static function isPrivateIp(string $ip): bool
    {
        return filter_var(
            $ip,
            FILTER_VALIDATE_IP,
            FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE,
        ) === false;
    }
}
