<?php

namespace App\Modules\Shifts\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Shifts\Models\ClockDevice;
use App\Modules\Shifts\Models\LocationConsent;
use App\Modules\Shifts\Models\ShiftSetting;
use App\Modules\Shifts\Models\StaffingRule;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * Mesai ayarları + KVKK konum rızası + yetkili cihazlar + min. personel
 * kuralları.
 *
 * KVKK (prompt §7): konum takibi VARSAYILAN KAPALIDIR; açmak için politika
 * metni zorunludur. Açılsa bile personel rıza vermedikçe konum yazılmaz.
 */
class ShiftSettingController extends Controller
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    /* ---------------- Ayarlar ---------------- */

    public function show(Request $request): JsonResponse
    {
        $settings = ShiftSetting::current();
        $canManage = $request->user()->hasPermission('staff.manage');

        return response()->json([
            'settings' => $canManage ? $settings : $settings->only([
                'location_tracking_enabled', 'location_policy',
            ]),
            'my_consent' => LocationConsent::activeFor((int) $request->user()->id),
        ]);
    }

    public function update(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        $data = $request->validate([
            'standard_daily_min' => ['sometimes', 'integer', 'min:60', 'max:1440'],
            'late_tolerance_min' => ['sometimes', 'integer', 'min:0', 'max:120'],
            'early_leave_tolerance_min' => ['sometimes', 'integer', 'min:0', 'max:120'],
            'default_break_min' => ['sometimes', 'integer', 'min:0', 'max:240'],
            'location_tracking_enabled' => ['sometimes', 'boolean'],
            // Konum takibi açılıyorsa politika metni ZORUNLU (KVKK aydınlatma).
            'location_policy' => ['required_if_accepted:location_tracking_enabled', 'nullable', 'string', 'max:5000'],
        ]);

        $settings = ShiftSetting::current();
        $settings->fill($data)->save();

        return response()->json(['settings' => $settings]);
    }

    /* ---------------- KVKK rızası (personelin kendisi) ---------------- */

    public function giveConsent(Request $request): JsonResponse
    {
        $user = $request->user();

        $consent = LocationConsent::query()->firstOrNew(['user_id' => $user->id]);
        $consent->consented_at = now();
        $consent->revoked_at = null;
        $consent->save();

        $this->audit->log('shifts.location_consent_given', $consent);

        return response()->json(['consent' => true]);
    }

    public function revokeConsent(Request $request): JsonResponse
    {
        $user = $request->user();

        $consent = LocationConsent::query()->where('user_id', $user->id)->first();

        if ($consent !== null && $consent->revoked_at === null) {
            $consent->revoked_at = now();
            $consent->save();

            $this->audit->log('shifts.location_consent_revoked', $consent);
        }

        return response()->json(['consent' => false]);
    }

    /* ---------------- Yetkili cihazlar ---------------- */

    public function devices(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        return response()->json([
            'devices' => ClockDevice::query()
                ->with('branch:id,name')
                ->orderBy('name')
                ->get(['id', 'branch_id', 'name', 'is_active', 'last_seen_at', 'created_at']),
        ]);
    }

    /** Cihaz kaydı: token yalnız BU yanıtta bir kez görünür. */
    public function storeDevice(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'branch_id' => ['nullable', 'integer'],
        ]);

        if (isset($data['branch_id'])) {
            abort_unless(Branch::query()->whereKey($data['branch_id'])->exists(), 404);
        }

        $token = Str::random(40);

        $device = new ClockDevice([
            'name' => $data['name'],
            'branch_id' => $data['branch_id'] ?? null,
            'is_active' => true,
        ]);
        $device->token_hash = ClockDevice::hashToken($token);
        $device->created_by_id = $request->user()->id;
        $device->save();

        return response()->json(['device' => $device, 'token' => $token], 201);
    }

    public function destroyDevice(Request $request, ClockDevice $device): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        $device->delete();

        return response()->json(null, 204);
    }

    /* ---------------- Minimum personel kuralları ---------------- */

    public function staffingRules(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        return response()->json([
            'rules' => StaffingRule::query()->with('branch:id,name')->orderBy('id')->get(),
        ]);
    }

    public function storeStaffingRule(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        $data = $request->validate([
            'branch_id' => ['required', 'integer'],
            'weekday' => ['nullable', 'integer', 'min:0', 'max:6'],
            'position' => ['nullable', 'string', 'max:80'],
            'min_count' => ['required', 'integer', 'min:1', 'max:500'],
        ]);

        abort_unless(Branch::query()->whereKey($data['branch_id'])->exists(), 404);

        $rule = StaffingRule::query()->create($data);

        return response()->json(['rule' => $rule->load('branch:id,name')], 201);
    }

    public function destroyStaffingRule(Request $request, StaffingRule $rule): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        $rule->delete();

        return response()->json(null, 204);
    }
}
