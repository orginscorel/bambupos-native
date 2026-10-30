<?php

use App\Modules\Orders\Http\Controllers\OncekiAdisyonController;
use App\Modules\Orders\Http\Controllers\OrderCatalogController;
use App\Modules\Orders\Http\Controllers\DiscountPresetController;
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

    /* ÖNCEKİ ADİSYONLAR (2026-10-24): kapanmış adisyonların listesi.
       Siparişler ekranının sekmesi gibi davranır ama KENDİ ADRESİ vardır —
       dönem ve arama sorgu dizisinde, yani adres paylaşılabilir. */
    Route::get('/siparisler/gecmis', [OrderPageController::class, 'gecmis'])
        ->name('panel.orders.history');
});

/* ---- Panel API'si ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('api/v1')->group(function (): void {

    // Masa ızgarası + hızlı ekleme kataloğu
    // ETag/304 (2026-10-27): her POS cihazı 5 sn'de bir yokluyor; değişmeyen pano gövdesiz döner.
    Route::get('orders/board', [OrderController::class, 'board'])
        ->middleware(\App\Http\Middleware\EtagJson::class)->name('orders.board');

    /* DEĞİŞİM AKIŞI (2026-10-30): POS uygulaması adisyon olaylarını uzun
       yoklamayla izler (KDS updates kalıbı) — birleştir/taşı/kapat diğer
       cihazlara ~0,5 sn'de yansır. Pano yoklaması YEDEK olarak sürer. */
    Route::get('orders/degisim', [\App\Modules\Orders\Http\Controllers\OrderSenkronController::class, 'degisim'])
        ->name('orders.degisim');

    /* ÖNCEKİ ADİSYONLAR: liste · detay · fişi yeniden bas (2026-10-24).
       Yetki uçların içinde: liste/detay `orders.view`, yeniden basım
       `payments.take` (fiş basımı tahsilat akışının parçası). */
    Route::get('orders/gecmis', [OncekiAdisyonController::class, 'index'])->name('orders.history');
    Route::get('orders/gecmis/{order}', [OncekiAdisyonController::class, 'show'])
        ->whereNumber('order')->name('orders.history.show');
    Route::post('orders/gecmis/{order}/fis', [OncekiAdisyonController::class, 'yenidenBas'])
        ->whereNumber('order')->name('orders.history.reprint');
    Route::get('orders/catalog', [OrderCatalogController::class, 'index'])->name('orders.catalog');

    // Adisyon CRUD (Faz-1 iskelet uçlarının devamı — aynı URI'ler)
    Route::get('orders', [OrderController::class, 'index'])->name('orders.index');
    Route::post('orders', [OrderController::class, 'store'])->name('orders.store');
    // ETag/304 (2026-10-27): açık kasa/adisyon ekranları adisyonu ~3 sn'de bir yokluyor
    // (başka personelin eklediği kalem anında görünsün); değişmeyen adisyon gövdesiz döner.
    Route::get('orders/{order}', [OrderController::class, 'show'])->whereNumber('order')
        ->middleware(\App\Http\Middleware\EtagJson::class)->name('orders.show');

    // Adisyon başlığı (kişi sayısı + adisyon notu) — sonradan düzeltilebilsin
    Route::put('orders/{order}/info', [OrderController::class, 'updateInfo'])->whereNumber('order')->name('orders.info');

    // Kalemler (Idempotency-Key başlığı desteklenir — prompt §12.4)
    Route::post('orders/{order}/items', [OrderController::class, 'addItem'])->name('orders.items.add');
    Route::put('orders/{order}/items/{item}', [OrderController::class, 'updateItem'])->name('orders.items.update');
    Route::delete('orders/{order}/items/{item}', [OrderController::class, 'removeItem'])->name('orders.items.remove');
    // Kalem notu (2026-10-27): yalnız hazırlığa gönderilmemiş adede; POST de kabul (istemci kolaylığı).
    Route::match(['patch', 'post'], 'orders/{order}/items/{item}/note', [OrderController::class, 'setItemNote'])
        ->whereNumber('order')->name('orders.items.note');
    Route::post('orders/{order}/items/{item}/cancel', [OrderController::class, 'cancelItem'])->name('orders.items.cancel');
    // Yanlış ürün girildiyse doğrusuyla değiştir (iptal + ekle, tek olay).
    Route::post('orders/{order}/items/{item}/swap', [OrderController::class, 'swapItem'])->name('orders.items.swap');
    Route::post('orders/{order}/items/{item}/comp', [OrderController::class, 'compItem'])->name('orders.items.comp');
    // İkramı geri al (yanlış kaleme ikram denmişse) — yetki ikramla aynı.
    Route::delete('orders/{order}/items/{item}/comp', [OrderController::class, 'uncompItem'])->name('orders.items.uncomp');
    Route::put('orders/{order}/items/{item}/status', [OrderController::class, 'setItemStatus'])->name('orders.items.status');
    Route::post('orders/{order}/items/{item}/move', [OrderController::class, 'moveItem'])->name('orders.items.move');
    // Seçili kalemleri TOPLU taşı (masa ya da şahıs) — 2026-09-12.
    Route::post('orders/{order}/items/toplu-tasi', [OrderController::class, 'moveItems'])->whereNumber('order')->name('orders.items.bulk-move');
    // Okey parti (el) takibi: partiyi kapat, yeni el başlat — 2026-09-12.
    Route::post('orders/{order}/parti-kapat', [OrderController::class, 'partiyiKapat'])->whereNumber('order')->name('orders.parti.close');
    Route::post('orders/{order}/parti-adi', [OrderController::class, 'partiyiAdlandir'])->whereNumber('order')->name('orders.parti.name');
    // Tek kalemi kişinin (cari) adisyonuna taşı.
    Route::post('orders/{order}/items/{item}/cariye-tasi', [OrderController::class, 'moveItemToReceivable'])->name('orders.items.move-receivable');

    // Durum makinesi
    Route::put('orders/{order}/status', [OrderController::class, 'setStatus'])->name('orders.status');
    Route::post('orders/{order}/approve', [OrderController::class, 'approve'])->name('orders.approve');
    Route::post('orders/{order}/send-to-kitchen', [OrderController::class, 'sendToKitchen'])->whereNumber('order')->name('orders.send-to-kitchen');
    Route::post('orders/{order}/request-bill', [OrderController::class, 'requestBill'])->name('orders.request-bill');
    Route::post('orders/{order}/send-to-service', [OrderController::class, 'sendBackToService'])->name('orders.send-to-service');

    // Hazır indirim tanımları (şehit/gazi yakını, kamu personeli, öğrenci…)
    Route::get('discount-presets', [DiscountPresetController::class, 'index'])->name('orders.discount-presets.index');
    Route::post('discount-presets', [DiscountPresetController::class, 'store'])->name('orders.discount-presets.store');
    Route::get('discount-presets/{discountPreset}/stats', [DiscountPresetController::class, 'stats'])->name('orders.discount-presets.stats');
    Route::put('discount-presets/{discountPreset}', [DiscountPresetController::class, 'update'])->name('orders.discount-presets.update');
    Route::delete('discount-presets/{discountPreset}', [DiscountPresetController::class, 'destroy'])->name('orders.discount-presets.destroy');

    // İndirim / ödeme / iptal / iade (§12.3 — ayrı izinler)
    Route::post('orders/{order}/discount', [OrderController::class, 'discount'])->name('orders.discount');

    // İskonto: kasada tutar yazarak düşüm — kupon/tanımlı indirimden AYRI alan.
    Route::post('orders/{order}/iskonto', [OrderController::class, 'iskonto'])->name('orders.iskonto');
    Route::delete('orders/{order}/iskonto', [OrderController::class, 'removeIskonto'])->name('orders.iskonto.remove');
    Route::delete('orders/{order}/discount', [OrderController::class, 'removeDiscount'])->name('orders.discount.remove');
    Route::post('orders/{order}/pay', [OrderController::class, 'pay'])->name('orders.pay');
    Route::post('orders/{order}/cancel', [OrderController::class, 'cancel'])->name('orders.cancel');
    // Ürün eklenmeden çıkılan boş adisyonu kapatır (masa boşa döner).
    Route::post('orders/{order}/discard-if-empty', [OrderController::class, 'discardIfEmpty'])->name('orders.discard-if-empty');
    Route::post('orders/{order}/refund', [OrderController::class, 'refund'])->name('orders.refund');

    // Taşı / birleştir / böl (§12.2)
    Route::post('orders/{order}/move', [OrderController::class, 'move'])->name('orders.move');
    // Masadaki hesabı kişinin (cari) hesabına taşı.
    Route::post('orders/{order}/cariye-tasi', [OrderController::class, 'moveToReceivable'])->name('orders.move-receivable');
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
