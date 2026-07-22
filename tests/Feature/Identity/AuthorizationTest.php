<?php

namespace Tests\Feature\Identity;

use App\Modules\Catalog\Models\Product;
use App\Modules\Identity\Models\Permission;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Yetki (izin) ve yetki yükseltme testleri.
 */
class AuthorizationTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    public function test_izni_olmayan_kullanici_urun_goremez(): void
    {
        $setup = $this->makeTenantWithUser(['orders.view']); // catalog izni yok

        $this->actingAs($setup['user'])->getJson('/api/v1/products')->assertForbidden();
    }

    public function test_view_izni_olan_ama_delete_izni_olmayan_silemez(): void
    {
        $setup = $this->makeTenantWithUser(['catalog.view']);

        $product = Product::factory()->create(['tenant_id' => $setup['tenant']->id]);

        $this->actingAs($setup['user']);

        $this->getJson("/api/v1/products/{$product->id}")->assertOk();
        $this->deleteJson("/api/v1/products/{$product->id}")->assertForbidden();
    }

    public function test_fiyat_degistirme_ayri_izin_ister(): void
    {
        $setup = $this->makeTenantWithUser(['catalog.view', 'catalog.update']); // change_price yok

        $product = Product::factory()->create(['tenant_id' => $setup['tenant']->id, 'price_minor' => 1000]);

        $this->actingAs($setup['user']);

        // Normal alan güncellenir
        $this->putJson("/api/v1/products/{$product->id}", ['name' => 'Yeni Ad'])->assertOk();

        // Fiyat değişikliği reddedilir (ADR-007 alanı ayrı yetkiye bağlı)
        $this->putJson("/api/v1/products/{$product->id}", ['price_minor' => 1])->assertForbidden();

        $this->assertSame(1000, $product->fresh()->price_minor);
    }

    public function test_staff_manage_izni_olmayan_personel_olusturamaz(): void
    {
        $setup = $this->makeTenantWithUser(['staff.view']);

        $this->actingAs($setup['user'])->postJson('/api/v1/staff', [
            'first_name' => 'Yeni',
            'last_name' => 'Personel',
            'email' => 'yeni@ornek.test',
            'password' => 'cok-guclu-parola-1',
        ])->assertForbidden();
    }

    public function test_yetki_yukseltme_kullanici_sahip_olmadigi_izni_role_ekleyemez(): void
    {
        // roles.manage VAR ama audit.view YOK
        $setup = $this->makeTenantWithUser(['roles.manage', 'roles.view', 'staff.manage', 'staff.view']);

        $auditPermission = Permission::query()->where('key', 'audit.view')->first();

        $this->actingAs($setup['user'])->postJson('/api/v1/roles', [
            'name' => 'Gizli Denetçi',
            'permissions' => [$auditPermission->id],
        ])->assertForbidden();

        $this->assertDatabaseMissing('roles', ['name' => 'Gizli Denetçi']);
    }

    public function test_kullanici_kendi_rolune_izin_ekleyerek_yukselemez(): void
    {
        $setup = $this->makeTenantWithUser(['roles.manage', 'roles.view']);

        $allPermissionIds = Permission::query()->pluck('id')->all();

        // Kendi rolüne TÜM izinleri vermeye çalışır → sahip olmadıkları reddedilir
        $this->actingAs($setup['user'])->putJson("/api/v1/roles/{$setup['role']->id}", [
            'permissions' => $allPermissionIds,
        ])->assertForbidden();

        $this->assertFalse($setup['user']->fresh()->hasPermission('audit.view'));
    }

    public function test_roles_manage_izni_olmayan_rol_olusturamaz(): void
    {
        $setup = $this->makeTenantWithUser(['catalog.view']);

        $anyPermission = Permission::query()->where('key', 'catalog.view')->first();

        $this->actingAs($setup['user'])->postJson('/api/v1/roles', [
            'name' => 'Korsan Rol',
            'permissions' => [$anyPermission->id],
        ])->assertForbidden();
    }

    public function test_sistem_rolu_silinemez(): void
    {
        $setup = $this->makeTenantWithUser(); // tüm izinler

        $systemRole = \App\Modules\Identity\Models\Role::factory()->create([
            'tenant_id' => $setup['tenant']->id,
            'is_system' => true,
        ]);

        $this->actingAs($setup['user'])
            ->deleteJson("/api/v1/roles/{$systemRole->id}")
            ->assertForbidden();

        $this->assertDatabaseHas('roles', ['id' => $systemRole->id]);
    }

    public function test_kullanici_kendi_hesabini_silemez(): void
    {
        $setup = $this->makeTenantWithUser();

        $this->actingAs($setup['user'])
            ->deleteJson("/api/v1/staff/{$setup['user']->id}")
            ->assertForbidden();
    }
}
