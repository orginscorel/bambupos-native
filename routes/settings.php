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

    // Hazır indirim tanımları (şehit/gazi yakını, kamu personeli, öğrenci…).
    // İndirim UYGULAMA yetkisiyle aynı kapı: tanımı yapan zaten indirim yetkilisi.
    Route::get('/panel/ayarlar/indirimler', function () {
        abort_unless(request()->user()->hasPermission('orders.discount'), 403);

        return Inertia::render('Panel/Settings/Discounts');
    })->name('panel.settings.discounts');

    // Panel ekranı — İşletme / Marka (logo; public menü başlığında gösterilir)
    Route::get('/panel/ayarlar/isletme', function () {
        abort_unless(request()->user()->hasPermission('settings.manage'), 403);

        return Inertia::render('Panel/Settings/Branding');
    })->name('panel.settings.branding');

    // Panel teması — marka rengi + font + varsayılan mod (kiracı bazlı).
    Route::get('/panel/ayarlar/tema', function () {
        abort_unless(request()->user()->hasPermission('settings.manage'), 403);

        return Inertia::render('Panel/Settings/Theme');
    })->name('panel.settings.theme');

    // Panel ekranı — Eklentiler (§9 feature-flag: opsiyonel özellik aç/kapa)
    Route::get('/panel/ayarlar/eklentiler', function () {
        abort_unless(request()->user()->hasPermission('settings.manage'), 403);

        return Inertia::render('Panel/Settings/Features');
    })->name('panel.settings.features');

    // Entegrasyonlar merkezi (teslimat/ödeme/e-fatura/muhasebe durum + yol haritası).
    Route::get('/panel/entegrasyonlar', function () {
        abort_unless(request()->user()->hasPermission('integrations.manage'), 403);

        return Inertia::render('Panel/Integrations/Index');
    })->name('panel.integrations.index');

    // POS / Yazarkasa entegratör kurulum sihirbazı (marka-bağımsız).
    Route::get('/panel/entegrasyonlar/pos', function () {
        abort_unless(request()->user()->hasPermission('settings.manage'), 403);

        return Inertia::render('Panel/Payments/PosIntegration');
    })->name('panel.integrations.pos');

    // API
    Route::prefix('api/v1/settings')->group(function (): void {
        Route::get('branding', [BrandingSettingsController::class, 'show'])->name('settings.branding.show');
        Route::put('branding/profile', [BrandingSettingsController::class, 'updateProfile'])->name('settings.branding.profile');
        Route::put('branding/theme', [BrandingSettingsController::class, 'updateTheme'])->name('settings.branding.theme');
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
