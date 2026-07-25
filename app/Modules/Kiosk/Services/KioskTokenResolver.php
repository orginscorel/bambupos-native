<?php

namespace App\Modules\Kiosk\Services;

use App\Modules\Kiosk\Models\KioskDevice;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;

/**
 * Kiosk cihaz token çözümleyici (masa QR deseninin birebir uyarlaması,
 * ADR-008): kiracı + şube YALNIZ opak token'dan çözülür; istekten kimlik
 * parametresi asla kabul edilmez. Public uçta bağlam yoktur — sorgular
 * bilinçli tenant-scope'suz çalışır; dönen cihazın tenant'ı sonraki yazma
 * işlemlerinde bağlama konarak kullanılır → bir kiosk başka işletmenin
 * menüsünü/siparişini token bilinmeden GÖREMEZ.
 */
class KioskTokenResolver
{
    /**
     * @return array{status: string, device: ?KioskDevice, tenant: ?Tenant, branch: ?Branch}
     *   status: ok | locked | revoked | inactive | invalid
     */
    public function resolve(string $token): array
    {
        $token = strtoupper(trim($token));

        // Biçim: 26 karakter base32 — uymayan girdi DB'ye inmez.
        if (preg_match('/^[A-Z2-7]{26}$/', $token) !== 1) {
            return $this->result('invalid');
        }

        $device = KioskDevice::withoutTenancy()->where('token', $token)->first();

        if ($device === null) {
            // Rotasyonla geçersiz kılınmış eski token → 410 (dürüst açıklama).
            $revoked = KioskDevice::withoutTenancy()->where('previous_token', $token)->exists();

            return $this->result($revoked ? 'revoked' : 'invalid');
        }

        $tenant = Tenant::query()->find($device->tenant_id);
        $branch = Branch::withoutTenancy()->find($device->branch_id);

        if ($tenant === null || ! $tenant->isActive() || $branch === null || ! $branch->is_active) {
            return $this->result('inactive', $device);
        }

        if ($device->isLocked()) {
            return $this->result('locked', $device, $tenant, $branch);
        }

        return $this->result('ok', $device, $tenant, $branch);
    }

    /** Kalp atışı izi: sağlık rozeti + son IP (panel). */
    public function touch(KioskDevice $device, ?string $ip): void
    {
        // Denetim kaydını kalp atışlarıyla doldurma (Auditable) — sessiz yaz.
        KioskDevice::withoutTenancy()->whereKey($device->getKey())->update([
            'last_seen_at' => now(),
            'last_ip' => $ip !== null ? mb_substr($ip, 0, 45) : null,
        ]);
    }

    /** @return array{status: string, device: ?KioskDevice, tenant: ?Tenant, branch: ?Branch} */
    private function result(string $status, ?KioskDevice $device = null, ?Tenant $tenant = null, ?Branch $branch = null): array
    {
        return ['status' => $status, 'device' => $device, 'tenant' => $tenant, 'branch' => $branch];
    }
}
