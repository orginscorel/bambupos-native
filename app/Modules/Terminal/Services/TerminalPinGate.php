<?php

namespace App\Modules\Terminal\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Shifts\Services\TimeClockService;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * TERMINAL PIN KAPISI — hassas eylemlerde personel atfı (§13, Faz B).
 *
 * Kasa / sipariş-giriş terminalleri cihaza-kilitli GİZLİ bir kullanıcıyla
 * çalışır (kişisel değil). Para eylemleri (ödeme al, adisyon iptali, iade,
 * ikram) bu gizli kullanıcıya değil, işlemi yapan GERÇEK personele atfedilmeli.
 *
 * Bu kapı yalnız is_terminal oturumda devreye girer:
 *  1) İstek gövdesinden `pin` (+ belirsizse `staff_code`) alınır.
 *  2) Mevcut PIN altyapısı (Shifts/TimeClockService::identifyByPin) ile
 *     personel çözülür — kiracı bağlamı içinde, PIN kilidi + belirsizlik
 *     kuralları AYNEN uygulanır.
 *  3) Personelin eyleme yetkisi doğrulanır (hasPermission). Yoksa → 422.
 *  4) Eylem O personele atfedilir (dönen User aktör olarak kullanılır) ve
 *     audit'e yazılır.
 *
 * NORMAL (terminal olmayan) oturumda ÇAĞRILMAZ → PIN istenmez; mevcut davranış
 * (policy + oturum kullanıcısı) korunur (bkz. TerminalPinGate::actor()).
 */
class TerminalPinGate
{
    public function __construct(
        private readonly TimeClockService $clock,
        private readonly AuditLogger $audit,
    ) {
    }

    /**
     * Hassas eylemde aktörü çöz.
     *  - NORMAL oturum: $authorize() (policy) çalışır, aktör = oturum kullanıcısı.
     *  - TERMINAL oturum: PIN'den personel çözülür + yetkisi doğrulanır, aktör =
     *    personel (eylem O'na atfedilir). PIN yok/yanlış/yetkisiz → 422/429.
     *
     * @param  Closure():void  $authorize  normal oturumda çalıştırılacak policy kontrolü
     */
    public function actor(Request $request, string $permission, string $action, Closure $authorize): User
    {
        $user = $request->user();

        if ($user instanceof User && $user->is_terminal) {
            return $this->resolveByPin($request, $permission, $action, $user);
        }

        $authorize();

        /** @var User $user */
        return $user;
    }

    /**
     * PIN'den personeli çöz, yetkisini doğrula, audit'e yaz. Terminal oturumuna
     * özeldir; başarısızlıkta ValidationException (422/429) fırlatır → eylem YOK.
     */
    private function resolveByPin(Request $request, string $permission, string $action, User $terminalUser): User
    {
        $data = $request->validate([
            'pin' => ['required', 'string', 'min:4', 'max:20'],
            'staff_code' => ['nullable', 'string', 'max:40'],
        ]);

        // identifyByPin: kiracı-içinde çözer; PIN kilidi + belirsiz eşleşme
        // (staff_code) kurallarını uygular; başarısızlıkta ValidationException.
        $staff = $this->clock->identifyByPin($data['pin'], $data['staff_code'] ?? null);

        if (! $staff->hasPermission($permission)) {
            $this->audit->log('terminal.pin_denied', $staff, null, [
                'action' => $action,
                'permission' => $permission,
                'terminal_user_id' => (int) $terminalUser->getKey(),
            ]);

            throw ValidationException::withMessages([
                'pin' => ['Bu personelin bu işlem için yetkisi yok.'],
            ])->status(422);
        }

        $this->audit->log('terminal.pin_action', $staff, null, [
            'action' => $action,
            'permission' => $permission,
            'terminal_user_id' => (int) $terminalUser->getKey(),
            'terminal_station' => $terminalUser->terminal_station,
        ]);

        return $staff;
    }
}
