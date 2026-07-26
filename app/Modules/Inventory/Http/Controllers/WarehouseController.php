<?php

namespace App\Modules\Inventory\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Inventory\Enums\WarehouseType;
use App\Modules\Inventory\Models\Warehouse;
use App\Modules\Inventory\Support\Qty;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Depo yönetimi (§17.1). */
class WarehouseController extends Controller
{
    use \App\Modules\Tenancy\Concerns\ScopesToBranch;

    public function index(): JsonResponse
    {
        $this->authorize('viewAny', Warehouse::class);

        // ŞUBE KAPSAMI: geçerli şubenin depoları + kiracı-geneli (şubesiz) depolar.
        $branchId = $this->currentBranchId();
        $warehouses = Warehouse::query()
            ->with('branch:id,name')
            ->withCount('levels')
            ->where(fn ($q) => $q->whereNull('branch_id')->orWhere('branch_id', $branchId))
            ->orderBy('name')
            ->get();

        $totals = \App\Modules\Inventory\Models\StockLevel::query()
            ->selectRaw('warehouse_id, SUM(qty_milli) as total')
            ->groupBy('warehouse_id')
            ->pluck('total', 'warehouse_id');

        return response()->json([
            'warehouses' => $warehouses->map(fn (Warehouse $w) => [
                'id' => $w->getKey(),
                'name' => $w->name,
                'code' => $w->code,
                'type' => $w->type,
                'type_label' => $w->typeEnum()->label(),
                'branch_id' => $w->branch_id,
                'branch_name' => $w->branch?->name,
                'is_default' => $w->is_default,
                'is_active' => $w->is_active,
                'item_count' => $w->levels_count,
                'total_qty' => Qty::toDecimalString((int) ($totals[$w->getKey()] ?? 0)),
            ]),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Warehouse::class);

        $data = $this->validated($request);

        $warehouse = new Warehouse($data);
        $warehouse->save();

        $this->syncDefault($warehouse);

        return response()->json(['warehouse' => $warehouse], 201);
    }

    public function update(Request $request, Warehouse $warehouse): JsonResponse
    {
        $this->authorize('update', $warehouse);

        $warehouse->fill($this->validated($request, $warehouse->getKey()));
        $warehouse->save();

        $this->syncDefault($warehouse);

        return response()->json(['warehouse' => $warehouse->fresh()]);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, ?int $ignoreId = null): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:120',
                Rule::unique('inv_warehouses', 'name')
                    ->where('tenant_id', $request->user()->tenant_id)
                    ->ignore($ignoreId),
            ],
            'code' => ['nullable', 'string', 'max:40'],
            'type' => ['required', Rule::in(array_column(WarehouseType::cases(), 'value'))],
            'branch_id' => ['nullable', 'integer',
                Rule::exists('branches', 'id')->where('tenant_id', $request->user()->tenant_id),
            ],
            'is_default' => ['boolean'],
            'is_active' => ['boolean'],
        ]);
    }

    /** Aynı kapsamda (şube ya da genel) tek varsayılan depo kalsın. */
    private function syncDefault(Warehouse $warehouse): void
    {
        if (! $warehouse->is_default) {
            return;
        }

        Warehouse::query()
            ->whereKeyNot($warehouse->getKey())
            ->where(fn ($q) => $warehouse->branch_id === null
                ? $q->whereNull('branch_id')
                : $q->where('branch_id', $warehouse->branch_id))
            ->update(['is_default' => false]);
    }
}
