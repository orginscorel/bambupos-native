<?php

use App\Modules\Reports\Http\Controllers\DashboardController;
use App\Modules\Reports\Http\Controllers\ExportController;
use App\Modules\Reports\Http\Controllers\ReportDataController;
use App\Modules\Reports\Http\Controllers\ReportPageController;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| Reports modülü (Faz-10): rol bazlı panel açılışı + rapor ekranı + JSON
| uçları + kuyruklu dışa aktarma.
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir.
|
| - /api/v1/reports/summary (Faz-1 iskeleti, identity.php) OLDUĞU GİBİ
|   durur; buradaki {report} deseni ondan SONRA kaydedildiği için eski uç
|   önceliğini korur.
| - Tüm uçlar auth + tenant ister; rapor verisi reports.view iznine bağlı,
|   dashboard ise izin-süzgeçli bölümler döndürür (DashboardService).
*/

Route::middleware(['web', 'auth:web', 'tenant'])->group(function (): void {

    /* ---- Panel ekranı (Inertia) ---- */
    Route::get('/panel/raporlar', [ReportPageController::class, 'index'])->name('panel.reports');

    // Nasıl Çalışır (kasa↔sipariş↔masa↔adisyon↔cari anlatımı): izin GEREKMEZ
    // — herhangi bir işletmeye özel veri taşımaz, /surum-notlari ile aynı
    // desen (auth:web + tenant yeterli).
    Route::get('/panel/nasil-calisir', fn () => Inertia::render('Panel/Wiki'))->name('panel.wiki');

    /* ---- JSON uçları ---- */
    Route::prefix('api/v1/reports')->group(function (): void {
        Route::get('dashboard', [DashboardController::class, 'index'])->name('reports.dashboard');

        Route::get('exports', [ExportController::class, 'index'])->name('reports.exports.index');
        Route::post('exports', [ExportController::class, 'store'])->name('reports.exports.store');
        Route::get('exports/{export}/download', [ExportController::class, 'download'])
            ->whereNumber('export')->name('reports.exports.download');

        // Kapalı listedeki rapor anahtarları (ReportRegistry).
        Route::get('{report}', [ReportDataController::class, 'show'])
            ->where('report', '[a-z0-9\-]+')->name('reports.show');
    });
});
