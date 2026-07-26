<?php

namespace Tests\Feature\Settings;

use App\Modules\Settings\Support\FeatureCatalog;
use App\Modules\Settings\Support\Features;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * §9 Eklentiler / feature-flag: depo+servis, Eklentiler API'si (yetki, aç/kapa),
 * varsayılanlar, kiracı izolasyonu ve kapalı-özellik-görünmez (panel rota 404 +
 * public QR sipariş 403) davranışı.
 */
class FeaturesTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    /* ================= Servis / varsayılanlar ================= */

    public function test_satir_yoksa_katalog_varsayilani_gecerlidir(): void
    {
        $setup = $this->makeTenantWithUser(['orders.view']);

        // Hiç satır yok → tüm opsiyonel özellikler varsayılan (açık).
        foreach (FeatureCatalog::keys() as $key) {
            $this->assertSame(
                FeatureCatalog::default($key),
                Features::enabled((int) $setup['tenant']->id, $key),
            );
        }
    }

    public function test_set_ile_kapatilan_ozellik_kapali_okunur(): void
    {
        $setup = $this->makeTenantWithUser();
        $tenantId = (int) $setup['tenant']->id;

        Features::set($tenantId, 'kiosk', false);

        $this->assertFalse(Features::enabled($tenantId, 'kiosk'));
        $this->assertTrue(Features::enabled($tenantId, 'reservations'));
        $this->assertDatabaseHas('tenant_features', [
            'tenant_id' => $tenantId, 'feature' => 'kiosk', 'enabled' => false,
        ]);
    }

    public function test_cekirdek_veya_bilinmeyen_anahtar_daima_acik(): void
    {
        $setup = $this->makeTenantWithUser();

        // Katalogda olmayan (çekirdek) anahtar → fail-open true; yazılamaz.
        $this->assertTrue(Features::enabled((int) $setup['tenant']->id, 'orders'));
        Features::set((int) $setup['tenant']->id, 'orders', false);
        $this->assertDatabaseMissing('tenant_features', ['feature' => 'orders']);
    }

    public function test_feature_kiracilar_arasinda_izole(): void
    {
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        Features::set((int) $a['tenant']->id, 'inventory', false);

        $this->assertFalse(Features::enabled((int) $a['tenant']->id, 'inventory'));
        $this->assertTrue(Features::enabled((int) $b['tenant']->id, 'inventory'));
    }

    /* ================= Eklentiler API'si ================= */

    public function test_settings_manage_izni_olmayan_erisemez(): void
    {
        $setup = $this->makeTenantWithUser(['orders.view']);
        $this->actingAs($setup['user']);

        $this->getJson('/api/v1/settings/features')->assertForbidden();
        $this->putJson('/api/v1/settings/features', ['feature' => 'kiosk', 'enabled' => false])
            ->assertForbidden();
    }

    public function test_show_katalog_ve_durum_doner(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $this->actingAs($setup['user']);

        Features::set((int) $setup['tenant']->id, 'kiosk', false);

        $response = $this->getJson('/api/v1/settings/features')->assertOk();
        $features = collect($response->json('features'));

        $this->assertCount(count(FeatureCatalog::keys()), $features);
        $this->assertFalse($features->firstWhere('key', 'kiosk')['enabled']);
        $this->assertTrue($features->firstWhere('key', 'reservations')['enabled']);
    }

    public function test_update_ozelligi_kapatir(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $this->actingAs($setup['user']);

        $this->putJson('/api/v1/settings/features', ['feature' => 'reservations', 'enabled' => false])
            ->assertOk()
            ->assertJson(['feature' => 'reservations', 'enabled' => false]);

        $this->assertDatabaseHas('tenant_features', [
            'tenant_id' => $setup['tenant']->id, 'feature' => 'reservations', 'enabled' => false,
        ]);
    }

    public function test_update_bilinmeyen_anahtari_reddeder(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $this->actingAs($setup['user']);

        $this->putJson('/api/v1/settings/features', ['feature' => 'orders', 'enabled' => false])
            ->assertStatus(422);
    }

    /* ================= Kapalı = görünmez (rota gate) ================= */

    public function test_kapali_ozellik_panel_rotasi_404(): void
    {
        $setup = $this->makeTenantWithUser(['receivables.view']);
        $this->actingAs($setup['user']);

        // Açıkken erişilir.
        $this->get('/panel/borclar')->assertOk();

        Features::set((int) $setup['tenant']->id, 'receivables', false);

        // Kapalıyken 404 (ADR: kapalı=yok).
        $this->get('/panel/borclar')->assertNotFound();
    }

    public function test_kapali_qr_ordering_public_siparisi_reddeder(): void
    {
        $setup = $this->makeTenantWithUser();
        $table = $this->makeTable($setup);
        $product = $this->makeProduct($setup, ['name' => 'Çorba', 'price_minor' => 8000, 'qr_price_minor' => 7500]);

        $payload = ['token' => $table->qr_token, 'items' => [['product_id' => $product->id, 'qty' => 1]]];

        // Açıkken sipariş alınır (onay bekler).
        $this->postJson('/api/v1/public/orders', $payload)->assertCreated();

        // QR'dan sipariş kapatılınca aynı token 403 (menü yalnız görüntülenir).
        Features::set((int) $setup['tenant']->id, 'qr_ordering', false);
        $this->postJson('/api/v1/public/orders', $payload)->assertForbidden();
    }
}
