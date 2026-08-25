<?php

namespace Tests\Feature\Devices;

use App\Modules\Settings\Support\Features;
use App\Modules\Terminal\Services\TerminalProvisioner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * İzinli Cihazlar panel API'si (A3 + §13 Faz 3 köprüsü).
 *
 * "synced" senkron görünümü (Terminal cihazları burada da görünür) +
 * device_lock özelliğinin panelden tek-tık aç/kapa kısayolu
 * (AuthorizedDeviceController::toggleLock) — Eklentiler ekranıyla AYNI
 * depoyu (tenant_features) kullanır, ayrı bir durum saklamaz.
 */
class AuthorizedDeviceControllerTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    private function makeTerminal(array $ctx, string $station = 'kitchen', string $name = 'Terminal 1')
    {
        return $this->asTenant($ctx['tenant'], fn () => app(TerminalProvisioner::class)
            ->createDevice($name, (int) $ctx['branch']->id, (int) $ctx['tenant']->id, $station));
    }

    /* ---------------- Senkron görünüm ---------------- */

    public function test_synced_gercek_terminal_cihazlarini_kilit_durumuyla_doner(): void
    {
        $manager = $this->makeTenantWithUser(['devices.view', 'terminals.manage']);
        $this->makeTerminal($manager, 'kitchen', 'Mutfak Terminal 1');

        $this->actingAs($manager['user']);

        $res = $this->getJson('/api/v1/devices/synced')->assertOk();

        $this->assertFalse($res->json('lock_enabled'));
        $rows = collect($res->json('devices'));
        $this->assertCount(1, $rows);
        $this->assertSame('terminal', $rows->first()['source']);
        $this->assertSame('Mutfak Terminal 1', $rows->first()['name']);
        $this->assertNull($rows->first()['binding']);
    }

    public function test_devices_view_izni_olmayan_erisemez(): void
    {
        $viewer = $this->makeTenantWithUser(['orders.view']);
        $this->actingAs($viewer['user']);

        $this->getJson('/api/v1/devices/synced')->assertForbidden();
    }

    /* ---------------- device_lock tek-tık aç/kapa ---------------- */

    public function test_yetkili_cihaz_kilidini_tek_tikla_acar(): void
    {
        $manager = $this->makeTenantWithUser(['devices.manage', 'devices.view']);
        $this->actingAs($manager['user']);

        $this->assertFalse(Features::enabled((int) $manager['tenant']->id, 'device_lock'));

        $this->postJson('/api/v1/devices/lock-feature', ['enabled' => true])
            ->assertOk()
            ->assertJson(['enabled' => true]);

        $this->assertTrue(Features::enabled((int) $manager['tenant']->id, 'device_lock'));

        // synced ucu da artık AÇIK döner (aynı depo, ayrı durum yok).
        $res = $this->getJson('/api/v1/devices/synced')->assertOk();
        $this->assertTrue($res->json('lock_enabled'));
    }

    public function test_yetkili_cihaz_kilidini_tek_tikla_kapatir(): void
    {
        $manager = $this->makeTenantWithUser(['devices.manage']);
        Features::set((int) $manager['tenant']->id, 'device_lock', true);

        $this->actingAs($manager['user']);

        $this->postJson('/api/v1/devices/lock-feature', ['enabled' => false])
            ->assertOk()
            ->assertJson(['enabled' => false]);

        $this->assertFalse(Features::enabled((int) $manager['tenant']->id, 'device_lock'));
    }

    public function test_devices_manage_izni_olmayan_kilidi_degistiremez(): void
    {
        $viewer = $this->makeTenantWithUser(['devices.view']);
        $this->actingAs($viewer['user']);

        $this->postJson('/api/v1/devices/lock-feature', ['enabled' => true])->assertForbidden();
        $this->assertFalse(Features::enabled((int) $viewer['tenant']->id, 'device_lock'));
    }

    public function test_kiraci_izolasyonu_kilit_ayri_kiracilari_etkilemez(): void
    {
        $a = $this->makeTenantWithUser(['devices.manage']);
        $b = $this->makeTenantWithUser(['devices.manage']);

        $this->actingAs($a['user']);
        $this->postJson('/api/v1/devices/lock-feature', ['enabled' => true])->assertOk();

        $this->assertTrue(Features::enabled((int) $a['tenant']->id, 'device_lock'));
        $this->assertFalse(Features::enabled((int) $b['tenant']->id, 'device_lock'));
    }

    /* ---------------- İptal / yeniden etkinleştirme (panel köprüsü) ---------------- */

    public function test_yetkili_cihazi_iptal_eder_ve_yeniden_etkinlestirir(): void
    {
        $manager = $this->makeTenantWithUser(['devices.manage']);
        $this->actingAs($manager['user']);

        $created = $this->postJson('/api/v1/devices', ['kind' => 'kiosk', 'name' => 'Test Kiosk'])
            ->assertCreated();
        $id = $created->json('device.id');

        $this->postJson("/api/v1/devices/{$id}/revoke")->assertOk()
            ->assertJsonPath('device.status', 'revoked');

        $this->postJson("/api/v1/devices/{$id}/reactivate")->assertOk()
            ->assertJsonPath('device.status', 'active');
    }
}
