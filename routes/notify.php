<?php

use App\Modules\Notify\Http\Controllers\NotificationController;
use App\Modules\Notify\Http\Controllers\NotificationPreferenceController;
use App\Modules\Notify\Http\Controllers\PushSubscriptionController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Notify modülü (§8): panel-içi zil + web push abonelik + kişi tercihleri.
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir. Tüm uçlar oturum + tenant;
| yeni izin GEREKTİRMEZ (her personel KENDİ bildirimlerini/tercihlerini yönetir
| — alıcı yönlendirmesi mevcut operasyonel izinlere göre yapılır). Public uç yok.
*/
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('api/v1')->group(function (): void {

    // Panel zili
    Route::get('notifications', [NotificationController::class, 'index'])->name('notify.index');
    Route::post('notifications/read-all', [NotificationController::class, 'markAllRead'])->name('notify.read-all');
    Route::post('notifications/{notification}/read', [NotificationController::class, 'markRead'])
        ->whereNumber('notification')->name('notify.read');

    // Kişi tercihleri (Profil > Bildirimler)
    Route::get('notifications/preferences', [NotificationPreferenceController::class, 'index'])->name('notify.prefs.index');
    Route::put('notifications/preferences', [NotificationPreferenceController::class, 'update'])->name('notify.prefs.update');

    // Web push (VAPID)
    Route::get('push/vapid-public-key', [PushSubscriptionController::class, 'vapidPublicKey'])->name('notify.push.key');
    Route::post('push/subscribe', [PushSubscriptionController::class, 'subscribe'])->name('notify.push.subscribe');
    Route::post('push/unsubscribe', [PushSubscriptionController::class, 'unsubscribe'])->name('notify.push.unsubscribe');
});
