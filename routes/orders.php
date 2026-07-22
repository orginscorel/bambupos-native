<?php

use App\Modules\Orders\Http\Controllers\OrderCatalogController;
use App\Modules\Orders\Http\Controllers\OrderController;
use App\Modules\Orders\Http\Controllers\OrderPageController;
use App\Modules\Orders\Http\Controllers\PublicOrderController;
use App\Modules\Orders\Http\Controllers\ServiceRequestController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Orders modülü (Faz-3): sipariş/adisyon çekirdeği + garson ekranları
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir.
|
| Faz-1'in identity.php'deki iskelet order uçları (index/store/show/cancel)
| BURAYA taşınıp genişletildi (aynı URI'ler korunur; TenantEscapeTest
| sözleşmesi: yabancı kayıt 404, yabancı şube 422).
|
| Public uç BİLİNÇLİ oturumsuz: kimlik yalnız QR token (ADR-008), yanıt
| kişiye özel olduğundan cache'lenmez. CSRF web grubuna bağlıdır; bu uçlar
| "web" DIŞINDA kayıtlıdır (kiosk/PWA fetch'i token'la yazar).
*/

/* ---- Panel Inertia sayfaları (garson ekranları) ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('panel')->group(function (): void {
    Route::get('/siparisler', [OrderPageController::class, 'board'])->name('panel.orders.board');
    Route::get('/siparisler/{order}', [OrderPageController::class, 'detail'])
        ->whereNumber('order')->name('panel.orders.detail');
});

/* ---- Panel API'si ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('api/v1')->group(function (): void {

    // Masa ızgarası + hızlı ekleme kataloğu
    Route::get('orders/board', [OrderController::class, 'board'])->name('orders.board');
    Route::get('orders/catalog', [OrderCatalogController::class, 'index'])->name('orders.catalog');

    // Adisyon CRUD (Faz-1 iskelet uçlarının devamı — aynı URI'ler)
    Route::get('orders', [OrderController::class, 'index'])->name('orders.index');
    Route::post('orders', [OrderController::class, 'store'])->name('orders.store');
    Route::get('orders/{order}', [OrderController::class, 'show'])->whereNumber('order')->name('orders.show');

    // Kalemler (Idempotency-Key başlığı desteklenir — prompt §12.4)
    Route::post('orders/{order}/items', [OrderController::class, 'addItem'])->name('orders.items.add');
    Route::put('orders/{order}/items/{item}', [OrderController::class, 'updateItem'])->name('orders.items.update');
    Route::delete('orders/{order}/items/{item}', [OrderController::class, 'removeItem'])->name('orders.items.remove');
    Route::post('orders/{order}/items/{item}/cancel', [OrderController::class, 'cancelItem'])->name('orders.items.cancel');
    Route::post('orders/{order}/items/{item}/comp', [OrderController::class, 'compItem'])->name('orders.items.comp');
    Route::put('orders/{order}/items/{item}/status', [OrderController::class, 'setItemStatus'])->name('orders.items.status');
    Route::post('orders/{order}/items/{item}/move', [OrderController::class, 'moveItem'])->name('orders.items.move');

    // Durum makinesi
    Route::put('orders/{order}/status', [OrderController::class, 'setStatus'])->name('orders.status');
    Route::post('orders/{order}/approve', [OrderController::class, 'approve'])->name('orders.approve');
    Route::post('orders/{order}/request-bill', [OrderController::class, 'requestBill'])->name('orders.request-bill');

    // İndirim / ödeme / iptal / iade (§12.3 — ayrı izinler)
    Route::post('orders/{order}/discount', [OrderController::class, 'discount'])->name('orders.discount');
    Route::post('orders/{order}/pay', [OrderController::class, 'pay'])->name('orders.pay');
    Route::post('orders/{order}/cancel', [OrderController::class, 'cancel'])->name('orders.cancel');
    Route::post('orders/{order}/refund', [OrderController::class, 'refund'])->name('orders.refund');

    // Taşı / birleştir / böl (§12.2)
    Route::post('orders/{order}/move', [OrderController::class, 'move'])->name('orders.move');
    Route::post('orders/{order}/merge', [OrderController::class, 'merge'])->name('orders.merge');
    Route::post('orders/{order}/split', [OrderController::class, 'split'])->name('orders.split');

    // Servis talebini kapat (garson panosu)
    Route::post('orders/service-requests/{serviceRequest}/done', [ServiceRequestController::class, 'done'])
        ->name('orders.service-requests.done');
});

/* ---- Public (oturumsuz) QR sipariş ucu — Musteri-Menu buraya bağlanır ---- */
Route::post('/api/v1/public/orders', [PublicOrderController::class, 'store'])
    ->name('orders.public.store');
Route::get('/api/v1/public/orders/{publicToken}', [PublicOrderController::class, 'show'])
    ->where('publicToken', '[A-Za-z2-7]{1,64}')
    ->name('orders.public.show');

/* ---- Public servis talebi: garson çağır / hesap iste / su iste ---- */
Route::post('/api/v1/public/service-requests', [ServiceRequestController::class, 'store'])
    ->name('orders.public.service-request');
