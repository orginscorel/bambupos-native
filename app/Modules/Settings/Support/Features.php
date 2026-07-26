<?php

namespace App\Modules\Settings\Support;

use App\Modules\Settings\Services\FeatureService;

/**
 * Feature-flag STATİK cephe (facade) — MODULE_MAP §9.
 *
 * Modüllerdeki yer-tutucu bayrak sınıfları (KioskFeature, ReservationFeature,
 * InventoryFeature, ShiftsFeature) ve rota gate'leri buradan çağırır:
 *
 *     Features::enabled($tenantId, 'kiosk')   // panel/public gate
 *     Features::all($tenantId)                // auth paylaşımı (nav süzgeci)
 *     Features::set($tenantId, 'kiosk', false)// Eklentiler ekranı
 *
 * Gerçek iş `FeatureService` (scoped, istek-başına memo) içinde; katalog
 * saf statik. ADR: kapalı = özellik hiç render edilmez, veri sızmaz.
 */
final class Features
{
    private static function service(): FeatureService
    {
        return app(FeatureService::class);
    }

    public static function enabled(?int $tenantId, string $key): bool
    {
        return self::service()->enabled($tenantId, $key);
    }

    /** @return array<string, bool> */
    public static function all(?int $tenantId): array
    {
        return self::service()->all($tenantId);
    }

    public static function set(int $tenantId, string $key, bool $enabled): void
    {
        self::service()->set($tenantId, $key, $enabled);
    }

    /** @return list<array{key: string, name: string, description: string, default: bool}> */
    public static function catalog(): array
    {
        return FeatureCatalog::all();
    }

    /** @return list<string> */
    public static function keys(): array
    {
        return FeatureCatalog::keys();
    }
}
