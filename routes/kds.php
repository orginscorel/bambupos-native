<?php

use App\Modules\Kds\Http\Controllers\KdsActionController;
use App\Modules\Kds\Http\Controllers\KdsPageController;
use App\Modules\Kds\Http\Controllers\KdsQueueController;
use App\Modules\Kds\Http\Controllers\StationController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| KDS modülü (Faz-4): mutfak/bar/komi ekranları.
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir.
|
| - Ekranlarda YALNIZ operasyon bilgisi vardır (prompt §20) — fiyat/ciro yok.
| - Gerçek zamanlılık ADR-006: 3-5 sn cursor'lı polling; değişiklik yoksa
|   204 boş yanıt (WS/SSE YOK — v1).
| - Tüm uçlar auth + tenant; kalem binding'i tenant-scope'ludur (yabancı 404).
*/

Route::middleware(['web', 'auth:web', 'tenant'])->group(function (): void {

    /* ---- Inertia sayfaları ---- */
    // Bar ekranı = aynı ekran, ?istasyon=bar (istasyon süzgeci kalıcıdır).
    Route::get('/panel/mutfak', [KdsPageController::class, 'kitchen'])->name('panel.kds.kitchen');
    Route::get('/panel/komi', [KdsPageController::class, 'runner'])->name('panel.kds.runner');

    /* ---- JSON uçları ---- */
    Route::prefix('api/v1/kds')->group(function (): void {

        // Okuma + polling (ADR-006)
        Route::get('queue', [KdsQueueController::class, 'queue'])->name('kds.queue');
        Route::get('updates', [KdsQueueController::class, 'updates'])->name('kds.updates');

        // İstasyon tanımları (yerleşik + işletmenin kendi istasyonları)
        Route::get('stations', [StationController::class, 'index'])->name('kds.stations.index');
        Route::post('stations', [StationController::class, 'store'])->name('kds.stations.store');
        Route::put('stations/{station}', [StationController::class, 'update'])->whereNumber('station')->name('kds.stations.update');
        Route::delete('stations/{station}', [StationController::class, 'destroy'])->whereNumber('station')->name('kds.stations.destroy');

        // Personel-istasyon ataması ("yalnız kendi istasyonunu görsün")
        Route::get('station-assignments', [StationController::class, 'assignments'])->name('kds.assignments.index');
        Route::put('station-assignments/{user}', [StationController::class, 'assign'])->whereNumber('user')->name('kds.assignments.update');

        // Mutfak eylemleri (mutasyonlar OrderService çekirdeğinden geçer)
        Route::post('items/{item}/status', [KdsActionController::class, 'itemStatus'])->whereNumber('item')->name('kds.items.status');
        Route::post('items/{item}/undo', [KdsActionController::class, 'undo'])->whereNumber('item')->name('kds.items.undo');
        Route::post('items/{item}/transfer', [KdsActionController::class, 'transfer'])->whereNumber('item')->name('kds.items.transfer');
        Route::post('orders/{order}/station-ready', [KdsActionController::class, 'stationReady'])->whereNumber('order')->name('kds.orders.station-ready');

        // Komi eylemleri
        Route::post('items/{item}/pickup', [KdsActionController::class, 'pickup'])->whereNumber('item')->name('kds.items.pickup');
        Route::delete('items/{item}/pickup', [KdsActionController::class, 'pickupUndo'])->whereNumber('item')->name('kds.items.pickup-undo');
    });
});
