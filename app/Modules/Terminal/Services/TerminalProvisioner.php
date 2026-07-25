<?php

namespace App\Modules\Terminal\Services;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\User;
use App\Modules\Kds\Models\UserStation;
use App\Modules\Terminal\Models\TerminalDevice;
use App\Modules\Terminal\Support\TerminalStation;
use App\Modules\Tenancy\TenantIsolationException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Terminal cihazı + GİZLİ terminal kullanıcısı üretimi (§13, Faz A).
 *
 * En az riskli yaklaşım: her terminal cihazı = istasyona-atanmış, gizli bir
 * kullanıcı + opak token. Kullanıcı mevcut auth/izin/istasyon-süzme
 * altyapısını BİREBİR kullanır; token'la oto-giriş → kilitli mod devreye
 * girer. Böylece endpoint/politika/istasyon-kapsamı hiç değişmeden çalışır.
 *
 * Gizli kullanıcı:
 *  - is_terminal=true → Personel listesinde görünmez, impersonate edilemez,
 *    normal (e-posta/PIN) giriş yapamaz (login/impersonation is_terminal süzer).
 *  - Rol YOK; izinler yalnız kişi-bazlı GRANT (istasyonun ihtiyacı kadar).
 *  - kds_user_stations'a istasyonu atanır (komi=tümü → atama yok).
 */
class TerminalProvisioner
{
    /** Cihaz + gizli kullanıcıyı tek transaction'da üretir. */
    public function createDevice(string $name, int $branchId, int $tenantId, string $station): TerminalDevice
    {
        if (! TerminalStation::isValid($station)) {
            throw new TerminalIsolation('Geçersiz terminal istasyonu.');
        }

        return DB::transaction(function () use ($name, $branchId, $tenantId, $station): TerminalDevice {
            $user = $this->makeTerminalUser($name, $branchId, $tenantId, $station);

            $device = new TerminalDevice([
                'name' => $name,
                'station' => $station,
                'status' => TerminalDevice::STATUS_ACTIVE,
            ]);
            $device->tenant_id = $tenantId;
            $device->branch_id = $branchId;
            $device->user_id = (int) $user->getKey();
            $device->save();

            return $device;
        });
    }

    /**
     * Cihaz güncellenince gizli kullanıcıyı da hizala: ad, şube, istasyon
     * (izin + kds_user_stations + terminal_station yeniden yazılır).
     */
    public function syncDevice(TerminalDevice $device): void
    {
        DB::transaction(function () use ($device): void {
            $user = $device->user;

            if ($user === null || ! $user->is_terminal) {
                return;
            }

            $user->first_name = $device->name;
            $user->last_name = null;
            $user->branch_id = $device->branch_id;
            $user->terminal_station = $device->station;
            $user->save();

            $this->grantStationPermissions($user, $device->station);
            $this->assignStations($user, (int) $device->tenant_id, $device->station);
            $user->flushPermissionCache();
        });
    }

    /** Cihaz silinince gizli kullanıcıyı da temizler (yetim hesap kalmaz). */
    public function deleteDevice(TerminalDevice $device): void
    {
        DB::transaction(function () use ($device): void {
            $user = $device->user;
            $device->delete();

            if ($user !== null && $user->is_terminal) {
                UserStation::query()->where('user_id', $user->getKey())->delete();
                $user->personalPermissions()->detach();
                $user->delete();
            }
        });
    }

    /* ---------------------------------------------------------- */

    private function makeTerminalUser(string $name, int $branchId, int $tenantId, string $station): User
    {
        $user = new User([
            'first_name' => $name,
            'is_active' => true,
        ]);
        $user->tenant_id = $tenantId;
        $user->branch_id = $branchId;
        // Global-benzersiz sentetik e-posta; normal girişte kullanılamaz.
        $user->email = 'terminal-'.Str::lower(Str::random(24)).'@terminal.local';
        // Parola zorunlu (kolon nullable değil) — asla eşleşmeyen rastgele hash.
        $user->password = Hash::make(Str::random(48));
        $user->is_terminal = true;
        $user->terminal_station = $station;
        $user->save();

        $this->grantStationPermissions($user, $station);
        $this->assignStations($user, $tenantId, $station);

        return $user;
    }

    /** İstasyonun ihtiyacı kadar kişi-bazlı GRANT (fazlası yok). */
    private function grantStationPermissions(User $user, string $station): void
    {
        $keys = TerminalStation::permissionsFor($station);

        $ids = Permission::query()->whereIn('key', $keys)->pluck('id')->all();

        $sync = [];
        foreach ($ids as $id) {
            $sync[$id] = ['mode' => 'grant'];
        }

        $user->personalPermissions()->sync($sync);
    }

    /** kds_user_stations: komi=tümü (atama yok), mutfak/barista=kendi ailesi. */
    private function assignStations(User $user, int $tenantId, string $station): void
    {
        UserStation::query()->where('user_id', $user->getKey())->delete();

        foreach (TerminalStation::stationKeysFor($station) as $key) {
            $assignment = new UserStation([
                'user_id' => (int) $user->getKey(),
                'station_key' => $key,
            ]);
            $assignment->tenant_id = $tenantId;
            $assignment->save();
        }
    }
}

/** Dar iç istisna (geçersiz istasyon) — 422'ye çevrilir. */
class TerminalIsolation extends TenantIsolationException
{
}
