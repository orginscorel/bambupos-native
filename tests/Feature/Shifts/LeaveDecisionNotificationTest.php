<?php

declare(strict_types=1);

namespace Tests\Feature\Shifts;

use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Models\Notification;

/**
 * §8 İzin kararı bildirimi: yönetici onaylayınca/reddedince YALNIZ talep sahibi
 * (extra_user_ids) LeaveDecided bildirimi alır; yönetici boğulmaz.
 */
class LeaveDecisionNotificationTest extends ShiftsTestCase
{
    /** @return \Illuminate\Support\Collection<int, Notification> */
    private function decidedNotifs(int $userId)
    {
        return Notification::withoutTenancy()
            ->where('user_id', $userId)
            ->where('type', NotificationType::LeaveDecided->value)
            ->get();
    }

    public function test_onaylaninca_talep_sahibine_bildirim_yazilir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);

        $leaveId = $this->actingAs($staff)->postJson('/api/v1/shifts/leave-requests', [
            'type' => 'annual',
            'starts_on' => now()->addWeek()->format('Y-m-d'),
            'ends_on' => now()->addWeek()->addDays(2)->format('Y-m-d'),
            'reason' => 'Aile ziyareti',
        ])->assertCreated()->json('leave.id');

        $this->actingAs($ctx['user'])
            ->postJson("/api/v1/shifts/leave-requests/{$leaveId}/approve")
            ->assertOk();

        // Talep sahibi tam bir onay bildirimi alır.
        $notifs = $this->decidedNotifs($staff->id);
        $this->assertCount(1, $notifs);
        $this->assertSame('İzniniz onaylandı', $notifs->first()->title);

        // Karar veren yönetici bu kişisel bildirimi ALMAZ.
        $this->assertCount(0, $this->decidedNotifs($ctx['user']->id));
    }

    public function test_reddedilince_talep_sahibine_ret_bildirimi_yazilir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $staff = $this->addStaff($ctx);

        $leaveId = $this->actingAs($staff)->postJson('/api/v1/shifts/leave-requests', [
            'type' => 'sick',
            'starts_on' => now()->addWeek()->format('Y-m-d'),
            'ends_on' => now()->addWeek()->format('Y-m-d'),
            'reason' => 'Rapor',
        ])->assertCreated()->json('leave.id');

        $this->actingAs($ctx['user'])
            ->postJson("/api/v1/shifts/leave-requests/{$leaveId}/reject")
            ->assertOk();

        $notifs = $this->decidedNotifs($staff->id);
        $this->assertCount(1, $notifs);
        $this->assertSame('İzniniz reddedildi', $notifs->first()->title);
    }
}
