<?php

namespace Tests\Unit;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\TenantContext;
use App\Modules\Tenancy\TenantIsolationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

class RolePermissionTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    public function test_izin_katalogu_modul_ve_islem_bazlidir(): void
    {
        $this->assertTrue(Permission::query()->where('key', 'orders.cancel')->exists());
        $this->assertTrue(Permission::query()->where('key', 'orders.refund')->exists());
        $this->assertTrue(Permission::query()->where('key', 'orders.discount')->exists());
        $this->assertTrue(Permission::query()->where('key', 'orders.comp')->exists());
        $this->assertTrue(Permission::query()->where('key', 'catalog.change_price')->exists());
        $this->assertTrue(Permission::query()->where('key', 'payments.take')->exists());
        $this->assertTrue(Permission::query()->where('key', 'cash.close')->exists());
        $this->assertTrue(Permission::query()->where('key', 'reports.view')->exists());
        $this->assertTrue(Permission::query()->where('key', 'stock.adjust')->exists());
        $this->assertTrue(Permission::query()->where('key', 'staff.manage')->exists());
        $this->assertTrue(Permission::query()->where('key', 'theme.manage')->exists());
        $this->assertTrue(Permission::query()->where('key', 'integrations.manage')->exists());
        $this->assertTrue(Permission::query()->where('key', 'audit.view')->exists());
    }

    public function test_has_permission_rol_uzerinden_calisir(): void
    {
        $setup = $this->makeTenantWithUser(['orders.view', 'orders.cancel']);

        $user = $setup['user'];

        $this->assertTrue($user->hasPermission('orders.view'));
        $this->assertTrue($user->hasPermission('orders.cancel'));
        $this->assertFalse($user->hasPermission('orders.refund'));
        $this->assertFalse($user->hasPermission('audit.view'));
    }

    public function test_ayni_rol_adi_farkli_kiracilarda_bagimsizdir(): void
    {
        $tenantA = Tenant::factory()->create();
        $tenantB = Tenant::factory()->create();

        $roleA = Role::factory()->create(['tenant_id' => $tenantA->id, 'name' => 'Garson', 'slug' => 'garson']);
        $roleB = Role::factory()->create(['tenant_id' => $tenantB->id, 'name' => 'Garson', 'slug' => 'garson']);

        $this->assertNotSame($roleA->id, $roleB->id);

        // A bağlamında yalnız A'nın rolü görünür
        app(TenantContext::class)->setTenant($tenantA);

        $visible = Role::query()->where('slug', 'garson')->get();

        $this->assertCount(1, $visible);
        $this->assertSame($roleA->id, $visible->first()->id);

        app(TenantContext::class)->forget();
    }

    public function test_baglamsiz_sorgu_hicbir_rol_dondurmez_fail_closed(): void
    {
        Role::factory()->create();

        $this->assertSame(0, Role::query()->count());
    }

    public function test_baglamsiz_ve_tenantsiz_kayit_yazilamaz(): void
    {
        $this->expectException(TenantIsolationException::class);

        Role::create(['name' => 'Bağlamsız', 'slug' => 'baglamsiz']);
    }

    public function test_baglamla_celisen_tenant_id_ile_kayit_yazilamaz(): void
    {
        $tenantA = Tenant::factory()->create();
        $tenantB = Tenant::factory()->create();

        app(TenantContext::class)->setTenant($tenantA);

        try {
            $this->expectException(TenantIsolationException::class);

            $role = new Role(['name' => 'Sızma', 'slug' => 'sizma']);
            $role->tenant_id = $tenantB->id;
            $role->save();
        } finally {
            app(TenantContext::class)->forget();
        }
    }
}
