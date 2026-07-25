<?php

namespace App\Modules\Reservations\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Reservations\Enums\ReservationStatus;
use App\Modules\Reservations\Models\Reservation;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Rezervasyon iş kuralları: oluşturma/güncelleme (çakışma + kapasite
 * denetiminden geçirir) ve durum makinesi geçişleri (masa durumu bağı ile).
 */
class ReservationService
{
    public function __construct(
        private readonly AvailabilityService $availability,
        private readonly ReservationTableSync $tableSync,
        private readonly ReservationMailer $mailer,
    ) {
    }

    /**
     * Kullanıcının girdiği "duvar saati"ni ŞUBE saat diliminde yorumlayıp
     * uygulama dilimine (UTC) çevirir. Uygulama UTC çalışır ama personel ve
     * müşteri şube saatiyle düşünür; çevrim yapılmazsa yaklaşan-rezervasyon /
     * gecikme / hatırlatma hesapları saat farkı kadar kayar.
     */
    public static function parseBranchTime(int $branchId, string $value): Carbon
    {
        $tz = \App\Modules\Tenancy\Models\Branch::query()
            ->withoutGlobalScopes()
            ->whereKey($branchId)
            ->value('timezone') ?: config('app.timezone');

        return Carbon::parse($value, $tz)->setTimezone(config('app.timezone'));
    }

    /**
     * @param  array<string, mixed>  $data  doğrulanmış girdi
     * @param  array<int, int>  $tableIds  atanacak masalar (boş olabilir)
     */
    public function create(array $data, array $tableIds, ?User $actor, string $source): Reservation
    {
        // Carbon geldiyse an zaten çözülmüştür (public uç); string ise şube
        // duvar saati olarak yorumlanır (panel).
        $startsAt = $data['reserved_at'] instanceof Carbon
            ? $data['reserved_at']->copy()->setTimezone(config('app.timezone'))
            : self::parseBranchTime((int) $data['branch_id'], (string) $data['reserved_at']);
        $duration = (int) ($data['duration_minutes'] ?? config('reservations.default_duration_minutes', 120));
        $buffer = (int) ($data['buffer_minutes'] ?? config('reservations.default_buffer_minutes', 15));

        return DB::transaction(function () use ($data, $tableIds, $actor, $source, $startsAt, $duration, $buffer): Reservation {
            if ($tableIds !== []) {
                $this->availability->assertTablesAvailable(
                    (int) $data['branch_id'],
                    $tableIds,
                    (int) $data['party_size'],
                    $startsAt,
                    $duration,
                    $buffer,
                );
            }

            $reservation = new Reservation([
                'customer_name' => $data['customer_name'],
                'customer_phone' => $data['customer_phone'] ?? null,
                'customer_email' => $data['customer_email'] ?? null,
                'reserved_at' => $startsAt,
                'duration_minutes' => $duration,
                'buffer_minutes' => $buffer,
                'party_size' => (int) $data['party_size'],
                'area_id' => $data['area_id'] ?? null,
                'special_note' => $data['special_note'] ?? null,
                'allergy_note' => $data['allergy_note'] ?? null,
                'occasion' => $data['occasion'] ?? null,
                'occasion_note' => $data['occasion_note'] ?? null,
                'deposit_minor' => (int) ($data['deposit_minor'] ?? 0),
                'deposit_status' => $data['deposit_status'] ?? (($data['deposit_minor'] ?? 0) > 0 ? 'pending' : 'none'),
                'source' => $source,
                'status' => $data['status'] ?? ReservationStatus::Requested->value,
            ]);

            $reservation->branch_id = (int) $data['branch_id'];
            $reservation->created_by = $actor?->id;
            $reservation->save();

            if ($tableIds !== []) {
                $reservation->tables()->sync($tableIds);
            }

            $reservation->load('tables');

            // Onaylı açıldıysa (panel/telefon) masa bağını hemen işlet.
            if ($reservation->status === ReservationStatus::Confirmed) {
                $reservation->confirmed_at = now();
                $reservation->save();
                $this->holdIfImminent($reservation);
            }

            return $reservation;
        });
    }

    /**
     * @param  array<string, mixed>  $data
     * @param  array<int, int>|null  $tableIds  null = masa ataması değişmiyor
     */
    public function update(Reservation $reservation, array $data, ?array $tableIds): Reservation
    {
        if ($reservation->status->isFinal()) {
            throw ValidationException::withMessages([
                'status' => ['Kapanmış (tamamlandı/iptal/no-show) rezervasyon düzenlenemez.'],
            ]);
        }

        return DB::transaction(function () use ($reservation, $data, $tableIds): Reservation {
            $startsAt = match (true) {
                ! isset($data['reserved_at']) => $reservation->startsAt(),
                $data['reserved_at'] instanceof Carbon => $data['reserved_at']->copy()->setTimezone(config('app.timezone')),
                default => self::parseBranchTime((int) $reservation->branch_id, (string) $data['reserved_at']),
            };

            if (isset($data['reserved_at'])) {
                $data['reserved_at'] = $startsAt; // fill() aynı dönüştürülmüş anı yazsın
            }
            $duration = (int) ($data['duration_minutes'] ?? $reservation->duration_minutes);
            $buffer = (int) ($data['buffer_minutes'] ?? $reservation->buffer_minutes);
            $partySize = (int) ($data['party_size'] ?? $reservation->party_size);
            $newTableIds = $tableIds ?? $reservation->tables->pluck('id')->all();

            if ($newTableIds !== []) {
                $this->availability->assertTablesAvailable(
                    (int) $reservation->branch_id,
                    $newTableIds,
                    $partySize,
                    $startsAt,
                    $duration,
                    $buffer,
                    ignoreReservationId: $reservation->id,
                );
            }

            $previousTables = $reservation->tables()->get();

            $reservation->fill(collect($data)->only([
                'customer_name', 'customer_phone', 'customer_email', 'reserved_at',
                'duration_minutes', 'buffer_minutes', 'party_size', 'area_id',
                'special_note', 'allergy_note', 'occasion', 'occasion_note',
                'deposit_minor', 'deposit_status',
            ])->all());
            $reservation->save();

            if ($tableIds !== null) {
                $reservation->tables()->sync($newTableIds);
                $reservation->load('tables');

                // Eski masalardan çıkarılanları bırak (uygunsa).
                $removed = $previousTables->whereNotIn('id', $newTableIds);
                if ($removed->isNotEmpty()) {
                    $ghost = clone $reservation;
                    $ghost->setRelation('tables', $removed->values());
                    $this->tableSync->release($ghost);
                }
            }

            $reservation->load('tables');

            if ($reservation->status === ReservationStatus::Confirmed) {
                $this->holdIfImminent($reservation);
            }

            return $reservation;
        });
    }

