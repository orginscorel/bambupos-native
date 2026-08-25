<?php

declare(strict_types=1);

namespace Tests\Feature\Integrations;

use App\Modules\Integrations\Support\Integrations;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Takılabilir entegrasyon çerçevesi: yetki (integrations.manage), aç/kapa,
 * config kaydet + gizli alan maskeleme, kiracı izolasyonu ve KAPALI = graceful
 * no-op (enabled=false, config=[]).
 */
class IntegrationTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    /** Sunucu maskesi (IntegrationController::SECRET_MASK ile aynı). */
    private const MASK = '••••••••';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
        Integrations::flush();
    }

    /* ================= Yetki ================= */

    public function test_integrations_manage_izni_olmayan_403(): void
    {
        $setup = $this->makeTenantWithUser(['orders.view']);
        $this->actingAs($setup['user']);

        $this->getJson('/api/v1/integrations')->assertForbidden();
        $this->postJson('/api/v1/integrations/toggle', ['key' => 'iyzico', 'is_enabled' => true])
            ->assertForbidden();
        $this->postJson('/api/v1/integrations/config', ['key' => 'iyzico', 'config' => []])
            ->assertForbidden();
    }

    /* ================= Aç/kapa ================= */

    public function test_toggle_sonrasi_enabled_true(): void
    {
        $setup = $this->makeTenantWithUser(['integrations.manage']);
        $tenantId = (int) $setup['tenant']->id;
        $this->actingAs($setup['user']);

        // Başlangıçta kapalı (satır yok).
        $this->assertFalse(Integrations::enabled($tenantId, 'iyzico'));

        $this->postJson('/api/v1/integrations/toggle', ['key' => 'iyzico', 'is_enabled' => true])
            ->assertOk()
            ->assertJsonPath('integration.is_enabled', true)
            ->assertJsonPath('integration.status', 'unconfigured'); // açık ama yapılandırılmadı

        $this->assertTrue(Integrations::enabled($tenantId, 'iyzico'));
        $this->assertDatabaseHas('tenant_integrations', [
            'tenant_id' => $tenantId, 'key' => 'iyzico', 'is_enabled' => true,
        ]);
    }

    public function test_kapaliyken_enabled_false_ve_config_bos(): void
    {
        $setup = $this->makeTenantWithUser(['integrations.manage']);
        $tenantId = (int) $setup['tenant']->id;
        $this->actingAs($setup['user']);

        // Aç + yapılandır, sonra kapat: config saklı kalsa da graceful no-op.
        $this->postJson('/api/v1/integrations/toggle', ['key' => 'paytr', 'is_enabled' => true])->assertOk();
        $this->postJson('/api/v1/integrations/config', [
            'key' => 'paytr',
            'config' => ['merchant_id' => 'M123', 'merchant_key' => 'KEY', 'merchant_salt' => 'SALT'],
        ])->assertOk();

        $this->assertTrue(Integrations::enabled($tenantId, 'paytr'));
        $this->assertNotEmpty(Integrations::config($tenantId, 'paytr'));

        // Kapat → çerçeve sessiz: enabled=false, config=[] (pasif sistem etkilemez).
        $this->postJson('/api/v1/integrations/toggle', ['key' => 'paytr', 'is_enabled' => false])->assertOk();

        $this->assertFalse(Integrations::enabled($tenantId, 'paytr'));
        $this->assertSame([], Integrations::config($tenantId, 'paytr'));
    }

    /* ================= Config kaydet + maskeleme ================= */

    public function test_config_kaydedilir_ve_gizli_alan_maskeli_doner(): void
    {
        $setup = $this->makeTenantWithUser(['integrations.manage']);
        $tenantId = (int) $setup['tenant']->id;
        $this->actingAs($setup['user']);

        $this->postJson('/api/v1/integrations/toggle', ['key' => 'iyzico', 'is_enabled' => true])->assertOk();

        $response = $this->postJson('/api/v1/integrations/config', [
            'key' => 'iyzico',
            'config' => ['api_key' => 'PK-REAL-123', 'secret_key' => 'SK-REAL-999', 'sandbox' => '1'],
        ])->assertOk();

        // Açık (non-secret) alan olduğu gibi; gizli alanlar MASKELİ döner.
        $response->assertJsonPath('integration.config.sandbox', '1');
        $response->assertJsonPath('integration.config.api_key', self::MASK);
        $response->assertJsonPath('integration.config.secret_key', self::MASK);
        $response->assertJsonPath('integration.status', 'active'); // açık + yapılandırılmış

        // Gerçek gizli değer API cevabında hiçbir yerde geçmez.
        $this->assertStringNotContainsString('SK-REAL-999', $response->getContent() ?: '');

        // Sistem tarafı (Integrations) GERÇEK değeri okur.
        $this->assertSame('SK-REAL-999', Integrations::config($tenantId, 'iyzico')['secret_key']);
        $this->assertSame('PK-REAL-123', Integrations::config($tenantId, 'iyzico')['api_key']);
    }

    public function test_bos_gizli_alan_mevcut_degeri_korur(): void
    {
        $setup = $this->makeTenantWithUser(['integrations.manage']);
        $tenantId = (int) $setup['tenant']->id;
        $this->actingAs($setup['user']);

        $this->postJson('/api/v1/integrations/toggle', ['key' => 'iyzico', 'is_enabled' => true])->assertOk();
        $this->postJson('/api/v1/integrations/config', [
            'key' => 'iyzico',
            'config' => ['api_key' => 'PK-1', 'secret_key' => 'SK-1', 'sandbox' => '0'],
        ])->assertOk();

        // Gizli alanı BOŞ, açık alanı değiştirerek kaydet → gizli değer korunur.
        $this->postJson('/api/v1/integrations/config', [
            'key' => 'iyzico',
            'config' => ['api_key' => '', 'secret_key' => '', 'sandbox' => '1'],
        ])->assertOk();

        Integrations::flush($tenantId);
        $config = Integrations::config($tenantId, 'iyzico');
        $this->assertSame('SK-1', $config['secret_key']); // korundu
        $this->assertSame('PK-1', $config['api_key']);     // korundu
        $this->assertSame('1', $config['sandbox']);        // güncellendi
    }

    /* ================= Kiracı izolasyonu ================= */

    public function test_entegrasyon_kiracilar_arasinda_izole(): void
    {
        $a = $this->makeTenantWithUser(['integrations.manage']);
        $b = $this->makeTenantWithUser(['integrations.manage']);

        $this->actingAs($a['user'])
            ->postJson('/api/v1/integrations/toggle', ['key' => 'trendyol', 'is_enabled' => true])
            ->assertOk();

        Integrations::flush();
        $this->assertTrue(Integrations::enabled((int) $a['tenant']->id, 'trendyol'));
        $this->assertFalse(Integrations::enabled((int) $b['tenant']->id, 'trendyol'));
    }

    public function test_bilinmeyen_anahtar_reddedilir(): void
    {
        $setup = $this->makeTenantWithUser(['integrations.manage']);
        $this->actingAs($setup['user']);

        $this->postJson('/api/v1/integrations/toggle', ['key' => 'bilinmeyen', 'is_enabled' => true])
            ->assertStatus(422);
    }
}
