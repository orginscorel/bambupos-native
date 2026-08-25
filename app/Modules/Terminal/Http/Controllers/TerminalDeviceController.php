<?php

namespace App\Modules\Terminal\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Terminal\Models\TerminalDevice;
use App\Modules\Terminal\Services\TerminalProvisioner;
use App\Modules\Terminal\Support\TerminalLicense;
use App\Modules\Terminal\Support\TerminalStation;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Terminal cihaz yönetimi (panel API'si, §13 Faz A).
 *
 * Yetki: terminals.view (salt-okunur liste/sağlık) + terminals.manage (cihaz
 * ekle/kaldır, token yenile, uzaktan kilit/aç). Kiosk cihaz-yönetim deseninin
 * aynısı; ek olarak her cihaz bir GİZLİ terminal kullanıcısı üretir/siler
 * (TerminalProvisioner). Tüm sorgular oturumdaki kiracının TenantScope'u
 * içinde çalışır; yabancı cihaz 404 (fail closed).
 */
class TerminalDeviceController extends Controller
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly TerminalProvisioner $provisioner,
    ) {
    }

    public function index(Request $request): JsonResponse
    {
        $this->authorizeView($request);

        $devices = TerminalDevice::query()
            ->with('branch:id,name')
            ->orderBy('name')
            ->get()
            ->map(fn (TerminalDevice $d): array => $this->present($d))
            ->values()
            ->all();

        $branches = Branch::query()->where('is_active', true)
            ->orderBy('name')->get(['id', 'name'])
            ->map(fn (Branch $b) => ['id' => (int) $b->id, 'name' => $b->name])
            ->values()->all();

        return response()->json([
            'devices' => $devices,
            'branches' => $branches,
            'stations' => TerminalStation::options(),
            // §13 Faz 3: panelde "3/5 terminal lisansı kullanıldı" göstergesi.
            'license' => TerminalLicense::snapshot($this->tenantOf($request)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorizeManage($request);

        $tenant = $this->tenantOf($request);

        // §13 Faz 3: lisans limiti — aşılınca net, eylem çağıran 422.
        if (! TerminalLicense::hasCapacity($tenant)) {
            $message = TerminalLicense::limitReachedMessage($tenant);

            return response()->json([
                'message' => $message,
                'errors' => ['license' => [$message]],
            ], 422);
        }

        $data = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'branch_id' => ['required', 'integer'],
            'station' => ['required', 'string', Rule::in(TerminalStation::keys())],
        ]);

        $branch = Branch::query()->find((int) $data['branch_id']);

        if ($branch === null) {
            return response()->json([
                'message' => 'Şube bulunamadı.',
                'errors' => ['branch_id' => ['Şube bulunamadı.']],
            ], 422);
        }

        $device = $this->provisioner->createDevice(
            $data['name'],
            (int) $branch->getKey(),
            (int) $request->user()->tenant_id,
            $data['station'],
        );

        $this->audit->log('terminal.device_created', $device, null, [
            'station' => $device->station,
            'performed_by' => $request->user()->getKey(),
        ]);

        return response()->json(['device' => $this->present($device->fresh('branch'))], 201);
    }

    public function update(Request $request, TerminalDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $data = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:100'],
            'branch_id' => ['sometimes', 'required', 'integer'],
            'station' => ['sometimes', 'required', 'string', Rule::in(TerminalStation::keys())],
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

        $device->fill(array_intersect_key($data, array_flip(['name', 'station'])));
        $device->save();

        // Gizli kullanıcıyı hizala (ad/şube/istasyon + izin + kds_user_stations).
        $this->provisioner->syncDevice($device);

        return response()->json(['device' => $this->present($device->fresh('branch'))]);
    }

    /** Token rotasyonu: eski adres ANINDA geçersiz (410); yeni adres döner. */
    public function rotateToken(Request $request, TerminalDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $device->rotateToken();

        $this->audit->log('terminal.token_rotated', $device, null, [
            'device_id' => $device->getKey(),
            'performed_by' => $request->user()->getKey(),
        ]);

        return response()->json(['device' => $this->present($device->fresh('branch'))]);
    }

    /** Uzaktan kilit: cihaz bir sonraki açılışında kilit ekranına düşer. */
    public function lock(Request $request, TerminalDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $device->status = TerminalDevice::STATUS_INACTIVE;
        $device->locked_at = now();
        $device->save();

        $this->audit->log('terminal.device_locked', $device, null, [
            'performed_by' => $request->user()->getKey(),
        ]);

        return response()->json(['device' => $this->present($device->fresh('branch'))]);
    }

    public function unlock(Request $request, TerminalDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $device->status = TerminalDevice::STATUS_ACTIVE;
        $device->locked_at = null;
        $device->save();

        return response()->json(['device' => $this->present($device->fresh('branch'))]);
    }

    public function destroy(Request $request, TerminalDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $this->audit->log('terminal.device_deleted', $device, $device->attributesToArray(), [
            'performed_by' => $request->user()->getKey(),
        ]);

        // Cihaz + gizli kullanıcı + istasyon ataması + izinler temizlenir.
        $this->provisioner->deleteDevice($device);

        return response()->json([], 204);
    }

    /* ---------------------------------------------------------- */

    private function authorizeManage(Request $request): void
    {
        abort_unless($request->user()->hasPermission('terminals.manage'), 403);
    }

    private function authorizeView(Request $request): void
    {
        abort_unless(
            $request->user()->hasPermission('terminals.view')
                || $request->user()->hasPermission('terminals.manage'),
            403,
        );
    }

    /** Oturumdaki kiracı (lisans sütununun kaynağı; id istekten ASLA alınmaz). */
    private function tenantOf(Request $request): Tenant
    {
        return Tenant::query()->findOrFail((int) $request->user()->tenant_id);
    }

    /** @return array<string, mixed> */
    private function present(TerminalDevice $d): array
    {
        return [
            'id' => (int) $d->getKey(),
            'name' => $d->name,
            'station' => $d->station,
            'station_label' => TerminalStation::labelFor($d->station),
            'branch_id' => (int) $d->branch_id,
            'branch_name' => $d->branch?->name,
            'status' => $d->status,
            'url' => $d->screenUrl(),
            'qr' => $d->qrDataUri(),
            'online' => $d->isOnline(),
            'last_seen_at' => $d->last_seen_at?->toIso8601String(),
            'last_ip' => $d->last_ip,
            'locked_at' => $d->locked_at?->toIso8601String(),
            'token_rotated_at' => $d->token_rotated_at?->toIso8601String(),
            'created_at' => $d->created_at?->toIso8601String(),
        ];
    }
}
