<?php

namespace App\Modules\Terminal\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Identity\Services\PinService;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderItem;
use App\Modules\Shifts\Services\TimeClockService;
use App\Modules\Terminal\Support\TerminalOperator;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * TERMINAL AKTİF OPERATÖR ucu (§13, Faz C).
 *
 * Paylaşımlı kasa / sipariş-giriş cihazında "kim çalışıyor"u belirler. Yalnız
 * gizli terminal (is_terminal) oturumu bu uçları çağırabilir — normal oturum
 * bu kavramı kullanmaz (operatör = oturum kullanıcısının kendisidir). Kimlik
 * yalnızca cihaz oturumudur; personel PIN'i ile kendini aktif eder.
 *
 * GÜVENLİK: personel DAİMA terminalin kiracısı + şubesiyle, aktif ve gizli-
 * OLMAYAN (is_terminal=false) olarak doğrulanır. PIN, mevcut PinService::verify
 * ile doğrulanır (bcrypt + deneme sınırı + kilit) — burada personel KİMLİĞİ
 * staff_id ile belli olduğundan identifyByPin'in kiracı-bağlamına ihtiyaç yok
 * (bu uçlar 'tenant' middleware'i DIŞINDA olduğundan bu bilinçli tercih).
 */
class TerminalOperatorController extends Controller
{
    public function __construct(
        private readonly PinService $pins,
        private readonly AuditLogger $audit,
        private readonly TimeClockService $clock,
    ) {
    }

    /**
     * Bu terminal oturumunun ŞUBESİNDE seçilebilir personel (aktif, gizli-
     * olmayan). Kimlik yüzeyi — hassas veri yok; oturum yeter. İsimleri gören
     * kişi zaten cihazın başındadır (PIN olmadan seçim işe yaramaz).
     */
    public function index(Request $request): JsonResponse
    {
        $terminal = $this->terminalUser($request);

        // Şube bilinmiyorsa fail-closed (boş liste).
        if ($terminal->branch_id === null) {
            return response()->json(['operators' => []]);
        }

        $operators = User::query()
            ->where('tenant_id', $terminal->tenant_id)
            ->where('branch_id', $terminal->branch_id)
            ->where('is_active', true)
            ->where('is_terminal', false)
            ->orderBy('name')
            ->get(['id', 'name', 'position']);

        return response()->json([
            'operators' => $operators->map(fn (User $u): array => [
                'id' => (int) $u->getKey(),
                'name' => (string) $u->name,
                'position' => $u->position,
            ])->values()->all(),
        ]);
    }

    /**
     * Aktif operatörü ayarla: {staff_id, pin} → personeli terminalin kiracı+
     * şubesinde doğrula, PIN'i doğrula (yanlış → 422; kilit → 429), oturuma yaz.
     */
    public function store(Request $request): JsonResponse
    {
        $terminal = $this->terminalUser($request);

        $data = $request->validate([
            'staff_id' => ['required', 'integer'],
            'pin' => ['required', 'string', 'min:4', 'max:20'],
        ]);

        // Terminalin kiracısı + şubesi + aktif + gizli-olmayan personel. Şube
        // bilinmiyorsa fail-closed. (User modelinde kiracı global-scope'u YOK →
        // tenant_id açıkça süzülür.)
        $staff = $terminal->branch_id === null ? null : User::query()
            ->where('id', (int) $data['staff_id'])
            ->where('tenant_id', $terminal->tenant_id)
            ->where('branch_id', $terminal->branch_id)
            ->where('is_active', true)
            ->where('is_terminal', false)
            ->first();

        if ($staff === null) {
            throw ValidationException::withMessages([
                'staff_id' => ['Bu personel bu terminalde operatör olamaz.'],
            ])->status(422);
        }

        // PIN doğrula (bcrypt + deneme sınırı + kilit). verify() kilitliyse 429
        // fırlatır; yanlış PIN'de false döner (denemeyi de arttırır).
        if (! $this->pins->verify($staff, (string) $data['pin'])) {
            throw ValidationException::withMessages([
                'pin' => ['PIN doğrulanamadı.'],
            ])->status(422);
        }

        TerminalOperator::set($request, $staff);

        // Girişte OTOMATİK mesai başlat (açık mesaisi yoksa) — personel terminale
        // giriş yapınca clock-in olur. Hata (ör. zaten açık) operatör set'ini
        // ETKİLEMEZ; personel yine de aktif olur.
        try {
            if ($this->clock->openEntryFor($staff) === null) {
                $this->clock->clockIn($staff, [
                    'method' => 'terminal',
                    'ip' => $request->ip(),
                    'branch_id' => $terminal->branch_id,
                ]);
            }
        } catch (\Throwable) {
            // sessiz — mesai elle de açılabilir
        }

        $this->audit->log('terminal.operator_set', $staff, null, [
            'terminal_user_id' => (int) $terminal->getKey(),
            'terminal_station' => $terminal->terminal_station,
        ]);

        return response()->json([
            'operator' => ['id' => (int) $staff->getKey(), 'name' => (string) $staff->name],
        ]);
    }

    /**
     * Aktif operatörün BUGÜNKÜ özeti (sağ-alt personel barı): mesai başlangıcı,
     * mola (adet/dk), açtığı adisyon, eklediği/iptal ettiği ürün. Para GÖSTERMEZ
     * (KDS istasyonları para görmez; tutar yerine adet). Bu uçlar 'tenant'
     * middleware'i dışında olduğundan tenant_id açıkça süzülür + global scope
     * atlanır.
     */
    public function stats(Request $request): JsonResponse
    {
        $terminal = $this->terminalUser($request);
        $operator = TerminalOperator::current($request);

        if ($operator === null) {
            return response()->json(['operator' => null]);
        }

        $today = now()->startOfDay();
        $entry = $this->clock->openEntryFor($operator);

        $breaks = $entry !== null ? $entry->breaks()->get() : collect();
        $breakMinutes = (int) $breaks->sum(fn ($b): int => (int) $b->minutes());

        $tid = (int) $terminal->tenant_id;
        $oid = (int) $operator->getKey();

        $ordersOpened = Order::withoutGlobalScopes()
            ->where('tenant_id', $tid)->where('opened_by_id', $oid)
            ->where('created_at', '>=', $today)->count();

        $itemsAdded = OrderItem::withoutGlobalScopes()
            ->where('tenant_id', $tid)->where('added_by_id', $oid)
            ->where('created_at', '>=', $today)->count();

        $itemsCancelled = OrderItem::withoutGlobalScopes()
            ->where('tenant_id', $tid)->where('cancelled_by_id', $oid)
            ->where('cancelled_at', '>=', $today)->count();

        return response()->json([
            'operator' => ['id' => $oid, 'name' => (string) $operator->name],
            'shift_start' => $entry?->clock_in_at?->toIso8601String(),
            'on_shift' => $entry !== null,
            'break_count' => $breaks->count(),
            'break_minutes' => $breakMinutes,
            'orders_opened' => $ordersOpened,
            'items_added' => $itemsAdded,
            'items_cancelled' => $itemsCancelled,
            'server_time' => now()->toIso8601String(),
        ]);
    }

    /** Aktif operatörü temizle (personel değişimi / vardiya sonu). */
    public function clear(Request $request): JsonResponse
    {
        $terminal = $this->terminalUser($request);

        $previous = TerminalOperator::current($request);

        TerminalOperator::clear($request);

        if ($previous !== null) {
            $this->audit->log('terminal.operator_cleared', $previous, null, [
                'terminal_user_id' => (int) $terminal->getKey(),
            ]);
        }

        return response()->json(['operator' => null]);
    }

    /** Oturum bir gizli terminal kullanıcısı mı? Değilse 403 (kavram yalnız terminale özgü). */
    private function terminalUser(Request $request): User
    {
        $user = $request->user();

        abort_unless($user instanceof User && $user->is_terminal, 403);

        return $user;
    }
}
