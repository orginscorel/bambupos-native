<?php

use App\Modules\Billing\Http\Controllers\BillingOverviewController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| A2 — Abonelik & Faturalama (SaaS gelir modeli) — süper-admin salt-okuma.
|--------------------------------------------------------------------------
| routes/web.php içindeki mevcut `superadmin.` grubuyla AYNI middleware/
| prefix/name deseni burada tekrarlanır (o dosyaya DOKUNULMADI — bilinçli
| ayrı dosya). Kayıt (register) için ana oturumun yapması gereken adım
| raporda belirtilmiştir; bu dosya kendiliğinden yüklenmez.
|--------------------------------------------------------------------------
*/
Route::middleware(['auth:web', 'superadmin'])->prefix('yonetim')->name('superadmin.')->group(function (): void {
    Route::get('/faturalama', [BillingOverviewController::class, 'overview'])->name('billing');
});
