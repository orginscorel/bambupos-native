<?php

namespace App\Console\Commands;

use App\Modules\Reservations\Enums\ReservationStatus;
use App\Modules\Reservations\Models\Reservation;
use App\Modules\Reservations\Services\ReservationMailer;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Console\Command;

/**
 * Hatırlatma altyapısı (schedule, 5 dakikada bir): başlangıcına
 * reminder_lead_minutes kalan ONAYLI rezervasyonlara e-posta gönderir
 * (panelden yapılandırılan SMTP — Settings modülü — üzerinden).
 *
 * E-posta adresi olmayan kayıtlar 'skipped' işaretlenir; başarısız gönderim
 * 'failed' olur ve TEKRAR DENENMEZ (spam önlemi) — panel elle gönderime izin verir.
 * SMS/push kanalı eklenecekse ReservationMailer genişletilir.
 */
class SendReservationReminders extends Command
{
    protected $signature = 'reservations:send-reminders';

    protected $description = 'Yaklaşan onaylı rezervasyonlara hatırlatma e-postası gönderir';

    public function handle(TenantContext $context, ReservationMailer $mailer): int
    {
        $lead = (int) config('reservations.reminder_lead_minutes', 120);

        $sent = $context->runWithoutTenancy(function () use ($mailer, $lead): int {
            $due = Reservation::withoutTenancy()
                ->where('status', ReservationStatus::Confirmed->value)
                ->where('reminder_status', 'pending')
                ->whereBetween('reserved_at', [now(), now()->addMinutes($lead)])
                ->orderBy('reserved_at')
                ->limit(100)
                ->get();

            $count = 0;

            foreach ($due as $reservation) {
                if (blank($reservation->customer_email)) {
                    $reservation->reminder_status = 'skipped';
                    $reservation->save();

                    continue;
                }

                $ok = $mailer->sendReminder($reservation);

                $reservation->reminder_status = $ok ? 'sent' : 'failed';
                $reservation->reminder_sent_at = $ok ? now() : null;
                $reservation->save();

                $count += $ok ? 1 : 0;
            }

            return $count;
        });

        $this->info("Hatırlatma gönderilen rezervasyon: {$sent}");

        return self::SUCCESS;
    }
}
