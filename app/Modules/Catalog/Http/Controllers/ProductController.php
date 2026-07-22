<?php

namespace App\Modules\Catalog\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Models\Product;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * Faz-1 iskelet CRUD'u — kiracı izolasyonunun uçtan uca kanıtı.
 * Route model binding + global scope: yabancı kiracının ürünü 404.
 */
class ProductController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Product::class);

        return response()->json(['products' => Product::query()->orderBy('name')->paginate(50)]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Product::class);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'sku' => ['nullable', 'string', 'max:64'],
            'price_minor' => ['sometimes', 'integer', 'min:0'],
            'branch_id' => ['nullable', 'integer'],
        ]);

        $product = new Product($data);
        $product->branch_id = $this->resolveBranchId($data['branch_id'] ?? null);
        $product->save(); // tenant_id bağlamdan (BelongsToTenant), istekten asla

        return response()->json(['product' => $product], 201);
    }

    public function show(Request $request, Product $product): JsonResponse
    {
        $this->authorize('view', $product);

        return response()->json(['product' => $product]);
    }

    public function update(Request $request, Product $product): JsonResponse
    {
        $this->authorize('update', $product);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'sku' => ['nullable', 'string', 'max:64'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        if ($request->has('price_minor')) {
            $this->authorize('changePrice', $product);
            $data['price_minor'] = $request->validate(['price_minor' => ['integer', 'min:0']])['price_minor'];
        }

        $product->update($data);

        return response()->json(['product' => $product]);
    }

    public function destroy(Request $request, Product $product): JsonResponse
    {
        $this->authorize('delete', $product);

        $product->delete();

        return response()->json(['ok' => true]);
    }

    private function resolveBranchId(?int $branchId): ?int
    {
        if ($branchId === null) {
            return null;
        }

        // Branch global scope'lu: yabancı şube id'si çözülmez → 422.
        $branch = Branch::query()->find($branchId);

        if ($branch === null) {
            throw ValidationException::withMessages(['branch_id' => ['Şube bulunamadı.']]);
        }

        return $branch->id;
    }
}
