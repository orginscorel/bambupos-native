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
