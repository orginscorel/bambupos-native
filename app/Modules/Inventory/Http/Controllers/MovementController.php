<?php

namespace App\Modules\Inventory\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Models\MovementRequest;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\StockMovement;
use App\Modules\Inventory\Models\Warehouse;
use App\Modules\Inventory\Services\StockLedger;
use App\Modules\Inventory\Support\Qty;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Hareket defteri (§17.4): salt-okunur liste + ONAYLI manuel giriş.
 *
 * Manuel hareket önce MovementRequest olur; `stock.adjust` yetkilisi
 * onaylayınca StockLedger deftere yazar. Defterde güncelleme/silme ucu
 * BİLİNÇLİ olarak YOKTUR (değişmezlik) — düzeltme = ters kayıt.
 */
class MovementController extends Controller
{
    public function __construct(
        private readonly StockLedger $ledger,
        private readonly AuditLogger $audit,
    ) {
    }

    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', StockMovement::class);

        $query = StockMovement::query()
            ->with(['item:id,name,base_unit', 'warehouse:id,name', 'user:id,first_name,last_name'])
            ->orderByDesc('occurred_at')
            ->orderByDesc('id');

        if ($itemId = (int) $request->query('item_id')) {
            $query->where('item_id', $itemId);
        }

        if ($warehouseId = (int) $request->query('warehouse_id')) {
            $query->where('warehouse_id', $warehouseId);
        }

        if ($type = $request->query('type')) {
            $query->where('type', (string) $type);
        }

        if ($from = $request->query('from')) {
            $query->where('occurred_at', '>=', $from.' 00:00:00');
        }

        if ($to = $request->query('to')) {
            $query->where('occurred_at', '<=', $to.' 23:59:59');
        }

        $page = $query->paginate(50);

