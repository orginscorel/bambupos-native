<?php

namespace App\Console\Commands;

use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Services\NotificationDispatcher;
use App\Modules\Shifts\Models\Shift;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Console\Command;

/**
 * Vardiya başlangıcına ~10 dk kala ilgili personele hatırlatma (her dakika).
 *
 * Pencere [now+10dk, now+11dk): her vardiya, başlangıcına 10-11 dk kala olan
 * TEK dakika-tikinde eşleşir → bir kez tetiklenir. Ek güvenlik: dispatcher
 * dedup_key='shift_reminder:{id}' + 30 dk pencere (yinelenmez).
 *
 * Kiracı-üstü tarama (runWithoutTenancy); bildirim kaydı tenant_id'yi vardiyadan
 * alır. Bildirim in-app + web push'u (WebPushSender) birlikte üretir. Best-effort.
 */
class SendShiftStartReminders extends Command
{
    protected $signature = 'shifts:send-start-reminders';

    protected $description = 'Vardiya başlangıcına ~10 dk kala ilgili personele hatırlatma bildirimi gönderir';

    public function handle(TenantContext $context, NotificationDispatcher $dispatcher): int
    {
        $now = now();
        $from = $now->copy()->addMinutes(10);
        $to = $now->copy()->addMinutes(11);
        $count = 0;

        $context->runWithoutTenancy(function () use ($dispatcher, $from, $to, &$count): void {
            Shift::query()
                ->whereNotNull('user_id')
                ->where('starts_at', '>=', $from)
                ->where('starts_at', '<', $to)
                ->chunkById(200, function ($shifts) use ($dispatcher, &$count): void {
                    foreach ($shifts as $shift) {
                        try {
                            $dispatcher->notify(NotificationType::ShiftReminder, [
                                'tenant_id' => (int) $shift->tenant_id,
                                'branch_id' => $shift->branch_id !== null ? (int) $shift->branch_id : null,
                                'title' => 'Mesain birazdan başlıyor',
                                'body' => 'Vardiyan '.$shift->starts_at->format('H:i').' başlıyor — 10 dakika kaldı.',
                                'data' => ['url' => '/panelim'],
                                'extra_user_ids' => [(int) $shift->user_id],
                                'dedup_key' => 'shift_reminder:'.$shift->getKey(),
                                'dedup_window' => 1800,
                            ]);
                            $count++;
                        } catch (\Throwable) {
                            // best-effort — bir vardiya hatası cron'u düşürmesin
                        }
                    }
                });
        });

        $this->info("Mesai hatırlatması: {$count} vardiya bildirildi.");

        return self::SUCCESS;
    }
}
