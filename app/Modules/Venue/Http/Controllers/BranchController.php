<?php

namespace App\Modules\Venue\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Venue\Models\Area;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Şube yönetimi. Branch modeli Tenancy modülünündür; burada yalnız
 * kullanılır (değiştirilmez). Global scope + BranchPolicy: yabancı şube 404.
 */
class BranchController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Branch::class);

        $branches = Branch::query()
            ->orderBy('name')
            ->get()
            ->map(function (Branch $branch): array {
                return [
                    'id' => $branch->id,
                    'name' => $branch->name,
                    'code' => $branch->code,
                    'address' => $branch->address,
                    'phone' => $branch->phone,
                    'timezone' => $branch->timezone,
                    'is_active' => $branch->is_active,
                    'has_qr_token' => $branch->qr_token !== null,
                    'areas_count' => Area::query()->where('branch_id', $branch->id)->count(),
                    'tables_count' => Table::query()->where('branch_id', $branch->id)->count(),
                ];
            });

        return response()->json(['branches' => $branches]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Branch::class);

        $data = $this->validated($request);

        $branch = new Branch($data);
        $branch->save(); // tenant_id bağlamdan (BelongsToTenant)

        return response()->json(['branch' => $branch], 201);
    }

    public function update(Request $request, Branch $branch): JsonResponse
    {
        $this->authorize('update', $branch);

        $branch->update($this->validated($request, $branch));

        return response()->json(['branch' => $branch->fresh()]);
    }

    public function destroy(Request $request, Branch $branch): JsonResponse
    {
        $this->authorize('delete', $branch);

        if (Table::query()->where('branch_id', $branch->id)->exists()) {
            throw ValidationException::withMessages([
                'branch' => ['Bu şubede masalar var; önce masaları silin veya taşıyın.'],
            ]);
        }

        if (Branch::query()->count() <= 1) {
            throw ValidationException::withMessages([
                'branch' => ['Son şube silinemez; işletmenin en az bir şubesi olmalıdır.'],
            ]);
        }

        $branch->delete();

        return response()->json(['ok' => true]);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, ?Branch $branch = null): array
    {
        $tenantId = (int) $request->user()->tenant_id;

        return $request->validate([
            'name' => [$branch === null ? 'required' : 'sometimes', 'string', 'max:255'],
            'code' => [
                'nullable', 'string', 'max:32',
                Rule::unique('branches', 'code')
                    ->where('tenant_id', $tenantId)
                    ->ignore($branch?->id),
            ],
            'address' => ['nullable', 'string', 'max:500'],
            'phone' => ['nullable', 'string', 'max:32'],
            'timezone' => ['sometimes', 'string', 'max:64', 'timezone:all'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
    }
}
