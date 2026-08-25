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
 * istemci tarafında müşteri verisinin kalıcı depolanmadığının bekçi testi
 * (localStorage yalnız PII-olmayan cihaz-bağlama token'ına izinli — §18).
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

    public function test_istemci_kalici_depolama_sadece_cihaz_kimligine_izinli(): void
    {
        // Bekçi test (§18 — 2026-08-04 itibarıyla daraltılmış sözleşme):
        // müşteri SİPARİŞ/SEPET/KİŞİSEL verisi (sepet, isim, not, seçimler,
        // ödeme) yalnız bellekte (S nesnesi) tutulur ve ASLA kalıcı
        // depolamaya yazılmaz. sessionStorage/çerez/indexedDB kiosk.js'de
        // HİÇ geçmemeli. localStorage'a TEK istisna tanınır: device_lock
        // özelliği için PII-olmayan, opak cihaz-bağlama token'ı
        // ('bbpos_kiosk_device') — bu test her localStorage çağrısının
        // yalnız o anahtarla yapıldığını ve hiçbirinin müşteri verisi
        // alanı (cart/name/note/order/receipt/paymentRef/S.) TAŞIMADIĞINI
        // doğrular. Kiosk.js'e sepet/isim/not gibi müşteri verisini kalıcı
        // depolamaya yazan YENİ bir çağrı eklenirse bu test düşer.
        $js = (string) file_get_contents(public_path('assets/kiosk.js'));

        $this->assertStringNotContainsString('sessionStorage', $js);
        $this->assertStringNotContainsString('document.cookie', $js);
        $this->assertStringNotContainsString('indexedDB', $js);

        // localStorage yalnız cihaz-kilidi kimliği için kullanılabilir;
        // ham anahtar dizesi tek bir sabitten (DEVICE_KEY) gelmeli.
        $this->assertMatchesRegularExpression(
            '/DEVICE_KEY\s*=\s*[\'"]bbpos_kiosk_device[\'"]/',
            $js
        );

        preg_match_all('/localStorage\.[a-zA-Z]+\([^)]*\)/', $js, $matches);
        $this->assertNotEmpty($matches[0], 'localStorage cihaz-kilidi kodu bulunamadı (device_lock kaldırıldıysa bu satır da temizlenmeli).');

        $forbiddenCustomerDataTokens = [
            'cart', 'name', 'note', 'order', 'receipt', 'paymentRef', 'S.',
        ];

        foreach ($matches[0] as $call) {
            $this->assertStringContainsString(
                'DEVICE_KEY',
                $call,
                "localStorage çağrısı DEVICE_KEY dışında bir anahtar kullanıyor: {$call}"
            );

            foreach ($forbiddenCustomerDataTokens as $forbidden) {
                $this->assertStringNotContainsString(
                    $forbidden,
                    $call,
                    "localStorage çağrısı müşteri verisi alanı içeriyor ({$forbidden}): {$call}"
                );
            }
        }

        // Sıfırlama tam sayfa yeniden yüklemedir (bellek/S nesnesi tamamen
        // boşalır; cihaz kimliği kasıtlı olarak localStorage'da kalır).
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
