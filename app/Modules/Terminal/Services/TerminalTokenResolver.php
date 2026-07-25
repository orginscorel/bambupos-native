<?php

namespace App\Modules\Terminal\Services;

use App\Modules\Terminal\Models\TerminalDevice;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;

/**
 * Terminal cihaz token çözümleyici (KioskTokenResolver'ın birebir deseni,
 * ADR-008): kiracı + şube + istasyon YALNIZ opak token'dan çözülür; istekten
 * kimlik parametresi asla kabul edilmez. Terminal uçta oturum henüz yoktur —
 * sorgular bilinçli tenant-scope'suz çalışır; dönen cihazın kullanıcısı
 * Auth::login ile oturuma konur → bir terminal başka işletmenin ekranını
 * token bilinmeden AÇAMAZ.
 */
class TerminalTokenResolver
{
    /**
     * @return array{status: string, device: ?TerminalDevice, tenant: ?Tenant, branch: ?Branch}
     *   status: ok | locked | revoked | inactive | invalid
     */
    public function resolve(string $token): array
    {
        $token = strtoupper(trim($token));

        // Biçim: 26 karakter base32 — uymayan girdi DB'ye inmez.
        if (preg_match('/^[A-Z2-7]{26}$/', $token) !== 1) {
            return $this->result('invalid');
        }

        $device = TerminalDevice::withoutTenancy()->where('token', $token)->first();

        if ($device === null) {
            // Rotasyonla geçersiz kılınmış eski token → 410 (dürüst açıklama).
            $revoked = TerminalDevice::withoutTenancy()->where('previous_token', $token)->exists();

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

    /** Kalp atışı izi: sağlık rozeti + son IP (panel). Sessiz yaz (audit yok). */
    public function touch(TerminalDevice $device, ?string $ip): void
    {
        TerminalDevice::withoutTenancy()->whereKey($device->getKey())->update([
            'last_seen_at' => now(),
            'last_ip' => $ip !== null ? mb_substr($ip, 0, 45) : null,
        ]);
    }

    /** @return array{status: string, device: ?TerminalDevice, tenant: ?Tenant, branch: ?Branch} */
    private function result(string $status, ?TerminalDevice $device = null, ?Tenant $tenant = null, ?Branch $branch = null): array
    {
        return ['status' => $status, 'device' => $device, 'tenant' => $tenant, 'branch' => $branch];
    }
}
