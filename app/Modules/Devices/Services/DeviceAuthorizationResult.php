<?php

namespace App\Modules\Devices\Services;

use App\Modules\Devices\Models\AuthorizedDevice;

/**
 * DeviceBindingService::authorize() sonucu.
 *
 * $tokenToPersist DOLU ise middleware bunu tarayıcıya çerez olarak yazmalıdır
 * (yeni bağlanma / ilk ziyaret). NULL ise ya istek reddedildi ya da tarayıcı
 * zaten doğru token'ı sunuyordu (yeniden yazmaya gerek yok).
 */
final class DeviceAuthorizationResult
{
    private function __construct(
        public readonly bool $allowed,
        public readonly ?AuthorizedDevice $device,
        public readonly ?string $reason,
        public readonly ?string $tokenToPersist,
    ) {
    }

    public static function allow(AuthorizedDevice $device, ?string $tokenToPersist = null): self
    {
        return new self(true, $device, null, $tokenToPersist);
    }

    /** @param  'revoked'|'locked_to_other_device'|'invalid_token'  $reason */
    public static function deny(string $reason, ?AuthorizedDevice $device = null): self
    {
        return new self(false, $device, $reason, null);
    }
}
