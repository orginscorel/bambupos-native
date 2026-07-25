<?php

namespace App\Modules\Inventory\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Inventory\Models\StockCount;
use App\Modules\Inventory\Services\CountService;
use App\Modules\Inventory\Support\Qty;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Sayım ekranı (§17). KÖR SAYIM: taslak aşamasında beklenen miktar
 * yanıtlara HİÇ konmaz — sayan kişi ezberden yazamaz; fark gönderimde
 * hesaplanır, onay stock.adjust ister.
 */
class CountController extends Controller
{
    public function __construct(private readonly CountService $counts)
    {
    }

    public function index(): JsonResponse
    {
        $this->authorize('viewAny', StockCount::class);

        return response()->json([
            'counts' => StockCount::query()
                ->with('warehouse:id,name')
                ->withCount('lines')
                ->orderByDesc('id')
                ->limit(50)
                ->get()
                ->map(fn (StockCount $c) => [
                    'id' => $c->getKey(),
                    'warehouse_name' => $c->warehouse?->name,
                    'status' => $c->status,
                    'is_blind' => $c->is_blind,
                    'note' => $c->note,
                    'line_count' => $c->lines_count,
                    'created_at' => $c->created_at?->toIso8601String(),
                    'submitted_at' => $c->submitted_at?->toIso8601String(),
                    'approved_at' => $c->approved_at?->toIso8601String(),
                ]),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', StockCount::class);

        $data = $request->validate([
            'warehouse_id' => ['required', 'integer',
                Rule::exists('inv_warehouses', 'id')->where('tenant_id', $request->user()->tenant_id),
            ],
            'is_blind' => ['boolean'],
            'note' => ['nullable', 'string', 'max:500'],
        ]);

        $count = new StockCount([
            'warehouse_id' => (int) $data['warehouse_id'],
            'is_blind' => $data['is_blind'] ?? true,
            'note' => $data['note'] ?? null,
        ]);
        $count->status = StockCount::STATUS_DRAFT;
        $count->created_by_id = $request->user()->getKey();
        $count->save();

        return response()->json(['count' => $count], 201);
    }

    public function show(StockCount $count): JsonResponse
    {
        $this->authorize('view', $count);

        return response()->json(['count' => $this->present($count->load(['lines.item:id,name,base_unit,sub_unit,sub_unit_factor', 'warehouse:id,name']))]);
    }

    public function saveLines(Request $request, StockCount $count): JsonResponse
    {
        $this->authorize('update', $count);

        $data = $request->validate([
            'lines' => ['required', 'array', 'min:1'],
            'lines.*.item_id' => ['required', 'integer'],
            'lines.*.counted_qty' => ['nullable', 'string'],
        ]);

        $lines = array_map(function (array $l): array {
            $milli = $l['counted_qty'] !== null && $l['counted_qty'] !== ''
                ? Qty::parseToMilli($l['counted_qty'])
                : null;

            if (($l['counted_qty'] ?? null) !== null && $l['counted_qty'] !== '' && $milli === null) {
                throw ValidationException::withMessages(['lines' => ['Geçersiz miktar girdisi.']]);
            }

            return ['item_id' => (int) $l['item_id'], 'counted_qty_milli' => $milli];
        }, $data['lines']);

        $count = $this->counts->saveLines($count, $lines);

        return response()->json(['count' => $this->present($count->load('warehouse:id,name'))]);
    }

    public function submit(Request $request, StockCount $count): JsonResponse
    {
        $this->authorize('update', $count);

        $count = $this->counts->submit($count, $request->user());

        return response()->json(['count' => $this->present($count->load('warehouse:id,name'))]);
    }

    /** Onay farkları deftere işler — stock.adjust. */
    public function approve(Request $request, StockCount $count): JsonResponse
    {
        $this->authorize('adjust', $count);

        $count = $this->counts->approve($count, $request->user());

        return response()->json(['count' => $this->present($count->load('warehouse:id,name'))]);
    }

    public function cancel(StockCount $count): JsonResponse
    {
        $this->authorize('update', $count);

        if ($count->status === StockCount::STATUS_APPROVED) {
            throw ValidationException::withMessages(['count' => ['Onaylanmış sayım iptal edilemez.']]);
        }

        $count->status = StockCount::STATUS_CANCELLED;
        $count->save();

        return response()->json(['count' => $count]);
    }

    /** @return array<string, mixed> KÖR kural: taslakta beklenen/fark GÖNDERİLMEZ. */
    private function present(StockCount $count): array
    {
        $revealing = ! $count->is_blind || $count->status !== StockCount::STATUS_DRAFT;

        return [
            'id' => $count->getKey(),
            'warehouse_id' => $count->warehouse_id,
            'warehouse_name' => $count->warehouse?->name,
            'status' => $count->status,
            'is_blind' => $count->is_blind,
            'note' => $count->note,
            'submitted_at' => $count->submitted_at?->toIso8601String(),
            'approved_at' => $count->approved_at?->toIso8601String(),
            'lines' => $count->lines->map(fn ($l) => [
                'item_id' => $l->item_id,
                'item_name' => $l->item?->name,
                'unit' => $l->item?->base_unit,
                'counted_qty' => $l->counted_qty_milli !== null ? Qty::toDecimalString((int) $l->counted_qty_milli) : null,
                'expected_qty' => $revealing && $l->expected_qty_milli !== null ? Qty::toDecimalString((int) $l->expected_qty_milli) : null,
                'diff_qty' => $revealing && $l->diff_qty_milli !== null ? Qty::toDecimalString((int) $l->diff_qty_milli) : null,
                'diff_milli' => $revealing ? $l->diff_qty_milli : null,
            ])->values(),
        ];
    }
}
