<?php

namespace App\Modules\Devices\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Devices\Models\AuthorizedDevice;
use App\Modules\Devices\Services\DeviceBindingService;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Kiosk\Models\KioskDevice;
use App\Modules\Settings\Support\Features;
use App\Modules\Terminal\Models\TerminalDevice;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use InvalidArgumentException;

/**
 * İzinli Cihazlar yönetimi (panel API'si, A3).
 *
 * Yetki: devices.view (salt-okunur liste) + devices.manage (ekle/kaldır,
 * izin kaldır/geri ver, boşa düşür, aktar). Tüm sorgular TenantScope
 * içinde çalışır (BelongsToTenant) — yabancı cihaz 404 (fail closed).
 */
class AuthorizedDeviceController extends Controller
{
    public function __construct(
        private readonly DeviceBindingService $binding,
        private readonly AuditLogger $audit,
    ) {
    }

    public function index(Request $request): JsonResponse
    {
        $this->authorizeView($request);

        $query = AuthorizedDevice::query()->orderByDesc('created_at');

        if ($request->filled('kind')) {
            $query->where('kind', (string) $request->query('kind'));
        }

        $devices = $query->get()->map(fn (AuthorizedDevice $d): array => $this->present($d))->values()->all();

        return response()->json([
            'devices' => $devices,
            'kinds' => AuthorizedDevice::KINDS,
        ]);
    }

    /**
     * SENKRON GÖRÜNÜM: gerçek terminal + kiosk cihazlarını (Terminaller/Kiosklar
     * ekranlarındaki AYNI cihazlar) hazır bağlantı + QR + cihaz-kilidi durumuyla
     * listeler. Böylece opak token elle girmeye gerek kalmaz: her cihazın kendi
     * /terminal/{token} veya /kiosk/{token} adresi + karekodu burada; o adresi
     * İLK açan fiziksel cihaz (device_lock AÇIKSA) kilitlenir.
     */
    public function synced(Request $request): JsonResponse
    {
        $this->authorizeView($request);

        $tenantId = (int) $request->user()->tenant_id;
        $lockEnabled = Features::enabled($tenantId, 'device_lock');

        $rows = [];

        foreach (TerminalDevice::query()->orderBy('name')->get() as $t) {
            $rows[] = $this->syncedRow(
                'terminal', (int) $t->id, $t->name ?: ('Terminal #'.$t->id),
                $t->station, (string) $t->token, (string) $t->status,
                $t->screenUrl(), $t->qrDataUri(), $t->last_seen_at,
            );
        }

        foreach (KioskDevice::query()->orderBy('name')->get() as $k) {
            $rows[] = $this->syncedRow(
                'kiosk', (int) $k->id, $k->name ?: ('Kiosk #'.$k->id),
                null, (string) $k->token, (string) $k->status,
                $k->screenUrl(), $k->qrDataUri(), $k->last_seen_at,
            );
        }

        return response()->json([
            'lock_enabled' => $lockEnabled,
            'devices' => $rows,
        ]);
    }

    /**
     * §13 Faz 3: "Terminaller & İzinli Cihazlar" köprüsü — cihaz kilidi
     * (device_lock) özelliğini panelin İZİNLİ CİHAZLAR/TERMİNALLER
     * ekranlarından TEK TIKLA aç/kapa. Depo AYNI: FeatureCatalog/
     * TenantFeature (bkz. App\Modules\Settings\Support\Features) — bu uç
     * yalnız Eklentiler ekranına gitmeden erişebilecek KISAYOLDUR, ayrı bir
     * durum SAKLAMAZ. devices.manage yetkisi yeterli (settings.manage şart
     * değil) çünkü bu ekranın doğrudan sorumluluğu budur.
     */
    public function toggleLock(Request $request): JsonResponse
    {
        $this->authorizeManage($request);

        $data = $request->validate([
            'enabled' => ['required', 'boolean'],
        ]);

        $tenantId = (int) $request->user()->tenant_id;
        $enabled = (bool) $data['enabled'];

        Features::set($tenantId, 'device_lock', $enabled);

        $this->audit->log('authorized_devices.lock_feature_toggled', null, null, ['enabled' => $enabled], $tenantId);

        return response()->json(['enabled' => $enabled]);
    }

    private function syncedRow(string $kind, int $id, string $name, ?string $station, string $token, string $status, string $url, string $qr, $lastSeen): array
    {
        $binding = AuthorizedDevice::query()
            ->where('kind', $kind)->where('bound_link', $token)->first();

        return [
            'source' => $kind,
            'source_id' => $id,
            'name' => $name,
            'station' => $station,
            'status' => $status,
            'token' => $token,
            'connect_url' => $url,
            'qr' => $qr,
            'device_last_seen_at' => $lastSeen?->toIso8601String(),
            'binding' => $binding ? [
                // AuthorizedDevice'ın kendi id'si — revoke/reactivate/release/transfer
                // panel aksiyonları bu id ile çağrılır (İzinli Cihazlar ekranı).
                'id' => (int) $binding->getKey(),
                'bound' => $binding->isBound(),
                'online' => $binding->isOnline(),
                'revoked' => $binding->isRevoked(),
                'last_ip' => $binding->meta['last_ip'] ?? null,
                'last_seen_at' => $binding->last_seen_at?->toIso8601String(),
            ] : null,
        ];
    }

