<?php

namespace App\Modules\Payments\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Payments\Enums\CashMovementType;
use App\Modules\Payments\Models\CashMovement;
use App\Modules\Payments\Models\CashRegister;
use App\Modules\Payments\Models\CashSession;
use App\Modules\Payments\Services\CashSessionService;
use App\Modules\Payments\Support\PaymentPresenter;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Kasa yönetimi API'si (prompt §16). Görüntüleme `cash.view`;
 * açılış/kapanış/sayım/hareket `cash.close`.
 */
class CashController extends Controller
{
    public function __construct(private readonly CashSessionService $cash)
    {
    }

    /* ---------------- Kasalar ---------------- */

    public function registers(Request $request): JsonResponse
    {
        $this->authorize('viewAny', CashRegister::class);

        $registers = CashRegister::query()
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', (int) $request->query('branch_id')))
            ->orderBy('name')
            ->get();

        // Açık oturumlar tek sorguda.
        $openSessions = CashSession::query()
            ->with(['register:id,name', 'openedBy:id,name'])
            ->whereIn('cash_register_id', $registers->pluck('id'))
            ->where('status', 'open')
            ->get()
            ->keyBy('cash_register_id');

        return response()->json([
            'registers' => $registers->map(fn (CashRegister $r): array => PaymentPresenter::register($r, $openSessions->get($r->id)))->values()->all(),
        ]);
    }

    public function storeRegister(Request $request): JsonResponse
    {
        $this->authorize('manage', CashRegister::class);

        $data = $request->validate([
            'branch_id' => ['required', 'integer'],
            'name' => ['required', 'string', 'min:2', 'max:80'],
        ]);

        $branch = Branch::query()->find((int) $data['branch_id']); // scoped

        if ($branch === null) {
            throw ValidationException::withMessages(['branch_id' => ['Şube bulunamadı.']]);
        }

        $exists = CashRegister::query()
            ->where('branch_id', $branch->id)
            ->where('name', $data['name'])
            ->exists();

        if ($exists) {
            throw ValidationException::withMessages(['name' => ['Bu şubede aynı adlı kasa zaten var.']]);
        }

        $register = new CashRegister(['name' => $data['name'], 'is_active' => true]);
        $register->branch_id = $branch->id;
        $register->save();

        return response()->json(['register' => PaymentPresenter::register($register)], 201);
    }

    /* ---------------- Oturumlar ---------------- */

    public function sessions(Request $request): JsonResponse
    {
        $this->authorize('viewAny', CashSession::class);

        $sessions = CashSession::query()
            ->with(['register:id,name', 'openedBy:id,name', 'closedBy:id,name'])
            ->when($request->filled('register_id'), fn ($q) => $q->where('cash_register_id', (int) $request->query('register_id')))
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', (int) $request->query('branch_id')))
            ->when($request->filled('status'), fn ($q) => $q->where('status', (string) $request->query('status')))
            ->orderByDesc('id')
            ->limit(100)
            ->get();

        return response()->json([
            'sessions' => $sessions->map(fn (CashSession $s): array => PaymentPresenter::session($s))->values()->all(),
        ]);
    }

    public function openSession(Request $request): JsonResponse
    {
        $data = $request->validate([
            'cash_register_id' => ['required', 'integer'],
            'opening_float_minor' => ['required', 'integer', 'min:0'],
        ]);

        $register = CashRegister::query()->find((int) $data['cash_register_id']); // scoped

        if ($register === null) {
            throw ValidationException::withMessages(['cash_register_id' => ['Kasa bulunamadı.']]);
        }

        $this->authorize('manage', [CashRegister::class, $register]);

        $session = $this->cash->open($register, (int) $data['opening_float_minor'], $request->user());

        return response()->json(['session' => PaymentPresenter::session($session->load('register:id,name'))], 201);
    }

    /** Oturum detayı + hareketler + canlı X raporu. */
    public function showSession(Request $request, CashSession $session): JsonResponse
    {
        $this->authorize('view', $session);

        $session->load(['register:id,name', 'openedBy:id,name', 'closedBy:id,name']);

        return response()->json([
            'session' => PaymentPresenter::session($session),
            'movements' => $session->movements()->with('user:id,name')->get()
                ->map(fn (CashMovement $m): array => PaymentPresenter::movement($m))->values()->all(),
            'report' => $this->cash->report($session),
        ]);
    }

    public function addMovement(Request $request, CashSession $session): JsonResponse
    {
        $this->authorize('manage', $session);

        $data = $request->validate([
            'type' => ['required', Rule::in(array_map(fn ($t) => $t->value, CashMovementType::manualTypes()))],
            'amount_minor' => ['required', 'integer', 'min:1'],
            'reason' => ['required', 'string', 'min:3', 'max:255'],
        ]);

        $movement = $this->cash->addMovement(
            $session,
            CashMovementType::from($data['type']),
            (int) $data['amount_minor'],
            $data['reason'],
            $request->user(),
        );

        return response()->json(['movement' => PaymentPresenter::movement($movement)], 201);
    }

    public function reverseMovement(Request $request, CashMovement $movement): JsonResponse
    {
        $session = CashSession::query()->findOrFail($movement->cash_session_id); // scoped
        $this->authorize('manage', $session);

        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:255'],
        ]);

        $reversal = $this->cash->reverse($movement, $data['reason'], $request->user());

        return response()->json(['movement' => PaymentPresenter::movement($reversal)], 201);
    }

    public function closeSession(Request $request, CashSession $session): JsonResponse
    {
        $this->authorize('manage', $session);

        $data = $request->validate([
            'counted_cash_minor' => ['required', 'integer', 'min:0'],
            'closing_note' => ['nullable', 'string', 'max:500'],
        ]);

        $closed = $this->cash->close($session, (int) $data['counted_cash_minor'], $data['closing_note'] ?? null, $request->user());

        return response()->json([
            'session' => PaymentPresenter::session($closed->load(['register:id,name'])),
            'report' => $this->cash->report($closed),
        ]);
    }

    /** Z (kapalı: dondurulmuş) / X (açık: canlı) raporu. */
    public function report(Request $request, CashSession $session): JsonResponse
    {
        $this->authorize('view', $session);

        return response()->json([
            'session' => PaymentPresenter::session($session->load(['register:id,name', 'openedBy:id,name', 'closedBy:id,name'])),
            'report' => $this->cash->report($session),
        ]);
    }
}
