<?php

declare(strict_types=1);

namespace App\Modules\Integrations\Support;

use App\Modules\Integrations\Models\TenantIntegration;

/**
 * Takılabilir entegrasyon çerçevesinin OKUMA cephesi (facade).
 *
 * Sistemin geri kalanı bir entegrasyonun bu kiracı için açık olup olmadığını
 * ve (açıksa) yapılandırmasını buradan sorar:
 *
 *     Integrations::enabled($tenantId, 'iyzico')  // ödeme akışı seçenek ekler mi?
 *     Integrations::config($tenantId, 'iyzico')   // API anahtarları
 *
 * SÖZLEŞME (graceful no-op): KAPALI veya YAPILANDIRILMAMIŞ → enabled=false,
 * config=[]. Böylece pasif entegrasyon sistemi HİÇ etkilemez; çağıran taraf
 * yalnız `enabled` true dönerse entegrasyona uyum sağlar.
 *
 * Kiracı süzgeci BURADA AÇIKÇA uygulanır (withoutTenancy + explicit tenant_id)
 * — bağlamdan bağımsız doğru kiracıyı okur; çapraz-kiracı sızıntısı olmaz.
 * İstek başına memo ile tekrar sorgular tek okumaya iner.
 */
final class Integrations
{
    /** @var array<int, array<string, array{is_enabled: bool, config: array<string, mixed>}>> */
    private static array $memo = [];

    /** Bu entegrasyon bu kiracı için AKTİF mi? Bilinmeyen/kapalı → false. */
    public static function enabled(?int $tenantId, string $key): bool
    {
        $tenantId = (int) $tenantId;

        if ($tenantId <= 0 || ! IntegrationCatalog::isKnown($key)) {
            return false;
        }

        return self::rows($tenantId)[$key]['is_enabled'] ?? false;
    }

    /**
     * Entegrasyonun yapılandırması (API anahtarları vb.). KAPALIYSA veya
     * yapılandırılmamışsa BOŞ dizi döner — çağıran taraf güvenle no-op yapar.
     *
     * @return array<string, mixed>
     */
    public static function config(?int $tenantId, string $key): array
    {
        $tenantId = (int) $tenantId;

        if ($tenantId <= 0 || ! IntegrationCatalog::isKnown($key)) {
            return [];
        }

        $row = self::rows($tenantId)[$key] ?? null;

        // Sözleşme: yalnız AKTİF entegrasyon config verir (pasifse sistem sessiz).
        if ($row === null || $row['is_enabled'] !== true) {
            return [];
        }

        return $row['config'];
    }

    /** İstek-başı memo'yu temizler (yazma sonrası tazeleme; testler). */
    public static function flush(?int $tenantId = null): void
    {
        if ($tenantId === null) {
            self::$memo = [];

            return;
        }

        unset(self::$memo[(int) $tenantId]);
    }

    /**
     * Kiracının tüm entegrasyon satırları (key => durum+config), tek sorgu.
     *
     * @return array<string, array{is_enabled: bool, config: array<string, mixed>}>
     */
    private static function rows(int $tenantId): array
    {
        if (isset(self::$memo[$tenantId])) {
            return self::$memo[$tenantId];
        }

        $rows = TenantIntegration::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->get(['key', 'is_enabled', 'config']);

        $state = [];

        foreach ($rows as $row) {
            // Katalogdan kalkmış eski anahtarları yok say (kirlilik sızmasın).
            if (! IntegrationCatalog::isKnown((string) $row->key)) {
                continue;
            }

            $state[(string) $row->key] = [
                'is_enabled' => (bool) $row->is_enabled,
                'config' => is_array($row->config) ? $row->config : [],
            ];
        }

        return self::$memo[$tenantId] = $state;
    }
}
