<?php

declare(strict_types=1);

namespace App\Modules\Commission\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Commission\Models\CommissionScheme;
use App\Modules\Commission\Services\CommissionService;
use App\Modules\Tenancy\Concerns\ScopesToBranch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/**
 * Panel (yönetici) PRİM API'si. İzin: `commission.view` rapor okuma,
 * `commission.manage` prim şeması yaz/sil. Şemalar tenant-scope'ludur
 * (BelongsToTenant); rapordaki personel BranchContext'e göre süzülebilir.
 */
class CommissionController extends Controller
{
    use ScopesToBranch;

    public function __construct(
        private readonly CommissionService $service,
    ) {
    }

    /** Şema listesi. İzin: commission.view VEYA commission.manage. */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        abort_unless(
            $user->hasPermission('commission.view') || $user->hasPermission('commission.manage'),
            403
        );

        $schemes = CommissionScheme::query()
            ->orderByRaw('position IS NULL')
            ->orderBy('id')
            ->get()
            ->map(fn (CommissionScheme $s): array => $this->toDto($s))
            ->all();

        return response()->json(['schemes' => $schemes]);
    }

    /** Şema oluştur. İzin: commission.manage. */
    public function store(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('commission.manage'), 403);

        $data = $this->validateScheme($request);

        $scheme = CommissionScheme::create($data);

        return response()->json(['scheme' => $this->toDto($scheme)], 201);
    }

    /** Şema güncelle. İzin: commission.manage. */
    public function update(Request $request, CommissionScheme $scheme): JsonResponse
    {
        abort_unless($request->user()->hasPermission('commission.manage'), 403);

        $data = $this->validateScheme($request, partial: true);

        $scheme->update($data);

        return response()->json(['scheme' => $this->toDto($scheme->fresh())]);
    }

    /** Şema sil. İzin: commission.manage. */
    public function destroy(Request $request, CommissionScheme $scheme): JsonResponse
    {
        abort_unless($request->user()->hasPermission('commission.manage'), 403);

        $scheme->delete();

        return response()->json(null, 204);
    }

    /** Prim raporu. İzin: commission.view. */
    public function report(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('commission.view'), 403);

        $data = $request->validate([
            'from' => ['required', 'date'],
            'to' => ['required', 'date', 'after_or_equal:from'],
        ]);

        $tz = config('app.timezone');
        $from = Carbon::parse($data['from'], $tz)->startOfDay();
        // "to" günü DAHİL: gün sonuna kadar → ertesi günün başlangıcı (dışlayıcı üst sınır).
        $to = Carbon::parse($data['to'], $tz)->startOfDay()->addDay();

        return response()->json(
            $this->service->report($from, $to, $this->currentBranchId())
        );
    }

    /**
     * Şema doğrulama. Oluşturmada tüm alanlar zorunlu; güncellemede kısmi.
     *
     * @return array<string, mixed>
     */
    private function validateScheme(Request $request, bool $partial = false): array
    {
        $req = $partial ? 'sometimes' : 'required';

        return $request->validate([
            'name' => [$req, 'string', 'max:100'],
            'basis' => [$req, Rule::in(['percent_sales', 'per_order', 'target_bonus'])],
            'rate_bps' => ['nullable', 'integer', 'min:0', 'max:100000'],
            'per_order_minor' => ['nullable', 'integer', 'min:0'],
            'target_minor' => ['nullable', 'integer', 'min:0'],
            'bonus_minor' => ['nullable', 'integer', 'min:0'],
            'position' => ['nullable', 'string', 'max:80'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    private function toDto(CommissionScheme $scheme): array
    {
        return [
            'id' => (int) $scheme->getKey(),
            'name' => $scheme->name,
            'basis' => $scheme->basis,
            'rate_bps' => (int) $scheme->rate_bps,
            'per_order_minor' => (int) $scheme->per_order_minor,
            'target_minor' => (int) $scheme->target_minor,
            'bonus_minor' => (int) $scheme->bonus_minor,
            'position' => $scheme->position,
            'is_active' => (bool) $scheme->is_active,
        ];
    }
}
