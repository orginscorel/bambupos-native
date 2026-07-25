<?php

namespace App\Modules\Kiosk\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Kiosk\Models\KioskDevice;
use Illuminate\Support\Str;

/**
 * Kiosk sistem aktörü.
 *
 * Orders/Payments servisleri (bilinçli olarak) bazı işlemlerde User aktör
 * ister — kioskta oturum açan kimse yoktur. Her kiracı için, GİRİŞ YAPAMAYAN
 * (is_active=false, rastgele parola, rolü yok) bir sistem kullanıcısı tembel
 * oluşturulur; kiosk siparişinin açan/kasiyer izi bu kullanıcıya bağlanır.
 * Böylece denetim kayıtları "kim yaptı?" sorusuna dürüst yanıt verir:
 * kiosk cihazı adına sistem hesabı.
 */
class KioskActor
{
    public const EMAIL_PREFIX = 'kiosk-system';

    public function forDevice(KioskDevice $device): User
    {
        $email = sprintf('%s@tenant-%d.invalid', self::EMAIL_PREFIX, (int) $device->tenant_id);

        /** @var User|null $user */
        $user = User::query()
            ->where('tenant_id', $device->tenant_id)
            ->where('email', $email)
            ->first();

        if ($user !== null) {
            return $user;
        }

        $user = new User([
            'first_name' => 'Kiosk',
            'last_name' => '(sistem)',
            'email' => $email,
            'password' => Str::random(64), // cast 'hashed' — bilinmeyen rastgele parola
            'is_active' => false,          // oturum açamaz (EnsureUserIsActive + login denetimi)
        ]);
        $user->tenant_id = (int) $device->tenant_id;
        $user->branch_id = (int) $device->branch_id;
        $user->name = 'Kiosk (sistem)';
        $user->save();

        return $user;
    }
}
