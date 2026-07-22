<?php

namespace App\Modules\Catalog\Http\Controllers\Panel;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Models\Category;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/** Kategori: Inertia sayfası + JSON CRUD + drag-drop sıralama. */
class CategoryController extends Controller
{
    public function page(): Response
    {
        $this->authorize('viewAny', Category::class);

        return Inertia::render('Panel/Catalog/Categories/Index');
    }

    public function index(): JsonResponse
    {
        $this->authorize('viewAny', Category::class);

        $categories = Category::query()
            ->withCount('products')
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get();

        return response()->json(['categories' => $categories]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Category::class);

        $data = $this->validated($request);
        $data['slug'] = $this->uniqueSlug($data['name']);
        $data['sort_order'] = ((int) Category::query()->max('sort_order')) + 10;

        $category = Category::query()->create($data);

        return response()->json(['category' => $category->loadCount('products')], 201);
    }

    public function update(Request $request, Category $category): JsonResponse
    {
        $this->authorize('update', $category);

        $data = $this->validated($request, $category);

        if (array_key_exists('name', $data) && $data['name'] !== $category->name) {
            $data['slug'] = $this->uniqueSlug($data['name'], $category->id);
        }

        $category->update($data);

        return response()->json(['category' => $category->loadCount('products')]);
    }

    public function destroy(Category $category): JsonResponse
    {
        $this->authorize('delete', $category);

        if ($category->products()->exists()) {
            throw ValidationException::withMessages([
                'category' => ['Bu kategoride ürün var; önce ürünleri taşıyın veya silin.'],
            ]);
        }

        if ($category->children()->exists()) {
            throw ValidationException::withMessages([
                'category' => ['Bu kategorinin alt kategorileri var; önce onları taşıyın veya silin.'],
            ]);
        }

        $category->delete();

        return response()->json(['ok' => true]);
    }

    /** Drag-drop sonucu: sıralı id listesi → sort_order. */
    public function reorder(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('catalog.update'), 403);

        $data = $request->validate([
            'ids' => ['required', 'array', 'min:1'],
            'ids.*' => ['integer'],
        ]);

        // Global scope: yalnız kendi kiracısının kayıtları güncellenebilir.
        $owned = Category::query()->whereIn('id', $data['ids'])->pluck('id')->all();

        foreach (array_values($data['ids']) as $index => $id) {
            if (in_array((int) $id, $owned, true)) {
                Category::query()->whereKey($id)->update(['sort_order' => ($index + 1) * 10]);
            }
        }

        return response()->json(['ok' => true]);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, ?Category $category = null): array
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:150'],
            'description' => ['nullable', 'string', 'max:500'],
            'parent_id' => ['nullable', 'integer'],
            'icon' => ['nullable', 'string', 'max:60'],
            'color' => ['nullable', 'string', 'max:20', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'available_from' => ['nullable', 'date_format:H:i'],
            'available_until' => ['nullable', 'date_format:H:i'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        if (! empty($data['parent_id'])) {
            $parent = Category::query()->find($data['parent_id']); // scope: yabancı kiracı çözülmez

            if ($parent === null) {
                throw ValidationException::withMessages(['parent_id' => ['Üst kategori bulunamadı.']]);
            }

            if ($category !== null && $this->wouldCreateCycle($category, $parent)) {
                throw ValidationException::withMessages(['parent_id' => ['Kategori kendi altına taşınamaz.']]);
            }

            $data['parent_id'] = $parent->id;
        } else {
            $data['parent_id'] = null;
        }

        return $data;
    }

    private function wouldCreateCycle(Category $category, Category $candidateParent): bool
    {
        $cursor = $candidateParent;

        while ($cursor !== null) {
            if ((int) $cursor->id === (int) $category->id) {
                return true;
            }
            $cursor = $cursor->parent;
        }

        return false;
    }

    private function uniqueSlug(string $name, ?int $ignoreId = null): string
    {
        $base = Str::slug($name) ?: 'kategori';
        $slug = $base;
        $i = 2;

        while (Category::query()
            ->where('slug', $slug)
            ->when($ignoreId, fn ($q) => $q->where('id', '!=', $ignoreId))
            ->exists()) {
            $slug = $base.'-'.$i++;
        }

        return $slug;
    }
}
