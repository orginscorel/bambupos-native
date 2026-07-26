<?php

use App\Modules\Settings\Http\Controllers\BrandingSettingsController;
use App\Modules\Settings\Http\Controllers\FeatureSettingsController;
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

    // Panel ekranı — İşletme / Marka (logo; public menü başlığında gösterilir)
    Route::get('/panel/ayarlar/isletme', function () {
        abort_unless(request()->user()->hasPermission('settings.manage'), 403);

        return Inertia::render('Panel/Settings/Branding');
    })->name('panel.settings.branding');

    // Panel ekranı — Eklentiler (§9 feature-flag: opsiyonel özellik aç/kapa)
    Route::get('/panel/ayarlar/eklentiler', function () {
        abort_unless(request()->user()->hasPermission('settings.manage'), 403);

        return Inertia::render('Panel/Settings/Features');
    })->name('panel.settings.features');

    // API
    Route::prefix('api/v1/settings')->group(function (): void {
        Route::get('branding', [BrandingSettingsController::class, 'show'])->name('settings.branding.show');
        Route::post('branding/logo', [BrandingSettingsController::class, 'uploadLogo'])->name('settings.branding.logo.upload');
        Route::delete('branding/logo', [BrandingSettingsController::class, 'destroyLogo'])->name('settings.branding.logo.destroy');
        // §9 Eklentiler / feature-flag
        Route::get('features', [FeatureSettingsController::class, 'show'])->name('settings.features.show');
        Route::put('features', [FeatureSettingsController::class, 'update'])->name('settings.features.update');
        Route::get('mail', [MailSettingsController::class, 'show'])->name('settings.mail.show');
        Route::put('mail/{scope}', [MailSettingsController::class, 'update'])
            ->whereIn('scope', ['tenant', 'platform'])
            ->name('settings.mail.update');
        Route::delete('mail/tenant', [MailSettingsController::class, 'destroy'])->name('settings.mail.destroy');
        Route::post('mail/test', [MailSettingsController::class, 'test'])->name('settings.mail.test');
    });
});
