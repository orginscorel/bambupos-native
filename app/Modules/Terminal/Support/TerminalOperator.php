<?php

namespace App\Modules\Terminal\Support;

use App\Modules\Identity\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * TERMINAL AKTİF OPERATÖR — paylaşımlı cihazda "kim çalışıyor" (§13, Faz C).
 *
 * SORUN: Sabit kasa / sipariş-giriş terminalleri PAYLAŞILIR. Cihaz GİZLİ,
 * istasyona-atanmış bir kullanıcıyla (is_terminal) çalışır; bu yüzden bu
 * cihazdan açılan adisyon / alınan ödeme gizli kullanıcıya atfediliyor →
 * "kim girdi" belli olmuyordu. ÇÖZÜM (kafe POS standardı): personel PIN'iyle
 * kendini "aktif operatör" yapar; açtığı adisyon / aldığı ödeme ONA atfedilir.
 *
 * Aktif operatör oturum (session) düzeyinde tutulur — cihaza değil, o cihazın
 * TARAYICI OTURUMUNA bağlıdır. Yalnız is_terminal oturumda anlamlıdır. Rutin
 * işlemler (adisyon aç / ödeme al) idle-timeout içinde operatörü tazeler
 * (touch); IDLE_MINUTES boyunca işlem yoksa operatör düşer (yeniden PIN gerekir)
 * — bir personel kalkıp gidince başkasının onun adına işlem yapması engellenir.
 *
 * GÜVENLİK: operatör DAİMA terminalin kiracısı + şubesiyle, aktif ve gizli-
 * OLMAYAN (is_terminal=false) bir kullanıcı olarak yeniden doğrulanır; session'da
 * yalnız id tutulur, kimlik her okuyuşta DB'den tazelenir (bayat/pasif/şube-dışı
 * operatör asla çözülmez). Bu sınıf hassas-eylem PIN kapısını (TerminalPinGate)
 * DEĞİŞTİRMEZ — void/iade/iptal/ikram yine her seferinde PIN ister.
 */
final class TerminalOperator
{
    /** Session anahtarları — yalnız operatör KİMLİĞİ + zaman damgaları tutulur. */
    private const SESSION_ID = 'terminal.operator_id';

    private const SESSION_SET_AT = 'terminal.operator_set_at';

    private const SESSION_ACTIVE_AT = 'terminal.operator_active_at';

    /** İşlemsiz geçen bu süreden sonra operatör düşer (yeniden PIN gerekir). */
    public const IDLE_MINUTES = 10;

    /** Aktif operatörü oturuma yazar (PIN doğrulaması ÇAĞIRANDA yapılmış olmalı). */
    public static function set(Request $request, User $operator): void
    {
        $now = now();
        $request->session()->put(self::SESSION_ID, (int) $operator->getKey());
        $request->session()->put(self::SESSION_SET_AT, $now->toIso8601String());
        $request->session()->put(self::SESSION_ACTIVE_AT, $now->toIso8601String());
    }

    /** Aktif operatörü temizler (personel değişimi / vardiya sonu). */
    public static function clear(Request $request): void
    {
        $request->session()->forget([self::SESSION_ID, self::SESSION_SET_AT, self::SESSION_ACTIVE_AT]);
    }

    /**
     * Geçerli aktif operatör (yoksa null). YALNIZ is_terminal oturumda çözülür;
     * operatör hâlâ aktif + aynı kiracı/şube + gizli-olmayan olmalı; idle-timeout
     * geçtiyse null (ve session temizlenir → kendini iyileştirir). YAN ETKİSİ
     * sadece bayat/geçersiz durumu temizlemektir; geçerli okuma "touch" ETMEZ
     * (tazeleme yalnız gerçek atıflı eylemde — bkz. touch()).
     */
    public static function current(Request $request): ?User
    {
        $terminal = $request->user();

        // Operatör kavramı yalnız gizli terminal oturumunda anlamlıdır.
        if (! $terminal instanceof User || ! $terminal->is_terminal) {
            return null;
        }

        $id = (int) $request->session()->get(self::SESSION_ID, 0);

        if ($id <= 0) {
            return null;
        }

        // Idle-timeout: son eylemden IDLE_MINUTES geçtiyse operatör düşer.
        $activeAt = $request->session()->get(self::SESSION_ACTIVE_AT);

        if ($activeAt !== null && Carbon::parse((string) $activeAt)->addMinutes(self::IDLE_MINUTES)->isPast()) {
            self::clear($request);

            return null;
        }

        // Terminalin şubesi bilinmiyorsa fail-closed (operatör şubeye kilitlenir).
        if ($terminal->branch_id === null) {
            return null;
        }

        // Kimliği DB'den TAZELE: aynı kiracı + aynı şube + aktif + gizli-olmayan.
        // (User modelinde kiracı global-scope'u YOK → tenant_id açıkça süzülür.)
        $operator = User::query()
            ->where('id', $id)
            ->where('tenant_id', $terminal->tenant_id)
            ->where('branch_id', $terminal->branch_id)
            ->where('is_active', true)
            ->where('is_terminal', false)
            ->first();

        if ($operator === null) {
            // Operatör pasifleştirilmiş / şubesi değişmiş / silinmiş → düşür.
            self::clear($request);

            return null;
        }

        return $operator;
    }

    /**
     * Gerçek atıflı eylem (adisyon aç / ödeme al) sonrası operatörü TAZELE —
     * böylece cihaz kullanılıyorken idle-timeout devreye girmez; kullanım durunca
     * IDLE_MINUTES sonra düşer. Operatör yoksa hiçbir şey yapmaz.
     */
    public static function touch(Request $request): void
    {
        if ((int) $request->session()->get(self::SESSION_ID, 0) > 0) {
            $request->session()->put(self::SESSION_ACTIVE_AT, now()->toIso8601String());
        }
    }

    /**
     * Inertia paylaşımı / API yanıtı için hafif özet (yoksa null).
     *
     * @return array{id: int, name: string}|null
     */
    public static function summary(Request $request): ?array
    {
        $operator = self::current($request);

        if ($operator === null) {
            return null;
        }

        return ['id' => (int) $operator->getKey(), 'name' => (string) $operator->name];
    }
}
