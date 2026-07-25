<?php

namespace App\Modules\Shifts\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Shifts\Models\ClockDevice;
use App\Modules\Shifts\Models\LocationConsent;
use App\Modules\Shifts\Models\ShiftSetting;
use App\Modules\Shifts\Models\TimeEntry;
use App\Modules\Shifts\Services\TimeClockService;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;

/**
 * İşe giriş/çıkış uçları.
 *
 * İki kanal:
 *  1. /api/v1/shifts/clock — panel kiosk ekranı (oturumlu bir cihaz açar;
 *     kimlik PIN'den çözülür, oturum sahibinden DEĞİL).
 *  2. /api/v1/shifts/device-clock — yetkili cihaz (X-Device-Token başlığı,
 *     oturumsuz; kiracı kimliği CİHAZDAN gelir). NFC/QR okuyucular ileride
 *     bu ucu kullanır (method alanı hazır).
 *
 * KVKK: lat/lng isteğe bağlıdır; işletme ayarı kapalıysa veya personel
 * rızası yoksa TimeClockService koordinatı hiç saklamaz.
 */
class ClockController extends Controller
{
    public function __construct(private readonly TimeClockService $clock)
    {
    }

    /** Panel kiosk ucu (oturumlu). */
    public function clock(Request $request): JsonResponse
    {
        $this->throttle('clock:'.$request->ip());

        return $this->handle($request, method: 'pin', device: null);
    }

    /** Yetkili cihaz ucu (oturumsuz; X-Device-Token). */
    public function deviceClock(Request $request): JsonResponse
    {
        $this->throttle('device-clock:'.$request->ip());

        $token = (string) $request->header('X-Device-Token', '');
        $device = $token !== '' ? ClockDevice::findByToken($token) : null;

        if ($device === null) {
            return response()->json(['message' => 'Cihaz doğrulanamadı.'], 401);
        }

        // Kiracı bağlamı cihazdan kurulur (istek parametresinden ASLA).
        app(TenantContext::class)->setTenant((int) $device->tenant_id);

        $device->forceFill(['last_seen_at' => now()])->save();

        return $this->handle($request, method: 'device', device: $device);
    }

    private function handle(Request $request, string $method, ?ClockDevice $device): JsonResponse
    {
        $data = $request->validate([
            'action' => ['required', 'in:status,in,out,break_start,break_end'],
            'pin' => ['required', 'string', 'max:10'],
            'staff_code' => ['nullable', 'string', 'max:32'],
            'branch_id' => ['nullable', 'integer'],
            'lat' => ['nullable', 'numeric', 'between:-90,90'],
            'lng' => ['nullable', 'numeric', 'between:-180,180'],
        ]);

        $user = $this->clock->identifyByPin($data['pin'], $data['staff_code'] ?? null);

        $ctx = [
            'branch_id' => $device?->branch_id ?? (isset($data['branch_id']) ? (int) $data['branch_id'] : null),
            'method' => $method,
            'device' => $device,
            'ip' => $request->ip(),
            'lat' => isset($data['lat']) ? (float) $data['lat'] : null,
            'lng' => isset($data['lng']) ? (float) $data['lng'] : null,
        ];

        $entry = match ($data['action']) {
            'in' => $this->clock->clockIn($user, $ctx),
            'out' => $this->clock->clockOut($user, $ctx),
            'break_start' => $this->clock->breakStart($user)->timeEntry,
            'break_end' => $this->clock->breakEnd($user)->timeEntry,
            default => $this->clock->openEntryFor($user),
        };

        if ($entry !== null) {
            $entry->loadMissing('breaks');
        }

        return response()->json([
            'user' => ['id' => $user->id, 'name' => $user->name, 'position' => $user->position],
            'state' => $this->stateOf($user, $entry),
            'entry' => $entry === null ? null : $this->presentEntry($entry),
        ]);
    }

    /** Kiosk ekranı meta: konum takibi durumu (KVKK bilgilendirmesi için). */
    public function clockMeta(Request $request): JsonResponse
    {
        $settings = ShiftSetting::current();
        $user = $request->user();

        return response()->json([
            'location_tracking_enabled' => $settings->location_tracking_enabled,
            'location_policy' => $settings->location_tracking_enabled ? $settings->location_policy : null,
            'my_consent' => $user !== null && LocationConsent::activeFor((int) $user->id),
        ]);
    }

    /** @return array{status: string, on_break: bool} */
    private function stateOf(User $user, ?TimeEntry $entry): array
    {
        if ($entry === null || ! $entry->isOpen()) {
            return ['status' => $entry === null ? 'off' : 'closed', 'on_break' => false];
        }

        return ['status' => 'working', 'on_break' => $entry->openBreak() !== null];
    }

    /** @return array<string, mixed> */
    private function presentEntry(TimeEntry $entry): array
    {
        return [
            'id' => $entry->id,
            'clock_in_at' => $entry->clock_in_at->toIso8601String(),
            'clock_out_at' => $entry->clock_out_at?->toIso8601String(),
            'status' => $entry->status,
            'break_total_min' => $entry->break_total_min,
            'worked_min' => $entry->worked_min,
            'overtime_min' => $entry->overtime_min,
            'late_min' => $entry->late_min,
            'early_leave_min' => $entry->early_leave_min,
            'breaks' => $entry->breaks->map(fn ($b) => [
                'started_at' => $b->started_at->toIso8601String(),
                'ended_at' => $b->ended_at?->toIso8601String(),
            ]),
        ];
    }

    private function throttle(string $key): void
    {
        if (RateLimiter::tooManyAttempts($key, 20)) {
            throw ValidationException::withMessages([
                'pin' => ['Çok fazla deneme; lütfen bekleyin.'],
            ])->status(429);
        }

        RateLimiter::hit($key, 60);
    }
}
