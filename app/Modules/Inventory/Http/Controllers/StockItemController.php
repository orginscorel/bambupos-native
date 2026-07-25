<?php

namespace App\Modules\Inventory\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Inventory\Models\ItemCategory;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\StockLevel;
use App\Modules\Inventory\Support\Qty;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Stok kartları (§17.2) + kategoriler. Miktar girişleri ana birim ondalık; milli'ye çevrilir. */
class StockItemController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', StockItem::class);

        $query = StockItem::query()
            ->with(['category:id,name', 'defaultSupplier:id,name'])
            ->orderBy('name');

        if ($search = trim((string) $request->query('q'))) {
            $query->where(fn ($q) => $q
                ->where('name', 'like', "%{$search}%")
                ->orWhere('code', 'like', "%{$search}%")
                ->orWhere('barcode', 'like', "%{$search}%"));
        }

        if ($categoryId = (int) $request->query('category_id')) {
            $query->where('category_id', $categoryId);
        }

        if ($request->boolean('only_active', true)) {
            $query->where('is_active', true);
        }

        $items = $query->get();

        $levels = StockLevel::query()
            ->whereIn('item_id', $items->pluck('id'))
            ->get()
            ->groupBy('item_id');

        $rows = $items->map(function (StockItem $item) use ($levels) {
            $itemLevels = $levels->get($item->getKey(), collect());
            $onHand = (int) $itemLevels->sum('qty_milli');

            $status = 'ok';
            if ($onHand < 0) {
                $status = 'negative';
            } elseif ((int) $item->critical_qty_milli > 0 && $onHand <= (int) $item->critical_qty_milli) {
                $status = 'critical';
            } elseif ((int) $item->min_qty_milli > 0 && $onHand <= (int) $item->min_qty_milli) {
                $status = 'low';
            }

            return [
                'id' => $item->getKey(),
                'name' => $item->name,
                'code' => $item->code,
                'barcode' => $item->barcode,
                'category_id' => $item->category_id,
                'category_name' => $item->category?->name,
                'base_unit' => $item->base_unit,
                'sub_unit' => $item->sub_unit,
                'sub_unit_factor' => $item->sub_unit_factor,
                'on_hand_milli' => $onHand,
                'on_hand' => Qty::toDecimalString($onHand),
                'min_qty' => Qty::toDecimalString((int) $item->min_qty_milli),
                'critical_qty' => Qty::toDecimalString((int) $item->critical_qty_milli),
                'max_qty' => $item->max_qty_milli !== null ? Qty::toDecimalString((int) $item->max_qty_milli) : null,
                'avg_cost_minor' => (int) $item->avg_cost_minor,
                'last_cost_minor' => $item->last_cost_minor,
                'last_purchase_at' => $item->last_purchase_at?->toIso8601String(),
                'default_supplier_id' => $item->default_supplier_id,
                'default_supplier_name' => $item->defaultSupplier?->name,
                'track_expiry' => $item->track_expiry,
                'track_lot' => $item->track_lot,
                'shelf_location' => $item->shelf_location,
                'tax_rate' => (float) $item->tax_rate,
                'is_semi_finished' => $item->is_semi_finished,
                'is_active' => $item->is_active,
                'status' => $status,
                'levels' => $itemLevels->map(fn (StockLevel $l) => [
                    'warehouse_id' => $l->warehouse_id,
                    'qty_milli' => (int) $l->qty_milli,
                    'qty' => Qty::toDecimalString((int) $l->qty_milli),
                ])->values(),
            ];
        });

        return response()->json(['items' => $rows]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', StockItem::class);

        $item = new StockItem($this->validated($request));
        $item->save();

        return response()->json(['item' => $item], 201);
    }

    public function update(Request $request, StockItem $item): JsonResponse
    {
        $this->authorize('update', $item);

        $item->fill($this->validated($request, $item->getKey()));
        $item->save();

        return response()->json(['item' => $item->fresh()]);
    }

    public function categories(): JsonResponse
    {
        $this->authorize('viewAny', StockItem::class);

        return response()->json([
            'categories' => ItemCategory::query()->orderBy('sort_order')->orderBy('name')->get(['id', 'name', 'sort_order']),
        ]);
    }

    public function storeCategory(Request $request): JsonResponse
    {
        $this->authorize('create', StockItem::class);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:120',
                Rule::unique('inv_categories', 'name')->where('tenant_id', $request->user()->tenant_id),
            ],
        ]);

        $category = ItemCategory::query()->create($data + ['sort_order' => (int) ItemCategory::query()->max('sort_order') + 1]);

        return response()->json(['category' => $category], 201);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, ?int $ignoreId = null): array
    {
        $tenantId = $request->user()->tenant_id;

        $data = $request->validate([
            'name' => ['required', 'string', 'max:160',
                Rule::unique('inv_items', 'name')->where('tenant_id', $tenantId)->ignore($ignoreId),
            ],
            'code' => ['nullable', 'string', 'max:60'],
            'barcode' => ['nullable', 'string', 'max:60'],
            'category_id' => ['nullable', 'integer',
                Rule::exists('inv_categories', 'id')->where('tenant_id', $tenantId),
            ],
            'base_unit' => ['required', 'string', 'max:20'],
            'sub_unit' => ['nullable', 'string', 'max:20'],
            'sub_unit_factor' => ['nullable', 'integer', 'min:1', 'max:1000000', 'required_with:sub_unit'],
            'min_qty' => ['nullable', 'string'],
            'critical_qty' => ['nullable', 'string'],
            'max_qty' => ['nullable', 'string'],
            'default_supplier_id' => ['nullable', 'integer',
                Rule::exists('inv_suppliers', 'id')->where('tenant_id', $tenantId),
            ],
            'track_expiry' => ['boolean'],
            'track_lot' => ['boolean'],
            'shelf_location' => ['nullable', 'string', 'max:80'],
            'tax_rate' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'is_semi_finished' => ['boolean'],
            'is_active' => ['boolean'],
        ]);

        // Ondalık miktar girişleri → milli.
        foreach (['min_qty' => 'min_qty_milli', 'critical_qty' => 'critical_qty_milli', 'max_qty' => 'max_qty_milli'] as $in => $out) {
            if (array_key_exists($in, $data)) {
                $data[$out] = $data[$in] !== null ? (Qty::parseToMilli($data[$in]) ?? 0) : null;
                unset($data[$in]);
            }
        }

        $data['min_qty_milli'] ??= 0;
        $data['critical_qty_milli'] ??= 0;

        return $data;
    }
}
