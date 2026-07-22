<?php

namespace Tests\Feature\Catalog;

use App\Modules\Catalog\Models\Product;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Görsel yükleme güvenliği (prompt §26.3):
 * uzantı + gerçek içerik doğrulaması, rastgele ad, tenant-izolasyonlu yol,
 * script dosyalarının reddi.
 */
class ProductImageUploadTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    private array $a;

    private Product $product;

    /** 1×1 geçerli PNG (gerçek görsel içerik). */
    private function validPngBytes(): string
    {
        return base64_decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
        );
    }

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('public');

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->product = Product::factory()->create(['tenant_id' => $this->a['tenant']->id]);

        $this->actingAs($this->a['user']);
    }

    public function test_gecerli_png_yuklenir_rastgele_adla_tenant_yolunda_saklanir(): void
    {
        $response = $this->post("/api/v1/catalog/products/{$this->product->id}/images", [
            'image' => UploadedFile::fake()->createWithContent('menü fotoğrafı.png', $this->validPngBytes()),
        ], ['Accept' => 'application/json'])->assertCreated();

        $path = $response->json('image.path');

        // Kiracı-izolasyonlu yol + rastgele dosya adı (istemci adı kullanılmaz)
        $tenantId = $this->a['tenant']->id;
        $this->assertMatchesRegularExpression(
            "#^tenants/{$tenantId}/products/{$this->product->id}/[a-z0-9]{40}\.png$#",
            $path,
        );
        Storage::disk('public')->assertExists($path);

        // Script çalıştırmayı kapatan .htaccess yazılmış olmalı
        Storage::disk('public')->assertExists('tenants/.htaccess');

        // İlk görsel otomatik kapak olur
        $this->assertTrue((bool) $response->json('image.is_primary'));
    }

    public function test_php_dosyasi_reddedilir(): void
    {
        $this->post("/api/v1/catalog/products/{$this->product->id}/images", [
            'image' => UploadedFile::fake()->createWithContent('shell.php', "<?php system('id');"),
        ], ['Accept' => 'application/json'])->assertStatus(422);

        $this->assertSame(0, $this->product->images()->count());
    }

    public function test_png_uzantili_ama_icerigi_php_olan_dosya_reddedilir(): void
    {
        $this->post("/api/v1/catalog/products/{$this->product->id}/images", [
            'image' => UploadedFile::fake()->createWithContent('sahte.png', "<?php echo 'pwned';"),
        ], ['Accept' => 'application/json'])->assertStatus(422);

        $this->assertSame(0, $this->product->images()->count());
    }

    public function test_exe_dosyasi_reddedilir(): void
    {
        $this->post("/api/v1/catalog/products/{$this->product->id}/images", [
            'image' => UploadedFile::fake()->createWithContent('zarar.exe', "MZ\x90\x00\x03"),
        ], ['Accept' => 'application/json'])->assertStatus(422);

        $this->assertSame(0, $this->product->images()->count());
    }

    public function test_cift_uzantili_dosya_reddedilir(): void
    {
        $this->post("/api/v1/catalog/products/{$this->product->id}/images", [
            'image' => UploadedFile::fake()->createWithContent('resim.php.png', "<?php phpinfo();"),
        ], ['Accept' => 'application/json'])->assertStatus(422);
    }

    public function test_baska_kiracinin_urunune_gorsel_yuklenemez(): void
    {
        // Fixture üretimi bilinçli kapsam dışı (aktif oturum A kiracısında)
        $bProduct = app(\App\Modules\Tenancy\TenantContext::class)->runWithoutTenancy(function () {
            $b = $this->makeTenantWithUser();

            return Product::factory()->create(['tenant_id' => $b['tenant']->id]);
        });

        $this->post("/api/v1/catalog/products/{$bProduct->id}/images", [
            'image' => UploadedFile::fake()->createWithContent('a.png', $this->validPngBytes()),
        ], ['Accept' => 'application/json'])->assertNotFound();
    }

    public function test_gorsel_silinince_dosya_da_silinir_ve_kapak_devrolur(): void
    {
        $first = $this->post("/api/v1/catalog/products/{$this->product->id}/images", [
            'image' => UploadedFile::fake()->createWithContent('a.png', $this->validPngBytes()),
        ], ['Accept' => 'application/json'])->json('image');

        $second = $this->post("/api/v1/catalog/products/{$this->product->id}/images", [
            'image' => UploadedFile::fake()->createWithContent('b.png', $this->validPngBytes()),
        ], ['Accept' => 'application/json'])->json('image');

        $this->delete("/api/v1/catalog/products/{$this->product->id}/images/{$first['id']}", [], [
            'Accept' => 'application/json',
        ])->assertOk();

        Storage::disk('public')->assertMissing($first['path']);
        $this->assertDatabaseHas('product_images', ['id' => $second['id'], 'is_primary' => 1]);
    }
}
