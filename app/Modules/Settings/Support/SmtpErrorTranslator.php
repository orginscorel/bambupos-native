<?php

namespace App\Modules\Settings\Support;

use Throwable;

/**
 * Ham SMTP/taşıyıcı hatasını kullanıcıya anlaşılır Türkçe mesaja çevirir.
 * Parola (ve base64 hali) mesajdan HER DURUMDA temizlenir — hata metni
 * ekrana gittiği için sızıntı olmaz.
 */
class SmtpErrorTranslator
{
    public static function friendly(Throwable $e, ?string $secret = null): string
    {
        $raw = self::scrub($e->getMessage(), $secret);
        $lower = mb_strtolower($raw);

        $hint = match (true) {
            str_contains($lower, 'authentication')
                || str_contains($raw, '535')
                || str_contains($lower, 'auth ')
                || str_contains($lower, 'username and password not accepted')
                => 'Kimlik doğrulama reddedildi: kullanıcı adı/parolayı kontrol edin.',

            str_contains($lower, 'timed out')
                || str_contains($lower, 'timeout')
                => 'Sunucuya ulaşılamadı: zaman aşımı. Sunucu adresi ve portu kontrol edin.',

            str_contains($lower, 'connection refused')
                => 'Sunucu bağlantıyı reddetti: port yanlış olabilir veya serviste SMTP dinlemiyor.',

            str_contains($lower, 'connection could not be established')
                || str_contains($lower, 'getaddrinfo')
                || str_contains($lower, 'name or service not known')
                || str_contains($lower, 'network is unreachable')
                => 'Sunucuya ulaşılamadı: adres çözülemedi veya ağ erişimi yok.',

            str_contains($lower, 'starttls')
                || str_contains($lower, 'ssl')
                || str_contains($lower, 'tls')
                || str_contains($lower, 'certificate')
                => 'Şifreleme (TLS/SSL) anlaşması başarısız: şifreleme türünü ve portu kontrol edin (TLS→587, SSL→465 yaygındır).',

            str_contains($raw, '550') || str_contains($raw, '553')
                => 'Sunucu gönderen/alıcı adresini kabul etmedi: gönderen adresinin bu hesapta yetkili olduğundan emin olun.',

            default => 'E-posta gönderilemedi.',
        };

        return $hint.' — Sunucu yanıtı: '.mb_substr($raw, 0, 400);
    }

    /** Parolayı ve base64 kodlanmış hallerini metinden temizler. */
    public static function scrub(string $text, ?string $secret): string
    {
        if ($secret !== null && $secret !== '') {
            $needles = array_filter([
                $secret,
                base64_encode($secret),
                base64_encode("\0".$secret),
            ]);

            $text = str_replace($needles, '[gizli]', $text);
        }

        return $text;
    }
}
