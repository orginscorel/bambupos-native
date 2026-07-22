<?php

namespace App\Modules\Catalog\Http\Controllers\Panel;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Models\Category;
use App\Modules\Catalog\Models\Menu;
use App\Modules\Catalog\Models\Product;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

/** Menü planlama: zaman/gün/kanal kuralları + kategori ataması. */
class MenuController extends Controller
{
    public function page(): Response
    {
        $this->authorize('viewAny', Menu::class);

        return Inertia::render('Panel/Catalog/Menus/Index');
    }

    public function index(): JsonResponse
    {
        $this->authorize('viewAny', Menu::class);

        return response()->json([
            'menus' => Menu::query()
                ->with('categories:id,name')
                ->orderBy('sort_order')
                ->orderBy('id')
                ->get(),
            'categories' => Category::query()->orderBy('sort_order')->get(['id', 'name', 'parent_id']),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Menu::class);

        [$data, $categoryIds] = $this->validated($request);

        $menu = DB::transaction(function () use ($data, $categoryIds) {
            $data['sort_order'] = ((int) Menu::query()->max('sort_order')) + 10;
            $menu = Menu::query()->create($data);
            $this->syncCategories($menu, $categoryIds);

            return $menu;
        });

        return response()->json(['menu' => $menu->load('categories:id,name')], 201);
    }

    public function update(Request $request, Menu $menu): JsonResponse
    {
        $this->authorize('update', $menu);

        [$data, $categoryIds] = $this->validated($request);

        DB::transaction(function () use ($menu, $data, $categoryIds): void {
            $menu->update($data);
            $this->syncCategories($menu, $categoryIds);
        });

        return response()->json(['menu' => $menu->fresh('categories')]);
    }

    public function destroy(Menu $menu): JsonResponse
    {
        $this->authorize('delete', $menu);

        $menu->delete();

        return response()->json(['ok' => true]);
    }

    /** @return array{0: array<string, mixed>, 1: array<int, int>|null} */
    private function validated(Request $request): array
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:150'],
            'description' => ['nullable', 'string', 'max:500'],
            'days' => ['nullable', 'array', 'max:7'],
            'days.*' => ['integer', 'min:1', 'max:7'], // ISO: 1=Pzt … 7=Paz
            'start_time' => ['nullable', 'date_format:H:i'],
            'end_time' => ['nullable', 'date_format:H:i'],
            'channels' => ['nullable', 'array'],
            'channels.*' => [Rule::in(Product::CHANNELS)],
            'is_active' => ['sometimes', 'boolean'],
            'category_ids' => ['sometimes', 'array', 'max:100'],
            'category_ids.*' => ['integer'],
        ]);

        if (isset($data['days'])) {
            $data['days'] = array_values(array_unique(array_map('intval', $data['days'])));
            sort($data['days']);
        }

        $categoryIds = $data['category_ids'] ?? null;
        unset($data['category_ids']);

        return [$data, $categoryIds];
    }

    /** @param array<int, int>|null $categoryIds */
    private function syncCategories(Menu $menu, ?array $categoryIds): void
    {
        if (! is_array($categoryIds)) {
            return;
        }

        // Scope: yabancı kiracının kategorisi sessizce elenir
        $ownedIds = Category::query()->whereIn('id', $categoryIds)->pluck('id');

        $sync = [];
        foreach (array_values($categoryIds) as $index => $id) {
            if ($ownedIds->contains((int) $id)) {
                $sync[(int) $id] = ['sort_order' => ($index + 1) * 10];
            }
        }

        $menu->categories()->sync($sync);
    }
}
