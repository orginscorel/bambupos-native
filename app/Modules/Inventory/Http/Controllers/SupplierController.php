<?php

namespace App\Modules\Inventory\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Inventory\Models\Supplier;
use App\Modules\Inventory\Models\SupplierPrice;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Tedarikçi yönetimi + fiyat geçmişi (§17.6). */
class SupplierController extends Controller
{
    public function index(): JsonResponse
    {
        $this->authorize('viewAny', Supplier::class);

        return response()->json([
            'suppliers' => Supplier::query()->orderBy('name')->get(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Supplier::class);

        $supplier = new Supplier($this->validated($request));
        $supplier->save();

        return response()->json(['supplier' => $supplier], 201);
    }

    public function update(Request $request, Supplier $supplier): JsonResponse
    {
        $this->authorize('update', $supplier);

        $supplier->fill($this->validated($request, $supplier->getKey()));
        $supplier->save();

        return response()->json(['supplier' => $supplier->fresh()]);
    }

    /** Fiyat geçmişi (kalem bazlı, mal kabullerinden). */
    public function prices(Supplier $supplier): JsonResponse
    {
        $this->authorize('view', $supplier);

        return response()->json([
            'prices' => SupplierPrice::query()
                ->with('item:id,name,base_unit')
                ->where('supplier_id', $supplier->getKey())
                ->orderByDesc('recorded_at')
                ->limit(100)
                ->get()
                ->map(fn (SupplierPrice $p) => [
                    'item_name' => $p->item?->name,
                    'unit' => $p->item?->base_unit,
                    'unit_price_minor' => (int) $p->unit_price_minor,
                    'recorded_at' => $p->recorded_at?->toIso8601String(),
                ]),
        ]);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, ?int $ignoreId = null): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:160',
                Rule::unique('inv_suppliers', 'name')
                    ->where('tenant_id', $request->user()->tenant_id)
                    ->ignore($ignoreId),
            ],
            'contact_name' => ['nullable', 'string', 'max:120'],
            'phone' => ['nullable', 'string', 'max:40'],
            'email' => ['nullable', 'email', 'max:160'],
            'tax_no' => ['nullable', 'string', 'max:40'],
            'address' => ['nullable', 'string', 'max:500'],
            'payment_term_days' => ['nullable', 'integer', 'min:0', 'max:365'],
            'note' => ['nullable', 'string', 'max:500'],
            'is_active' => ['boolean'],
        ]);
    }
}
