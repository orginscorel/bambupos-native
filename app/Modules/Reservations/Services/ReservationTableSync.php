<?php

namespace App\Modules\Reservations\Services;

use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Reservations\Enums\ReservationStatus;
use App\Modules\Reservations\Models\Reservation;
use App\Modules\Tables\Models\Table;
use App\Modules\Venue\Enums\TableStatus;

/**
 * Rezervasyon → masa durumu bağı (prompt §9.4).
 *
 * Rezervasyon bir "GELECEK" katmandır; masadaki CANLI operasyon (açık
 * adisyon) her zaman önceliklidir:
 *
 *  - Masa yalnız BOŞ (Available) ya da Temizleniyor iken 'reserved' /
 *    'reservation_late' yapılır. Açık adisyonu olan masaya DOKUNULMAZ.
 *  - Bırakırken de yalnız 'reserved'/'reservation_late' durumundan
 *    'available'a çekilir; sipariş-türevli durumlar asla ezilmez.
 *  - Orders tarafındaki TableStatusSynchronizer zaten Reserved/
 *    ReservationLate'i sipariş kapanışında ezmiyor (mevcut davranış).
 */
class ReservationTableSync
{
    /** Rezervasyonun tuttuğu masaları (uygunsa) hedef duruma alır. */
    public function hold(Reservation $reservation, bool $late = false): void
    {
        $target = $late ? TableStatus::ReservationLate : TableStatus::Reserved;

        foreach ($reservation->tables as $table) {
            $this->applyHold($table, $target);
        }
    }

    /** Rezervasyon kapanınca (iptal/tamam/no-show/masaya alınma) masaları bırakır. */
    public function release(Reservation $reservation): void
    {
        foreach ($reservation->tables as $table) {
            $this->applyRelease($table, $reservation->id);
        }
    }

    /**
     * Masa şu an rezervasyon katmanı tarafından tutulabilir mi?
     * Açık adisyon varsa ya da masa operasyon akışındaysa: HAYIR.
     */
    public function canHold(Table $table): bool
    {
        $current = $table->status instanceof TableStatus
            ? $table->status
            : TableStatus::tryFrom((string) $table->status);

        if (! in_array($current, [
            TableStatus::Available,
            TableStatus::Cleaning,
            TableStatus::Reserved,
            TableStatus::ReservationLate,
        ], true)) {
            return false;
        }

        return ! $this->hasOpenOrder($table);
    }

    private function applyHold(Table $table, TableStatus $target): void
    {
        if (! $this->canHold($table)) {
            return; // aktif adisyon / canlı operasyon ezilmez
        }

        if ($table->status === $target) {
            return;
        }

        $table->status = $target;
        $table->save();
    }

    private function applyRelease(Table $table, ?int $ignoreReservationId = null): void
    {
        $current = $table->status instanceof TableStatus
            ? $table->status
            : TableStatus::tryFrom((string) $table->status);

        if (! in_array($current, [TableStatus::Reserved, TableStatus::ReservationLate], true)) {
            return; // yalnız kendi koyduğumuz durumu geri alırız
        }

        // Aynı masada yer tutan BAŞKA aktif rezervasyon penceresi varsa bırakma.
        // (Bırakılan rezervasyonun kendisi hesaba katılmaz — "masaya alındı"
        // durumu blocking sayılır ama masa artık canlı operasyona geçmiştir.)
        $now = now();
        $stillHeld = Reservation::withoutTenancy()
            ->blocking()
            ->when($ignoreReservationId !== null, fn ($q) => $q->where('id', '!=', $ignoreReservationId))
            ->whereHas('tables', fn ($q) => $q->where('tables.id', $table->id))
            ->where('reserved_at', '<=', $now->copy()->addMinutes((int) config('reservations.reserve_lead_minutes', 60)))
            ->get()
            ->contains(fn (Reservation $r): bool => $r->blocksUntil()->gt($now));

        if ($stillHeld) {
            return;
        }

        $table->status = TableStatus::Available;
        $table->save();
    }

    private function hasOpenOrder(Table $table): bool
    {
        return Order::withoutTenancy()
            ->where('table_id', $table->id)
            ->whereNotIn('status', [
                OrderStatus::Paid->value,
                OrderStatus::Cancelled->value,
                OrderStatus::Refunded->value,
            ])
            ->exists();
    }

    /**
     * Cron güvenlik ağı (reservations:sync-tables):
     *  1) Yaklaşan onaylı rezervasyonların masalarını 'reserved' yapar.
     *  2) Saati + tolerans geçmiş onaylı rezervasyonları 'late' durumuna
     *     alır, masayı 'reservation_late' yapar.
     *  3) Gecikmeden no_show_after_minutes sonra otomatik no-show.
     *
     * @return array{held: int, late: int, no_show: int}
     */
    public function syncUpcoming(): array
    {
        $now = now();
        $lead = (int) config('reservations.reserve_lead_minutes', 60);
        $grace = (int) config('reservations.late_grace_minutes', 15);
        $noShowAfter = (int) config('reservations.no_show_after_minutes', 45);

        $held = $late = $noShow = 0;

        // 1) Yaklaşanlar → masa reserved
        Reservation::withoutTenancy()
            ->where('status', ReservationStatus::Confirmed->value)
            ->whereBetween('reserved_at', [$now, $now->copy()->addMinutes($lead)])
            ->with('tables')
            ->get()
            ->each(function (Reservation $r) use (&$held): void {
                $this->hold($r);
                $held++;
            });

        // 2) Saati geçenler → late + masa reservation_late
        Reservation::withoutTenancy()
            ->where('status', ReservationStatus::Confirmed->value)
            ->where('reserved_at', '<', $now->copy()->subMinutes($grace))
            ->with('tables')
            ->get()
            ->each(function (Reservation $r) use (&$late): void {
                $r->status = ReservationStatus::Late;
                $r->save();
                $this->hold($r, late: true);
                $late++;
            });

        // 3) Uzun süredir gecikenler → otomatik no-show + masa bırakılır
        Reservation::withoutTenancy()
            ->where('status', ReservationStatus::Late->value)
            ->where('reserved_at', '<', $now->copy()->subMinutes($grace + $noShowAfter))
            ->with('tables')
            ->get()
            ->each(function (Reservation $r) use (&$noShow): void {
                $r->status = ReservationStatus::NoShow;
                $r->save();
                $this->release($r);
                $noShow++;
            });

        return ['held' => $held, 'late' => $late, 'no_show' => $noShow];
    }
}