        return response()->json([
            'movements' => collect($page->items())->map(fn (StockMovement $m) => $this->present($m)),
            'total' => $page->total(),
            'current_page' => $page->currentPage(),
            'last_page' => $page->lastPage(),
        ]);
    }

    /** Manuel hareket İSTEĞİ oluştur (herkes değil: stock.view yetmez, adjust da isteyebilir onaysız mı? — istek herkese açık, DEFTERE yazan onaydır). */
    public function store(Request $request): JsonResponse
    {
        $this->authorize('viewAny', StockMovement::class);

        $tenantId = $request->user()->tenant_id;

        $manualTypes = array_values(array_filter(
            array_column(MovementType::cases(), 'value'),
            fn (string $v) => MovementType::from($v)->isManual(),
        ));

        $data = $request->validate([
            'warehouse_id' => ['required', 'integer', Rule::exists('inv_warehouses', 'id')->where('tenant_id', $tenantId)],
            'item_id' => ['required', 'integer', Rule::exists('inv_items', 'id')->where('tenant_id', $tenantId)],
            'type' => ['required', Rule::in($manualTypes)],
            'qty' => ['required', 'string'],
            'unit_cost_minor' => ['nullable', 'integer', 'min:0'],
            'lot_no' => ['nullable', 'string', 'max:60'],
            'expires_at' => ['nullable', 'date'],
            'description' => ['required', 'string', 'max:500'], // gerekçesiz manuel hareket yok
        ]);

        $qtyMilli = Qty::parseToMilli($data['qty']);

        if ($qtyMilli === null || $qtyMilli === 0) {
            throw ValidationException::withMessages(['qty' => ['Geçerli bir miktar girin.']]);
        }

        $type = MovementType::from($data['type']);

        if ($type->direction() === -1) {
            $qtyMilli = -abs($qtyMilli);
        } elseif ($type->direction() === 1) {
            $qtyMilli = abs($qtyMilli);
        }

        $req = new MovementRequest([
            'warehouse_id' => (int) $data['warehouse_id'],
            'item_id' => (int) $data['item_id'],
            'type' => $type->value,
            'qty_milli' => $qtyMilli,
            'unit_cost_minor' => $data['unit_cost_minor'] ?? null,
            'lot_no' => $data['lot_no'] ?? null,
            'expires_at' => $data['expires_at'] ?? null,
            'description' => $data['description'],
        ]);
        $req->status = MovementRequest::STATUS_PENDING;
        $req->requested_by_id = $request->user()->getKey();
        $req->save();

        // İsteyen zaten stock.adjust yetkilisiyse bekletmeden onayla.
        if ($request->user()->hasPermission('stock.adjust')) {
            return $this->approve($request, $req);
        }

        return response()->json(['request' => $req], 201);
    }

    public function requests(Request $request): JsonResponse
    {
        $this->authorize('viewAny', StockMovement::class);

        $requests = MovementRequest::query()
            ->with(['item:id,name,base_unit', 'warehouse:id,name', 'requestedBy:id,first_name,last_name'])
            ->where('status', MovementRequest::STATUS_PENDING)
            ->orderByDesc('id')
            ->get();

        return response()->json([
            'requests' => $requests->map(fn (MovementRequest $r) => [
                'id' => $r->getKey(),
                'item_name' => $r->item?->name,
                'warehouse_name' => $r->warehouse?->name,
                'type' => $r->type,
                'type_label' => $r->typeEnum()->label(),
                'qty' => Qty::toDecimalString((int) $r->qty_milli),
                'unit' => $r->item?->base_unit,
                'description' => $r->description,
                'requested_by' => trim(($r->requestedBy?->first_name ?? '').' '.($r->requestedBy?->last_name ?? '')),
                'created_at' => $r->created_at?->toIso8601String(),
            ]),
        ]);
    }

    /** Onay: istek deftere yazılır (stock.adjust). */
    public function approve(Request $request, MovementRequest $movementRequest): JsonResponse
    {
        $this->authorize('adjust', $movementRequest);

        if ($movementRequest->status !== MovementRequest::STATUS_PENDING) {
            throw ValidationException::withMessages(['request' => ['İstek zaten sonuçlanmış.']]);
        }

        $item = StockItem::query()->findOrFail($movementRequest->item_id);
        $warehouse = Warehouse::query()->findOrFail($movementRequest->warehouse_id);

        $movement = $this->ledger->record([
            'type' => $movementRequest->typeEnum(),
            'item' => $item,
            'warehouse' => $warehouse,
            'qty_milli' => (int) $movementRequest->qty_milli,
            'tenant_id' => (int) $movementRequest->tenant_id,
            'unit_cost_minor' => $movementRequest->unit_cost_minor,
            'lot_no' => $movementRequest->lot_no,
            'expires_at' => $movementRequest->expires_at?->toDateString(),
            'ref_type' => 'movement_request',
            'ref_id' => $movementRequest->getKey(),
            'description' => $movementRequest->description,
            'user' => $movementRequest->requestedBy ?? $request->user(),
            'approved_by' => $request->user(),
        ]);

        $movementRequest->status = MovementRequest::STATUS_APPROVED;
        $movementRequest->decided_by_id = $request->user()->getKey();
        $movementRequest->decided_at = now();
        $movementRequest->movement_id = $movement->getKey();
        $movementRequest->save();

        $this->audit->log('inventory.movement_approved', $movement, null, [
            'request_id' => $movementRequest->getKey(),
            'performed_by' => $request->user()->getKey(),
        ]);

        return response()->json(['movement' => $this->present($movement->load(['item:id,name,base_unit', 'warehouse:id,name']))], 201);
    }

    public function reject(Request $request, MovementRequest $movementRequest): JsonResponse
    {
        $this->authorize('adjust', $movementRequest);

        if ($movementRequest->status !== MovementRequest::STATUS_PENDING) {
            throw ValidationException::withMessages(['request' => ['İstek zaten sonuçlanmış.']]);
        }

        $movementRequest->status = MovementRequest::STATUS_REJECTED;
        $movementRequest->decided_by_id = $request->user()->getKey();
        $movementRequest->decided_at = now();
        $movementRequest->save();

        return response()->json(['request' => $movementRequest]);
    }

    /** Depolar arası transfer (stock.adjust — anında, çift kayıt). */
    public function transfer(Request $request): JsonResponse
    {
        $this->authorize('adjust', StockMovement::class);

        $tenantId = $request->user()->tenant_id;

        $data = $request->validate([
            'item_id' => ['required', 'integer', Rule::exists('inv_items', 'id')->where('tenant_id', $tenantId)],
            'from_warehouse_id' => ['required', 'integer', Rule::exists('inv_warehouses', 'id')->where('tenant_id', $tenantId)],
            'to_warehouse_id' => ['required', 'integer', 'different:from_warehouse_id', Rule::exists('inv_warehouses', 'id')->where('tenant_id', $tenantId)],
            'qty' => ['required', 'string'],
            'description' => ['nullable', 'string', 'max:500'],
        ]);

        $qtyMilli = Qty::parseToMilli($data['qty']);

        if ($qtyMilli === null || $qtyMilli <= 0) {
            throw ValidationException::withMessages(['qty' => ['Geçerli bir miktar girin.']]);
        }

        [$out, $in] = $this->ledger->transfer(
            StockItem::query()->findOrFail((int) $data['item_id']),
            Warehouse::query()->findOrFail((int) $data['from_warehouse_id']),
            Warehouse::query()->findOrFail((int) $data['to_warehouse_id']),
            $qtyMilli,
            $request->user(),
            $data['description'] ?? null,
        );

        return response()->json(['out' => $this->present($out), 'in' => $this->present($in)], 201);
    }

    /** @return array<string, mixed> */
    private function present(StockMovement $m): array
    {
        return [
            'id' => $m->getKey(),
            'type' => $m->type,
            'type_label' => $m->typeEnum()->label(),
            'type_variant' => $m->typeEnum()->variant(),
            'item_id' => $m->item_id,
            'item_name' => $m->item?->name,
            'warehouse_name' => $m->warehouse?->name,
            'qty_milli' => (int) $m->qty_milli,
            'qty' => Qty::toDecimalString((int) $m->qty_milli),
            'unit' => $m->unit_label,
            'unit_cost_minor' => $m->unit_cost_minor,
            'total_cost_minor' => $m->total_cost_minor,
            'lot_no' => $m->lot_no,
            'expires_at' => $m->expires_at?->toDateString(),
            'ref_type' => $m->ref_type,
            'ref_id' => $m->ref_id,
            'description' => $m->description,
            'user_name' => $m->user !== null ? trim($m->user->first_name.' '.$m->user->last_name) : null,
            'occurred_at' => $m->occurred_at?->toIso8601String(),
        ];
    }
}
