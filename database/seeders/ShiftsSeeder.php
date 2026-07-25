<?php

namespace Database\Seeders;

use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Shifts\Models\ClockDevice;
use App\Modules\Shifts\Models\LeaveRequest;
use App\Modules\Shifts\Models\Shift;
use App\Modules\Shifts\Models\ShiftSetting;
use App\Modules\Shifts\Models\TimeEntry;
use App\Modules\Shifts\Services\TimeClockService;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Hash;

/**
 * VARDİYA / MESAİ demo verisi (Faz-7): ekranlar dolu ve TUTARLI görünsün.
 *
 *  - Birkaç demo personel (garson/mutfak/komi) — her biri PIN'li, böylece
 *    hem panel atamaları hem PIN'li giriş/çıkış + cihaz-clock denenebilir.
 *  - Bu haftanın vardiya planı (haftalık grid dolu): sabah/akşam vardiyaları,
 *    pozisyon bazlı.
 *  - Geçmiş günlerin mesai kayıtları: zamanında / geç kalma / fazla mesai /
 *    erken çıkış varyasyonları → rapor (geç/fazla/eksik) gerçek hesapla dolar.
 *  - Bugün AÇIK bir mesai kaydı (canlı "içeride" durumu).
 *  - Onaylı yıllık izin + bir devamsızlık kaydı (leave_requests).
 *  - Ortak giriş/çıkış tableti (clock_devices) demo token'ıyla.
 *
 * Idempotent: demo kiracıda vardiya zaten varsa hiçbir şey yazılmaz.
 * Süreler dakika-integer; türetilmiş alanlar TimeClockService::finalize ile.
 */
class ShiftsSeeder extends Seeder
{
    /** Cihaz-clock denemesi için sabit demo token (yalnız demo ortamı). */
    public const DEMO_DEVICE_TOKEN = 'demo-clock-tablet-token-0001';

    public function run(): void
    {
        $ctx = app(TenantContext::class);

        $tenant = $ctx->runWithoutTenancy(
            fn () => Tenant::query()->where('slug', 'demo')->first()
        );

        if ($tenant === null) {
            return;
        }

        $tenantId = (int) $tenant->id;

        $ctx->setTenant($tenantId);

        try {
            if (Shift::query()->exists()) {
                return; // zaten seed'li
            }

            $branch = Branch::query()->orderBy('id')->first();

            if ($branch === null) {
                return;
            }

            $branchId = (int) $branch->id;

            // İşletme mesai ayarları (varsayılan toleranslar).
            ShiftSetting::current();

            $staff = $this->seedStaff($tenantId, $branchId);
            $this->seedDevice($tenantId, $branchId);
            $this->seedSchedule($branchId, $staff);
            $this->seedLeaves($branchId, $staff);
        } finally {
            $ctx->forget();
        }
    }

    /**
     * Demo personel (PIN'li). Rol atanır (garson/mutfak/komi şablonları
     * DemoTenantSeeder'dan gelir). staff_code + PIN cihaz-clock için gerekli.
     *
     * @return array<string, User>
     */
    private function seedStaff(int $tenantId, int $branchId): array
    {
        $defs = [
            'garson' => ['Ayşe', 'Yıldız', 'GARSON01', 'Garson', '1111'],
            'mutfak' => ['Mehmet', 'Demir', 'MUTFAK01', 'Aşçı', '2222'],
            'komi' => ['Can', 'Öztürk', 'KOMI01', 'Komi', '3333'],
        ];

        $out = [];

        foreach ($defs as $roleSlug => [$first, $last, $code, $position, $pin]) {
            $user = new User([
                'first_name' => $first,
                'last_name' => $last,
                'email' => strtolower($code).'@demo.qrmenu.local',
                'staff_code' => $code,
                'position' => $position,
                'locale' => 'tr',
                'is_active' => true,
            ]);
            $user->tenant_id = $tenantId;
            $user->branch_id = $branchId;
            $user->password = Hash::make('demo1234');
            $user->pin_hash = Hash::make($pin);
            $user->email_verified_at = now();
            $user->hired_at = now()->subMonths(6);
            $user->save();

            $role = Role::query()->where('slug', $roleSlug)->first();

            if ($role !== null) {
                $user->roles()->sync([$role->id]);
            }

            $out[$roleSlug] = $user;
        }

        return $out;
    }

    /** Ortak giriş/çıkış tableti (token yalnız hash olarak saklanır). */
    private function seedDevice(int $tenantId, int $branchId): void
    {
        $device = new ClockDevice([
            'branch_id' => $branchId,
            'name' => 'Giriş / Çıkış Tableti',
            'is_active' => true,
        ]);
        $device->tenant_id = $tenantId;
        $device->token_hash = ClockDevice::hashToken(self::DEMO_DEVICE_TOKEN);
        $device->save();
    }

