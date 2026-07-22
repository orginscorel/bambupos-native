<?php

namespace Tests\Feature\Catalog;

use App\Modules\Catalog\Models\Product;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/** catalog.* izin denetimi: izinsiz kullanıcı katalog ekran ve uçlarına giremez. */
class CatalogAuthorizationTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
    }

    public function test_catalog_view_izni_olmayan_panel_ve_json_uclarina_giremez(): void
    {
        $noPerm = $this->makeTenantWithUser(['orders.view']); // katalog izni yok

        $this->actingAs($noPerm['user']);

        $this->get('/panel/menu')->assertForbidden();
        $this->get('/panel/menu/kategoriler')->assertForbidden();
        $this->get('/panel/menu/secenekler')->assertForbidden();
        $this->get('/panel/menu/alerjenler')->assertForbidden();
        $this->get('/panel/menu/menuler')->assertForbidden();

        $this->getJson('/api/v1/catalog/products')->assertForbidden();
        $this->getJson('/api/v1/catalog/categories')->assertForbidden();
        $this->getJson('/api/v1/catalog/option-groups')->assertForbidden();
        $this->getJson('/api/v1/catalog/allergens')->assertForbidden();
        $this->getJson('/api/v1/catalog/menus')->assertForbidden();
    }

    public function test_catalog_view_izni_olan_ama_create_izni_olmayan_urun_ekleyemez(): void
    {
        $viewer = $this->makeTenantWithUser(['catalog.view']);

        $this->actingAs($viewer['user']);

        $this->get('/panel/menu')->assertOk();
        $this->get('/panel/menu/urunler/yeni')->assertForbidden();

        $this->postJson('/api/v1/catalog/products', ['name' => 'X', 'price_minor' => 100])
            ->assertForbidden();
        $this->postJson('/api/v1/catalog/categories', ['name' => 'X'])->assertForbidden();
    }

    public function test_update_izni_var_ama_change_price_izni_yoksa_fiyat_degistiremez(): void
    {
        $editor = $this->makeTenantWithUser(['catalog.view', 'catalog.update']);
        $product = Product::factory()->create([
            'tenant_id' => $editor['tenant']->id,
            'price_minor' => 10000,
        ]);

        $this->actingAs($editor['user']);

        // Ad değişikliği serbest
        $this->putJson("/api/v1/catalog/products/{$product->id}", [
            'name' => 'Yeni Ad', 'price_minor' => 10000,
        ])->assertOk();

        // Fiyat değişikliği 403
        $this->putJson("/api/v1/catalog/products/{$product->id}", [
            'name' => 'Yeni Ad', 'price_minor' => 99999,
        ])->assertForbidden();

        $this->assertDatabaseHas('products', ['id' => $product->id, 'price_minor' => 10000]);
    }

    public function test_delete_izni_olmayan_toplu_silme_yapamaz(): void
    {
        $editor = $this->makeTenantWithUser(['catalog.view', 'catalog.update']);
        $product = Product::factory()->create(['tenant_id' => $editor['tenant']->id]);

        $this->actingAs($editor['user'])
            ->postJson('/api/v1/catalog/products/bulk', ['action' => 'delete', 'ids' => [$product->id]])
            ->assertForbidden();

        $this->assertDatabaseHas('products', ['id' => $product->id]);
    }

    public function test_oturumsuz_istek_401_json_panel_sayfasi_girise_yonlenir(): void
    {
        $this->getJson('/api/v1/catalog/products')->assertUnauthorized();
        $this->get('/panel/menu')->assertRedirect('/giris');
    }
}
