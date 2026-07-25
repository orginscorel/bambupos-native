<?php

namespace Tests\Feature\Kiosk;

use App\Modules\Kiosk\Models\KioskDevice;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Kiosk cihaz yönetimi: yetki (settings.manage), kiracı izolasyonu,
 * token rotasyonu (eski adres 410), uzaktan kilit, silme.
 */
class KioskDeviceManagementTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    private array $a;

    private array $b;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->b = $this->makeTenantWithUser();
    }

    private function makeDevice(array $ctx, array $attrs = []): KioskDevice
    {
        return $this->asTenant($ctx['tenant'], function () use ($ctx, $attrs): KioskDevice {
            $device = new KioskDevice(array_merge([
                'name' => 'Test Kiosk',
                'status' => KioskDevice::STATUS_ACTIVE,
                'payment_mode' => KioskDevice::MODE_KIOSK_POS,
            ], $attrs));
            $device->branch_id = (int) $ctx['branch']->id;
            $device->save();

            return $device;
        });
    }

    public function test_yetkili_cihaz_ekler_token_uretilir(): void
    {
        $this->actingAs($this->a['user']);

        $res = $this->postJson('/api/v1/kiosk/devices', [
            'name' => 'Giriş Kiosk',
            'branch_id' => $this->a['branch']->id,
            'payment_mode' => 'kiosk_pos',
        ])->assertCreated();

        $device = KioskDevice::withoutTenancy()->first();
        $this->assertSame((int) $this->a['tenant']->id, (int) $device->tenant_id);
        $this->assertMatchesRegularExpression('/^[A-Z2-7]{26}$/', $device->token);
        $this->assertStringContainsString('/kiosk/'.$device->token, $res->json('device.url'));
    }

    public function test_settings_manage_olmayan_yonetemez(): void
    {
        $limited = $this->makeTenantWithUser(['orders.view']);
        $this->actingAs($limited['user']);

        $this->getJson('/api/v1/kiosk/devices')->assertForbidden();
        $this->postJson('/api/v1/kiosk/devices', [
            'name' => 'X', 'branch_id' => $limited['branch']->id, 'payment_mode' => 'counter',
        ])->assertForbidden();
        $this->get('/panel/kiosklar')->assertForbidden();
    }

    public function test_yabanci_kiracinin_cihazi_yonetilemez(): void
    {
        $device = $this->makeDevice($this->b);

        $this->actingAs($this->a['user']);

        // TenantScope: yabancı cihaz görünmez → 404 (fail closed)
        $this->putJson('/api/v1/kiosk/devices/'.$device->id, ['name' => 'Ele geçti'])->assertNotFound();
        $this->postJson('/api/v1/kiosk/devices/'.$device->id.'/lock')->assertNotFound();
        $this->deleteJson('/api/v1/kiosk/devices/'.$device->id)->assertNotFound();

        // Listede de yoktur
        $this->assertSame([], $this->getJson('/api/v1/kiosk/devices')->json('devices'));
    }

    public function test_baska_subeye_cihaz_acilamaz(): void
    {
        $this->actingAs($this->a['user']);

        $this->postJson('/api/v1/kiosk/devices', [
            'name' => 'Sızma', 'branch_id' => $this->b['branch']->id, 'payment_mode' => 'counter',
        ])->assertUnprocessable();
    }

    public function test_token_rotasyonu_eski_adresi_aninda_gecersiz_kilar(): void
    {
        $device = $this->makeDevice($this->a);
        $oldToken = $device->token;

        $this->get('/kiosk/'.$oldToken)->assertOk();

        $this->actingAs($this->a['user']);
        $res = $this->postJson('/api/v1/kiosk/devices/'.$device->id.'/rotate-token')->assertOk();

        $newToken = KioskDevice::withoutTenancy()->find($device->id)->token;
        $this->assertNotSame($oldToken, $newToken);

        // Eski token 410 (rotasyon izi), yeni token çalışır
        $this->get('/kiosk/'.$oldToken)->assertGone();
        $this->get('/kiosk/'.$newToken)->assertOk();
        $this->assertStringContainsString($newToken, $res->json('device.url'));
    }

    public function test_uzaktan_kilit_ekrani_ve_siparisi_kapatir(): void
    {
        $device = $this->makeDevice($this->a);

        $this->actingAs($this->a['user']);
        $this->postJson('/api/v1/kiosk/devices/'.$device->id.'/lock')->assertOk();

        // Ekran kilit sayfası döner; sipariş ucu 423
        $this->get('/kiosk/'.$device->token)->assertOk()->assertSee('kilitlendi');
        $this->postJson('/kiosk/api/orders', [
            'token' => $device->token, 'order_type' => 'takeaway',
            'items' => [['product_id' => 1, 'qty' => 1]],
        ])->assertStatus(423);

        // Kalp atışı "locked" bildirir
        $this->postJson('/kiosk/api/heartbeat', ['token' => $device->token])
            ->assertOk()->assertJsonPath('status', 'locked');

        // Kilit açılınca normale döner
        $this->postJson('/api/v1/kiosk/devices/'.$device->id.'/unlock')->assertOk();
        $this->postJson('/kiosk/api/heartbeat', ['token' => $device->token])
            ->assertOk()->assertJsonPath('status', 'ok');
    }

    public function test_silinen_cihazin_adresi_calismaz(): void
    {
        $device = $this->makeDevice($this->a);

        $this->actingAs($this->a['user']);
        $this->deleteJson('/api/v1/kiosk/devices/'.$device->id)->assertNoContent();

        $this->get('/kiosk/'.$device->token)->assertNotFound();
    }
}
