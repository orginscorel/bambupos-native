<?php

namespace App\Modules\Payments\Providers;

/**
 * Adapter çağrılarının ortak sonucu. `status` sağlayıcı gerçeğidir:
 *  - approved  → sağlayıcı işlemi ONAYLADI (tek "başarılı" kaynağı)
 *  - declined  → sağlayıcı reddetti
 *  - pending   → sağlayıcı hâlâ işliyor (callback/sorgu beklenir)
 *  - timeout   → sağlayıcıya ulaşılamadı / cevap gelmedi (durum BİLİNMİYOR;
 *                asla başarısız sayma — queryPayment ile netleştir)
 *  - error     → çağrı hatası (durum bilinmiyor)
 */
final class ProviderResult
{
    public const APPROVED = 'approved';

    public const DECLINED = 'declined';

    public const PENDING = 'pending';

    public const TIMEOUT = 'timeout';

    public const ERROR = 'error';

    /** @param array<string, mixed> $raw */
    public function __construct(
        public readonly string $status,
        public readonly ?string $providerTxnId = null,
        public readonly ?string $message = null,
        public readonly array $raw = [],
    ) {
    }

    public function approved(): bool
    {
        return $this->status === self::APPROVED;
    }

    public function declined(): bool
    {
        return $this->status === self::DECLINED;
    }

    /** Durum belirsiz mi (pending/timeout/error → sorgu gerekir)? */
    public function unknown(): bool
    {
        return in_array($this->status, [self::PENDING, self::TIMEOUT, self::ERROR], true);
    }
}
