<?php

namespace App\Modules\Settings\Services;

use App\Modules\Settings\Models\MailSetting;

/**
 * E-posta ayarlarının saklanması ve "geçerli ayar" çözümlemesi.
 *
 * Çözümleme sırası (effective):
 *  1. İşletmenin kendi override satırı   → source: tenant
 *  2. Platform varsayılan satırı (NULL)  → source: platform
 *  3. Hiçbiri yoksa .env yapılandırması  → source: env (setting: null)
 */
class MailSettingsService
{
    public function platform(): ?MailSetting
    {
        return MailSetting::query()->whereNull('tenant_id')->first();
    }

    public function forTenant(?int $tenantId): ?MailSetting
    {
        if ($tenantId === null) {
            return null;
        }

        return MailSetting::query()->where('tenant_id', $tenantId)->first();
    }

    /**
     * @return array{setting: MailSetting|null, source: 'tenant'|'platform'|'env'}
     */
    public function effective(?int $tenantId): array
    {
        $tenantSetting = $this->forTenant($tenantId);

        if ($tenantSetting !== null) {
            return ['setting' => $tenantSetting, 'source' => 'tenant'];
        }

        $platform = $this->platform();

        if ($platform !== null) {
            return ['setting' => $platform, 'source' => 'platform'];
        }

        return ['setting' => null, 'source' => 'env'];
    }

    /**
     * Kaydet (yoksa oluştur). $tenantId NULL ise platform satırı hedeflenir.
     *
     * Parola kuralı: $data['password'] anahtarı YOKSA veya boşsa mevcut
     * parola korunur; yalnız dolu bir değer geldiğinde değiştirilir.
     *
     * @param  array<string, mixed>  $data
     */
    public function save(?int $tenantId, array $data): MailSetting
    {
        $setting = ($tenantId === null ? $this->platform() : $this->forTenant($tenantId))
            ?? new MailSetting;

        if (! $setting->exists) {
            $setting->tenant_id = $tenantId;
        }

        $password = $data['password'] ?? null;
        unset($data['password']);

        $setting->fill($data);

        if (is_string($password) && $password !== '') {
            $setting->password = $password;
        }

        $setting->save();

        return $setting;
    }
}
