<?php

namespace App\Modules\Kiosk\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Kiosk\Models\KioskDevice;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Kiosk cihaz yönetimi (panel API'si, Faz 8).
 *
 * Yetki: kiosk.view (salt-okunur liste/sağlık) + kiosk.manage (cihaz
 * ekle/kaldır, token yenile, uzaktan kilit/aç). Kiosk kendi izin
 * namespace'ine sahiptir (authz kataloğu 'kiosk'); ileride "Eklentiler"
 * feature-flag'i de bu izinlere yaslanır. Tüm sorgular oturumdaki
 * kiracının TenantScope'u içinde çalışır; yabancı cihaz 404 (fail closed).
 */
class KioskDeviceController extends Controller
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $this->authorizeView($request);

        $devices = KioskDevice::query()
            ->with('branch:id,name')
            ->orderBy('name')
            ->get()
            ->map(fn (KioskDevice $d): array => $this->present($d))
            ->values()
            ->all();

        $branches = Branch::query()->where('is_active', true)
            ->orderBy('name')->get(['id', 'name'])
            ->map(fn (Branch $b) => ['id' => (int) $b->id, 'name' => $b->name])
            ->values()->all();

        return response()->json(['devices' => $devices, 'branches' => $branches]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorizeManage($request);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'branch_id' => ['required', 'integer'],
            'payment_mode' => ['required', 'in:kiosk_pos,counter'],
        ]);

        $branch = Branch::query()->find((int) $data['branch_id']);

        if ($branch === null) {
            return response()->json([
                'message' => 'Şube bulunamadı.',
                'errors' => ['branch_id' => ['Şube bulunamadı.']],
            ], 422);
        }

        $device = new KioskDevice([
            'name' => $data['name'],
            'payment_mode' => $data['payment_mode'],
            'status' => KioskDevice::STATUS_ACTIVE,
        ]);
        $device->branch_id = (int) $branch->getKey();
        $device->save();

        return response()->json(['device' => $this->present($device->fresh('branch'))], 201);
    }

    public function update(Request $request, KioskDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $data = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:100'],
            'branch_id' => ['sometimes', 'required', 'integer'],
            'payment_mode' => ['sometimes', 'required', 'in:kiosk_pos,counter'],
        ]);

        if (array_key_exists('branch_id', $data)) {
            $branch = Branch::query()->find((int) $data['branch_id']);

            if ($branch === null) {
                return response()->json([
                    'message' => 'Şube bulunamadı.',
                    'errors' => ['branch_id' => ['Şube bulunamadı.']],
                ], 422);
            }

            $device->branch_id = (int) $branch->getKey();
        }

        $device->fill(array_intersect_key($data, array_flip(['name', 'payment_mode'])));
        $device->save();

        return response()->json(['device' => $this->present($device->fresh('branch'))]);
    }

    /** Token rotasyonu: eski adres ANINDA geçersiz (410); yeni adres döner. */
    public function rotateToken(Request $request, KioskDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $device->rotateToken();

        $this->audit->log('kiosk.token_rotated', $device, null, [
            'device_id' => $device->getKey(),
            'performed_by' => $request->user()->getKey(),
        ]);

        return response()->json(['device' => $this->present($device->fresh('branch'))]);
    }

    /** Uzaktan kilit: cihaz bir sonraki kalp atışında kilit ekranına düşer. */
    public function lock(Request $request, KioskDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $device->status = KioskDevice::STATUS_LOCKED;
        $device->locked_at = now();
        $device->save();

        return response()->json(['device' => $this->present($device->fresh('branch'))]);
    }

    public function unlock(Request $request, KioskDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $device->status = KioskDevice::STATUS_ACTIVE;
        $device->locked_at = null;
        $device->save();

        return response()->json(['device' => $this->present($device->fresh('branch'))]);
    }

    public function destroy(Request $request, KioskDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $this->audit->log('kiosk.device_deleted', $device, $device->attributesToArray(), [
            'performed_by' => $request->user()->getKey(),
        ]);

        $device->delete();

        return response()->json([], 204);
    }

    /* ---------------------------------------------------------- */

    private function authorizeManage(Request $request): void
    {
        abort_unless($request->user()->hasPermission('kiosk.manage'), 403);
    }

    private function authorizeView(Request $request): void
    {
        // Salt-okunur liste/sağlık: manage yetkisi de görebilir (kapsar).
        abort_unless(
            $request->user()->hasPermission('kiosk.view')
                || $request->user()->hasPermission('kiosk.manage'),
            403,
        );
    }

    /** @return array<string, mixed> */
    private function present(KioskDevice $d): array
    {
        return [
            'id' => (int) $d->getKey(),
            'name' => $d->name,
            'branch_id' => (int) $d->branch_id,
            'branch_name' => $d->branch?->name,
            'status' => $d->status,
            'payment_mode' => $d->payment_mode,
            'url' => $d->screenUrl(),
            'online' => $d->isOnline(),
            'last_seen_at' => $d->last_seen_at?->toIso8601String(),
            'last_ip' => $d->last_ip,
            'locked_at' => $d->locked_at?->toIso8601String(),
            'token_rotated_at' => $d->token_rotated_at?->toIso8601String(),
            'created_at' => $d->created_at?->toIso8601String(),
        ];
    }
}
