<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

/*
|--------------------------------------------------------------------------
| Zamanlanmış görevler (crontab: * * * * * artisan schedule:run)
|--------------------------------------------------------------------------
*/

// Rezervasyon ↔ masa durumu güvenlik ağı (reserved / late / auto no-show).
Schedule::command('reservations:sync-tables')->everyMinute()->withoutOverlapping();

// Yaklaşan onaylı rezervasyonlara e-posta hatırlatması (SMTP paneli üzerinden).
Schedule::command('reservations:send-reminders')->everyFiveMinutes()->withoutOverlapping();

// §8/§11 Bildirim: komi teslim SLA ihlali + yaklaşan rezervasyon taraması.
Schedule::command('notify:check-sla')->everyMinute()->withoutOverlapping();

// Personel: vardiya başlangıcına ~10 dk kala hatırlatma (in-app + web push).
Schedule::command('shifts:send-start-reminders')->everyMinute()->withoutOverlapping();

// §17.5 Stok: kritik eşik altı kalemler için bildirim + periyodik hatırlatıcı
// (komut kendi dedup'ıyla spam'i keser; saatte bir tarama yeterli).
Schedule::command('inventory:low-stock-notify')->hourly()->withoutOverlapping();
