<?php

namespace App\Modules\Orders\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Models\Category;
use App\Modules\Catalog\Models\Product;
use App\Modules\Orders\Models\Order;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Hızlı ürün ekleme (garson) için katalog OKUMA modeli: kategori → ürün →
 * varyant/seçenek ağacı tek istekte. Yalnız orders.view ister (garsona
 * catalog.view verilmesi gerekmez); Catalog modeline salt-okunur bağlanır.
 */
class OrderCatalogController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Order::class);

        $branchId = (int) $request->query('branch_id', 0);

        $categories = Category::query()
            ->where('is_active', true)
            ->orderBy('sort_order')->orderBy('name')
            ->get(['id', 'name', 'icon', 'color', 'sort_order']);

        $products = Product::query()
            ->with([
                'variants' => fn ($q) => $q->where('is_active', true),
                'optionGroups.options' => fn ($q) => $q->where('is_active', true),
            ])
            ->where('is_active', true)
            ->when($branchId > 0, fn ($q) => $q->where(function ($sub) use ($branchId): void {
                $sub->whereNull('branch_id')->orWhere('branch_id', $branchId);
            }))
            ->orderBy('sort_order')->orderBy('name')
            ->get();

        return response()->json([
            'categories' => $categories->map(fn (Category $c): array => [
                'id' => $c->id,
                'name' => $c->name,
                'icon' => $c->icon,
                'color' => $c->color,
            ])->values()->all(),
            'products' => $products->map(fn (Product $p): array => [
                'id' => $p->id,
                'category_id' => $p->category_id,
                'name' => $p->name,
                'price_minor' => (int) $p->price_minor,
                'discounted_price_minor' => $p->discounted_price_minor !== null ? (int) $p->discounted_price_minor : null,
                'kiosk_price_minor' => $p->kiosk_price_minor !== null ? (int) $p->kiosk_price_minor : null,
                'package_price_minor' => $p->package_price_minor !== null ? (int) $p->package_price_minor : null,
                'qr_price_minor' => $p->qr_price_minor !== null ? (int) $p->qr_price_minor : null,
                'is_available' => (bool) $p->is_available,
                'channels' => $p->channels,
                'min_order_qty' => (int) $p->min_order_qty,
                'max_order_qty' => $p->max_order_qty !== null ? (int) $p->max_order_qty : null,
                'station' => $p->station,
                'variants' => $p->variants->map(fn ($v): array => [
                    'id' => $v->id,
                    'name' => $v->name,
                    'price_minor' => (int) $v->price_minor,
                    'is_default' => (bool) $v->is_default,
                ])->values()->all(),
                'option_groups' => $p->optionGroups->map(fn ($g): array => [
                    'id' => $g->id,
                    'name' => $g->name,
                    'selection_type' => $g->selection_type,
                    'is_required' => (bool) $g->is_required,
                    'min_select' => (int) $g->min_select,
                    'max_select' => $g->max_select !== null ? (int) $g->max_select : null,
                    'free_limit' => (int) $g->free_limit,
                    'options' => $g->options->map(fn ($o): array => [
                        'id' => $o->id,
                        'name' => $o->name,
                        'price_minor' => (int) $o->price_minor,
                        'is_default' => (bool) $o->is_default,
                    ])->values()->all(),
                ])->values()->all(),
            ])->values()->all(),
        ]);
    }
}
