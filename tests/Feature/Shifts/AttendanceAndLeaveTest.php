<?php

namespace Tests\Feature\Shifts;

use App\Modules\Shifts\Models\LeaveRequest;

/**
 * İzin akışı + devam özeti + performans ucu yetkisi.
 */
class AttendanceAndLeaveTest extends ShiftsTestCase
{
    public function test_personel_izin_talebi_acar_yonetici_onaylar(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);

        $leaveId = $this->actingAs($staff)->postJson('/api/v1/shifts/leave-requests', [
            'type' => 'annual',
            'starts_on' => now()->addWeek()->format('Y-m-d'),
            'ends_on' => now()->addWeek()->addDays(2)->format('Y-m-d'),
            'reason' => 'Aile ziyareti',
        ])->assertCreated()->json('leave.id');

        $this->assertDatabaseHas('leave_requests', ['id' => $leaveId, 'status' => 'pending', 'user_id' => $staff->id]);

        // Sınırlı personel onaylayamaz
        $this->actingAs($staff)->postJson("/api/v1/shifts/leave-requests/{$leaveId}/approve")->assertForbidden();

        // Yönetici onaylar
        $this->actingAs($ctx['user'])->postJson("/api/v1/shifts/leave-requests/{$leaveId}/approve")->assertOk();
        $this->assertDatabaseHas('leave_requests', ['id' => $leaveId, 'status' => 'approved']);
    }

    public function test_personel_baskasi_adina_izin_acamaz_yonetici_devamsizlik_kaydi_acar(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);
        $other = $this->addStaff($ctx);

        // Personel başkası adına açamaz
        $this->actingAs($staff)->postJson('/api/v1/shifts/leave-requests', [
            'user_id' => $other->id,
            'type' => 'annual',
            'starts_on' => now()->format('Y-m-d'),
            'ends_on' => now()->format('Y-m-d'),
        ])->assertForbidden();

        // Personel devamsızlık türünü kendisi için de açamaz (yönetici kaydıdır)
        $this->actingAs($staff)->postJson('/api/v1/shifts/leave-requests', [
            'type' => 'absence',
            'starts_on' => now()->format('Y-m-d'),
            'ends_on' => now()->format('Y-m-d'),
        ])->assertForbidden();

        // Yönetici devamsızlık kaydı açar → doğrudan onaylı
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/leave-requests', [
            'user_id' => $other->id,
            'type' => 'absence',
            'starts_on' => now()->format('Y-m-d'),
            'ends_on' => now()->format('Y-m-d'),
        ])->assertCreated();

        $this->assertDatabaseHas('leave_requests', [
            'user_id' => $other->id,
            'type' => 'absence',
            'status' => LeaveRequest::STATUS_APPROVED,
        ]);
    }

    public function test_kiraci_izolasyonu_yabanci_izin_listede_gorunmez(): void
    {
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        $staffB = $this->addStaff($b);

        $this->actingAs($staffB)->postJson('/api/v1/shifts/leave-requests', [
            'type' => 'annual',
            'starts_on' => now()->format('Y-m-d'),
            'ends_on' => now()->format('Y-m-d'),
        ])->assertCreated();

        $list = $this->actingAs($a['user'])->getJson('/api/v1/shifts/leave-requests')->assertOk();
        $this->assertSame(0, $list->json('total'));
    }

    public function test_devam_ozeti_calisilan_sure_ve_izinleri_toplar(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);
        $this->setPin($staff, '246813');

        $today = now()->format('Y-m-d');
        $this->travelTo("{$today} 09:00:00");
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', ['action' => 'in', 'pin' => '246813'])->assertOk();
        $this->travelTo("{$today} 17:00:00");
        $this->actingAs($ctx['user'])->postJson('/api/v1/shifts/clock', ['action' => 'out', 'pin' => '246813'])->assertOk();

        $summary = $this->actingAs($ctx['user'])->getJson(
            '/api/v1/shifts/attendance-summary?from='.now()->subDay()->format('Y-m-d').'&to='.now()->addDay()->format('Y-m-d'),
        )->assertOk()->json('summary');

        $row = collect($summary)->firstWhere('user.id', $staff->id);
        $this->assertNotNull($row);
        $this->assertSame(480, $row['worked_min']);
        $this->assertSame(1, $row['days_worked']);
    }

    public function test_performans_ucu_staff_view_ister(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx); // catalog.view

        $range = 'from='.now()->subWeek()->format('Y-m-d').'&to='.now()->addDay()->format('Y-m-d');

        $this->actingAs($staff)->getJson("/api/v1/shifts/performance?{$range}")->assertForbidden();
        $this->actingAs($ctx['user'])->getJson("/api/v1/shifts/performance?{$range}")->assertOk();
    }

    public function test_ayarlar_yalniz_yonetici_gunceller_ve_konum_politikasi_zorunlu(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);

        $this->actingAs($staff)->putJson('/api/v1/shifts/settings', [
            'location_tracking_enabled' => true,
        ])->assertForbidden();

        // Politika metni olmadan konum takibi AÇILAMAZ (KVKK aydınlatma)
        $this->actingAs($ctx['user'])->putJson('/api/v1/shifts/settings', [
            'location_tracking_enabled' => true,
        ])->assertStatus(422);

        $this->actingAs($ctx['user'])->putJson('/api/v1/shifts/settings', [
            'location_tracking_enabled' => true,
            'location_policy' => 'Konum yalnız mesai doğrulaması için işlenir; dilediğinizde rızanızı geri çekebilirsiniz.',
        ])->assertOk();

        $this->assertDatabaseHas('shift_settings', [
            'tenant_id' => $ctx['tenant']->id,
            'location_tracking_enabled' => true,
        ]);
    }
}
