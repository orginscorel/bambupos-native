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
                    'showcase' => $branch->showcase,
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

        // ŞUBE KAPSAMI: çok-şube (branches feature) kapalıysa tek-şube modu —
        // yeni şube eklenemez.
        abort_unless(
            \App\Modules\Settings\Support\Features::enabled((int) $request->user()->tenant_id, 'branches'),
            403,
            'Çok şube özelliği kapalı; yeni şube eklenemez.'
        );

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

            // İşletme Vitrini (public QR menüsünde görünen bilgi kartı).
            'showcase' => ['sometimes', 'nullable', 'array'],
            'showcase.wifi_ssid' => ['nullable', 'string', 'max:64'],
            'showcase.wifi_password' => ['nullable', 'string', 'max:128'],
            'showcase.maps_url' => ['nullable', 'url', 'max:500'],
            'showcase.show_map' => ['sometimes', 'boolean'],
            'showcase.hours' => ['nullable', 'array', 'max:7'],
            'showcase.hours.*.d' => ['required_with:showcase.hours', 'integer', 'between:0,6'],
            'showcase.hours.*.closed' => ['sometimes', 'boolean'],
            'showcase.hours.*.open' => ['nullable', 'date_format:H:i'],
            'showcase.hours.*.close' => ['nullable', 'date_format:H:i'],
            'showcase.social' => ['nullable', 'array'],
            'showcase.social.instagram' => ['nullable', 'string', 'max:120'],
            'showcase.social.facebook' => ['nullable', 'string', 'max:120'],
            'showcase.social.x' => ['nullable', 'string', 'max:120'],
            'showcase.social.tiktok' => ['nullable', 'string', 'max:120'],
            'showcase.social.youtube' => ['nullable', 'string', 'max:120'],
            'showcase.social.whatsapp' => ['nullable', 'string', 'max:32'],
            'showcase.social.website' => ['nullable', 'string', 'max:200'],
        ]);
    }
}
