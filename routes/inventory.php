<?php

use App\Modules\Inventory\Http\Controllers\AlertController;
use App\Modules\Inventory\Http\Controllers\CountController;
use App\Modules\Inventory\Http\Controllers\InventoryPageController;
use App\Modules\Inventory\Http\Controllers\MovementController;
use App\Modules\Inventory\Http\Controllers\PurchaseController;
use App\Modules\Inventory\Http\Controllers\RecipeController;
use App\Modules\Inventory\Http\Controllers\StockItemController;
use App\Modules\Inventory\Http\Controllers\SupplierController;
use App\Modules\Inventory\Http\Controllers\WarehouseController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Inventory modülü (Faz 6, §17): stok + depo + reçete + sayım + satın alma
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir. Tüm uçlar oturum + kiracı
| bağlamı ister; public uç YOKTUR. Yetki: stock.view (okuma) /
| stock.adjust (stok değiştiren her şey) — policy'ler denetler.
*/

Route::middleware(['web', 'auth:web', 'tenant'])->group(function (): void {

    /* ---- Panel ekranları (Inertia) ---- */
    Route::prefix('panel/stok')->group(function (): void {
        Route::get('/', [InventoryPageController::class, 'items'])->name('panel.inventory.items');
        Route::get('/hareketler', [InventoryPageController::class, 'movements'])->name('panel.inventory.movements');
        Route::get('/receteler', [InventoryPageController::class, 'recipes'])->name('panel.inventory.recipes');
        Route::get('/sayim', [InventoryPageController::class, 'counts'])->name('panel.inventory.counts');
        Route::get('/tedarikciler', [InventoryPageController::class, 'suppliers'])->name('panel.inventory.suppliers');
        Route::get('/satin-alma', [InventoryPageController::class, 'purchasing'])->name('panel.inventory.purchasing');
        Route::get('/uyarilar', [InventoryPageController::class, 'alerts'])->name('panel.inventory.alerts');
    });

    /* ---- JSON uçları ---- */
    Route::prefix('api/v1/inventory')->group(function (): void {

        // Depolar
        Route::get('warehouses', [WarehouseController::class, 'index'])->name('inventory.warehouses.index');
        Route::post('warehouses', [WarehouseController::class, 'store'])->name('inventory.warehouses.store');
        Route::put('warehouses/{warehouse}', [WarehouseController::class, 'update'])->whereNumber('warehouse')->name('inventory.warehouses.update');

        // Stok kartları + kategoriler
        Route::get('items', [StockItemController::class, 'index'])->name('inventory.items.index');
        Route::post('items', [StockItemController::class, 'store'])->name('inventory.items.store');
        Route::put('items/{item}', [StockItemController::class, 'update'])->whereNumber('item')->name('inventory.items.update');
        Route::get('categories', [StockItemController::class, 'categories'])->name('inventory.categories.index');
        Route::post('categories', [StockItemController::class, 'storeCategory'])->name('inventory.categories.store');

        // Hareket defteri (salt liste + onaylı manuel giriş + transfer).
        // GÜNCELLEME / SİLME UCU BİLİNÇLİ YOK — defter değişmez (§17.4).
        Route::get('movements', [MovementController::class, 'index'])->name('inventory.movements.index');
        Route::post('movements', [MovementController::class, 'store'])->name('inventory.movements.store');
        Route::get('movement-requests', [MovementController::class, 'requests'])->name('inventory.movement-requests.index');
        Route::post('movement-requests/{movementRequest}/approve', [MovementController::class, 'approve'])->whereNumber('movementRequest')->name('inventory.movement-requests.approve');
        Route::post('movement-requests/{movementRequest}/reject', [MovementController::class, 'reject'])->whereNumber('movementRequest')->name('inventory.movement-requests.reject');
        Route::post('transfers', [MovementController::class, 'transfer'])->name('inventory.transfers.store');

        // Reçeteler
        Route::get('recipes/products', [RecipeController::class, 'products'])->name('inventory.recipes.products');
        Route::get('recipes', [RecipeController::class, 'show'])->name('inventory.recipes.show');
        Route::get('recipes/versions/{recipe}', [RecipeController::class, 'version'])->whereNumber('recipe')->name('inventory.recipes.version');
        Route::post('recipes', [RecipeController::class, 'save'])->name('inventory.recipes.save');
        Route::post('production', [RecipeController::class, 'produce'])->name('inventory.production.store');

        // Sayım
        Route::get('counts', [CountController::class, 'index'])->name('inventory.counts.index');
        Route::post('counts', [CountController::class, 'store'])->name('inventory.counts.store');
        Route::get('counts/{count}', [CountController::class, 'show'])->whereNumber('count')->name('inventory.counts.show');
        Route::put('counts/{count}/lines', [CountController::class, 'saveLines'])->whereNumber('count')->name('inventory.counts.lines');
        Route::post('counts/{count}/submit', [CountController::class, 'submit'])->whereNumber('count')->name('inventory.counts.submit');
        Route::post('counts/{count}/approve', [CountController::class, 'approve'])->whereNumber('count')->name('inventory.counts.approve');
        Route::post('counts/{count}/cancel', [CountController::class, 'cancel'])->whereNumber('count')->name('inventory.counts.cancel');

        // Tedarikçiler
        Route::get('suppliers', [SupplierController::class, 'index'])->name('inventory.suppliers.index');
        Route::post('suppliers', [SupplierController::class, 'store'])->name('inventory.suppliers.store');
        Route::put('suppliers/{supplier}', [SupplierController::class, 'update'])->whereNumber('supplier')->name('inventory.suppliers.update');
        Route::get('suppliers/{supplier}/prices', [SupplierController::class, 'prices'])->whereNumber('supplier')->name('inventory.suppliers.prices');

        // Satın alma
        Route::get('purchases', [PurchaseController::class, 'index'])->name('inventory.purchases.index');
        Route::post('purchases', [PurchaseController::class, 'store'])->name('inventory.purchases.store');
        Route::get('purchases/suggested', [PurchaseController::class, 'suggested'])->name('inventory.purchases.suggested');
        Route::get('purchases/{purchase}', [PurchaseController::class, 'show'])->whereNumber('purchase')->name('inventory.purchases.show');
        Route::put('purchases/{purchase}', [PurchaseController::class, 'update'])->whereNumber('purchase')->name('inventory.purchases.update');
        Route::post('purchases/{purchase}/transition', [PurchaseController::class, 'transition'])->whereNumber('purchase')->name('inventory.purchases.transition');
        Route::post('purchases/{purchase}/receive', [PurchaseController::class, 'receive'])->whereNumber('purchase')->name('inventory.purchases.receive');
        Route::post('purchases/{purchase}/return', [PurchaseController::class, 'returnGoods'])->whereNumber('purchase')->name('inventory.purchases.return');
        Route::post('purchases/{purchase}/invoice', [PurchaseController::class, 'invoice'])->whereNumber('purchase')->name('inventory.purchases.invoice');

        // Uyarılar (§17.5)
        Route::get('alerts', [AlertController::class, 'index'])->name('inventory.alerts.index');
    });
});
