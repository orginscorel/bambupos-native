<?php

namespace App\Modules\Catalog\Http\Controllers\Panel;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Models\Allergen;
use App\Modules\Catalog\Models\Category;
use App\Modules\Catalog\Models\OptionGroup;
use App\Modules\Catalog\Models\Product;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Ürün yönetimi: liste (arama/filtre/sayfalama/toplu işlem/sıralama)
 * + sekmeli düzenleme sayfası için JSON uçları.
 * Fiyat alanı değişiklikleri ayrıca `catalog.change_price` iznine bağlıdır.
 */
class ProductController extends Controller
{
    private const PRICE_FIELDS = [
        'price_minor', 'cost_minor', 'package_price_minor', 'kiosk_price_minor',
        'qr_price_minor', 'discounted_price_minor', 'tax_rate',
    ];

    /* ---------------- Inertia sayfaları ---------------- */

    public function indexPage(): Response
    {
        $this->authorize('viewAny', Product::class);

        return Inertia::render('Panel/Catalog/Products/Index');
    }

    public function createPage(): Response
    {
        $this->authorize('create', Product::class);

        return Inertia::render('Panel/Catalog/Products/Edit', ['productId' => null]);
    }

    public function editPage(Product $product): Response
    {
        $this->authorize('view', $product);

        return Inertia::render('Panel/Catalog/Products/Edit', ['productId' => $product->id]);
    }

