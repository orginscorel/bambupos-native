<?php

namespace Tests\Feature\Catalog;

use App\Modules\Catalog\Models\Allergen;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/** Katalog CRUD akışları: kategori, ürün (varyant/seçenek/alerjen), menü, sıralama. */
class CatalogCrudTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);
    }

    public function test_kategori_olusturma_ve_siralama(): void
    {
        $c1 = $this->postJson('/api/v1/catalog/categories', ['name' => 'Çorbalar'])
            ->assertCreated()->json('category');
        $c2 = $this->postJson('/api/v1/catalog/categories', ['name' => 'Ana Yemekler'])
            ->assertCreated()->json('category');

        $this->assertSame('corbalar', $c1['slug']);
        $this->assertSame((int) $this->a['tenant']->id, (int) $c1['tenant_id']);

        // Aynı ad → benzersiz slug türetilir
        $c3 = $this->postJson('/api/v1/catalog/categories', ['name' => 'Çorbalar'])
            ->assertCreated()->json('category');
        $this->assertSame('corbalar-2', $c3['slug']);

        // Drag-drop sıralama
        $this->postJson('/api/v1/catalog/categories/reorder', ['ids' => [$c2['id'], $c1['id'], $c3['id']]])
            ->assertOk();

        $this->assertDatabaseHas('categories', ['id' => $c2['id'], 'sort_order' => 10]);
        $this->assertDatabaseHas('categories', ['id' => $c1['id'], 'sort_order' => 20]);
    }

    public function test_urun_varyant_secenek_ve_alerjenle_olusturulur_ve_guncellenir(): void
    {
        $category = $this->postJson('/api/v1/catalog/categories', ['name' => 'Pizzalar'])->json('category');

        $group = $this->postJson('/api/v1/catalog/option-groups', [
            'name' => 'Ekstra Malzemeler',
            'selection_type' => 'multiple',
            'free_limit' => 1,
            'options' => [
                ['name' => 'Mantar', 'price_minor' => 1000],
                ['name' => 'Ekstra Peynir', 'price_minor' => 1500],
            ],
        ])->assertCreated()->json('option_group');

        $allergen = $this->postJson('/api/v1/catalog/allergens', [
            'kind' => 'allergen', 'name' => 'Ev Baharatı', 'description' => 'İşletmeye özel karışım.',
        ])->assertCreated()->json('allergen');

        $product = $this->postJson('/api/v1/catalog/products', [
            'name' => 'Margherita',
            'description' => 'Domates sos, mozzarella, fesleğen',
            'category_id' => $category['id'],
            'price_minor' => 25000,
            'tax_rate' => 10,
            'channels' => ['qr', 'pos'],
            'spiciness' => 0,
            'is_new' => true,
            'variants' => [
                ['name' => 'Küçük', 'price_minor' => 20000, 'is_default' => true],
                ['name' => 'Büyük', 'price_minor' => 30000],
            ],
            'option_group_ids' => [$group['id']],
            'allergen_ids' => [$allergen['id']],
        ])->assertCreated()->json('product');

        $this->assertCount(2, $product['variants']);
        $this->assertCount(1, $product['option_groups']);
        $this->assertCount(1, $product['allergens']);
        $this->assertSame(25000, $product['price_minor']);

        // Güncelleme: varyantlardan biri silinir, biri güncellenir, yeni eklenir
        $updated = $this->putJson("/api/v1/catalog/products/{$product['id']}", [
            'name' => 'Margherita',
            'price_minor' => 25000,
            'variants' => [
                ['id' => $product['variants'][0]['id'], 'name' => 'Küçük Boy', 'price_minor' => 21000, 'is_default' => true],
                ['name' => 'Orta', 'price_minor' => 26000],
            ],
        ])->assertOk()->json('product');

        $names = array_column($updated['variants'], 'name');
        $this->assertSame(['Küçük Boy', 'Orta'], $names);
        $this->assertDatabaseMissing('product_variants', ['id' => $product['variants'][1]['id']]);
    }

    public function test_urun_listesi_arama_ve_filtre(): void
    {
        $category = $this->postJson('/api/v1/catalog/categories', ['name' => 'İçecekler'])->json('category');

        $this->postJson('/api/v1/catalog/products', [
            'name' => 'Ayran', 'price_minor' => 4000, 'category_id' => $category['id'], 'sku' => 'AYR-1',
        ])->assertCreated();
        $this->postJson('/api/v1/catalog/products', [
            'name' => 'Kola', 'price_minor' => 6000, 'is_active' => false,
        ])->assertCreated();

        // Arama
        $found = $this->getJson('/api/v1/catalog/products?q=ayran')->assertOk()->json('products.data');
        $this->assertCount(1, $found);
        $this->assertSame('Ayran', $found[0]['name']);

        // SKU araması
        $found = $this->getJson('/api/v1/catalog/products?q=AYR-1')->assertOk()->json('products.data');
        $this->assertCount(1, $found);

        // Kategori filtresi
        $found = $this->getJson("/api/v1/catalog/products?category_id={$category['id']}")->assertOk()->json('products.data');
        $this->assertCount(1, $found);

        // Durum filtresi
        $found = $this->getJson('/api/v1/catalog/products?status=passive')->assertOk()->json('products.data');
        $this->assertCount(1, $found);
        $this->assertSame('Kola', $found[0]['name']);
    }

    public function test_menu_planlama_zaman_gun_kanal_ve_kategori_atamasi(): void
    {
        $category = $this->postJson('/api/v1/catalog/categories', ['name' => 'Kahvaltılar'])->json('category');

        $menu = $this->postJson('/api/v1/catalog/menus', [
            'name' => 'Kahvaltı Menüsü',
            'days' => [6, 7, 1],
            'start_time' => '07:00',
            'end_time' => '12:30',
            'channels' => ['qr', 'kiosk'],
            'category_ids' => [$category['id']],
        ])->assertCreated()->json('menu');

        $this->assertSame([1, 6, 7], $menu['days']); // normalize edilir
        $this->assertSame(['qr', 'kiosk'], $menu['channels']);
        $this->assertCount(1, $menu['categories']);

        $this->putJson("/api/v1/catalog/menus/{$menu['id']}", [
            'name' => 'Kahvaltı', 'category_ids' => [],
        ])->assertOk();

        $this->assertDatabaseMissing('category_menu', ['menu_id' => $menu['id']]);
    }

    public function test_gecersiz_kanal_ve_saat_reddedilir(): void
    {
        $this->postJson('/api/v1/catalog/products', [
            'name' => 'X', 'price_minor' => 100, 'channels' => ['dolap'],
        ])->assertStatus(422);

        $this->postJson('/api/v1/catalog/menus', [
            'name' => 'X', 'start_time' => '25:99',
        ])->assertStatus(422);
    }

    public function test_seed_kuresel_alerjen_sozlugu_14_alerjen_7_diyet(): void
    {
        $this->seed(\Database\Seeders\CatalogSeeder::class);

        $this->assertSame(14, Allergen::query()->withoutGlobalScopes()
            ->whereNull('tenant_id')->where('kind', 'allergen')->count());
        $this->assertSame(7, Allergen::query()->withoutGlobalScopes()
            ->whereNull('tenant_id')->where('kind', 'diet')->count());

        // Ad + açıklama zorunlu doluluk (ikon tek başına yeterli değil)
        $this->assertSame(0, Allergen::query()->withoutGlobalScopes()
            ->whereNull('tenant_id')
            ->where(fn ($q) => $q->whereNull('description')->orWhere('description', ''))
            ->count());
    }
}
