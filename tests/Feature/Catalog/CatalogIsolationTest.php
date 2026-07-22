<?php

namespace Tests\Feature\Catalog;

use App\Modules\Catalog\Models\Allergen;
use App\Modules\Catalog\Models\Category;
use App\Modules\Catalog\Models\Menu;
use App\Modules\Catalog\Models\OptionGroup;
use App\Modules\Catalog\Models\Product;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Katalog kiracı izolasyonu (ADR-004): A işletmesinin kullanıcısı B'nin
 * kategori/ürün/seçenek/menü/alerjen verisine ERİŞEMEZ.
 */
class CatalogIsolationTest extends TestCase
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

    private function makeCategoryFor(int $tenantId, string $name = 'Kategori'): Category
    {
        return tap(new Category([
            'name' => $name, 'slug' => uniqid('kat-'), 'is_active' => true,
        ]), function (Category $c) use ($tenantId): void {
            $c->tenant_id = $tenantId;
            $c->save();
        });
    }

    public function test_a_b_nin_kategorisini_goremez_guncelleyemez_silemez(): void
    {
        $bCategory = $this->makeCategoryFor($this->b['tenant']->id, 'B Kategorisi');

        $this->actingAs($this->a['user']);

        $this->putJson("/api/v1/catalog/categories/{$bCategory->id}", ['name' => 'ele geçirildi'])->assertNotFound();
        $this->deleteJson("/api/v1/catalog/categories/{$bCategory->id}")->assertNotFound();

        $this->assertDatabaseHas('categories', ['id' => $bCategory->id, 'name' => 'B Kategorisi']);
    }

    public function test_kategori_listesi_yalniz_kendi_kiracisini_doner(): void
    {
        $aCategory = $this->makeCategoryFor($this->a['tenant']->id, 'A Kategorisi');
        $bCategory = $this->makeCategoryFor($this->b['tenant']->id, 'B Kategorisi');

        $ids = collect($this->actingAs($this->a['user'])
            ->getJson('/api/v1/catalog/categories')
            ->assertOk()
            ->json('categories'))->pluck('id');

        $this->assertTrue($ids->contains($aCategory->id));
        $this->assertFalse($ids->contains($bCategory->id));
    }

    public function test_a_b_nin_urun_duzenleme_sayfasina_ve_json_una_erisemez(): void
    {
        $bProduct = Product::factory()->create(['tenant_id' => $this->b['tenant']->id]);

        $this->actingAs($this->a['user']);

        $this->get("/panel/menu/urunler/{$bProduct->id}")->assertNotFound();
        $this->getJson("/api/v1/catalog/products/{$bProduct->id}")->assertNotFound();
        $this->putJson("/api/v1/catalog/products/{$bProduct->id}", ['name' => 'x', 'price_minor' => 1])->assertNotFound();
        $this->deleteJson("/api/v1/catalog/products/{$bProduct->id}")->assertNotFound();
    }

    public function test_urun_b_nin_kategorisine_atanamaz(): void
    {
        $bCategory = $this->makeCategoryFor($this->b['tenant']->id);

        $this->actingAs($this->a['user'])
            ->postJson('/api/v1/catalog/products', [
                'name' => 'Deneme Ürün',
                'price_minor' => 1000,
                'category_id' => $bCategory->id,
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['category_id']);
    }

    public function test_toplu_islem_b_nin_urununu_etkilemez(): void
    {
        $bProduct = Product::factory()->create(['tenant_id' => $this->b['tenant']->id, 'is_active' => true]);

        $this->actingAs($this->a['user'])
            ->postJson('/api/v1/catalog/products/bulk', [
                'action' => 'deactivate',
                'ids' => [$bProduct->id],
            ])
            ->assertOk()
            ->assertJsonPath('affected', 0);

        $this->assertDatabaseHas('products', ['id' => $bProduct->id, 'is_active' => 1]);
    }

    public function test_a_b_nin_secenek_grubunu_ve_menusunu_goremez(): void
    {
        $bGroup = tap(new OptionGroup(['name' => 'B Grubu', 'selection_type' => 'multiple']), function ($g): void {
            $g->tenant_id = $this->b['tenant']->id;
            $g->save();
        });
        $bMenu = tap(new Menu(['name' => 'B Menüsü']), function ($m): void {
            $m->tenant_id = $this->b['tenant']->id;
            $m->save();
        });

        $this->actingAs($this->a['user']);

        $this->putJson("/api/v1/catalog/option-groups/{$bGroup->id}", [
            'name' => 'x', 'selection_type' => 'multiple',
        ])->assertNotFound();
        $this->deleteJson("/api/v1/catalog/option-groups/{$bGroup->id}")->assertNotFound();
        $this->putJson("/api/v1/catalog/menus/{$bMenu->id}", ['name' => 'x'])->assertNotFound();
        $this->deleteJson("/api/v1/catalog/menus/{$bMenu->id}")->assertNotFound();
    }

    public function test_kuresel_alerjen_herkese_gorunur_ama_kimse_degistiremez(): void
    {
        $global = app(\App\Modules\Tenancy\TenantContext::class)->runWithoutTenancy(
            fn () => Allergen::query()->withoutGlobalScopes()->create([
                'kind' => 'allergen', 'code' => 'gluten', 'name' => 'Gluten', 'description' => 'Test',
            ]),
        );

        $this->actingAs($this->a['user']);

        $ids = collect($this->getJson('/api/v1/catalog/allergens')->assertOk()->json('allergens'))->pluck('id');
        $this->assertTrue($ids->contains($global->id));

        $this->putJson("/api/v1/catalog/allergens/{$global->id}", [
            'kind' => 'allergen', 'name' => 'Hack', 'description' => 'x',
        ])->assertForbidden();
        $this->deleteJson("/api/v1/catalog/allergens/{$global->id}")->assertForbidden();
    }

    public function test_a_b_nin_ozel_alerjenini_goremez_ve_degistiremez(): void
    {
        $bAllergen = app(\App\Modules\Tenancy\TenantContext::class)->runWithoutTenancy(
            function () {
                // tenant_id fillable DEĞİL (mass-assignment koruması) → açıkça atanır
                $allergen = new Allergen([
                    'kind' => 'allergen', 'code' => 'custom-b', 'name' => 'B Özel', 'description' => 'B kiracısına özel',
                ]);
                $allergen->tenant_id = $this->b['tenant']->id;
                $allergen->save();

                return $allergen;
            },
        );

        $this->actingAs($this->a['user']);

        $ids = collect($this->getJson('/api/v1/catalog/allergens')->assertOk()->json('allergens'))->pluck('id');
        $this->assertFalse($ids->contains($bAllergen->id));

        $this->putJson("/api/v1/catalog/allergens/{$bAllergen->id}", [
            'kind' => 'allergen', 'name' => 'x', 'description' => 'x',
        ])->assertNotFound();
        $this->deleteJson("/api/v1/catalog/allergens/{$bAllergen->id}")->assertNotFound();
    }

    public function test_siralama_ucu_b_nin_kayitlarini_gunceleyemez(): void
    {
        $aCategory = $this->makeCategoryFor($this->a['tenant']->id);
        $bCategory = $this->makeCategoryFor($this->b['tenant']->id);
        $bOldSort = (int) $bCategory->refresh()->sort_order;

        $this->actingAs($this->a['user'])
            ->postJson('/api/v1/catalog/categories/reorder', [
                'ids' => [$bCategory->id, $aCategory->id],
            ])
            ->assertOk();

        $this->assertDatabaseHas('categories', ['id' => $bCategory->id, 'sort_order' => $bOldSort]);
    }
}
