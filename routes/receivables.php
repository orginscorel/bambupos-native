<?php

use App\Modules\Receivables\Http\Controllers\ReceivableController;
use App\Modules\Receivables\Http\Controllers\ReceivablePageController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Borçlar / Cari modülü (Adisyon-Cari): "adisyonu borca taşı" hedefi
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir.
|
| `orders/{order}/transfer-to-debt` BİLİNÇLİ olarak burada yaşar — Orders
| rotasına dokunulmadı; Payments modülünün `orders/{order}/payments`
| ucuyla AYNI desen (bir modül başka modülün ana varlığı üzerinde eylem
| kaydedebilir; kimlik/kiracılık route-model-binding'den gelir).
*/

/* ---- Panel Inertia sayfası ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('panel')->group(function (): void {
    Route::get('/borclar', [ReceivablePageController::class, 'index'])->name('panel.receivables.index');
});

/* ---- Panel API'si ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('api/v1')->group(function (): void {
    Route::get('receivables', [ReceivableController::class, 'index'])->name('receivables.index');
    Route::post('receivables', [ReceivableController::class, 'store'])->name('receivables.store');
    Route::get('receivables/{receivable}', [ReceivableController::class, 'show'])->whereNumber('receivable')->name('receivables.show');
    Route::put('receivables/{receivable}', [ReceivableController::class, 'update'])->whereNumber('receivable')->name('receivables.update');
    Route::post('receivables/{receivable}/collect', [ReceivableController::class, 'collect'])->whereNumber('receivable')->name('receivables.collect');

    // Adisyonu borca taşı (Orders köprüsü — bkz. dosya başlığı)
    Route::post('orders/{order}/transfer-to-debt', [ReceivableController::class, 'transferOrder'])
        ->whereNumber('order')->name('receivables.transfer-order');
});
