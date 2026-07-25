<?php

namespace App\Modules\Reservations\Services;

use App\Modules\Reservations\Models\Reservation;
use App\Modules\Settings\Services\MailConfigurator;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

/**
 * Rezervasyon e-postaları (onay / iptal / hatırlatma).
 *
 * Gönderim, Settings modülünün panelden yapılandırılan SMTP altyapısından
 * geçer (RuntimeMailManager); kiracı bağlamı olmayan akışlarda (cron)
 * MailConfigurator::hintTenant ile doğru kiracı ayarı uygulanır.
 *
 * E-posta adresi yoksa sessizce atlanır; gönderim hatası ana işlemi
 * DÜŞÜRMEZ (rezervasyon kaydı e-postadan kıymetlidir), yalnız loglanır.
 * SMS/push kanalları için genişleme noktası burasıdır.
 */
class ReservationMailer
{
    public function __construct(private readonly MailConfigurator $mailConfig)
    {
    }

    public function sendConfirmation(Reservation $reservation): bool
    {
        return $this->send($reservation, 'Rezervasyonunuz onaylandı', implode("\n", [
            sprintf('Sayın %s,', $reservation->customer_name),
            '',
            sprintf(
                'Rezervasyonunuz onaylanmıştır: %s, %d kişi.',
                $reservation->localReservedAt()->format('d.m.Y H:i'),
                $reservation->party_size,
            ),
            '',
            'Rezervasyonunuzu görüntülemek ya da iptal etmek için:',
            $this->manageUrl($reservation),
        ]));
    }

    public function sendCancellation(Reservation $reservation): bool
    {
        return $this->send($reservation, 'Rezervasyonunuz iptal edildi', implode("\n", [
            sprintf('Sayın %s,', $reservation->customer_name),
            '',
            sprintf(
                'Rezervasyonunuz iptal edilmiştir: %s, %d kişi.',
                $reservation->localReservedAt()->format('d.m.Y H:i'),
                $reservation->party_size,
            ),
        ]));
    }

    public function sendReminder(Reservation $reservation): bool
    {
        return $this->send($reservation, 'Rezervasyon hatırlatması', implode("\n", [
            sprintf('Sayın %s,', $reservation->customer_name),
            '',
            sprintf(
                'Hatırlatma: bugünkü rezervasyonunuz %s saatinde, %d kişi.',
                $reservation->localReservedAt()->format('H:i'),
                $reservation->party_size,
            ),
            '',
            'Gelemeyecekseniz lütfen iptal edin:',
            $this->manageUrl($reservation),
        ]));
    }

    public function manageUrl(Reservation $reservation): string
    {
        return rtrim((string) config('app.url'), '/').'/r/'.$reservation->confirmation_token;
    }

    private function send(Reservation $reservation, string $subject, string $body): bool
    {
        $email = trim((string) $reservation->customer_email);

        if ($email === '') {
            return false;
        }

        try {
            // Cron akışında oturum/kiracı bağlamı yok → doğru SMTP için ipucu.
            $this->mailConfig->hintTenant((int) $reservation->tenant_id);

            Mail::raw($body, function ($message) use ($email, $reservation, $subject): void {
                $message->to($email, $reservation->customer_name)->subject($subject);
            });

            return true;
        } catch (\Throwable $e) {
            Log::warning('Rezervasyon e-postası gönderilemedi', [
                'reservation_id' => $reservation->id,
                'error' => $e->getMessage(),
            ]);

            return false;
        } finally {
            $this->mailConfig->hintTenant(null);
        }
    }
}
