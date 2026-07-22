<?php

namespace App\Modules\Venue\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Venue\Models\Floor;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/** Kat yönetimi (şube → KAT → alan → masa). */
class FloorController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Floor::class);

        $query = Floor::query()->withCount('areas')->orderBy('sort_order')->orderBy('name');

        if ($request->filled('branch_id')) {
            $query->where('branch_id', (int) $request->query('branch_id'));
        }

        return response()->json(['floors' => $query->get()]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Floor::class);

        $data = $request->validate([
            'branch_id' => ['required', 'integer'],
            'name' => ['required', 'string', 'max:100'],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:65000'],
        ]);

        $branch = Branch::query()->find($data['branch_id']); // scoped: yabancı şube çözülmez

        if ($branch === null) {
            throw ValidationException::withMessages(['branch_id' => ['Şube bulunamadı.']]);
        }

        $this->assertUniqueName($request, (int) $branch->id, $data['name']);

        $floor = new Floor(['name' => $data['name'], 'sort_order' => $data['sort_order'] ?? 0]);
        $floor->branch_id = $branch->id;
        $floor->save();

        return response()->json(['floor' => $floor], 201);
    }

    public function update(Request $request, Floor $floor): JsonResponse
    {
        $this->authorize('update', $floor);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:100'],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:65000'],
        ]);

        if (isset($data['name']) && $data['name'] !== $floor->name) {
            $this->assertUniqueName($request, (int) $floor->branch_id, $data['name'], $floor->id);
        }

        $floor->update($data);

        return response()->json(['floor' => $floor->fresh()]);
    }

    public function destroy(Request $request, Floor $floor): JsonResponse
    {
        $this->authorize('delete', $floor);

        // Alanlar silinmez; kat bağı koparılır (nullOnDelete).
        $floor->delete();

        return response()->json(['ok' => true]);
    }

    private function assertUniqueName(Request $request, int $branchId, string $name, ?int $ignoreId = null): void
    {
        $exists = Floor::query()
            ->where('branch_id', $branchId)
            ->where('name', $name)
            ->when($ignoreId !== null, fn ($q) => $q->whereKeyNot($ignoreId))
            ->exists();

        if ($exists) {
            throw ValidationException::withMessages(['name' => ['Bu şubede aynı adlı bir kat zaten var.']]);
        }
    }
}
