<?php

namespace App\Modules\Reservations\Services;

use App\Modules\Reservations\Models\Reservation;
use App\Modules\Tables\Models\Table;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;

/**
 * Kapasite + çakışma denetimi (prompt §9.3).
 *
 * Çakışma tanımı: iki rezervasyonun TAMPONLU pencereleri kesişiyorsa aynı
 * masada yaşayamazlar. Pencere = [reserved_at, reserved_at + süre + tampon).
 * Karşılaştırmada HER İKİ tarafın tamponu hesaba katılır: A'nın tamponlu
 * bitişi B'nin başlangıcından büyükse VE B'nin tamponlu bitişi A'nın
 * başlangıcından büyükse çakışır (yarım-açık aralık kesişimi).
 *
 * Yer TUTAN durumlar: requested/pending/confirmed/late/arrived/seated.
 * İptal, no-show ve tamamlanmış rezervasyonlar masa tutmaz.
 */
class AvailabilityService
{
    /**
     * Masa listesi için çakışan rezervasyonları döndürür.
     *
     * @param  array<int, int>  $tableIds
     * @return Collection<int, Reservation>
     */
    public function conflictsFor(
        array $tableIds,
        Carbon $startsAt,
        int $durationMinutes,
        int $bufferMinutes,
        ?int $ignoreReservationId = null,
    ): Collection {
        if ($tableIds === []) {
            return collect();
        }

        $blockEnd = $startsAt->copy()->addMinutes($durationMinutes + $bufferMinutes);

        // Aday küme dar tutulur (aynı gün ± 1 gün); kesin kesişim PHP'de,
        // karşı tarafın kendi süre+tamponuyla hesaplanır.
        $candidates = Reservation::query()
            ->blocking()
            ->when($ignoreReservationId !== null, fn ($q) => $q->where('id', '!=', $ignoreReservationId))
            ->whereHas('tables', fn ($q) => $q->whereIn('tables.id', $tableIds))
            ->whereBetween('reserved_at', [
                $startsAt->copy()->subDay(),
                $blockEnd->copy()->addDay(),
            ])
            ->with('tables:id,name,number')
            ->get();

        return $candidates->filter(
            fn (Reservation $other): bool => $startsAt->lt($other->blocksUntil()) && $other->startsAt()->lt($blockEnd)
        )->values();
    }

    /**
     * Masa seçimini doğrular: aynı şube + kapasite + birleştirme kuralı +
     * çakışma. Hata durumunda alan-bazlı ValidationException fırlatır.
     *
     * @param  array<int, int>  $tableIds
     * @return Collection<int, Table> doğrulanan masalar
     */
    public function assertTablesAvailable(
        int $branchId,
        array $tableIds,
        int $partySize,
        Carbon $startsAt,
        int $durationMinutes,
        int $bufferMinutes,
        ?int $ignoreReservationId = null,
    ): Collection {
        $tableIds = array_values(array_unique(array_map('intval', $tableIds)));

        $tables = Table::query()
            ->whereIn('id', $tableIds)
            ->where('branch_id', $branchId)
            ->where('is_active', true)
            ->get();

        if ($tables->count() !== count($tableIds)) {
            throw ValidationException::withMessages([
                'table_ids' => ['Seçilen masalardan biri bu şubede bulunamadı ya da pasif.'],
            ]);
        }

        // Masa birleştirme: birden çok masa seçildiyse hepsi birleştirilebilir olmalı.
        if ($tables->count() > 1 && $tables->contains(fn (Table $t) => ! $t->is_joinable)) {
            throw ValidationException::withMessages([
                'table_ids' => ['Seçilen masalardan biri birleştirmeye kapalı.'],
            ]);
        }

        // Kapasite: toplam kapasite kişi sayısını karşılamalı.
        $capacity = (int) $tables->sum('capacity');

        if ($capacity < $partySize) {
            throw ValidationException::withMessages([
                'party_size' => ["Seçilen masaların toplam kapasitesi ({$capacity}) kişi sayısını ({$partySize}) karşılamıyor."],
            ]);
        }

        // Çakışma: aynı masa + kesişen tamponlu zaman penceresi.
        $conflicts = $this->conflictsFor($tableIds, $startsAt, $durationMinutes, $bufferMinutes, $ignoreReservationId);

        if ($conflicts->isNotEmpty()) {
            $first = $conflicts->first();

            throw ValidationException::withMessages([
                'reserved_at' => [sprintf(
                    'Çakışma: %s için %s saatinde başka bir rezervasyon var (%s, tampon dahil %s kadar dolu).',
                    $first->tables->pluck('name')->implode(', '),
                    $first->localReservedAt()->format('d.m.Y H:i'),
                    $first->customer_name,
                    $first->blocksUntil()->setTimezone($first->branch?->timezone ?: config('app.timezone'))->format('H:i'),
                )],
            ]);
        }

        return $tables;
    }

    /**
     * Belirli bir pencere için şubedeki masaların uygunluk haritası
     * (rezervasyon formunda masa seçtirme).
     *
     * @return array<int, array<string, mixed>>
     */
    public function tableAvailability(
        int $branchId,
        Carbon $startsAt,
        int $durationMinutes,
        int $bufferMinutes,
        ?int $ignoreReservationId = null,
    ): array {
        $tables = Table::query()
            ->where('branch_id', $branchId)
            ->where('is_active', true)
            ->with(['area:id,name'])
            ->orderBy('number')->orderBy('name')
            ->get();

        $conflicts = $this->conflictsFor(
            $tables->pluck('id')->all(),
            $startsAt,
            $durationMinutes,
            $bufferMinutes,
            $ignoreReservationId,
        );

        $busyTableIds = $conflicts
            ->flatMap(fn (Reservation $r) => $r->tables->pluck('id'))
            ->unique()
            ->all();

        return $tables->map(fn (Table $t): array => [
            'id' => $t->id,
            'name' => $t->name,
            'number' => $t->number,
            'capacity' => (int) $t->capacity,
            'is_joinable' => (bool) $t->is_joinable,
            'area_id' => $t->area_id,
            'area_name' => $t->area?->name,
            'status' => $t->status->value,
            'available' => ! in_array($t->id, $busyTableIds, true),
        ])->all();
    }
}
