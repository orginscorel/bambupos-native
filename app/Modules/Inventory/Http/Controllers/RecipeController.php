<?php

namespace App\Modules\Inventory\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Models\Product;
use App\Modules\Inventory\Models\Recipe;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\Warehouse;
use App\Modules\Inventory\Services\ConsumptionService;
use App\Modules\Inventory\Services\RecipeService;
use App\Modules\Inventory\Support\Qty;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Reçete ekranı uçları (§17.3). Katalog ürünleri SALT OKUNUR kullanılır
 * (Catalog modülü değiştirilmez); erişim stok izniyle sınırlıdır.
 */
class RecipeController extends Controller
{
    public function __construct(
        private readonly RecipeService $recipes,
        private readonly ConsumptionService $consumption,
    ) {
    }

    /** Reçete hedefi seçimi: ürünler (varyantlarıyla) + reçete durumu. */
    public function products(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Recipe::class);

        $products = Product::query()
            ->with('variants:id,product_id,name,is_active')
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'name', 'category_id']);

        $recipeIndex = Recipe::query()
            ->where('is_active', true)
            ->whereNotNull('product_id')
            ->get(['id', 'product_id', 'variant_id', 'branch_id', 'version'])
            ->groupBy('product_id');

        return response()->json([
            'products' => $products->map(fn (Product $p) => [
                'id' => $p->id,
                'name' => $p->name,
                'variants' => $p->variants->where('is_active', true)->map(fn ($v) => ['id' => $v->id, 'name' => $v->name])->values(),
                'recipes' => ($recipeIndex[$p->id] ?? collect())->map(fn (Recipe $r) => [
                    'id' => $r->id,
                    'variant_id' => $r->variant_id,
                    'branch_id' => $r->branch_id,
                    'version' => $r->version,
                ])->values(),
            ]),
        ]);
    }

    /** Hedefin aktif reçetesi + sürüm tarihçesi. */
    public function show(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Recipe::class);

        $data = $request->validate([
            'product_id' => ['nullable', 'integer'],
            'variant_id' => ['nullable', 'integer'],
            'item_id' => ['nullable', 'integer'],
            'branch_id' => ['nullable', 'integer'],
        ]);

        $query = Recipe::query()
            ->with(['lines.item:id,name,base_unit,sub_unit,sub_unit_factor,avg_cost_minor'])
            ->where('product_id', $data['product_id'] ?? null)
            ->where('variant_id', $data['variant_id'] ?? null)
            ->where('item_id', $data['item_id'] ?? null)
            ->where('branch_id', $data['branch_id'] ?? null)
            ->orderByDesc('version');

        $versions = $query->get();
        $active = $versions->firstWhere('is_active', true);

        return response()->json([
            'recipe' => $active !== null ? $this->present($active) : null,
            'versions' => $versions->map(fn (Recipe $r) => [
                'id' => $r->getKey(),
                'version' => $r->version,
                'is_active' => $r->is_active,
                'created_at' => $r->created_at?->toIso8601String(),
                'line_count' => $r->lines->count(),
            ]),
        ]);
    }

    /** Geçmiş bir sürümün satır dökümü (tarihçe görüntüleme). */
    public function version(Recipe $recipe): JsonResponse
    {
        $this->authorize('view', $recipe);

        return response()->json(['recipe' => $this->present($recipe->load('lines.item:id,name,base_unit,sub_unit,sub_unit_factor,avg_cost_minor'))]);
    }

    /** Kaydet = YENİ sürüm (RecipeService::saveVersion). */
    public function save(Request $request): JsonResponse
    {
        $this->authorize('create', Recipe::class);

        $tenantId = (int) $request->user()->tenant_id;

        $data = $request->validate([
            'product_id' => ['nullable', 'integer', Rule::exists('products', 'id')->where('tenant_id', $tenantId)],
            'variant_id' => ['nullable', 'integer'],
            'item_id' => ['nullable', 'integer', Rule::exists('inv_items', 'id')->where('tenant_id', $tenantId)],
            'branch_id' => ['nullable', 'integer', Rule::exists('branches', 'id')->where('tenant_id', $tenantId)],
            'yield_qty' => ['nullable', 'string'],
            'waste_percent' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'note' => ['nullable', 'string', 'max:500'],
            'lines' => ['required', 'array', 'min:1'],
            'lines.*.item_id' => ['required', 'integer'],
            'lines.*.qty' => ['required', 'string'],
            'lines.*.unit_entry' => ['nullable', Rule::in(['base', 'sub'])],
            'lines.*.waste_percent' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'lines.*.warehouse_id' => ['nullable', 'integer', Rule::exists('inv_warehouses', 'id')->where('tenant_id', $tenantId)],
        ]);

        // Varyant gerçekten ürüne mi ait? (sızıntı koruması)
        if (! empty($data['variant_id'])) {
            $owns = \App\Modules\Catalog\Models\ProductVariant::query()
                ->where('id', (int) $data['variant_id'])
                ->where('product_id', (int) ($data['product_id'] ?? 0))
                ->exists();

            if (! $owns) {
                throw ValidationException::withMessages(['variant_id' => ['Varyant bu ürüne ait değil.']]);
            }
        }

        $lines = [];

        foreach ($data['lines'] as $line) {
            $item = StockItem::query()->find((int) $line['item_id']);

            if ($item === null) {
                throw ValidationException::withMessages(['lines' => ['Bileşen bulunamadı.']]);
            }

            // Girilen miktar: base ise doğrudan; sub ise faktörle çevir.
            $entry = $line['unit_entry'] ?? 'base';
            $qtyMilli = $entry === 'sub' && $item->sub_unit_factor
                ? Qty::subToMilli((float) str_replace(',', '.', $line['qty']), (int) $item->sub_unit_factor)
                : Qty::parseToMilli($line['qty']);

            if ($qtyMilli === null || $qtyMilli <= 0) {
                throw ValidationException::withMessages(['lines' => ['Bileşen miktarı geçersiz: '.$item->name]]);
            }

            $lines[] = [
                'item_id' => $item->getKey(),
                'qty_milli' => $qtyMilli,
                'unit_entry' => $entry,
                'waste_percent' => (float) ($line['waste_percent'] ?? 0),
                'warehouse_id' => $line['warehouse_id'] ?? null,
            ];
        }

        $recipe = $this->recipes->saveVersion($tenantId, [
            'product_id' => $data['product_id'] ?? null,
            'variant_id' => $data['variant_id'] ?? null,
            'item_id' => $data['item_id'] ?? null,
            'branch_id' => $data['branch_id'] ?? null,
            'yield_qty_milli' => Qty::parseToMilli($data['yield_qty'] ?? null) ?? 1000,
            'waste_percent' => (float) ($data['waste_percent'] ?? 0),
            'note' => $data['note'] ?? null,
            'lines' => $lines,
        ], $request->user());

        return response()->json(['recipe' => $this->present($recipe->load('lines.item:id,name,base_unit,sub_unit,sub_unit_factor,avg_cost_minor'))], 201);
    }

    /** Yarı mamul üretimi. */
    public function produce(Request $request): JsonResponse
    {
        $this->authorize('adjust', Recipe::class);

        $tenantId = (int) $request->user()->tenant_id;

        $data = $request->validate([
            'item_id' => ['required', 'integer', Rule::exists('inv_items', 'id')->where('tenant_id', $tenantId)],
            'warehouse_id' => ['required', 'integer', Rule::exists('inv_warehouses', 'id')->where('tenant_id', $tenantId)],
            'qty' => ['required', 'string'],
        ]);

        $qtyMilli = Qty::parseToMilli($data['qty']);

        if ($qtyMilli === null || $qtyMilli <= 0) {
            throw ValidationException::withMessages(['qty' => ['Geçerli bir üretim miktarı girin.']]);
        }

        $result = $this->consumption->produce(
            StockItem::query()->findOrFail((int) $data['item_id']),
            $qtyMilli,
            Warehouse::query()->findOrFail((int) $data['warehouse_id']),
            $request->user(),
        );

        return response()->json([
            'production_id' => $result['production']->getKey(),
            'consumed_count' => count($result['consumed']),
        ], 201);
    }

    /** @return array<string, mixed> */
    private function present(Recipe $recipe): array
    {
        return [
            'id' => $recipe->getKey(),
            'product_id' => $recipe->product_id,
            'variant_id' => $recipe->variant_id,
            'item_id' => $recipe->item_id,
            'branch_id' => $recipe->branch_id,
            'version' => $recipe->version,
            'yield_qty' => Qty::toDecimalString((int) $recipe->yield_qty_milli),
            'waste_percent' => (float) $recipe->waste_percent,
            'note' => $recipe->note,
            'is_active' => $recipe->is_active,
            'lines' => $recipe->lines->map(fn ($l) => [
                'item_id' => $l->item_id,
                'item_name' => $l->item?->name,
                'base_unit' => $l->item?->base_unit,
                'sub_unit' => $l->item?->sub_unit,
                'sub_unit_factor' => $l->item?->sub_unit_factor,
                'qty_milli' => (int) $l->qty_milli,
                'qty' => Qty::toDecimalString((int) $l->qty_milli),
                'unit_entry' => $l->unit_entry,
                'waste_percent' => (float) $l->waste_percent,
                'warehouse_id' => $l->warehouse_id,
                'line_cost_minor' => Qty::cost((int) $l->qty_milli, (int) ($l->item?->avg_cost_minor ?? 0)),
            ])->values(),
        ];
    }
}
