<?php

namespace Tests\Feature\Kiosk;

use App\Modules\Kiosk\Models\KioskDevice;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Kiosk ekranı: kiracı izolasyonu (token yalnız kendi menüsünü görür),
 * kanal süzgeci + kiosk fiyatı, oturumsuzluk (Set-Cookie yok — §18),
 * istemci tarafında kalıcı depolama kullanılmadığının bekçi testi.
 */
class KioskScreenTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

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

    public function test_kiosk_yalniz_kendi_kiracisinin_menusunu_gorur(): void
    {
        $this->makeProduct($this->a, ['name' => 'Adana Kebap Kiosk']);
        $this->makeProduct($this->b, ['name' => 'Rakip Lahmacun Gizli']);

        $device = $this->makeDevice($this->a);

        $res = $this->get('/kiosk/'.$device->token)->assertOk();

        $res->assertSee('Adana Kebap Kiosk');
        $res->assertDontSee('Rakip Lahmacun Gizli');
    }

    public function test_kanal_suzgeci_ve_kiosk_fiyati(): void
    {
        // kiosk kanalına kapalı ürün görünmez
        $this->makeProduct($this->a, ['name' => 'Sadece QR Urunu', 'channels' => ['qr']]);
        // kiosk fiyatı olan ürün kiosk fiyatıyla listelenir
        $this->makeProduct($this->a, [
            'name' => 'Kiosk Ozel Menu',
            'price_minor' => 20000,
            'kiosk_price_minor' => 17500,
            'channels' => ['qr', 'kiosk', 'pos'],
        ]);

        $device = $this->makeDevice($this->a);
        $res = $this->get('/kiosk/'.$device->token)->assertOk();

        $res->assertDontSee('Sadece QR Urunu');
        $res->assertSee('Kiosk Ozel Menu');
        $res->assertSee('"price_minor":17500', false);
    }

    public function test_kiosk_yuzeyi_oturumsuzdur_cerez_birakmaz(): void
    {
        $device = $this->makeDevice($this->a);

        // §18: kiosk yanıtı çerez/oturum taşımaz — sunucuda müşteri izi yok.
        $this->get('/kiosk/'.$device->token)->assertOk()->assertHeaderMissing('Set-Cookie');
        $this->postJson('/kiosk/api/heartbeat', ['token' => $device->token])
            ->assertOk()->assertHeaderMissing('Set-Cookie');
    }

    public function test_istemci_kalici_depolama_kullanmaz(): void
    {
        // Bekçi test (§18): sepet/isim yalnız bellekte tutulur; kiosk.js'e
        // localStorage/sessionStorage/çerez girerse bu test düşer.
        $js = (string) file_get_contents(public_path('assets/kiosk.js'));

        $this->assertStringNotContainsString('localStorage', $js);
        $this->assertStringNotContainsString('sessionStorage', $js);
        $this->assertStringNotContainsString('document.cookie', $js);
        $this->assertStringNotContainsString('indexedDB', $js);

        // Sıfırlama tam sayfa yeniden yüklemedir (bellek tamamen boşalır).
        $this->assertStringContainsString('location.reload()', $js);
    }

    public function test_gecersiz_token_404_bicimsiz_token_db_gormez(): void
    {
        $this->get('/kiosk/AAAAAAAAAAAAAAAAAAAAAAAAAA')->assertNotFound();
        $this->get('/kiosk/kisa')->assertNotFound();
    }

    public function test_pasif_kiraci_veya_sube_410(): void
    {
        $device = $this->makeDevice($this->a);

        $this->asTenant($this->a['tenant'], fn () => $this->a['branch']->update(['is_active' => false]));

        $this->get('/kiosk/'.$device->token)->assertGone();
    }
}
