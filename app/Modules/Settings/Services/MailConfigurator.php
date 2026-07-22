<?php

namespace App\Modules\Settings\Services;

use App\Modules\Settings\Models\MailSetting;
use App\Modules\Tenancy\TenantContext;

/**
 * Veritabanındaki e-posta ayarını ÇALIŞMA ANINDA mail yapılandırmasına
 * uygular (.env düzenlemeye gerek kalmaz).
 *
 * Tembel çalışır: RuntimeMailManager, bir mailer çözümlenirken (yani
 * gerçekten e-posta gönderilirken) apply() çağırır; normal isteklere
 * ek veritabanı maliyeti binmez.
 *
 * Hiç kayıt yoksa .env tabanlı özgün yapılandırma (baseline) aynen kalır.
 */
class MailConfigurator
{
    /** .env'den gelen özgün mail yapılandırması (ilk apply'da alınır). */
    private ?array $baseline = null;

    /** Son uygulanan yapılandırmanın imzası (gereksiz yeniden kurulumu önler). */
    private ?string $appliedSignature = null;

    /**
     * Bildirim gönderimi gibi kiracı bağlamının oturumdan çözülemediği
     * akışlar için açık kiracı ipucu (ör. parola sıfırlama: misafir istek,
     * ama alıcının tenant_id'si bilinir).
     */
    private ?int $tenantHint = null;

    public function __construct(
        private readonly MailSettingsService $settings,
        private readonly TenantContext $context,
    ) {
    }

    public function hintTenant(?int $tenantId): void
    {
        $this->tenantHint = $tenantId;
    }

    /** Geçerli kiracı için DB ayarını mail config'ine uygular. */
    public function apply(): void
    {
        $this->baseline ??= (array) config('mail');

        $tenantId = $this->tenantHint ?? $this->context->tenantId();

        ['setting' => $setting] = $this->settings->effective($tenantId);

        $config = $this->buildConfig($setting);

        $signature = md5(serialize([
            $config['default'] ?? null,
            $config['mailers'] ?? null,
            $config['from'] ?? null,
            $config['reply_to'] ?? null,
        ]));

        if ($signature === $this->appliedSignature) {
            return;
        }

        config(['mail' => $config]);

        // Önceden çözülmüş taşıyıcılar bayat kaldı; sıradaki çözümleme
        // yeni yapılandırmayla kurulsun.
        app('mail.manager')->forgetMailers();

        $this->appliedSignature = $signature;
    }

    /**
     * @return array<string, mixed>
     */
    private function buildConfig(?MailSetting $setting): array
    {
        $config = $this->baseline;

        if ($setting === null) {
            return $config; // .env'e düş
        }

        $config['default'] = $setting->mailer;
        $config['mailers'][$setting->mailer] = $setting->toMailerConfig();

        if ($setting->from_address) {
            $config['from'] = [
                'address' => $setting->from_address,
                'name' => $setting->from_name ?: ($config['from']['name'] ?? config('app.name')),
            ];
        }

        $config['reply_to'] = $setting->reply_to
            ? ['address' => $setting->reply_to, 'name' => $setting->from_name ?: null]
            : null;

        return $config;
    }
}
