<?php

declare(strict_types=1);

namespace App\Modules\Payments\Services;

use App\Modules\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;

/**
 * POS ENTEGRATÖR ÇÖZÜCÜSÜ — her işletme (tenant) kendi ödeme cihazını/kimliğini
 * seçer; çekirdek koda dokunmadan yeni cihaz/banka eklenir ("kod değil konfig").
 *
 * Kaynak: `tenant_integrations` (key='pos_terminal', is_enabled=1, config JSON).
 * config örneği:
 *   {
 *     "provider": "generic_rest",        // registry anahtarı (adaptör)
 *     "preset": "token_gmp3",            // config/payments.presets şablonu (opsiyonel)
 *     "base_url": "https://tsm.saglayici.com/api",
 *     "merchant_id": "...", "terminal_id": "...",
 *     "auth": {"type":"hmac","key_id":"...","secret":"..."},
 *     "endpoints": {...}, "map": {...},  // preset ile birleşir (tenant üstün gelir)
 *     "callback": {"sig_header":"X-Pos-Signature","ts_header":"X-Pos-Timestamp","secret":"..."}
 *   }
 *
 * Sır alanlar (secret/api_key/password) DB'de yaşar; burada YALNIZ okunur, log'a
 * DÜŞMEZ (PaymentService/loglar bunları maskeler).
 */
class PosConfigResolver
{
    /** @var array<int, array<string, mixed>|null> istek-içi önbellek (tenant → config) */
    private array $cache = [];

    public function __construct(private readonly TenantContext $tenants)
    {
    }

    /**
     * Geçerli işletmenin POS entegratör yapılandırması (yoksa null).
     * preset + tenant config derin-birleştirilir (tenant değerleri üstün).
     *
     * @return array<string, mixed>|null
     */
    public function forCurrentTenant(): ?array
    {
        $tenantId = (int) $this->tenants->tenantId();

        if ($tenantId <= 0) {
            return null;
        }

        if (array_key_exists($tenantId, $this->cache)) {
            return $this->cache[$tenantId];
        }

        return $this->cache[$tenantId] = $this->load($tenantId);
    }

    /** Geçerli işletmenin seçili sağlayıcı anahtarı (yoksa null → global varsayılan). */
    public function providerKey(): ?string
    {
        $cfg = $this->forCurrentTenant();
        $key = is_array($cfg) ? ($cfg['provider'] ?? null) : null;

        return is_string($key) && $key !== '' ? $key : null;
    }

    /** İstek-içi önbelleği temizle (test/işletme değişimi). */
    public function flush(): void
    {
        $this->cache = [];
    }

    /**
     * @return array<string, mixed>|null
     */
    private function load(int $tenantId): ?array
    {
        $row = DB::table('tenant_integrations')
            ->where('tenant_id', $tenantId)
            ->where('key', 'pos_terminal')
            ->where('is_enabled', true)
            ->first();

        if ($row === null) {
            return null;
        }

        $config = json_decode((string) $row->config, true);

        if (! is_array($config) || ($config['provider'] ?? '') === '') {
            return null;
        }

        // Preset varsa şablonla birleştir (tenant değerleri ÜSTÜN gelir).
        $preset = is_string($config['preset'] ?? null)
            ? (array) config('payments.presets.'.$config['preset'], [])
            : [];

        return $this->deepMerge($preset, $config);
    }

    /**
     * Derin birleştirme: iç içe dizilerde $override, $base'i geçersiz kılar.
     *
     * @param  array<string, mixed>  $base
     * @param  array<string, mixed>  $override
     * @return array<string, mixed>
     */
    private function deepMerge(array $base, array $override): array
    {
        foreach ($override as $key => $value) {
            if (is_array($value) && isset($base[$key]) && is_array($base[$key])) {
                $base[$key] = $this->deepMerge($base[$key], $value);
            } else {
                $base[$key] = $value;
            }
        }

        return $base;
    }
}
