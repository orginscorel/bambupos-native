<?php

namespace Tests\Feature\Catalog;

use App\Modules\Catalog\Models\Product;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Satır içi "Satışta" / "Mevcut" switch'lerinin dar ucu
 * (PATCH /api/v1/catalog/products/{id}/availability).
 *
 * Hata kaydı (2026-07): switch'ler tam ürün güncelleme ucuna (PUT) gidiyor,
 * o uç name/price_minor zorunlu tuttuğu için "name alanı zorunlu" 422'siyle
 * hiçbir aç/kapa çalışmıyordu. Dar uç yalnız boolean(ları) doğrular.
 */
class ProductAvailabilityToggleTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
    }

    public function test_yalniz_is_active_gonderilerek_urun_satistan_kaldirilir(): void
    {
        $ctx = $this->makeTenantWithUser(['catalog.view', 'catalog.update']);
        $product = Product::factory()->create([
            'tenant_id' => $ctx['tenant']->id,
            'name' => 'Ayran',
            'is_active' => true,
        ]);

        $this->actingAs($ctx['user']);

        // name/price_minor göndermeden — tam form doğrulaması ÇALIŞMAMALI.
        $this->patchJson("/api/v1/catalog/products/{$product->id}/availability", ['is_active' => false])
            ->assertOk()
            ->assertJsonPath('product.is_active', false);

        $this->assertDatabaseHas('products', ['id' => $product->id, 'is_active' => false, 'name' => 'Ayran']);

        // Denetim kaydı düşer.
        $this->assertDatabaseHas('audit_logs', [
            'action' => 'catalog.product_availability_changed',
            'entity_id' => $product->id,
        ]);
    }

    public function test_yalniz_is_available_gonderilerek_tukendi_isaretlenir(): void
    {
        $ctx = $this->makeTenantWithUser(['catalog.view', 'catalog.update']);
        $product = Product::factory()->create([
            'tenant_id' => $ctx['tenant']->id,
            'is_available' => true,
        ]);

        $this->actingAs($ctx['user']);

        $this->patchJson("/api/v1/catalog/products/{$product->id}/availability", ['is_available' => false])
            ->assertOk()
            ->assertJsonPath('product.is_available', false);

        $this->patchJson("/api/v1/catalog/products/{$product->id}/availability", ['is_available' => true])
            ->assertOk()
            ->assertJsonPath('product.is_available', true);
    }

    public function test_bos_govde_422_doner(): void
    {
        $ctx = $this->makeTenantWithUser(['catalog.view', 'catalog.update']);
        $product = Product::factory()->create(['tenant_id' => $ctx['tenant']->id]);

        $this->actingAs($ctx['user']);

        $this->patchJson("/api/v1/catalog/products/{$product->id}/availability", [])
            ->assertUnprocessable();
    }

    public function test_update_izni_olmayan_switch_kullanamaz(): void
    {
        $ctx = $this->makeTenantWithUser(['catalog.view']); // update yok
        $product = Product::factory()->create(['tenant_id' => $ctx['tenant']->id, 'is_active' => true]);

        $this->actingAs($ctx['user']);

        $this->patchJson("/api/v1/catalog/products/{$product->id}/availability", ['is_active' => false])
            ->assertForbidden();

        $this->assertDatabaseHas('products', ['id' => $product->id, 'is_active' => true]);
    }

    public function test_yabanci_kiracinin_urunu_404(): void
    {
        $a = $this->makeTenantWithUser(['catalog.view', 'catalog.update']);
        $b = $this->makeTenantWithUser(['catalog.view', 'catalog.update']);

        $foreign = Product::factory()->create(['tenant_id' => $b['tenant']->id, 'is_active' => true]);

        $this->actingAs($a['user']);

        $this->patchJson("/api/v1/catalog/products/{$foreign->id}/availability", ['is_active' => false])
            ->assertNotFound();

        $this->assertDatabaseHas('products', ['id' => $foreign->id, 'is_active' => true]);
    }
}
