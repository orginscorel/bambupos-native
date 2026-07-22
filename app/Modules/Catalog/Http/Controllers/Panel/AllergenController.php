<?php

namespace App\Modules\Catalog\Http\Controllers\Panel;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Models\Allergen;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Alerjen / diyet etiketi yönetimi: küresel sözlük salt-okunur listelenir,
 * kiracı kendi özel satırlarını ekler/düzenler/siler.
 */
class AllergenController extends Controller
{
    public function page(): Response
    {
        $this->authorize('viewAny', Allergen::class);

        return Inertia::render('Panel/Catalog/Allergens/Index');
    }

    public function index(): JsonResponse
    {
        $this->authorize('viewAny', Allergen::class);

        $allergens = Allergen::query()
            ->withCount('products')
            ->orderBy('kind')
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get()
            ->map(function (Allergen $a) {
                $a->setAttribute('is_global', $a->isGlobal());

                return $a;
            });

        return response()->json(['allergens' => $allergens]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Allergen::class);

        $data = $this->validated($request);
        $data['code'] = 'custom-'.(Str::slug($data['name']) ?: Str::lower(Str::random(8)));
        $data['sort_order'] = ((int) Allergen::query()->max('sort_order')) + 10;

        $allergen = Allergen::query()->create($data); // tenant_id bağlamdan (creating event)

        $allergen->setAttribute('is_global', false);
        $allergen->setAttribute('products_count', 0);

        return response()->json(['allergen' => $allergen], 201);
    }

    public function update(Request $request, Allergen $allergen): JsonResponse
    {
        $this->authorize('update', $allergen); // küresel satır: policy reddeder (403)

        $allergen->update($this->validated($request));

        $allergen->setAttribute('is_global', false);

        return response()->json(['allergen' => $allergen->loadCount('products')]);
    }

    public function destroy(Allergen $allergen): JsonResponse
    {
        $this->authorize('delete', $allergen);

        $allergen->delete(); // pivot FK cascade

        return response()->json(['ok' => true]);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request): array
    {
        return $request->validate([
            'kind' => ['required', Rule::in(Allergen::KINDS)],
            'name' => ['required', 'string', 'max:100'],
            // İkon tek başına yeterli değil: açıklama istenir (erişilebilirlik + prompt §10.3)
            'description' => ['required', 'string', 'max:500'],
            'icon' => ['nullable', 'string', 'max:60'],
            'color' => ['nullable', 'string', 'max:20', 'regex:/^#[0-9a-fA-F]{6}$/'],
        ]);
    }
}
