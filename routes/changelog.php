<?php

use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| Sürüm notları (Surum-Changelog ajanı)
|--------------------------------------------------------------------------
| Site (panel) ve native (henüz yayınlanmadı) sürüm geçmişi. Herhangi bir
| işletmeye özel veri taşımaz — özel bir izin gerektirmez, oturumu olan her
| personel görebilir (routes/web.php'deki /panel/profil ile aynı desen:
| yalnız auth:web + tenant).
*/
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('panel')->group(function (): void {
    Route::get('/surum-notlari', function () {
        return Inertia::render('Panel/Changelog', [
            'site' => config('changelog'),
            'native' => config('native_changelog'),
        ]);
    })->name('panel.changelog');
});

/*
|--------------------------------------------------------------------------
| Alt bilgi sürüm rozeti
|--------------------------------------------------------------------------
| PanelShell her panel sayfasında görünür; tam changelog verisini yeniden
| çekmeden yalnız güncel sürüm numaralarını okur (hafif JSON, tenant'a özel
| bir şey döndürmez).
*/
Route::middleware(['web', 'auth:web', 'tenant'])->get('/api/v1/changelog/version', function () {
    return response()->json([
        'site' => [
            'version' => config('changelog.current_version'),
            'released_at' => config('changelog.released_at'),
        ],
        'native' => [
            'status' => config('native_changelog.status'),
            'version' => config('native_changelog.current_version'),
        ],
    ]);
})->name('api.changelog.version');

/*
|--------------------------------------------------------------------------
| Sürüm yoklama ucu (açık oturumlara "yeni güncelleme" bildirimi)
|--------------------------------------------------------------------------
| Tüm istemci kabukları (panel / personel portalı / patron / KDS) periyodik
| olarak yalnız güncel sürüm numarasını yoklar. Auth GEREKTİRMEZ, tenant'a
| özel veri taşımaz — hafif ve hızlı. İlk görülenden farklı sürüm görülünce
| istemci "yenile" toast'ı gösterir.
*/
Route::middleware(['web'])->get('/api/v1/app-version', function () {
    return response()->json([
        'version' => config('changelog.current_version'),
    ]);
})->name('api.app-version');
