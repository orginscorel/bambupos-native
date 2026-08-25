<?php

namespace App\Modules\Terminal\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Shifts\Services\TimeClockService;
use App\Modules\Terminal\Support\TerminalOperator;
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
     * ÖDEME ALMA aktörü (§13, Faz C). Terminal oturumda:
     *  - PIN GÖNDERİLMEDİ → aktif operatöre atfedilir (rutin; operatör yoksa 422).
     *    Operatörün ilgili izni (payments.take) yeniden doğrulanır.
     *  - PIN GÖNDERİLDİ → mevcut PIN kapısı (actor()) çalışır — geriye dönük
     *    uyumluluk + hassas-eylem akışı BOZULMAZ.
     *  - NORMAL oturum → actor() (policy + oturum kullanıcısı; mevcut davranış).
     *
     * @param  Closure():void  $authorize
     */
    public function actorOrOperator(Request $request, string $permission, string $action, Closure $authorize): User
    {
        $user = $request->user();

        if ($user instanceof User && $user->is_terminal && ! $request->filled('pin')) {
            $operator = $this->requireOperator($request);

            if (! $operator->hasPermission($permission)) {
                $this->audit->log('terminal.operator_denied', $operator, null, [
                    'action' => $action,
                    'permission' => $permission,
                    'terminal_user_id' => (int) $user->getKey(),
                ]);

                throw ValidationException::withMessages([
                    'operator' => ['Aktif personelin bu işlem için yetkisi yok.'],
                ])->status(422);
            }

            TerminalOperator::touch($request); // yetkili gerçek eylem → idle sayacını tazele

            $this->audit->log('terminal.operator_action', $operator, null, [
                'action' => $action,
                'permission' => $permission,
                'terminal_user_id' => (int) $user->getKey(),
                'terminal_station' => $user->terminal_station,
            ]);

            return $operator;
        }

        return $this->actor($request, $permission, $action, $authorize);
    }

    /**
     * Aktif operatörü döndür ya da 422 fırlat. (Operatör kimliği current()
     * içinde kiracı+şube+aktif+gizli-değil olarak DB'den yeniden doğrulanır;
     * idle-timeout geçmişse null → 422.) Tazeleme (touch) çağırana bırakılır:
     * yalnız YETKİLİ gerçek eylemde idle sayacı yenilenir.
     */
    private function requireOperator(Request $request): User
    {
        $operator = TerminalOperator::current($request);

        if ($operator === null) {
            throw ValidationException::withMessages([
                'operator' => ['Önce personel seçin.'],
            ])->status(422);
        }

        return $operator;
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
