<?php

namespace Tests\Feature\Portal;

/**
 * Mesaim: kişinin KENDİ mesai/mola/tuvalet başlat-bitir uçları — PIN'SİZ
 * (oturum sahibine yazılır). Mola türü time_entry_breaks.kind'a düşer.
 */
class PortalClockTest extends PortalTestCase
{
    public function test_mesai_baslat_pinsiz_kendi_oturumuna_yazilir(): void
    {
        $ctx = $this->makeTenantWithUser();

        $res = $this->actingAs($ctx['user'])
            ->postJson($this->portalUrl('/api/v1/portal/clock/in'))
            ->assertOk();

        $this->assertSame('working', $res->json('status'));
        $this->assertDatabaseHas('time_entries', [
            'user_id' => $ctx['user']->id,
            'status' => 'open',
            'method_in' => 'portal',
        ]);
    }

    public function test_normal_ve_tuvalet_molasi_ayri_turde_kaydedilir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $user = $ctx['user'];

        $this->actingAs($user)->postJson($this->portalUrl('/api/v1/portal/clock/in'))->assertOk();

        // Tuvalet molası
        $this->actingAs($user)
            ->postJson($this->portalUrl('/api/v1/portal/break/start'), ['kind' => 'toilet'])
            ->assertOk()
            ->assertJsonPath('on_break', true)
            ->assertJsonPath('break_kind', 'toilet');

        $this->assertDatabaseHas('time_entry_breaks', ['kind' => 'toilet', 'ended_at' => null]);

        // Bitir → dönüş
        $this->actingAs($user)->postJson($this->portalUrl('/api/v1/portal/break/end'))
            ->assertOk()->assertJsonPath('on_break', false);

        // Normal mola
        $this->actingAs($user)
            ->postJson($this->portalUrl('/api/v1/portal/break/start'), ['kind' => 'break'])
            ->assertOk()->assertJsonPath('break_kind', 'break');

        $this->assertDatabaseHas('time_entry_breaks', ['kind' => 'break', 'ended_at' => null]);
    }

    public function test_mesai_bitir_kaydi_kapatir(): void
    {
        $ctx = $this->makeTenantWithUser();
        $user = $ctx['user'];

        $this->actingAs($user)->postJson($this->portalUrl('/api/v1/portal/clock/in'))->assertOk();
        $this->actingAs($user)->postJson($this->portalUrl('/api/v1/portal/clock/out'))
            ->assertOk()->assertJsonPath('status', 'off');

        $this->assertDatabaseHas('time_entries', ['user_id' => $user->id, 'status' => 'closed']);
    }

    public function test_reports_ucu_kendi_verisini_dondurur(): void
    {
        $ctx = $this->makeTenantWithUser();
        $user = $ctx['user'];

        $this->actingAs($user)->postJson($this->portalUrl('/api/v1/portal/clock/in'))->assertOk();

        $this->actingAs($user)->getJson($this->portalUrl('/api/v1/portal/reports'))
            ->assertOk()
            ->assertJsonStructure([
                'period', 'from', 'to',
                'worked' => ['total_min', 'active_days', 'by_day'],
                'ops' => ['prepared_count', 'taken_count', 'served_count', 'by_day'],
                'orders' => ['order_count'],
            ]);
    }
}
