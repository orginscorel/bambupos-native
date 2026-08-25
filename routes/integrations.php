<?php

use App\Modules\Integrations\Http\Controllers\IntegrationController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Entegrasyonlar (takılabilir çerçeve) — API
|--------------------------------------------------------------------------
| Panelden ödeme / teslimat platformu / e-fatura / muhasebe entegrasyonlarını
| TEK yerden aç/kapa + yapılandırma. Aktifse sistem uyum sağlar, pasifse
| çerçeve sessizdir (graceful no-op). Yetki: integrations.manage (controller
| içinde denetlenir). Kiracı bağlamı: `tenant` middleware.
|
| Panel ekranı GET /panel/entegrasyonlar routes/settings.php içinde ZATEN
| tanımlıdır; burada YALNIZ JSON API uçları vardır (çakışma yok).
*/
Route::middleware(['web', 'auth:web', 'tenant'])->group(function (): void {

    Route::prefix('api/v1/integrations')->group(function (): void {
        Route::get('/', [IntegrationController::class, 'index'])->name('integrations.index');
        Route::post('toggle', [IntegrationController::class, 'toggle'])->name('integrations.toggle');
        Route::post('config', [IntegrationController::class, 'saveConfig'])->name('integrations.config');
    });
});
