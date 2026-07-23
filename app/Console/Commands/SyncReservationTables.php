<?php

namespace App\Console\Commands;

use App\Modules\Reservations\Services\ReservationTableSync;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Console\Command;

/**
 * Rezervasyon ↔ masa durumu güvenlik ağı (her dakika, schedule):
 *  - Yaklaşan onaylı rezervasyon → masa 'reserved'
 *  - Saati + tolerans geçen onaylı rezervasyon → 'late' + masa 'reservation_late'
 *  - Uzun süre gecikenler → otomatik no-show + masa serbest
 *
 * Aktif adisyonlu masalara ASLA dokunmaz (ReservationTableSync::canHold).
 */
class SyncReservationTables extends Command
{
    protected $signature = 'reservations:sync-tables';

    protected $description = 'Rezervasyon-masa durumlarını senkronlar (reserved / late / auto no-show)';

    public function handle(TenantContext $context, ReservationTableSync $sync): int
    {
        $result = $context->runWithoutTenancy(fn (): array => $sync->syncUpcoming());

        $this->info(sprintf(
            'Rezervasyon senkronu: %d masa rezerve, %d gecikti, %d otomatik no-show.',
            $result['held'],
            $result['late'],
            $result['no_show'],
        ));

        return self::SUCCESS;
    }
}
