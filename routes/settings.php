<?php

use App\Modules\Settings\Http\Controllers\MailSettingsController;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| Ayarlar modülü (Ayarlar-SMTP ajanı)
|--------------------------------------------------------------------------
| Panelden yönetilen e-posta (SMTP) yapılandırması: platform varsayılanı
| + işletme override'ı. Tümü oturum + kiracı bağlamı + settings.manage ister.
*/

Route::middleware(['auth:web', 'tenant'])->group(function (): void {

    // Panel ekranı
    Route::get('/panel/ayarlar/e-posta', function () {
        abort_unless(request()->user()->hasPermission('settings.manage'), 403);

        return Inertia::render('Panel/Settings/Mail');
    })->name('panel.settings.mail');

    // API
    Route::prefix('api/v1/settings')->group(function (): void {
        Route::get('mail', [MailSettingsController::class, 'show'])->name('settings.mail.show');
        Route::put('mail/{scope}', [MailSettingsController::class, 'update'])
            ->whereIn('scope', ['tenant', 'platform'])
            ->name('settings.mail.update');
        Route::delete('mail/tenant', [MailSettingsController::class, 'destroy'])->name('settings.mail.destroy');
        Route::post('mail/test', [MailSettingsController::class, 'test'])->name('settings.mail.test');
    });
});
