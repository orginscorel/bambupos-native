<?php

use App\Modules\Boss\Http\Controllers\BossController;
use App\Modules\Boss\Support\BossHost;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| PATRON PANELİ (executive — AYRI SİSTEM)
|--------------------------------------------------------------------------
| Ayrı, kapsamlı yönetici/patron ekranı; verileri mevcut modüllerden (sipariş/
| ödeme/stok/performans/teslimat) ÇEKER. Yetki: boss.view. Şube kapsamı
| BranchContext ile — yönetici seçili şubesini, sahip/müdür genel/seçili şubeyi.
|
| ERİŞİM: YALNIZ AYRI SUBDOMAIN (patron.*) — personel portalı deseninin eşi;
| Patron Paneli KÖKTE (/) açılır. Operasyon paneli içindeki /panel/boss erişimi
| KALDIRILDI (2026-07-29) — patron ayrı bir uygulamadır, kendi host'undan girilir.
| API uçları host'tan bağımsız (domain kısıtsız) → subdomain app'inden çağrılır.
*/

/* ---- Patron subdomain: Patron Paneli kökte ---- */
Route::domain(BossHost::host())
    ->middleware(['web', 'auth:web', 'tenant'])
    ->group(function (): void {
        Route::get('/', fn () => Inertia::render('Panel/Boss/Index'))->name('boss.home');
        Route::get('/vardiya', fn () => Inertia::render('Panel/Boss/Shifts'))->name('boss.shifts');
        Route::get('/gorevler', fn () => Inertia::render('Panel/Boss/Tasks'))->name('boss.tasks');
    });

/* ---- Ortak API uçları (host'tan bağımsız; patron.* app'inden çağrılır) ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->group(function (): void {
    Route::prefix('api/v1/boss')->group(function (): void {
        Route::get('overview', [BossController::class, 'overview'])->name('boss.overview');
    });
});
