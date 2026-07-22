<?php

use App\Modules\Catalog\Http\Controllers\Panel\AllergenController;
use App\Modules\Catalog\Http\Controllers\Panel\CategoryController;
use App\Modules\Catalog\Http\Controllers\Panel\MenuController;
use App\Modules\Catalog\Http\Controllers\Panel\OptionGroupController;
use App\Modules\Catalog\Http\Controllers\Panel\ProductController;
use App\Modules\Catalog\Http\Controllers\Panel\ProductImageController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Katalog domaini (Faz 2) — panel sayfaları + oturumlu JSON uçları.
| Tüm uçlar auth + tenant bağlamı ister; model binding'ler global scope
| sayesinde yabancı kiracıda 404 üretir (ADR-004).
|--------------------------------------------------------------------------
*/

Route::middleware(['auth:web', 'tenant'])->group(function (): void {

    /* ---- Panel ekranları (Inertia) ---- */
    Route::prefix('panel/menu')->group(function (): void {
        Route::get('/', [ProductController::class, 'indexPage'])->name('panel.catalog.products');
        Route::get('/urunler/yeni', [ProductController::class, 'createPage'])->name('panel.catalog.products.create');
        Route::get('/urunler/{product}', [ProductController::class, 'editPage'])->name('panel.catalog.products.edit');
        Route::get('/kategoriler', [CategoryController::class, 'page'])->name('panel.catalog.categories');
        Route::get('/secenekler', [OptionGroupController::class, 'page'])->name('panel.catalog.options');
        Route::get('/alerjenler', [AllergenController::class, 'page'])->name('panel.catalog.allergens');
        Route::get('/menuler', [MenuController::class, 'page'])->name('panel.catalog.menus');
    });

    /* ---- JSON uçları ---- */
    Route::prefix('api/v1/catalog')->group(function (): void {

        Route::get('categories', [CategoryController::class, 'index'])->name('catalog.categories.index');
        Route::post('categories', [CategoryController::class, 'store'])->name('catalog.categories.store');
        Route::post('categories/reorder', [CategoryController::class, 'reorder'])->name('catalog.categories.reorder');
        Route::put('categories/{category}', [CategoryController::class, 'update'])->name('catalog.categories.update');
        Route::delete('categories/{category}', [CategoryController::class, 'destroy'])->name('catalog.categories.destroy');

        Route::get('products', [ProductController::class, 'index'])->name('catalog.products.index');
        Route::get('products/form-options', [ProductController::class, 'formOptions'])->name('catalog.products.form-options');
        Route::post('products', [ProductController::class, 'store'])->name('catalog.products.store');
        Route::post('products/bulk', [ProductController::class, 'bulk'])->name('catalog.products.bulk');
        Route::post('products/reorder', [ProductController::class, 'reorder'])->name('catalog.products.reorder');
        Route::get('products/{product}', [ProductController::class, 'show'])->name('catalog.products.show');
        Route::put('products/{product}', [ProductController::class, 'update'])->name('catalog.products.update');
        Route::delete('products/{product}', [ProductController::class, 'destroy'])->name('catalog.products.destroy');

        Route::post('products/{product}/images', [ProductImageController::class, 'store'])->name('catalog.products.images.store');
        Route::post('products/{product}/images/{image}/primary', [ProductImageController::class, 'makePrimary'])->name('catalog.products.images.primary');
        Route::delete('products/{product}/images/{image}', [ProductImageController::class, 'destroy'])->name('catalog.products.images.destroy');

        Route::get('option-groups', [OptionGroupController::class, 'index'])->name('catalog.option-groups.index');
        Route::post('option-groups', [OptionGroupController::class, 'store'])->name('catalog.option-groups.store');
        Route::put('option-groups/{optionGroup}', [OptionGroupController::class, 'update'])->name('catalog.option-groups.update');
        Route::delete('option-groups/{optionGroup}', [OptionGroupController::class, 'destroy'])->name('catalog.option-groups.destroy');

        Route::get('allergens', [AllergenController::class, 'index'])->name('catalog.allergens.index');
        Route::post('allergens', [AllergenController::class, 'store'])->name('catalog.allergens.store');
        Route::put('allergens/{allergen}', [AllergenController::class, 'update'])->name('catalog.allergens.update');
        Route::delete('allergens/{allergen}', [AllergenController::class, 'destroy'])->name('catalog.allergens.destroy');

        Route::get('menus', [MenuController::class, 'index'])->name('catalog.menus.index');
        Route::post('menus', [MenuController::class, 'store'])->name('catalog.menus.store');
        Route::put('menus/{menu}', [MenuController::class, 'update'])->name('catalog.menus.update');
        Route::delete('menus/{menu}', [MenuController::class, 'destroy'])->name('catalog.menus.destroy');
    });
});