    /* ---------------- JSON uçları ---------------- */

    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Product::class);

        $filters = $request->validate([
            'q' => ['nullable', 'string', 'max:150'],
            'category_id' => ['nullable', 'integer'],
            'status' => ['nullable', Rule::in(['active', 'passive', 'unavailable'])],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'min:5', 'max:100'],
        ]);

        $query = Product::query()
            ->with(['category:id,name', 'images'])
            ->withCount('variants');

        if (! empty($filters['q'])) {
            $q = $filters['q'];
            $query->where(function ($w) use ($q): void {
                $w->where('name', 'like', "%{$q}%")
                    ->orWhere('sku', 'like', "%{$q}%")
                    ->orWhere('barcode', 'like', "%{$q}%");
            });
        }

        if (! empty($filters['category_id'])) {
            $query->where('category_id', (int) $filters['category_id']);
        }

        match ($filters['status'] ?? null) {
            'active' => $query->where('is_active', true),
            'passive' => $query->where('is_active', false),
            'unavailable' => $query->where('is_available', false),
            default => null,
        };

        $products = $query
            ->orderBy('sort_order')
            ->orderBy('id')
            ->paginate((int) ($filters['per_page'] ?? 25));

        return response()->json(['products' => $products]);
    }

    /** Düzenleme formunun sözlükleri: kategoriler, seçenek grupları, alerjenler. */
    public function formOptions(): JsonResponse
    {
        $this->authorize('viewAny', Product::class);

        return response()->json([
            'categories' => Category::query()->orderBy('sort_order')->get(['id', 'name', 'parent_id']),
            'option_groups' => OptionGroup::query()->with('options:id,option_group_id,name,price_minor')
                ->orderBy('sort_order')->get(),
            'allergens' => Allergen::query()->orderBy('kind')->orderBy('sort_order')->get(),
        ]);
    }

    public function show(Product $product): JsonResponse
    {
        $this->authorize('view', $product);

        return response()->json([
            'product' => $product->load([
                'category:id,name',
                'variants',
                'optionGroups.options',
                'allergens',
                'images',
            ]),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Product::class);

        [$data, $relations] = $this->validatedPayload($request);

        $product = DB::transaction(function () use ($data, $relations) {
            $data['sort_order'] = ((int) Product::query()->max('sort_order')) + 10;
            $product = Product::query()->create($data);
            $this->syncRelations($product, $relations);

            return $product;
        });

        return response()->json(['product' => $this->freshPayload($product)], 201);
    }

    public function update(Request $request, Product $product): JsonResponse
    {
        $this->authorize('update', $product);

        [$data, $relations] = $this->validatedPayload($request, $product);

        // Fiyat/KDV değişikliği ayrı izne bağlı (catalog.change_price)
        foreach (self::PRICE_FIELDS as $field) {
            if (array_key_exists($field, $data) && (string) $data[$field] !== (string) $product->{$field}) {
                $this->authorize('changePrice', $product);
                break;
            }
        }

        DB::transaction(function () use ($product, $data, $relations): void {
            $product->update($data);
            $this->syncRelations($product, $relations);
        });

        return response()->json(['product' => $this->freshPayload($product)]);
    }

    public function destroy(Product $product): JsonResponse
    {
        $this->authorize('delete', $product);

        $product->delete();

        return response()->json(['ok' => true]);
    }

    /** Toplu işlem: etkinleştir / pasifleştir / mevcut değil / mevcut / kategori ata / sil. */
    public function bulk(Request $request): JsonResponse
    {
        $data = $request->validate([
            'action' => ['required', Rule::in(['activate', 'deactivate', 'set_available', 'set_unavailable', 'set_category', 'delete'])],
            'ids' => ['required', 'array', 'min:1', 'max:200'],
            'ids.*' => ['integer'],
            'category_id' => ['nullable', 'integer'],
        ]);

        $user = $request->user();
        $needed = $data['action'] === 'delete' ? 'catalog.delete' : 'catalog.update';
        abort_unless($user->hasPermission($needed), 403);

        // Global scope: yalnız kendi kiracısının ürünleri seçilir.
        $products = Product::query()->whereIn('id', $data['ids'])->get();

        $categoryId = null;
        if ($data['action'] === 'set_category') {
            if (empty($data['category_id'])) {
                throw ValidationException::withMessages(['category_id' => ['Kategori seçin.']]);
            }
            $category = Category::query()->find($data['category_id']);
            if ($category === null) {
                throw ValidationException::withMessages(['category_id' => ['Kategori bulunamadı.']]);
            }
            $categoryId = $category->id;
        }

        foreach ($products as $product) {
            match ($data['action']) {
                'activate' => $product->update(['is_active' => true]),
                'deactivate' => $product->update(['is_active' => false]),
                'set_available' => $product->update(['is_available' => true]),
                'set_unavailable' => $product->update(['is_available' => false]),
                'set_category' => $product->update(['category_id' => $categoryId]),
                'delete' => $product->delete(),
            };
        }

        return response()->json(['ok' => true, 'affected' => $products->count()]);
    }

    /** Drag-drop sonucu: sıralı id listesi → sort_order. */
    public function reorder(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('catalog.update'), 403);

        $data = $request->validate([
            'ids' => ['required', 'array', 'min:1'],
            'ids.*' => ['integer'],
        ]);

        $owned = Product::query()->whereIn('id', $data['ids'])->pluck('id')->all();

        foreach (array_values($data['ids']) as $index => $id) {
            if (in_array((int) $id, $owned, true)) {
                Product::query()->whereKey($id)->update(['sort_order' => ($index + 1) * 10]);
            }
        }

        return response()->json(['ok' => true]);
    }

    /* ---------------- Doğrulama + ilişkiler ---------------- */

    /** @return array{0: array<string, mixed>, 1: array<string, mixed>} */
    private function validatedPayload(Request $request, ?Product $product = null): array
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'description' => ['nullable', 'string', 'max:2000'],
            'sku' => ['nullable', 'string', 'max:64'],
            'barcode' => ['nullable', 'string', 'max:64'],
            'category_id' => ['nullable', 'integer'],

            'price_minor' => ['required', 'integer', 'min:0', 'max:99999999999'],
            'cost_minor' => ['nullable', 'integer', 'min:0', 'max:99999999999'],
            'package_price_minor' => ['nullable', 'integer', 'min:0', 'max:99999999999'],
            'kiosk_price_minor' => ['nullable', 'integer', 'min:0', 'max:99999999999'],
            'qr_price_minor' => ['nullable', 'integer', 'min:0', 'max:99999999999'],
            'discounted_price_minor' => ['nullable', 'integer', 'min:0', 'max:99999999999'],
            'tax_rate' => ['nullable', 'numeric', 'min:0', 'max:100'],

            'portion' => ['nullable', 'string', 'max:100'],
            'unit' => ['nullable', 'string', 'max:30'],
            'prep_minutes' => ['nullable', 'integer', 'min:0', 'max:600'],

            'calories' => ['nullable', 'integer', 'min:0', 'max:20000'],
            'protein' => ['nullable', 'numeric', 'min:0', 'max:2000'],
            'carbs' => ['nullable', 'numeric', 'min:0', 'max:2000'],
            'fat' => ['nullable', 'numeric', 'min:0', 'max:2000'],

            'spiciness' => ['sometimes', 'integer', 'min:0', 'max:3'],
            'is_new' => ['sometimes', 'boolean'],
            'is_chef_pick' => ['sometimes', 'boolean'],
            'is_bestseller' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
            'is_available' => ['sometimes', 'boolean'],

            'channels' => ['nullable', 'array'],
            'channels.*' => [Rule::in(Product::CHANNELS)],
            'available_from' => ['nullable', 'date_format:H:i'],
            'available_until' => ['nullable', 'date_format:H:i'],
            'station' => ['nullable', 'string', 'max:40'],

            'track_stock' => ['sometimes', 'boolean'],
            'stock_quantity' => ['nullable', 'integer', 'min:0'],
            'min_order_qty' => ['sometimes', 'integer', 'min:1', 'max:1000'],
            'max_order_qty' => ['nullable', 'integer', 'min:1', 'max:1000'],

            'variants' => ['sometimes', 'array', 'max:20'],
            'variants.*.id' => ['nullable', 'integer'],
            'variants.*.name' => ['required_with:variants', 'string', 'max:100'],
            'variants.*.price_minor' => ['required_with:variants', 'integer', 'min:0', 'max:99999999999'],
            'variants.*.is_default' => ['sometimes', 'boolean'],
            'variants.*.is_active' => ['sometimes', 'boolean'],

            'option_group_ids' => ['sometimes', 'array', 'max:30'],
            'option_group_ids.*' => ['integer'],

            'allergen_ids' => ['sometimes', 'array', 'max:60'],
            'allergen_ids.*' => ['integer'],
        ]);

        if (isset($data['min_order_qty'], $data['max_order_qty'])
            && $data['max_order_qty'] !== null
            && (int) $data['max_order_qty'] < (int) $data['min_order_qty']) {
            throw ValidationException::withMessages([
                'max_order_qty' => ['En fazla sipariş adedi, en az adetten küçük olamaz.'],
            ]);
        }

        if (array_key_exists('category_id', $data) && ! empty($data['category_id'])) {
            // Scope'lu arama: yabancı kiracının kategorisi çözülmez → 422
            $category = Category::query()->find($data['category_id']);
            if ($category === null) {
                throw ValidationException::withMessages(['category_id' => ['Kategori bulunamadı.']]);
            }
            $data['category_id'] = $category->id;
        }

        // Kiracı içi SKU benzersizliği (UNIQUE(tenant_id, sku) — dostça mesaj)
        if (! empty($data['sku'])) {
            $exists = Product::query()
                ->where('sku', $data['sku'])
                ->when($product, fn ($q) => $q->where('id', '!=', $product->id))
                ->exists();
            if ($exists) {
                throw ValidationException::withMessages(['sku' => ['Bu ürün kodu zaten kullanılıyor.']]);
            }
        } else {
            $data['sku'] = null;
        }

        $relations = [
            'variants' => $data['variants'] ?? null,
            'option_group_ids' => $data['option_group_ids'] ?? null,
            'allergen_ids' => $data['allergen_ids'] ?? null,
        ];
        unset($data['variants'], $data['option_group_ids'], $data['allergen_ids']);

        return [$data, $relations];
    }

    /** @param array<string, mixed> $relations */
    private function syncRelations(Product $product, array $relations): void
    {
        if (is_array($relations['variants'])) {
            $keptIds = [];
            $hasDefault = false;

            foreach (array_values($relations['variants']) as $index => $row) {
                $attributes = [
                    'name' => $row['name'],
                    'price_minor' => (int) $row['price_minor'],
                    'is_default' => ! $hasDefault && (bool) ($row['is_default'] ?? false),
                    'is_active' => (bool) ($row['is_active'] ?? true),
                    'sort_order' => ($index + 1) * 10,
                ];
                $hasDefault = $hasDefault || $attributes['is_default'];

                $existing = ! empty($row['id'])
                    ? $product->variants()->whereKey((int) $row['id'])->first()
                    : null;

                if ($existing !== null) {
                    $existing->update($attributes);
                    $keptIds[] = $existing->id;
                } else {
                    $keptIds[] = $product->variants()->create($attributes)->id;
                }
            }

            $product->variants()->whereNotIn('id', $keptIds)->delete();
        }

        if (is_array($relations['option_group_ids'])) {
            // Scope'lu sorgu: yabancı kiracının grubu sessizce elenir
            $ownedIds = OptionGroup::query()
                ->whereIn('id', $relations['option_group_ids'])
                ->pluck('id');

            $sync = [];
            foreach (array_values($relations['option_group_ids']) as $index => $id) {
                if ($ownedIds->contains((int) $id)) {
                    $sync[(int) $id] = ['sort_order' => ($index + 1) * 10];
                }
            }

            $product->optionGroups()->sync($sync);
        }

        if (is_array($relations['allergen_ids'])) {
            // Scope: küresel VEYA kendi kiracısının alerjenleri
            $validIds = Allergen::query()
                ->whereIn('id', $relations['allergen_ids'])
                ->pluck('id')
                ->all();

            $product->allergens()->sync($validIds);
        }
    }

    private function freshPayload(Product $product): Product
    {
        return $product->fresh([
            'category:id,name',
            'variants',
            'optionGroups.options',
            'allergens',
            'images',
        ]);
    }
}
