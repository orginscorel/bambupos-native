<?php

use App\Modules\Venue\Http\Controllers\AreaController;
use App\Modules\Venue\Http\Controllers\BranchController;
use App\Modules\Venue\Http\Controllers\FloorController;
use App\Modules\Venue\Http\Controllers\PublicMenuController;
use App\Modules\Venue\Http\Controllers\QrController;
use App\Modules\Venue\Http\Controllers\VenuePageController;
use App\Modules\Venue\Http\Controllers\VenueTableController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Venue modülü (Faz-2): şube / kat / alan / masa + QR (ADR-008)
|--------------------------------------------------------------------------
| Bu dosya bootstrap/app.php `then:` bloğunda kaydedilir.
| Panel sayfaları ve /api/v1/venue uçları "web" grubuyla; public QR ucu
| ise BİLİNÇLİ olarak oturumsuz kayıtlıdır (ADR-011: cache'lenen yanıtta
| Set-Cookie olamaz; rate limit denetimi controller içindedir).
*/

/* ---- Public QR ucu: kimlik YALNIZ opak token (ADR-008) ---- */
Route::get('/m/{token}', [PublicMenuController::class, 'show'])
    ->where('token', '[A-Za-z2-7]{1,64}')
    ->name('venue.public.menu');

/* ---- Panel Inertia sayfaları ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('panel')->group(function (): void {
    Route::get('/subeler', [VenuePageController::class, 'branches'])->name('panel.venue.branches');
    Route::get('/masalar', [VenuePageController::class, 'tables'])->name('panel.venue.tables');
    Route::get('/masalar/alanlar', [VenuePageController::class, 'areas'])->name('panel.venue.areas');
    Route::get('/masalar/qr', [VenuePageController::class, 'qr'])->name('panel.venue.qr');
});

/* ---- Panel API'si ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('api/v1/venue')->group(function (): void {

    // Şubeler
    Route::get('branches', [BranchController::class, 'index'])->name('venue.branches.index');
    Route::post('branches', [BranchController::class, 'store'])->name('venue.branches.store');
    Route::put('branches/{branch}', [BranchController::class, 'update'])->name('venue.branches.update');
    Route::delete('branches/{branch}', [BranchController::class, 'destroy'])->name('venue.branches.destroy');

    // Katlar
    Route::get('floors', [FloorController::class, 'index'])->name('venue.floors.index');
    Route::post('floors', [FloorController::class, 'store'])->name('venue.floors.store');
    Route::put('floors/{floor}', [FloorController::class, 'update'])->name('venue.floors.update');
    Route::delete('floors/{floor}', [FloorController::class, 'destroy'])->name('venue.floors.destroy');

    // Salon/alanlar
    Route::get('areas', [AreaController::class, 'index'])->name('venue.areas.index');
    Route::post('areas', [AreaController::class, 'store'])->name('venue.areas.store');
    Route::put('areas/{area}', [AreaController::class, 'update'])->name('venue.areas.update');
    Route::delete('areas/{area}', [AreaController::class, 'destroy'])->name('venue.areas.destroy');

    // Masalar (zengin liste + toplu işlemler)
    Route::get('tables', [VenueTableController::class, 'index'])->name('venue.tables.index');
    Route::post('tables', [VenueTableController::class, 'store'])->name('venue.tables.store');
    Route::post('tables/bulk', [VenueTableController::class, 'bulkStore'])->name('venue.tables.bulk');
    Route::post('tables/bulk-action', [VenueTableController::class, 'bulkAction'])->name('venue.tables.bulk-action');
    Route::put('tables/{table}', [VenueTableController::class, 'update'])->name('venue.tables.update');
    Route::put('tables/{table}/status', [VenueTableController::class, 'updateStatus'])->name('venue.tables.status');
    Route::delete('tables/{table}', [VenueTableController::class, 'destroy'])->name('venue.tables.destroy');

    // QR: şablon ayarları
    Route::get('qr/settings', [QrController::class, 'settings'])->name('venue.qr.settings');
    Route::put('qr/settings', [QrController::class, 'updateSettings'])->name('venue.qr.settings.update');
    Route::post('qr/logo', [QrController::class, 'uploadLogo'])->name('venue.qr.logo');
    Route::delete('qr/logo', [QrController::class, 'deleteLogo'])->name('venue.qr.logo.delete');

    // QR: görsel çıktılar (PNG/SVG ?format=, ?download=1) + A4 PDF
    Route::get('tables/{table}/qr-image', [QrController::class, 'tableImage'])->name('venue.qr.table-image');
    Route::get('branches/{branch}/qr-image', [QrController::class, 'branchImage'])->name('venue.qr.branch-image');
    Route::get('qr/sheet', [QrController::class, 'sheet'])->name('venue.qr.sheet');

    // QR: rotasyon (ADR-008 — eski token anında geçersiz)
    Route::post('tables/{table}/qr-rotate', [QrController::class, 'rotateTable'])->name('venue.qr.rotate-table');
    Route::post('branches/{branch}/qr-rotate', [QrController::class, 'rotateBranch'])->name('venue.qr.rotate-branch');
    Route::post('qr/rotate-bulk', [QrController::class, 'rotateBulk'])->name('venue.qr.rotate-bulk');
});
