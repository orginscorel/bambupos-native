<?php

namespace App\Modules\Venue\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Venue\Enums\AreaType;
use App\Modules\Venue\Models\Area;
use App\Modules\Venue\Models\Floor;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/** Salon/alan yönetimi (şube → kat → SALON/ALAN → masa). */
class AreaController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Area::class);

        $query = Area::query()
            ->with('floor:id,name')
            ->withCount('tables')
            ->orderBy('sort_order')
            ->orderBy('name');

        if ($request->filled('branch_id')) {
            $query->where('branch_id', (int) $request->query('branch_id'));
        }

        $areas = $query->get()->map(fn (Area $area): array => [
            'id' => $area->id,
            'branch_id' => $area->branch_id,
            'floor_id' => $area->floor_id,
            'floor_name' => $area->floor?->name,
            'name' => $area->name,
            'type' => $area->type->value,
            'type_label' => $area->type->label(),
            'sort_order' => $area->sort_order,
            'is_active' => $area->is_active,
            'tables_count' => $area->tables_count,
        ]);

        return response()->json(['areas' => $areas]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Area::class);

        $data = $this->validated($request, required: true);

        $branch = Branch::query()->find($data['branch_id']);

        if ($branch === null) {
            throw ValidationException::withMessages(['branch_id' => ['Şube bulunamadı.']]);
        }

        $floorId = $this->resolveFloorId($data['floor_id'] ?? null, (int) $branch->id);
        $this->assertUniqueName((int) $branch->id, $data['name']);

        $area = new Area([
            'name' => $data['name'],
            'type' => $data['type'] ?? AreaType::Indoor->value,
            'sort_order' => $data['sort_order'] ?? 0,
            'is_active' => $data['is_active'] ?? true,
        ]);
        $area->branch_id = $branch->id;
        $area->floor_id = $floorId;
        $area->save();

        return response()->json(['area' => $area], 201);
    }

    public function update(Request $request, Area $area): JsonResponse
    {
        $this->authorize('update', $area);

        $data = $this->validated($request, required: false);

        if (isset($data['name']) && $data['name'] !== $area->name) {
            $this->assertUniqueName((int) $area->branch_id, $data['name'], $area->id);
        }

        if (array_key_exists('floor_id', $data)) {
            $area->floor_id = $this->resolveFloorId($data['floor_id'], (int) $area->branch_id);
        }

        unset($data['branch_id'], $data['floor_id']); // şube değişmez; kat yukarıda doğrulandı
        $area->fill($data);
        $area->save();

        return response()->json(['area' => $area->fresh()]);
    }

    public function destroy(Request $request, Area $area): JsonResponse
    {
        $this->authorize('delete', $area);

        // Masalar silinmez; alan bağı koparılır (nullOnDelete).
        $area->delete();

        return response()->json(['ok' => true]);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, bool $required): array
    {
        return $request->validate([
            'branch_id' => [$required ? 'required' : 'sometimes', 'integer'],
            'floor_id' => ['nullable', 'integer'],
            'name' => [$required ? 'required' : 'sometimes', 'string', 'max:100'],
            'type' => ['sometimes', Rule::enum(AreaType::class)],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:65000'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
    }

    /** Kat, aynı kiracının aynı şubesine ait olmalı (scoped sorgu). */
    private function resolveFloorId(mixed $floorId, int $branchId): ?int
    {
        if ($floorId === null || $floorId === '') {
            return null;
        }

        $floor = Floor::query()->where('branch_id', $branchId)->find((int) $floorId);

        if ($floor === null) {
            throw ValidationException::withMessages(['floor_id' => ['Kat bu şubede bulunamadı.']]);
        }

        return (int) $floor->id;
    }

    private function assertUniqueName(int $branchId, string $name, ?int $ignoreId = null): void
    {
        $exists = Area::query()
            ->where('branch_id', $branchId)
            ->where('name', $name)
            ->when($ignoreId !== null, fn ($q) => $q->whereKeyNot($ignoreId))
            ->exists();

        if ($exists) {
            throw ValidationException::withMessages(['name' => ['Bu şubede aynı adlı bir alan zaten var.']]);
        }
    }
}
