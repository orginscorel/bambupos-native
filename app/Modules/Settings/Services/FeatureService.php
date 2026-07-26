<?php

namespace App\Modules\Settings\Services;

use App\Modules\Settings\Models\TenantFeature;
use App\Modules\Settings\Support\FeatureCatalog;

/**
 * Feature-flag okuma/yazma tek kapısı — MODULE_MAP §9.
 *
 * `scoped` bağlanır (SettingsServiceProvider) → memo İSTEK BAŞINA tazedir;
 * testler arası bayat durum riski yok, Redis'e ihtiyaç yok. Bir istekte
 * (nav süzgeci + rota gate'leri + auth paylaşımı) çok kez sorulsa da tek
 * sorguyla çözülür.
 *
 * Depo: `tenant_features` (satır yoksa FeatureCatalog::default). Kiracı
 * süzgeci burada AÇIKÇA uygulanır (global scope yok).
 */
class FeatureService
{
    /** @var array<int, array<string, bool>> tenantId => (key => enabled) */
    private array $memo = [];

    /**
     * Bir kiracının TÜM opsiyonel özelliklerinin efektif durumu.
     * Varsayılanların üstüne DB satırları bindirilir.
     *
     * @return array<string, bool>
     */
    public function all(?int $tenantId): array
    {
        $tenantId = (int) $tenantId;

        if ($tenantId <= 0) {
            // Kiracı bağlamı yok → salt varsayılanlar (yazma yapılmaz).
            return FeatureCatalog::defaults();
        }

        if (isset($this->memo[$tenantId])) {
            return $this->memo[$tenantId];
        }

        $state = FeatureCatalog::defaults();

        $rows = TenantFeature::query()
            ->where('tenant_id', $tenantId)
            ->get(['feature', 'enabled']);

        foreach ($rows as $row) {
            // Katalogdan kalkmış eski anahtarları yok say (kirlilik sızmasın).
            if (FeatureCatalog::isKnown((string) $row->feature)) {
                $state[$row->feature] = (bool) $row->enabled;
            }
        }

        return $this->memo[$tenantId] = $state;
    }

    /** Tek özellik açık mı? Bilinmeyen/çekirdek anahtar → true (fail-open). */
    public function enabled(?int $tenantId, string $key): bool
    {
        if (! FeatureCatalog::isKnown($key)) {
            return true;
        }

        return $this->all($tenantId)[$key] ?? FeatureCatalog::default($key);
    }

    /**
     * Bir özelliği aç/kapat (upsert). Yalnız katalogdaki anahtarlar yazılır.
     */
    public function set(int $tenantId, string $key, bool $enabled): void
    {
        if ($tenantId <= 0 || ! FeatureCatalog::isKnown($key)) {
            return;
        }

        TenantFeature::query()->updateOrCreate(
            ['tenant_id' => $tenantId, 'feature' => $key],
            ['enabled' => $enabled],
        );

        unset($this->memo[$tenantId]); // memo tazelensin
    }
}
