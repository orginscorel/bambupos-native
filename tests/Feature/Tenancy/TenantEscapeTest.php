<?php

namespace Tests\Feature\Tenancy;

use App\Modules\Catalog\Models\Product;
use App\Modules\Orders\Models\Customer;
use App\Modules\Orders\Models\Order;
use App\Modules\Tables\Models\Table;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * TENANT KAÇIŞI TESTLERİ (ADR-004 kanıtı):
 * A işletmesinin kullanıcısı, URL/parametre değiştirerek B'nin
 * ürün/sipariş/müşteri/masa/personel/rol/rapor verisine ERİŞEMEZ.
 */
class TenantEscapeTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    private array $a;

    private array $b;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser(); // tüm izinler
        $this->b = $this->makeTenantWithUser(); // tüm izinler
    }

    /* ---------------- ÜRÜN ---------------- */

    public function test_a_kullanicisi_b_nin_urununu_goremez_guncelleyemez_silemez(): void
    {
        $bProduct = Product::factory()->create(['tenant_id' => $this->b['tenant']->id]);

        $this->actingAs($this->a['user']);

        $this->getJson("/api/v1/products/{$bProduct->id}")->assertNotFound();
        $this->putJson("/api/v1/products/{$bProduct->id}", ['name' => 'ele geçirildi'])->assertNotFound();
        $this->deleteJson("/api/v1/products/{$bProduct->id}")->assertNotFound();

        $this->assertDatabaseHas('products', ['id' => $bProduct->id, 'name' => $bProduct->name]);
    }

    public function test_urun_listesinde_yalniz_kendi_kiracisinin_urunleri_doner(): void
    {
        $aProduct = Product::factory()->create(['tenant_id' => $this->a['tenant']->id]);
        $bProduct = Product::factory()->create(['tenant_id' => $this->b['tenant']->id]);

        $response = $this->actingAs($this->a['user'])->getJson('/api/v1/products')->assertOk();

        $ids = collect($response->json('products.data'))->pluck('id');

        $this->assertTrue($ids->contains($aProduct->id));
        $this->assertFalse($ids->contains($bProduct->id));
    }

    /* ---------------- SİPARİŞ ---------------- */

    public function test_a_kullanicisi_b_nin_siparisine_erisemez_ve_iptal_edemez(): void
    {
        $bOrder = Order::factory()->create([
            'tenant_id' => $this->b['tenant']->id,
            'branch_id' => $this->b['branch']->id,
        ]);

        $this->actingAs($this->a['user']);

        $this->getJson("/api/v1/orders/{$bOrder->id}")->assertNotFound();
        $this->postJson("/api/v1/orders/{$bOrder->id}/cancel")->assertNotFound();

        $this->assertDatabaseHas('orders', ['id' => $bOrder->id, 'status' => 'open']);
    }

    public function test_siparis_olustururken_b_nin_subesi_kullanilamaz(): void
    {
        $this->actingAs($this->a['user']);

        // Yabancı şube id'si: scoped Branch sorgusu çözmez → 422
        $this->postJson('/api/v1/orders', ['branch_id' => $this->b['branch']->id])
            ->assertUnprocessable();

        $this->assertDatabaseMissing('orders', ['branch_id' => $this->b['branch']->id]);
    }

    /* ---------------- MÜŞTERİ ---------------- */

    public function test_a_kullanicisi_b_nin_musterisine_erisemez(): void
    {
        $bCustomer = Customer::factory()->create(['tenant_id' => $this->b['tenant']->id]);

        $this->actingAs($this->a['user']);

        $this->getJson("/api/v1/customers/{$bCustomer->id}")->assertNotFound();
        $this->putJson("/api/v1/customers/{$bCustomer->id}", ['name' => 'X'])->assertNotFound();
        $this->deleteJson("/api/v1/customers/{$bCustomer->id}")->assertNotFound();
    }

    /* ---------------- MASA ----------------
     * NOT: Faz-1'in ayrı/paralel "/api/v1/tables" ucu (denetim ORTA #3) hiç
     * kullanılmadığı için kaldırıldı; masa yönetimi tek uçtan (VenueTableController,
     * "/api/v1/venue/tables") yapılıyor — tenant-kaçış kanıtı o uç üzerinden. */

    public function test_a_kullanicisi_b_nin_masasina_erisemez_qr_rotasyonu_yapamaz(): void
    {
        $bTable = Table::factory()->create([
            'tenant_id' => $this->b['tenant']->id,
            'branch_id' => $this->b['branch']->id,
        ]);

        $oldToken = $bTable->qr_token;

        $this->actingAs($this->a['user']);

        $this->putJson("/api/v1/venue/tables/{$bTable->id}", ['name' => 'ele geçirildi'])->assertNotFound();
        $this->postJson("/api/v1/venue/tables/{$bTable->id}/qr-rotate")->assertNotFound();

        $this->assertSame($oldToken, Table::withoutTenancy()->find($bTable->id)->qr_token);
    }

    /* ---------------- PERSONEL ---------------- */

    public function test_a_kullanicisi_b_nin_personelini_goremez_ve_degistiremez(): void
    {
        $bStaff = $this->b['user'];

        $this->actingAs($this->a['user']);

        $this->getJson("/api/v1/staff/{$bStaff->id}")->assertNotFound();
        $this->putJson("/api/v1/staff/{$bStaff->id}", ['first_name' => 'Hack'])->assertNotFound();
        $this->deleteJson("/api/v1/staff/{$bStaff->id}")->assertNotFound();
    }

    public function test_personel_listesi_yalniz_kendi_kiracisini_icerir(): void
    {
        $response = $this->actingAs($this->a['user'])->getJson('/api/v1/staff')->assertOk();

        $ids = collect($response->json('data'))->pluck('id');

        $this->assertTrue($ids->contains($this->a['user']->id));
        $this->assertFalse($ids->contains($this->b['user']->id));
    }

    /* ---------------- ROL ---------------- */

    public function test_a_kullanicisi_b_nin_rolune_erisemez(): void
    {
        $bRole = $this->b['role'];

        $this->actingAs($this->a['user']);

        $this->getJson("/api/v1/roles/{$bRole->id}")->assertNotFound();
        $this->putJson("/api/v1/roles/{$bRole->id}", ['name' => 'Ele Geçirildi'])->assertNotFound();
        $this->deleteJson("/api/v1/roles/{$bRole->id}")->assertNotFound();
    }

    public function test_personele_b_nin_rolu_atanamaz(): void
    {
        $this->actingAs($this->a['user']);

        $this->putJson("/api/v1/staff/{$this->a['user']->id}", [
            'roles' => [$this->b['role']->id],
        ])->assertUnprocessable();

        $this->assertDatabaseMissing('role_user', [
            'user_id' => $this->a['user']->id,
            'role_id' => $this->b['role']->id,
        ]);
    }

    /* ---------------- RAPOR ---------------- */

    public function test_rapor_ozeti_yalniz_kendi_kiracisinin_verisini_toplar(): void
    {
        Order::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'total_minor' => 10000,
        ]);
        Order::factory()->create([
            'tenant_id' => $this->b['tenant']->id,
            'branch_id' => $this->b['branch']->id,
            'total_minor' => 999999,
        ]);

        $this->actingAs($this->a['user'])
            ->getJson('/api/v1/reports/summary')
            ->assertOk()
            ->assertJson(['orders' => 1, 'revenue_minor' => 10000]);
    }

    /* ---------------- MASS ASSIGNMENT / PARAMETRE ZORLAMA ---------------- */

    public function test_istekten_gonderilen_tenant_id_yok_sayilir(): void
    {
        $this->actingAs($this->a['user']);

        $this->postJson('/api/v1/products', [
            'name' => 'Sızma Denemesi',
            'tenant_id' => $this->b['tenant']->id, // fillable değil → yok sayılır
        ])->assertCreated();

        $this->assertDatabaseHas('products', [
            'name' => 'Sızma Denemesi',
            'tenant_id' => $this->a['tenant']->id,
        ]);
        $this->assertDatabaseMissing('products', [
            'name' => 'Sızma Denemesi',
            'tenant_id' => $this->b['tenant']->id,
        ]);
    }

    /* ---------------- DENETİM KAYDI ---------------- */

    public function test_a_kullanicisi_b_nin_denetim_kayitlarini_goremez(): void
    {
        Product::factory()->create(['tenant_id' => $this->b['tenant']->id]); // B'ye audit satırı üretir

        $response = $this->actingAs($this->a['user'])->getJson('/api/v1/audit-logs')->assertOk();

        $tenantIds = collect($response->json('audit_logs.data'))->pluck('tenant_id')->unique()->filter();

        $this->assertFalse($tenantIds->contains($this->b['tenant']->id));
    }
}
