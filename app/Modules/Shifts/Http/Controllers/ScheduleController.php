<?php

namespace App\Modules\Shifts\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Shifts\Models\Shift;
use App\Modules\Shifts\Models\ShiftSetting;
use App\Modules\Shifts\Services\ShiftPlanner;
use App\Modules\Tenancy\Models\Branch;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Vardiya planlama uçları: takvim verisi + vardiya CRUD.
 *
 * - staff.view yoksa yalnız KENDİ vardiyaları döner.
 * - Yazma işlemleri staff.manage ister.
 * - Çakışma: 422 + 'conflicts'; allow_overlap=true ile bilinçli aşılır.
 */
class ScheduleController extends Controller
{
    public function __construct(private readonly ShiftPlanner $planner)
    {
    }

    /** Planlayıcı meta verisi: personel, şubeler, pozisyonlar, ayarlar. */
    public function meta(Request $request): JsonResponse
    {
        $user = $request->user();
        $canView = $user->hasPermission('staff.view') || $user->hasPermission('staff.manage');

        $staff = $canView
            ? User::ofCurrentTenant()
                ->where('is_active', true)
                ->orderBy('name')
                ->get(['id', 'name', 'position', 'branch_id', 'staff_code'])
            : User::ofCurrentTenant()->whereKey($user->id)->get(['id', 'name', 'position', 'branch_id', 'staff_code']);

        $positions = User::ofCurrentTenant()
            ->where('is_active', true)
            ->whereNotNull('position')
            ->where('position', '!=', '')
            ->distinct()
            ->pluck('position');

        $settings = ShiftSetting::current();

        return response()->json([
            'staff' => $staff,
            'branches' => Branch::query()->where('is_active', true)->orderBy('name')->get(['id', 'name']),
            'positions' => $positions,
            'default_break_min' => $settings->default_break_min,
            'can' => [
                'view_all' => $canView,
                'manage' => $user->hasPermission('staff.manage'),
            ],
        ]);
    }

    /** Takvim verisi (vardiyalar + onaylı izinler + min. personel uyarıları). */
    public function schedule(Request $request): JsonResponse
    {
        $data = $request->validate([
            'from' => ['required', 'date'],
            'to' => ['required', 'date', 'after:from'],
            'branch_id' => ['nullable', 'integer'],
        ]);

        $user = $request->user();
        $canViewAll = $user->hasPermission('staff.view') || $user->hasPermission('staff.manage');

        $result = $this->planner->schedule(
            CarbonImmutable::parse($data['from']),
            CarbonImmutable::parse($data['to']),
            isset($data['branch_id']) ? (int) $data['branch_id'] : null,
            $canViewAll ? null : (int) $user->id,
        );

        return response()->json($result);
    }

    public function store(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        $data = $request->validate([
            'branch_id' => ['required', 'integer'],
            'user_id' => ['required', 'integer'],
            'position' => ['nullable', 'string', 'max:80'],
            'starts_at' => ['required', 'date'],
            'ends_at' => ['required', 'date'],
            'break_min' => ['nullable', 'integer', 'min:0', 'max:480'],
            'note' => ['nullable', 'string', 'max:255'],
            'repeat_weeks' => ['nullable', 'integer', 'min:0', 'max:26'],
            'allow_overlap' => ['nullable', 'boolean'],
        ]);

        // Kiracı doğrulaması: personel ve şube bağlamdaki kiracıya ait olmalı.
        abort_unless(User::ofCurrentTenant()->whereKey($data['user_id'])->exists(), 404);
        abort_unless(Branch::query()->whereKey($data['branch_id'])->exists(), 404);

        $result = $this->planner->create($data);

        return response()->json([
            'shifts' => collect($result['shifts'])->map(fn (Shift $s) => $this->present($s->load('user:id,name,position'))),
            'skipped' => $result['skipped'],
        ], 201);
    }

    public function update(Request $request, Shift $shift): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        $data = $request->validate([
            'branch_id' => ['sometimes', 'integer'],
            'user_id' => ['sometimes', 'integer'],
            'position' => ['sometimes', 'nullable', 'string', 'max:80'],
            'starts_at' => ['sometimes', 'date'],
            'ends_at' => ['sometimes', 'date'],
            'break_min' => ['sometimes', 'integer', 'min:0', 'max:480'],
            'note' => ['sometimes', 'nullable', 'string', 'max:255'],
            'allow_overlap' => ['nullable', 'boolean'],
        ]);

        if (isset($data['user_id'])) {
            abort_unless(User::ofCurrentTenant()->whereKey($data['user_id'])->exists(), 404);
        }

        if (isset($data['branch_id'])) {
            abort_unless(Branch::query()->whereKey($data['branch_id'])->exists(), 404);
        }

        $shift = $this->planner->update($shift, $data);

        return response()->json(['shift' => $this->present($shift->load('user:id,name,position'))]);
    }

    public function destroy(Request $request, Shift $shift): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        // İsteğe bağlı: tekrar serisinin gelecekteki tümünü sil.
        if ($request->boolean('with_series') && $shift->repeat_group !== null) {
            Shift::query()
                ->where('repeat_group', $shift->repeat_group)
                ->where('starts_at', '>=', $shift->starts_at)
                ->delete();
        } else {
            $shift->delete();
        }

        return response()->json(null, 204);
    }

    /** @return array<string, mixed> */
    private function present(Shift $shift): array
    {
        return [
            'id' => $shift->id,
            'branch_id' => $shift->branch_id,
            'user_id' => $shift->user_id,
            'user' => $shift->relationLoaded('user') && $shift->user !== null
                ? ['id' => $shift->user->id, 'name' => $shift->user->name, 'position' => $shift->user->position]
                : null,
            'position' => $shift->position,
            'starts_at' => $shift->starts_at->toIso8601String(),
            'ends_at' => $shift->ends_at->toIso8601String(),
            'break_min' => $shift->break_min,
            'note' => $shift->note,
            'repeat_group' => $shift->repeat_group,
        ];
    }
}