    /** Durum makinesi geçişi + masa durumu bağı. */
    public function transition(Reservation $reservation, ReservationStatus $target, ?string $reason = null): Reservation
    {
        if (! $reservation->status->canTransitionTo($target)) {
            throw ValidationException::withMessages([
                'status' => [sprintf(
                    "'%s' durumundan '%s' durumuna geçilemez.",
                    $reservation->status->label(),
                    $target->label(),
                )],
            ]);
        }

        return DB::transaction(function () use ($reservation, $target, $reason): Reservation {
            $reservation->status = $target;

            match ($target) {
                ReservationStatus::Confirmed => $reservation->confirmed_at = now(),
                ReservationStatus::Arrived => $reservation->arrived_at = now(),
                ReservationStatus::Seated => $reservation->seated_at = now(),
                ReservationStatus::Completed => $reservation->completed_at = now(),
                ReservationStatus::Cancelled => $reservation->cancelled_at = now(),
                default => null,
            };

            if ($target === ReservationStatus::Cancelled && $reason !== null) {
                $reservation->cancel_reason = $reason;
            }

            $reservation->save();
            $reservation->load('tables');

            // Masa bağı: onay → tut; gecikti → geç işaretle; masaya alındı /
            // kapanış → bırak (masa katmanı canlı operasyona geçer/serbest kalır).
            match ($target) {
                ReservationStatus::Confirmed => $this->holdIfImminent($reservation),
                ReservationStatus::Late => $this->tableSync->hold($reservation, late: true),
                ReservationStatus::Seated,
                ReservationStatus::Completed,
                ReservationStatus::Cancelled,
                ReservationStatus::NoShow => $this->tableSync->release($reservation),
                default => null,
            };

            // E-posta bilgilendirmeleri (SMTP paneli üzerinden; adres yoksa sessiz geçer).
            if ($target === ReservationStatus::Confirmed) {
                $this->mailer->sendConfirmation($reservation);
            }

            if ($target === ReservationStatus::Cancelled) {
                $this->mailer->sendCancellation($reservation);
            }

            return $reservation;
        });
    }

    /**
     * Walk-in bir müşteri rezervasyonlu masaya oturdu (Orders bu masaya
     * adisyon açtı+onaylandı — §8). Masa katmanı zaten canlı operasyona
     * geçmiştir (TableStatusSynchronizer); burada yalnız REZERVASYON kaydı
     * uygun biçimde ilerletilir. Mevcut durum makinesi KULLANILIR:
     *
     *  - Onaylı/gecikmiş/gelmiş (confirmed/late/arrived) rezervasyon → Seated
     *    (masaya alındı; oturan bu müşteri kabul edilir). transition() masayı
     *    zaten bırakmaya çalışır ama açık adisyon nedeniyle no-op'tur —
     *    ReservationTableSync ile tutarlı (açık adisyon rezervasyonu ezmez).
     *  - Henüz onaylanmamış (requested/pending) rezervasyon seated'a GEÇEMEZ →
     *    net ÇAKIŞMA olarak işaretlenir (special_note başına damga + otomatik
     *    denetim kaydı) ki yönetici görüp karar versin.
     */
    public function markWalkInSeated(Reservation $reservation, ?User $actor = null): Reservation
    {
        if ($reservation->status === ReservationStatus::Seated || $reservation->status->isFinal()) {
            return $reservation; // zaten oturmuş / kapanmış — dokunma
        }

        if ($reservation->status->canTransitionTo(ReservationStatus::Seated)) {
            return $this->transition($reservation, ReservationStatus::Seated);
        }

        // Onaylanmamış rezervasyon: seated'a geçemez → görünür çakışma damgası.
        $mark = sprintf('[ÇAKIŞMA %s] Masaya walk-in adisyon açıldı.', now()->format('d.m.Y H:i'));

        if (! str_starts_with((string) $reservation->special_note, '[ÇAKIŞMA')) {
            $note = $reservation->special_note ? $mark.' '.$reservation->special_note : $mark;
            $reservation->special_note = mb_substr($note, 0, 500);
            $reservation->save(); // Auditable → reservations.updated denetim kaydı
        }

        return $reservation;
    }

    /**
     * Rezervasyon saati yaklaşıyorsa (lead penceresi içindeyse) masayı
     * hemen 'reserved' yap; uzaktaysa cron (reservations:sync-tables)
     * zamanı gelince yapacak.
     */
    private function holdIfImminent(Reservation $reservation): void
    {
        $lead = (int) config('reservations.reserve_lead_minutes', 60);

        if ($reservation->startsAt()->lte(now()->addMinutes($lead)) && $reservation->blocksUntil()->gt(now())) {
            $this->tableSync->hold($reservation);
        }
    }
}
