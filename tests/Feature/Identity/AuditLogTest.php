<?php

namespace Tests\Feature\Identity;

use App\Modules\Catalog\Models\Product;
use App\Modules\Identity\Models\AuditLog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use LogicException;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

class AuditLogTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    public function test_hassas_islemler_eski_ve_yeni_degerle_kayda_gecer(): void
    {
        $setup = $this->makeTenantWithUser();

        $product = Product::factory()->create(['tenant_id' => $setup['tenant']->id, 'name' => 'Eski Ad']);

        $this->actingAs($setup['user'])
            ->putJson("/api/v1/products/{$product->id}", ['name' => 'Yeni Ad'])
            ->assertOk();

        $log = AuditLog::withoutTenancy()
            ->where('action', 'products.updated')
            ->where('entity_id', $product->id)
            ->latest('id')
            ->first();

        $this->assertNotNull($log);
        $this->assertSame('Eski Ad', $log->old_values['name']);
        $this->assertSame('Yeni Ad', $log->new_values['name']);
        $this->assertSame($setup['user']->id, $log->user_id);
        $this->assertSame($setup['tenant']->id, $log->tenant_id);
        $this->assertNotNull($log->ip_address);
    }

    public function test_denetim_kaydi_guncellenemez(): void
    {
        $setup = $this->makeTenantWithUser();
        Product::factory()->create(['tenant_id' => $setup['tenant']->id]);

        $log = AuditLog::withoutTenancy()->latest('id')->first();

        $this->expectException(LogicException::class);
        $log->update(['action' => 'tahrif']);
    }

    public function test_denetim_kaydi_silinemez(): void
    {
        $setup = $this->makeTenantWithUser();
        Product::factory()->create(['tenant_id' => $setup['tenant']->id]);

        $log = AuditLog::withoutTenancy()->latest('id')->first();

        $this->expectException(LogicException::class);
        $log->delete();
    }

    public function test_denetim_ucu_icin_update_delete_rotasi_yoktur(): void
    {
        $setup = $this->makeTenantWithUser();
        $product = Product::factory()->create(['tenant_id' => $setup['tenant']->id]);

        $log = AuditLog::withoutTenancy()->latest('id')->first();

        $this->actingAs($setup['user']);

        $this->putJson("/api/v1/audit-logs/{$log->id}", ['action' => 'x'])->assertNotFound();
        $this->deleteJson("/api/v1/audit-logs/{$log->id}")->assertNotFound();
    }

    public function test_audit_view_izni_olmayan_kayitlari_goremez(): void
    {
        $setup = $this->makeTenantWithUser(['catalog.view']);

        $this->actingAs($setup['user'])->getJson('/api/v1/audit-logs')->assertForbidden();
    }

    public function test_parola_ve_pin_asla_kayda_dusmez(): void
    {
        $setup = $this->makeTenantWithUser();

        $this->actingAs($setup['user'])->postJson('/api/v1/auth/pin', [
            'password' => 'password',
            'pin' => '839274',
        ])->assertOk();

        $logs = AuditLog::withoutTenancy()->get();

        $this->assertStringNotContainsString('839274', $logs->toJson());
        $this->assertStringNotContainsString('password', json_encode($logs->pluck('new_values')));
    }
}
