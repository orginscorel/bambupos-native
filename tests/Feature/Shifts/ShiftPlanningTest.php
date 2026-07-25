<?php

namespace Tests\Feature\Shifts;

use App\Modules\Shifts\Models\Shift;
use App\Modules\Shifts\Models\StaffingRule;

/**
 * Vardiya planlama: kiracı izolasyonu, yetki (staff.manage), çakışma
 * tespiti, tekrarlayan vardiya, minimum personel uyarısı, değişim talebi.
 */
class ShiftPlanningTest extends ShiftsTestCase
{
    public function test_vardiya_olusturma_staff_manage_ister(): void
    {
        $ctx = $this->makeTenantWithUser();
        $limited = $this->addStaff($ctx); // yalnız catalog.view

        $payload = [
            'branch_id' => $ctx['branch']->id,
            'user_id' => $limited->id,
            'starts_at' => now()->addDay()->setTime(9, 0)->toDateTimeString(),
            'ends_at' => now()->addDay()->setTime(17, 0)->toDateTimeString(),
        ];

        $this->actingAs($limited)->postJson('/api/v1/shifts/shifts', $payload)->assertForbidden();
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/shifts', $payload)->assertCreated();
    }

    public function test_cakisan_vardiya_tespit_edilir_ve_reddedilir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);

        $day = now()->addDay()->format('Y-m-d');
        $this->makeShift($ctx, $staff, "{$day} 09:00:00", "{$day} 17:00:00");

        // Aynı personel, kesişen aralık → 422
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/shifts', [
            'branch_id' => $ctx['branch']->id,
            'user_id' => $staff->id,
            'starts_at' => "{$day} 16:00:00",
            'ends_at' => "{$day} 23:00:00",
        ])->assertStatus(422);

        // Bitişik (17:00 başlangıç) çakışma DEĞİLDİR
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/shifts', [
            'branch_id' => $ctx['branch']->id,
            'user_id' => $staff->id,
            'starts_at' => "{$day} 17:00:00",
            'ends_at' => "{$day} 23:00:00",
        ])->assertCreated();

        // allow_overlap ile bilinçli çakışma yazılabilir
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/shifts', [
            'branch_id' => $ctx['branch']->id,
            'user_id' => $staff->id,
            'starts_at' => "{$day} 16:00:00",
            'ends_at' => "{$day} 18:00:00",
            'allow_overlap' => true,
        ])->assertCreated();
    }

    public function test_tekrarlayan_vardiya_haftalik_kopyalar_uretir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);

        $day = now()->addDay()->format('Y-m-d');

        $response = $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/shifts', [
            'branch_id' => $ctx['branch']->id,
            'user_id' => $staff->id,
            'starts_at' => "{$day} 09:00:00",
            'ends_at' => "{$day} 17:00:00",
            'repeat_weeks' => 3,
        ])->assertCreated();

        $this->assertCount(4, $response->json('shifts'));

        $groups = collect($response->json('shifts'))->pluck('repeat_group')->unique();
        $this->assertCount(1, $groups);
        $this->assertNotNull($groups->first());
    }

    public function test_kiraci_izolasyonu_yabanci_vardiya_gorunmez_ve_degistirilemez(): void
    {
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        $staffB = $this->addStaff($b);
        $day = now()->addDay()->format('Y-m-d');
        $shiftB = $this->makeShift($b, $staffB, "{$day} 09:00:00", "{$day} 17:00:00");

        // A kiracısının yöneticisi B'nin vardiyasını göremez (takvim boş döner)
        $schedule = $this->actingAs($a['user'])->getJson(
            '/api/v1/shifts/schedule?from='.now()->format('Y-m-d').'&to='.now()->addDays(7)->format('Y-m-d'),
        )->assertOk();

        $this->assertSame([], $schedule->json('shifts'));

        // ve değiştiremez / silemez (binding 404)
        $this->actingAs($a['user'])->putJson("/api/v1/shifts/shifts/{$shiftB->id}", [
            'note' => 'ele geçirme',
        ])->assertNotFound();

        $this->actingAs($a['user'])->deleteJson("/api/v1/shifts/shifts/{$shiftB->id}")->assertNotFound();

        $this->assertDatabaseHas('shifts', ['id' => $shiftB->id, 'user_id' => $staffB->id]);
    }

    public function test_staff_view_olmayan_personel_yalniz_kendi_vardiyasini_gorur(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff1 = $this->addStaff($ctx);
        $staff2 = $this->addStaff($ctx);

        $day = now()->addDay()->format('Y-m-d');
        $this->makeShift($ctx, $staff1, "{$day} 09:00:00", "{$day} 17:00:00");
        $this->makeShift($ctx, $staff2, "{$day} 09:00:00", "{$day} 17:00:00");

        $schedule = $this->actingAs($staff1)->getJson(
            '/api/v1/shifts/schedule?from='.now()->format('Y-m-d').'&to='.now()->addDays(7)->format('Y-m-d'),
        )->assertOk();

        $this->assertCount(1, $schedule->json('shifts'));
        $this->assertSame($staff1->id, $schedule->json('shifts.0.user_id'));
    }

    public function test_minimum_personel_uyarisi_uretilir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);

        $this->asTenant($ctx['tenant'], fn () => StaffingRule::query()->create([
            'branch_id' => $ctx['branch']->id,
            'weekday' => null,
            'position' => null,
            'min_count' => 2,
        ]));

        $day = now()->addDay()->format('Y-m-d');
        $this->makeShift($ctx, $staff, "{$day} 09:00:00", "{$day} 17:00:00");

        $schedule = $this->actingAs($ctx['user'])->getJson(
            "/api/v1/shifts/schedule?from={$day}&to=".now()->addDays(2)->format('Y-m-d'),
        )->assertOk();

        $warnings = collect($schedule->json('warnings'));
        $this->assertTrue($warnings->contains(fn ($w) => $w['date'] === $day && $w['planned'] === 1 && $w['required'] === 2));
    }

    public function test_vardiya_degisim_talebi_onaylaninca_vardiya_devrolur(): void
    {
        $ctx = $this->makeTenantWithUser();
        $owner = $this->addStaff($ctx);
        $target = $this->addStaff($ctx);

        $day = now()->addDay()->format('Y-m-d');
        $shift = $this->makeShift($ctx, $owner, "{$day} 09:00:00", "{$day} 17:00:00");

        // Sahip talep açar
        $swapId = $this->actingAs($owner)->postJson("/api/v1/shifts/shifts/{$shift->id}/swap-requests", [
            'target_user_id' => $target->id,
            'reason' => 'Sağlık randevusu',
        ])->assertCreated()->json('swap.id');

        // Sınırlı personel onaylayamaz
        $this->actingAs($owner)->postJson("/api/v1/shifts/swap-requests/{$swapId}/approve")->assertForbidden();

        // Yönetici onaylar → vardiya hedefe geçer
        $this->actingAs($ctx['user'])->postJson("/api/v1/shifts/swap-requests/{$swapId}/approve")->assertOk();

        $this->assertSame($target->id, (int) Shift::withoutTenancy()->find($shift->id)->user_id);
    }
}
