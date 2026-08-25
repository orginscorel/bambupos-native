<?php

namespace App\Modules\Identity\Services;

use App\Modules\Identity\Models\User;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Personel hızlı PIN altyapısı.
 *
 * Eski sistemin açığı 4 haneli PIN'di — burada KESİN kural:
 *  - En az 6, en çok 10 hane; yalnız rakam.
 *  - Tek-tip (111111) ve düz artan/azalan (123456, 987654) diziler reddedilir.
 *  - bcrypt ile saklanır; düz metin hiçbir yerde tutulmaz/loglanmaz.
 *  - 5 hatalı denemede hesap PIN girişine 5 dk kilitlenir.
 */
class PinService
{
    public const MIN_LENGTH = 6;

    public const MAX_LENGTH = 10;

    public const MAX_ATTEMPTS = 5;

    public const LOCK_MINUTES = 5;

    public function __construct(private readonly AuditLogger $audit)
    {
    }

    public function setPin(User $user, string $pin): void
    {
        $this->assertStrong($pin);

        $user->forceFill([
            'pin_hash' => Hash::make($pin),
            // Yönetici "PIN görüntüle" için tersine-çevrilebilir kopya (app key ile
            // çözülür). Doğrulama HÂLÂ pin_hash (bcrypt) iledir.
            'pin_encrypted' => Crypt::encryptString($pin),
            'failed_pin_attempts' => 0,
            'pin_locked_until' => null,
        ])->save();

        $this->audit->log('auth.pin_set', $user);
    }

    /**
     * Personelin PIN'ini düz metin olarak çöz (yalnız YETKİLİ yönetici görüntüler;
     * çağıran taraf yetki + audit'ten sorumludur). Şifreli kopya yoksa (eski PIN
     * bcrypt-only) null döner → "yeniden ata" gerekir.
     */
    public function revealPin(User $user): ?string
    {
        if ($user->pin_encrypted === null || $user->pin_encrypted === '') {
            return null;
        }

        try {
            return Crypt::decryptString($user->pin_encrypted);
        } catch (\Throwable) {
            return null;
        }
    }

    /**
     * PIN doğrulama + deneme sınırı. Başarısızsa false döner; kilitliyse
     * ValidationException (429 anlamında) fırlatır.
     */
    public function verify(User $user, string $pin): bool
    {
        if ($user->pinIsLocked()) {
            throw ValidationException::withMessages([
                'pin' => ['Çok fazla hatalı deneme. PIN girişi geçici olarak kilitli.'],
            ])->status(429);
        }

        if ($user->pin_hash === null || ! Hash::check($pin, $user->pin_hash)) {
            $attempts = ($user->failed_pin_attempts ?? 0) + 1;

            $update = ['failed_pin_attempts' => $attempts];

            if ($attempts >= self::MAX_ATTEMPTS) {
                $update['pin_locked_until'] = now()->addMinutes(self::LOCK_MINUTES);
                $update['failed_pin_attempts'] = 0;
                $this->audit->log('auth.pin_locked', $user);
            }

            $user->forceFill($update)->save();

            return false;
        }

        $user->forceFill(['failed_pin_attempts' => 0, 'pin_locked_until' => null])->save();

        return true;
    }

    private function assertStrong(string $pin): void
    {
        $fail = function (string $message): never {
            throw ValidationException::withMessages(['pin' => [$message]]);
        };

        if (! preg_match('/^\d{'.self::MIN_LENGTH.','.self::MAX_LENGTH.'}$/', $pin)) {
            $fail(sprintf('PIN %d-%d haneli ve yalnız rakamlardan oluşmalıdır.', self::MIN_LENGTH, self::MAX_LENGTH));
        }

        if (preg_match('/^(\d)\1+$/', $pin)) {
            $fail('PIN tek bir rakamın tekrarından oluşamaz.');
        }

        if (str_contains('0123456789012345', $pin) || str_contains('9876543210987654', $pin)) {
            $fail('PIN ardışık bir sayı dizisi olamaz.');
        }
    }
}
