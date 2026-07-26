<?php

namespace Tests\Feature\Portal;

use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Models\Notification;
use App\Modules\Tenancy\Models\Branch;

/**
 * §8 Mola bildirimi: personel molaya/tuvalete çıkınca YÖNETİCİ + o an mesaide
 * olan DİĞER personel bildirim alır. Molaya çıkan KENDİ almaz; başka şube almaz.
 */
class PortalBreakNotificationTest extends PortalTestCase
{
    /** @return \Illuminate\Support\Collection<int, Notification> */
    private function breakNotifs(int $userId)
    {
        return Notification::withoutTenancy()
            ->where('user_id', $userId)
            ->where('type', NotificationType::StaffBreak->value)
            ->get();
    }

    public function test_yonetici_ve_mesaidekiler_alir_molaci_ve_baska_sube_almaz(): void
    {
        $ctx = $this->makeTenantWithUser();          // sahip = yönetici (tüm izinler)
        $manager = $ctx['user'];
        $branchA = $ctx['branch'];
        $branchB = Branch::factory()->create(['tenant_id' => $ctx['tenant']->id]);

        $breaker = $this->addStaff($ctx, ['catalog.view'], $branchA->id);   // molaya çıkacak
        $onShiftMate = $this->addStaff($ctx, ['catalog.view'], $branchA->id); // aynı şube, mesaide
        $offShiftMate = $this->addStaff($ctx, ['catalog.view'], $branchA->id); // aynı şube, MESAİDE DEĞİL
        $otherBranch = $this->addStaff($ctx, ['catalog.view'], $branchB->id); // başka şube, mesaide

        // Aynı şubede mesaide olan personel + başka şubede mesaide olan.
        $this->openShift($ctx['tenant'], $onShiftMate, $branchA->id);
        $this->openShift($ctx['tenant'], $otherBranch, $branchB->id);

        // Molaya çıkan personel mesai başlatır, sonra tuvalet molasına çıkar.
        $this->actingAs($breaker)->postJson($this->portalUrl('/api/v1/portal/clock/in'))->assertOk();
        $this->actingAs($breaker)
            ->postJson($this->portalUrl('/api/v1/portal/break/start'), ['kind' => 'toilet'])
            ->assertOk();

        // Yönetici alır.
        $mgr = $this->breakNotifs($manager->id);
        $this->assertCount(1, $mgr);
        $this->assertStringContainsString('tuvalete çıktı', (string) $mgr->first()->body);

        // Aynı şubede mesaide olan personel alır.
        $this->assertCount(1, $this->breakNotifs($onShiftMate->id));

        // Molaya çıkan KENDİ almaz.
        $this->assertCount(0, $this->breakNotifs($breaker->id));

        // Aynı şube ama MESAİDE OLMAYAN personel almaz.
        $this->assertCount(0, $this->breakNotifs($offShiftMate->id));

        // Başka şube personeli (mesaide olsa bile) almaz (şube-izole).
        $this->assertCount(0, $this->breakNotifs($otherBranch->id));
    }

    public function test_moladan_donus_de_bildirilir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $manager = $ctx['user'];
        $breaker = $this->addStaff($ctx, ['catalog.view']);

        $this->actingAs($breaker)->postJson($this->portalUrl('/api/v1/portal/clock/in'))->assertOk();
        $this->actingAs($breaker)->postJson($this->portalUrl('/api/v1/portal/break/start'), ['kind' => 'break'])->assertOk();
        $this->actingAs($breaker)->postJson($this->portalUrl('/api/v1/portal/break/end'))->assertOk();

        // Başlat + bitir → yöneticide iki ayrı bildirim (farklı dedup anahtarı).
        $notifs = $this->breakNotifs($manager->id);
        $this->assertCount(2, $notifs);
        $this->assertTrue($notifs->contains(fn ($n) => str_contains((string) $n->body, 'molaya çıktı')));
        $this->assertTrue($notifs->contains(fn ($n) => str_contains((string) $n->body, 'moladan döndü')));
    }
}
