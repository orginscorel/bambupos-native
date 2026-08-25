<?php

namespace Tests\Feature\Shifts;

use App\Modules\Identity\Models\User;
use App\Modules\Orders\Models\Order;
use App\Modules\Shifts\Models\TimeEntry;
use App\Modules\Tenancy\Models\Branch;

/**
 * ŞUBE KAPSAMI regresyon testi — denetim BLOKER bulgusu (2026-08-04):
 * /shifts/performance, /shifts/attendance-summary, /shifts/payroll GET+PUT
 * hiç branch_id filtresi uygulamıyordu (kardeş uçlar TimeEntry/LeaveRequest
 * gibi zaten ScopesToBranch kullanıyordu). Tek kiracı, İKİ şube (A/B);
 * A şubesine kilitli yönetici B şubesinin personel/ciro/mesai/bordro
 * verisini ASLA görmemeli/düzenlememeli.
 */
class BranchScopeShiftsTest extends ShiftsTestCase
{
    public function test_performans_ucu_baska_sube_personelini_ve_cirosunu_sizdirmiyor(): void
    {
        $ctx = $this->makeTenantWithUser(); // yönetici + A şubesi
        $branchB = $this->asTenant($ctx['tenant'], fn (): Branch => Branch::factory()->create([
            'tenant_id' => $ctx['tenant']->id,
            'name' => 'B Şube',
        ]));

        $staffA = $this->addStaff($ctx, ['staff.view'], ['name' => 'Personel A']);
        $staffB = $this->addStaff($ctx, ['staff.view'], ['name' => 'Personel B', 'branch_id' => $branchB->id]);

        $this->asTenant($ctx['tenant'], function () use ($ctx, $branchB, $staffA, $staffB): void {
            Order::unguarded(fn () => Order::factory()->create([
                'tenant_id' => $ctx['tenant']->id,
                'branch_id' => $ctx['branch']->id,
                'opened_by_id' => $staffA->id,
                'status' => 'closed',
                'total_minor' => 15000,
                'placed_at' => now()->subMinutes(20),
                'closed_at' => now(),
            ]));

            Order::unguarded(fn () => Order::factory()->create([
                'tenant_id' => $ctx['tenant']->id,
                'branch_id' => $branchB->id,
                'opened_by_id' => $staffB->id,
                'status' => 'closed',
                'total_minor' => 99999,
                'placed_at' => now()->subMinutes(20),
                'closed_at' => now(),
            ]));
        });

        // Yönetici A şubesine kilitli (varsayılan aktif şube = kendi şubesi).
        $metrics = collect(
            $this->actingAs($ctx['user'])
                ->getJson('/api/v1/shifts/performance?from='.now()->subDay()->toDateString().'&to='.now()->addDay()->toDateString())
                ->assertOk()
                ->json('metrics')
        );

        $ids = $metrics->pluck('user.id');
        $this->assertTrue($ids->contains($staffA->id));
        $this->assertFalse($ids->contains($staffB->id), 'B şubesi personeli performans listesine sızmamalı');

        $staffARow = $metrics->firstWhere('user.id', $staffA->id);
        $this->assertSame(15000, $staffARow['sales_minor'], 'B şubesinin cirosu A şubesinin toplamına karışmamalı');
    }

    public function test_devam_ozeti_baska_subenin_mesai_verisini_sizdirmiyor(): void
    {
        $ctx = $this->makeTenantWithUser();
        $branchB = $this->asTenant($ctx['tenant'], fn (): Branch => Branch::factory()->create([
            'tenant_id' => $ctx['tenant']->id,
            'name' => 'B Şube',
        ]));

        $staffA = $this->addStaff($ctx, ['staff.view'], ['name' => 'Personel A']);
        $staffB = $this->addStaff($ctx, ['staff.view'], ['name' => 'Personel B', 'branch_id' => $branchB->id]);

        $this->asTenant($ctx['tenant'], function () use ($ctx, $branchB, $staffA, $staffB): void {
            TimeEntry::unguarded(fn () => TimeEntry::query()->create([
                'branch_id' => $ctx['branch']->id,
                'user_id' => $staffA->id,
                'clock_in_at' => now()->subHours(4),
                'clock_out_at' => now(),
                'status' => TimeEntry::STATUS_CLOSED,
                'worked_min' => 240,
            ]));

            TimeEntry::unguarded(fn () => TimeEntry::query()->create([
                'branch_id' => $branchB->id,
                'user_id' => $staffB->id,
                'clock_in_at' => now()->subHours(8),
                'clock_out_at' => now(),
                'status' => TimeEntry::STATUS_CLOSED,
                'worked_min' => 480,
            ]));
        });

        $summary = collect(
            $this->actingAs($ctx['user'])
                ->getJson('/api/v1/shifts/attendance-summary?from='.now()->subDay()->toDateString().'&to='.now()->addDay()->toDateString())
                ->assertOk()
                ->json('summary')
        );

        $ids = $summary->pluck('user.id');
        $this->assertTrue($ids->contains($staffA->id));
        $this->assertFalse($ids->contains($staffB->id), 'B şubesi personeli devam özetine sızmamalı');

        $staffARow = $summary->firstWhere('user.id', $staffA->id);
        $this->assertSame(240, $staffARow['worked_min'], 'B şubesinin çalışma süresi A şubesinin toplamına karışmamalı');
    }

    public function test_payroll_bordro_baska_subeyi_ne_listeler_ne_guncellemeye_izin_verir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $branchB = $this->asTenant($ctx['tenant'], fn (): Branch => Branch::factory()->create([
            'tenant_id' => $ctx['tenant']->id,
            'name' => 'B Şube',
        ]));

        $staffA = $this->addStaff($ctx, ['staff.manage'], [
            'name' => 'Personel A', 'salary_type' => 'monthly', 'salary_amount_minor' => 3000000,
        ]);
        $staffB = $this->addStaff($ctx, ['staff.manage'], [
            'name' => 'Personel B', 'branch_id' => $branchB->id,
            'salary_type' => 'monthly', 'salary_amount_minor' => 9999900,
        ]);

        $manager = $ctx['user'];

        // GET: yalnız A şubesinin bordrosu listelenir.
        $rows = collect(
            $this->actingAs($manager)->getJson('/api/v1/shifts/payroll')->assertOk()->json('rows')
        );
        $ids = $rows->pluck('id');
        $this->assertTrue($ids->contains($staffA->id));
        $this->assertFalse($ids->contains($staffB->id), 'B şubesi personeli bordro listesine sızmamalı');

        // PUT: B şubesindeki personelin maaşı A şubesi yöneticisi tarafından güncellenemez.
        $this->actingAs($manager)
            ->putJson("/api/v1/shifts/payroll/{$staffB->id}", ['salary_type' => 'hourly', 'salary_amount' => 500])
            ->assertNotFound();

        $this->assertDatabaseHas('users', [
            'id' => $staffB->id,
            'salary_type' => 'monthly',
            'salary_amount_minor' => 9999900,
        ]);

        // Kendi şubesindeki personelin maaşı güncellenebilir (regresyon değil).
        $this->actingAs($manager)
            ->putJson("/api/v1/shifts/payroll/{$staffA->id}", ['salary_type' => 'hourly', 'salary_amount' => 250])
            ->assertOk();

        $this->assertDatabaseHas('users', [
            'id' => $staffA->id,
            'salary_type' => 'hourly',
            'salary_amount_minor' => 25000,
        ]);
    }
}
