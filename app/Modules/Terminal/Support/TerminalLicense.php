<?php

namespace App\Modules\Terminal\Support;

use App\Modules\Terminal\Models\TerminalDevice;
use App\Modules\Tenancy\Models\Tenant;

/**
 * Terminal LİSANS limiti (§13 Faz 3 — panelden lisanslı terminal kurulumu).
 *
 * Kaynak: `tenants.terminal_license_limit` (nullable int; NULL = sınırsız,
 * bilinçli istisna). Sütun bir DB-varsayılanına sahiptir (bkz. migration +
 * config/terminal.php `license.default_limit`) — yani "atanmamış" durum
 * pratikte yoktur; her kiracı en azından makul bir varsayılanla başlar.
 *
 * Kullanılan sayaç TenantScope (BelongsToTenant) üzerinden HER ZAMAN
 * oturumdaki kiracıya süzülür — çağıran ayrıca tenant_id filtrelemez.
 * Plana bağlı türetme BİLİNÇLİ OLARAK burada YOK (bkz. config/terminal.php).
 */
final class TerminalLicense
{
    public static function defaultLimit(): int
    {
        return (int) config('terminal.license.default_limit', 5);
    }

    /** NULL = sınırsız. */
    public static function limitFor(Tenant $tenant): ?int
    {
        return $tenant->terminal_license_limit;
    }

    /** O anki kiracının kullanımdaki terminal cihaz sayısı (TenantScope süzer). */
    public static function usedCount(): int
    {
        return TerminalDevice::query()->count();
    }

    public static function hasCapacity(Tenant $tenant): bool
    {
        $limit = self::limitFor($tenant);

        if ($limit === null) {
            return true;
        }

        return self::usedCount() < $limit;
    }

    /**
     * Panel göstergesi için tam durum: limit/kullanılan/kalan/sınırsız mı.
     *
     * @return array{limit: int|null, used: int, remaining: int|null, unlimited: bool}
     */
    public static function snapshot(Tenant $tenant): array
    {
        $limit = self::limitFor($tenant);
        $used = self::usedCount();

        return [
            'limit' => $limit,
            'used' => $used,
            'remaining' => $limit === null ? null : max(0, $limit - $used),
            'unlimited' => $limit === null,
        ];
    }

    /** 422 gövdesinde gösterilecek net, eylem çağıran hata metni. */
    public static function limitReachedMessage(Tenant $tenant): string
    {
        $limit = self::limitFor($tenant);
        $used = self::usedCount();

        return "Terminal lisans limitiniz doldu ({$used}/{$limit}). Yükseltme için destek ekibiyle iletişime geçin.";
    }
}
