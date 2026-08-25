<?php

use App\Modules\Shifts\Http\Controllers\ClockController;
use App\Modules\Shifts\Http\Controllers\LeaveRequestController;
use App\Modules\Shifts\Http\Controllers\PerformanceController;
use App\Modules\Shifts\Http\Controllers\ScheduleController;
use App\Modules\Shifts\Http\Controllers\ShiftPageController;
use App\Modules\Shifts\Http\Controllers\ShiftSettingController;
use App\Modules\Shifts\Http\Controllers\SwapRequestController;
use App\Modules\Shifts\Http\Controllers\TimeEntryController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Shifts modülü (Faz-7): vardiya planlama + mesai takibi.
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir.
|
| - Panel + API uçları oturum + kiracı bağlamı ister.
| - /api/v1/shifts/device-clock BİLİNÇLİ oturumsuzdur: yetkili cihaz
|   (X-Device-Token) kiracı kimliğini CİHAZDAN alır; PIN personeli çözer.
|   NFC/QR okuyucular ileride aynı ucu kullanır (method alanı hazır).
| - KVKK: konum takibi varsayılan KAPALI; işletme ayarı + personel rızası
|   olmadan koordinat saklanmaz (TimeClockService süzgeci).
*/

// feature:shifts (denetim #7): "Vardiya/Mesai" eklentisi kapalıysa TÜM grup 404 —
// eskiden yalnız Inertia sayfaları gate'liydi, API (schedule CRUD/clock/izin) açıktı.
Route::middleware(['web', 'auth:web', 'tenant', 'feature:shifts'])->group(function (): void {

    /* ---- Inertia sayfaları ---- */
    Route::get('/panel/vardiya', [ShiftPageController::class, 'schedule'])->name('panel.shifts.schedule');
    Route::prefix('panel/mesai')->group(function (): void {
        Route::get('/', [ShiftPageController::class, 'timeEntries'])->name('panel.shifts.time-entries');
        Route::get('/giris-cikis', [ShiftPageController::class, 'clock'])->name('panel.shifts.clock');
        Route::get('/izinler', [ShiftPageController::class, 'leaves'])->name('panel.shifts.leaves');
        Route::get('/talepler', [ShiftPageController::class, 'approvals'])->name('panel.shifts.approvals');
        Route::get('/performans', [ShiftPageController::class, 'performance'])->name('panel.shifts.performance');
        Route::get('/maaslar', [ShiftPageController::class, 'payroll'])->name('panel.shifts.payroll');
        Route::get('/ayarlar', [ShiftPageController::class, 'settings'])->name('panel.shifts.settings');
    });

    /* ---- JSON uçları ---- */
    Route::prefix('api/v1/shifts')->group(function (): void {

        // Planlayıcı
        Route::get('meta', [ScheduleController::class, 'meta'])->name('shifts.meta');
        Route::get('schedule', [ScheduleController::class, 'schedule'])->name('shifts.schedule');
        Route::post('shifts', [ScheduleController::class, 'store'])->name('shifts.store');
        Route::put('shifts/{shift}', [ScheduleController::class, 'update'])->whereNumber('shift')->name('shifts.update');
        Route::delete('shifts/{shift}', [ScheduleController::class, 'destroy'])->whereNumber('shift')->name('shifts.destroy');

        // Vardiya değişim talepleri
        Route::get('swap-requests', [SwapRequestController::class, 'index'])->name('shifts.swaps.index');
        Route::post('shifts/{shift}/swap-requests', [SwapRequestController::class, 'store'])->whereNumber('shift')->name('shifts.swaps.store');
        Route::post('swap-requests/{swap}/approve', [SwapRequestController::class, 'approve'])->whereNumber('swap')->name('shifts.swaps.approve');
        Route::post('swap-requests/{swap}/reject', [SwapRequestController::class, 'reject'])->whereNumber('swap')->name('shifts.swaps.reject');
        Route::post('swap-requests/{swap}/cancel', [SwapRequestController::class, 'cancel'])->whereNumber('swap')->name('shifts.swaps.cancel');

        // Kiosk giriş/çıkış (oturumlu ekran; kimlik PIN'den çözülür)
        Route::get('clock/meta', [ClockController::class, 'clockMeta'])->name('shifts.clock.meta');
        Route::post('clock', [ClockController::class, 'clock'])->name('shifts.clock');

        // Maaş / Bordro (staff.manage)
        Route::get('payroll', [\App\Modules\Shifts\Http\Controllers\PayrollController::class, 'index'])->name('shifts.payroll.index');
        Route::put('payroll/{user}', [\App\Modules\Shifts\Http\Controllers\PayrollController::class, 'update'])->whereNumber('user')->name('shifts.payroll.update');

        // Mesai kayıtları
        Route::get('time-entries', [TimeEntryController::class, 'index'])->name('shifts.entries.index');
        Route::put('time-entries/{entry}', [TimeEntryController::class, 'update'])->whereNumber('entry')->name('shifts.entries.update');
        Route::post('time-entries/{entry}/approve', [TimeEntryController::class, 'approve'])->whereNumber('entry')->name('shifts.entries.approve');
        Route::get('attendance-summary', [TimeEntryController::class, 'attendanceSummary'])->name('shifts.attendance');

        // İzin / rapor / devamsızlık
        Route::get('leave-requests', [LeaveRequestController::class, 'index'])->name('shifts.leaves.index');
        Route::post('leave-requests', [LeaveRequestController::class, 'store'])->name('shifts.leaves.store');
        Route::post('leave-requests/{leave}/approve', [LeaveRequestController::class, 'approve'])->whereNumber('leave')->name('shifts.leaves.approve');
        Route::post('leave-requests/{leave}/reject', [LeaveRequestController::class, 'reject'])->whereNumber('leave')->name('shifts.leaves.reject');
        Route::post('leave-requests/{leave}/cancel', [LeaveRequestController::class, 'cancel'])->whereNumber('leave')->name('shifts.leaves.cancel');

        // Performans (dengeli metrik seti)
        Route::get('performance', [PerformanceController::class, 'index'])->name('shifts.performance');

        // Ayarlar + KVKK rızası + cihazlar + min. personel kuralları
        Route::get('settings', [ShiftSettingController::class, 'show'])->name('shifts.settings.show');
        Route::put('settings', [ShiftSettingController::class, 'update'])->name('shifts.settings.update');
        Route::post('location-consent', [ShiftSettingController::class, 'giveConsent'])->name('shifts.consent.give');
        Route::delete('location-consent', [ShiftSettingController::class, 'revokeConsent'])->name('shifts.consent.revoke');
        Route::get('devices', [ShiftSettingController::class, 'devices'])->name('shifts.devices.index');
        Route::post('devices', [ShiftSettingController::class, 'storeDevice'])->name('shifts.devices.store');
        Route::delete('devices/{device}', [ShiftSettingController::class, 'destroyDevice'])->whereNumber('device')->name('shifts.devices.destroy');
        Route::get('staffing-rules', [ShiftSettingController::class, 'staffingRules'])->name('shifts.staffing.index');
        Route::post('staffing-rules', [ShiftSettingController::class, 'storeStaffingRule'])->name('shifts.staffing.store');
        Route::delete('staffing-rules/{rule}', [ShiftSettingController::class, 'destroyStaffingRule'])->whereNumber('rule')->name('shifts.staffing.destroy');
    });
});

/* ---- Yetkili cihaz ucu: oturumsuz, CSRF dışı (kimlik = X-Device-Token) ---- */
Route::post('api/v1/shifts/device-clock', [ClockController::class, 'deviceClock'])->name('shifts.device-clock');
