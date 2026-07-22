<?php

namespace App\Console\Commands;

use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Orders\Services\TableStatusSynchronizer;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Console\Command;

/**
 * Onarım: geçmişte tüm kalemleri silinmiş ama AÇIK kalmış adisyonları
 * kapatır ve masa durumlarını açık adisyonlardan yeniden türetir.
 *
 * (Kural artık OrderService::closeIfEmptied ile canlıda otomatik işler;
 * bu komut kuraldan ÖNCE oluşmuş bozuk veriyi düzeltmek içindir ve
 * istenirse periyodik güvenlik ağı olarak da çalıştırılabilir.)
 *
 * Rezerve / Kullanım dışı masalar TableStatusSynchronizer kuralı gereği
 * ezilmez. Yeni açılmış (garsonun kalem eklemek üzere olduğu) adisyonları
 * yarış hâlinde kapatmamak için --grace dakikalık koruma vardır.
 */
class RepairTableStatuses extends Command
{
    protected $signature = 'orders:repair-table-status
        {--dry-run : Değişiklik yazmadan yalnız raporla}
        {--grace=10 : Bu dakikadan yeni adisyonlara dokunma}';

    protected $description = 'Boş kalmış açık adisyonları kapatır, masa durumlarını yeniden türetir';

    public function handle(TenantContext $context, OrderService $orders, TableStatusSynchronizer $sync): int
    {
        $dryRun = (bool) $this->option('dry-run');
        $grace = max(0, (int) $this->option('grace'));

        return (int) $context->runWithoutTenancy(function () use ($orders, $sync, $dryRun, $grace): int {
            /* 1) Boş ama açık adisyonlar: aktif (iptal olmayan) kalemi yok,
             *    tahsilatı yok → otomatik kapat. */
            $emptyOpen = Order::withoutTenancy()
                ->whereNotIn('status', [OrderStatus::Paid->value, OrderStatus::Cancelled->value, OrderStatus::Refunded->value])
                ->where('paid_minor', 0)
                ->where('created_at', '<=', now()->subMinutes($grace))
                ->whereDoesntHave('items', fn ($q) => $q->where('status', '!=', 'cancelled'))
                ->orderBy('id')
                ->get();

            $closed = 0;

            foreach ($emptyOpen as $order) {
                $this->line(sprintf(
                    '  Adisyon #%d (masa %s, durum %s) boş ve açık%s',
                    $order->id,
                    $order->table_id ?? '—',
                    $order->status,
                    $dryRun ? ' [dry-run: dokunulmadı]' : ' → kapatılıyor',
                ));

                if (! $dryRun && $orders->autoCloseIfEmpty($order)) {
                    $closed++;
                }
            }

            /* 2) Tüm masaların durumunu açık adisyonlardan yeniden türet
             *    (Rezerve/Kullanım dışı synchronizer içinde korunur). */
            $fixedTables = 0;

            foreach (Table::withoutTenancy()->orderBy('id')->get() as $table) {
                $before = $table->status instanceof \BackedEnum ? $table->status->value : (string) $table->status;

                if ($dryRun) {
                    continue;
                }

                $sync->sync($table);
                $after = $table->fresh()->status;
                $after = $after instanceof \BackedEnum ? $after->value : (string) $after;

                if ($before !== $after) {
                    $fixedTables++;
                    $this->line(sprintf('  Masa #%d "%s": %s → %s', $table->id, $table->name, $before, $after));
                }
            }

            $this->info(sprintf(
                '%s: %d boş adisyon kapatıldı, %d masa durumu düzeltildi.',
                $dryRun ? 'DRY-RUN' : 'Tamamlandı',
                $closed,
                $fixedTables,
            ));

            return self::SUCCESS;
        });
    }
}
