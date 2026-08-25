<?php

namespace App\Console\Commands;

use App\Modules\Inventory\Services\AlertService;
use App\Modules\Inventory\Support\InventoryFeature;
use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Services\NotificationDispatcher;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Console\Command;

/**
 * Düşük stok BİLDİRİMİ + hatırlatıcı (§17.5 → §8 Notify köprüsü).
 *
 * AlertService kritik-eşik altı kalemleri SORGUyla bulur; her biri için depo
 * yetkilisi + yöneticiye bildirim düşer. `dedup_key` + uzun `dedup_window`
 * sayesinde aynı kalem sürekli SPAM YAPMAZ; kritik kaldıkça periyodik
 * HATIRLATICI olur (varsayılan 6 saatte bir). Kiracı-üstü tarama; her kiracı
 * için Stok özelliği açık değilse atlanır.
 */
class NotifyLowStock extends Command
{
    protected $signature = 'inventory:low-stock-notify';

    protected $description = 'Kritik eşik altı stok kalemleri için bildirim + periyodik hatırlatıcı (dedup ile spam yok).';

    public function handle(AlertService $alerts, NotificationDispatcher $dispatcher): int
    {
        $window = (int) config('inventory.low_stock_reminder_seconds', 6 * 3600);
        $notified = 0;

        Tenant::query()->pluck('id')->each(function ($id) use ($alerts, $dispatcher, $window, &$notified): void {
            $tenantId = (int) $id;

            if (! InventoryFeature::enabled($tenantId)) {
                return;
            }

            $critical = collect($alerts->build($tenantId)['critical'] ?? [])
                ->where('severity', 'critical');

            foreach ($critical as $row) {
                $dispatcher->notify(NotificationType::LowStock, [
                    'tenant_id' => $tenantId,
                    'title' => 'Düşük stok: '.$row['name'],
                    'body' => sprintf(
                        '%s kritik eşiğin altında (kalan %s %s).',
                        $row['name'],
                        $row['on_hand'],
                        $row['unit'] ?? ''
                    ),
                    'data' => [
                        'url' => '/panel/stok/uyarilar',
                        'item_id' => $row['item_id'],
                        'severity' => 'critical',
                    ],
                    // Alıcı+kalem başına dedup: pencere boyunca tek bildirim → hatırlatıcı.
                    'dedup_key' => 'lowstock-'.$tenantId.'-'.$row['item_id'],
                    'dedup_window' => $window,
                ]);
                $notified++;
            }
        });

        $this->info("Düşük stok taraması tamam: {$notified} bildirim (hatırlatma penceresi {$window} sn).");

        return self::SUCCESS;
    }
}