    /**
     * Bu haftanın vardiya planı + geçmiş günlerin mesai kayıtları.
     *
     * @param  array<string, User>  $staff
     */
    private function seedSchedule(int $branchId, array $staff): void
    {
        $clock = app(TimeClockService::class);
        $weekStart = Carbon::today()->startOfWeek(); // Pazartesi

        // [rol, pozisyon, başlangıç saati, bitiş saati, mola dk]
        $plan = [
            ['garson', 'Garson', 9, 17, 30],
            ['mutfak', 'Aşçı', 10, 18, 45],
            ['komi', 'Komi', 16, 23, 30],
        ];

        for ($day = 0; $day < 7; $day++) {
            $date = $weekStart->copy()->addDays($day);

            foreach ($plan as $index => [$roleSlug, $position, $startH, $endH, $breakMin]) {
                $user = $staff[$roleSlug];

                // Herkes her gün değil: komi Pazartesi izinli (devamsızlık demosu).
                if ($roleSlug === 'komi' && $day === 0) {
                    continue;
                }

                $startsAt = $date->copy()->setTime($startH, 0);
                $endsAt = $date->copy()->setTime($endH, 0);

                $shift = new Shift([
                    'branch_id' => $branchId,
                    'user_id' => $user->id,
                    'position' => $position,
                    'starts_at' => $startsAt,
                    'ends_at' => $endsAt,
                    'break_min' => $breakMin,
                    'note' => null,
                ]);
                $shift->save();

                // Yalnız GEÇMİŞ günler için mesai kaydı üret (gelecek plan boş).
                if ($date->isFuture() || $date->isToday()) {
                    continue;
                }

                $this->seedTimeEntry($clock, $branchId, $user, $shift, $index, $day);
            }
        }

        // Bugün: garson içeride (açık kayıt) — canlı durum ekranı dolu görünür.
        $today = Carbon::today();
        $garson = $staff['garson'];
        $todayShift = Shift::query()
            ->where('user_id', $garson->id)
            ->whereBetween('starts_at', [$today, $today->copy()->endOfDay()])
            ->first();

        $open = new TimeEntry([
            'branch_id' => $branchId,
            'user_id' => $garson->id,
            'shift_id' => $todayShift?->id,
            'clock_in_at' => $today->copy()->setTime(9, 3),
            'method_in' => 'device',
            'status' => TimeEntry::STATUS_OPEN,
        ]);
        $open->save();
    }

    /**
     * Geçmiş gün mesai kaydı — güne göre varyasyon (zamanında / geç / fazla /
     * erken). finalize türetilmiş alanları (late/overtime/missing) hesaplar.
     */
    private function seedTimeEntry(
        TimeClockService $clock,
        int $branchId,
        User $user,
        Shift $shift,
        int $index,
        int $day,
    ): void {
        // Güne+kişiye göre giriş/çıkış sapması (dakika).
        $variants = [
            [0, 0],     // tam zamanında
            [22, 15],   // 22 dk geç girdi, 15 dk fazla çalıştı
            [-5, -35],  // erken geldi, 35 dk erken çıktı
            [8, 40],    // hafif geç, fazla mesai
        ];
        [$inOffset, $outOffset] = $variants[($day + $index) % count($variants)];

        $entry = new TimeEntry([
            'branch_id' => $branchId,
            'user_id' => $user->id,
            'shift_id' => $shift->id,
            'clock_in_at' => $shift->starts_at->copy()->addMinutes($inOffset),
            'clock_out_at' => $shift->ends_at->copy()->addMinutes($outOffset),
            'method_in' => $day % 2 === 0 ? 'pin' : 'device',
            'method_out' => 'pin',
            'status' => TimeEntry::STATUS_CLOSED,
        ]);
        $entry->save();

        // Planlanan molayı tek satır olarak yaz (finalize toplamı düşer).
        if ($shift->break_min > 0) {
            $entry->breaks()->create([
                'started_at' => $entry->clock_in_at->copy()->addHours(3),
                'ended_at' => $entry->clock_in_at->copy()->addHours(3)->addMinutes((int) $shift->break_min),
            ]);
        }

        $clock->finalize($entry);
        $entry->save();
    }

    /**
     * İzin / devamsızlık kayıtları (rapor + takvim dolu görünür).
     *
     * @param  array<string, User>  $staff
     */
    private function seedLeaves(int $branchId, array $staff): void
    {
        $weekStart = Carbon::today()->startOfWeek();

        // Komi'nin Pazartesi devamsızlığı (vardiya atanmamıştı) — kayda geçer.
        $absence = LeaveRequest::query()->create([
            'branch_id' => $branchId,
            'user_id' => $staff['komi']->id,
            'type' => 'absence',
            'starts_on' => $weekStart->copy(),
            'ends_on' => $weekStart->copy(),
            'reason' => 'Haber vermeden gelmedi',
            'status' => 'approved',
        ]);
        $absence->forceFill(['decided_at' => now()])->save();

        // Aşçı gelecek hafta onaylı yıllık izin.
        $annual = LeaveRequest::query()->create([
            'branch_id' => $branchId,
            'user_id' => $staff['mutfak']->id,
            'type' => 'annual',
            'starts_on' => $weekStart->copy()->addDays(9),
            'ends_on' => $weekStart->copy()->addDays(11),
            'reason' => 'Yıllık izin',
            'status' => 'approved',
        ]);
        $annual->forceFill(['decided_at' => now()])->save();

        // Garson bekleyen izin talebi (onay ekranı dolu görünür).
        LeaveRequest::query()->create([
            'branch_id' => $branchId,
            'user_id' => $staff['garson']->id,
            'type' => 'sick',
            'starts_on' => $weekStart->copy()->addDays(14),
            'ends_on' => $weekStart->copy()->addDays(14),
            'reason' => 'Doktor randevusu',
            'status' => 'pending',
        ]);
    }
}