    /** Bir terminal/kiosk bağlantısının cihaz kilidini boşa düşür (token ile). */
    public function releaseByToken(Request $request): JsonResponse
    {
        $this->authorizeManage($request);

        $data = $request->validate([
            'kind' => ['required', 'in:'.implode(',', AuthorizedDevice::KINDS)],
            'token' => ['required', 'string', 'max:64'],
        ]);

        $device = AuthorizedDevice::query()
            ->where('kind', $data['kind'])->where('bound_link', $data['token'])->first();

        if ($device === null) {
            return response()->json(['message' => 'Bu bağlantı henüz bir cihaza kilitlenmemiş.'], 404);
        }

        $this->binding->release($device);
        $this->audit->log('authorized_devices.released', $device);

        return response()->json(['ok' => true]);
    }

    /** Bir terminal/kiosk bağlantısını başka cihaza aktar (token ile). */
    public function transferByToken(Request $request): JsonResponse
    {
        $this->authorizeManage($request);

        $data = $request->validate([
            'kind' => ['required', 'in:'.implode(',', AuthorizedDevice::KINDS)],
            'token' => ['required', 'string', 'max:64'],
        ]);

        $device = AuthorizedDevice::query()
            ->where('kind', $data['kind'])->where('bound_link', $data['token'])->first();

        if ($device === null) {
            return response()->json(['message' => 'Bu bağlantı henüz bir cihaza kilitlenmemiş.'], 404);
        }

        $this->binding->transfer($device);
        $this->audit->log('authorized_devices.transferred', $device);

        return response()->json(['ok' => true]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorizeManage($request);

        $data = $request->validate([
            'kind' => ['required', 'in:'.implode(',', AuthorizedDevice::KINDS)],
            'name' => ['nullable', 'string', 'max:100'],
            'bound_link' => ['nullable', 'string', 'max:255'],
        ]);

        try {
            $device = $this->binding->provision(
                $data['kind'],
                $data['name'] ?? null,
                $data['bound_link'] ?? null,
            );
        } catch (InvalidArgumentException $e) {
            return response()->json([
                'message' => $e->getMessage(),
                'errors' => ['bound_link' => [$e->getMessage()]],
            ], 422);
        }

        $this->audit->log('authorized_devices.provisioned', $device, null, $device->attributesToArray());

        return response()->json(['device' => $this->present($device, revealToken: true)], 201);
    }

    public function update(Request $request, AuthorizedDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $data = $request->validate([
            'name' => ['sometimes', 'nullable', 'string', 'max:100'],
            'bound_link' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);

        if (array_key_exists('bound_link', $data) && $device->isBound()) {
            return response()->json([
                'message' => 'Bağlı bir cihazın hedefi değiştirilemez; önce "Boşa düşür" kullanın.',
                'errors' => ['bound_link' => ['Bağlı bir cihazın hedefi değiştirilemez; önce "Boşa düşür" kullanın.']],
            ], 422);
        }

        $device->fill(array_intersect_key($data, array_flip(['name', 'bound_link'])));
        $device->save();

        return response()->json(['device' => $this->present($device)]);
    }

    public function revoke(Request $request, AuthorizedDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $before = $device->attributesToArray();
        $this->binding->revoke($device);
        $this->audit->log('authorized_devices.revoked', $device, $before, $device->attributesToArray());

        return response()->json(['device' => $this->present($device)]);
    }

    public function reactivate(Request $request, AuthorizedDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $before = $device->attributesToArray();
        $this->binding->reactivate($device);
        $this->audit->log('authorized_devices.reactivated', $device, $before, $device->attributesToArray());

        return response()->json(['device' => $this->present($device)]);
    }

    /** Boşa düşür: aynı hedef için yeni bir cihaz bağlanabilsin diye mevcut bağı çöz. */
    public function release(Request $request, AuthorizedDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $before = $device->attributesToArray();
        $this->binding->release($device);
        $this->audit->log('authorized_devices.released', $device, $before, $device->attributesToArray());

        return response()->json(['device' => $this->present($device, revealToken: true)]);
    }

    /** Başka cihaza aktar: release ile aynı mekanik, niyet farklı (kaybolan/değişen cihaz). */
    public function transfer(Request $request, AuthorizedDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $before = $device->attributesToArray();
        $this->binding->transfer($device);
        $this->audit->log('authorized_devices.transferred', $device, $before, $device->attributesToArray());

        return response()->json(['device' => $this->present($device, revealToken: true)]);
    }

    public function destroy(Request $request, AuthorizedDevice $device): JsonResponse
    {
        $this->authorizeManage($request);

        $this->audit->log('authorized_devices.deleted', $device, $device->attributesToArray(), null);
        $device->delete();

        return response()->json([], 204);
    }

    /* ---------------------------------------------------------- */

    private function authorizeManage(Request $request): void
    {
        abort_unless($request->user()->hasPermission('devices.manage'), 403);
    }

    private function authorizeView(Request $request): void
    {
        abort_unless(
            $request->user()->hasPermission('devices.view')
                || $request->user()->hasPermission('devices.manage'),
            403,
        );
    }

    /** @return array<string, mixed> */
    private function present(AuthorizedDevice $d, bool $revealToken = false): array
    {
        return [
            'id' => (int) $d->getKey(),
            'kind' => $d->kind,
            'name' => $d->name,
            'bound_link' => $d->bound_link,
            'status' => $d->status,
            'bound' => $d->isBound(),
            'online' => $d->isOnline(),
            'last_seen_at' => $d->last_seen_at?->toIso8601String(),
            'first_bound_at' => $d->first_bound_at?->toIso8601String(),
            'last_ip' => $d->meta['last_ip'] ?? null,
            'created_at' => $d->created_at?->toIso8601String(),
            // Yalnız provision/release/transfer sonrası bir kereliğine
            // döndürülür — admin bunu hedef cihaza (?dt=...) vermek için kullanır.
            'claim_token' => $revealToken ? $d->device_token : null,
            'claim_query_param' => $revealToken ? DeviceBindingService::CLAIM_QUERY_PARAM : null,
        ];
    }
}
