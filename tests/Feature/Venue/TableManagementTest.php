<?php

namespace Tests\Feature\Venue;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Orders\Models\Order;
use App\Modules\Tables\Models\Table;
use App\Modules\Venue\Models\Area;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Masa yönetimi: tekil/toplu oluşturma, şube içi tekillik, durum alanı,
 * toplu işlemler ve kiracı izolasyonu.
 */
class TableManagementTest extends TestCase
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

    public function test_yalnizca_goruntuleyen_garson_masa_olusturamaz_ve_toplu_yapamaz(): void
    {
        // Garson: tables.view + catalog.view (yönetim izni YOK) → 403.
        $role = Role::factory()->create(['tenant_id' => $this->a['tenant']->id]);
        $role->permissions()->sync(
            Permission::query()->whereIn('key', ['tables.view', 'catalog.view'])->pluck('id')->all(),
        );
        $garson = User::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
        ]);
        $garson->roles()->sync([$role->id]);

        $this->actingAs($garson);

        // Listeyi görebilir (tables.view)
        $this->getJson('/api/v1/venue/tables')->assertOk();

        // Ama yeni masa / toplu oluşturma / silme 403 (arayüzde de gizli)
        $this->postJson('/api/v1/venue/tables', [
            'branch_id' => $this->a['branch']->id, 'name' => 'Gizli Masa',
        ])->assertForbidden();

        $this->postJson('/api/v1/venue/tables/bulk', [
            'branch_id' => $this->a['branch']->id, 'name_prefix' => 'Teras', 'start' => 1, 'end' => 5,
        ])->assertForbidden();
    }

    public function test_masa_olusturma_qr_token_uretir_ve_numara_otomatik_artar(): void
    {
        $this->actingAs($this->a['user']);

        $first = $this->postJson('/api/v1/venue/tables', [
            'branch_id' => $this->a['branch']->id,
            'name' => 'Pencere Kenarı',
        ])->assertCreated()->json('table');

        $second = $this->postJson('/api/v1/venue/tables', [
            'branch_id' => $this->a['branch']->id,
            'name' => 'Şömine Yanı',
        ])->assertCreated()->json('table');

        $this->assertSame(1, $first['number']);
        $this->assertSame(2, $second['number']);

        $token = Table::withoutTenancy()->find($first['id'])->qr_token;
        $this->assertMatchesRegularExpression('/^[A-Z2-7]{26}$/', $token);
        $this->assertStringContainsString('/m/'.$token, $first['menu_url']);
    }

    public function test_toplu_olusturma_teras_1_20(): void
    {
        $this->actingAs($this->a['user']);

        $area = Area::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'name' => 'Teras',
            'type' => 'terrace',
        ]);

        $res = $this->postJson('/api/v1/venue/tables/bulk', [
            'branch_id' => $this->a['branch']->id,
            'area_id' => $area->id,
            'name_prefix' => 'Teras',
            'start' => 1,
            'end' => 20,
            'capacity' => 6,
        ])->assertCreated();

        $this->assertSame(20, $res->json('created_count'));

        $tables = Table::withoutTenancy()->where('branch_id', $this->a['branch']->id)->get();
        $this->assertCount(20, $tables);
        $this->assertSame(20, $tables->pluck('qr_token')->unique()->count(), 'Her masanın token\'ı tekil olmalı');
        $this->assertSame(range(1, 20), $tables->pluck('number')->sort()->values()->all());
        $this->assertTrue($tables->every(fn (Table $t) => (int) $t->area_id === (int) $area->id));
        $this->assertTrue($tables->contains(fn (Table $t) => $t->name === 'Teras 20'));
    }

    public function test_toplu_olusturmada_cakisan_numara_hepsini_reddeder(): void
    {
        $this->actingAs($this->a['user']);

        Table::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'name' => 'Bahçe 5',
            'number' => 5,
        ]);

        $this->postJson('/api/v1/venue/tables/bulk', [
            'branch_id' => $this->a['branch']->id,
            'name_prefix' => 'Teras',
            'start' => 1,
            'end' => 10,
        ])->assertUnprocessable();

        // Ya hepsi ya hiçbiri: hiçbir "Teras" masası yazılmamış olmalı
        $this->assertSame(0, Table::withoutTenancy()
            ->where('branch_id', $this->a['branch']->id)
            ->where('name', 'like', 'Teras%')->count());
    }

    public function test_ayni_masa_no_farkli_subede_kullanilabilir(): void
    {
        $this->actingAs($this->a['user']);

        $otherBranch = \App\Modules\Tenancy\Models\Branch::factory()->create(['tenant_id' => $this->a['tenant']->id]);

        // ŞUBE KAPSAMI: masa DAİMA geçerli (aktif) şubede oluşur; istekteki
        // branch_id yok sayılır. Farklı şubeye masa açmak için aktif şube
        // değiştirilir (yönetici — çok-şube açık).
        $this->postJson('/api/v1/venue/tables', [
            'name' => 'Masa Bir', 'number' => 1,
        ])->assertCreated();

        // Aktif şubeyi ikinci şubeye al → orada da aynı no serbest.
        $this->postJson('/api/v1/auth/active-branch', ['branch_id' => $otherBranch->id])->assertOk();

        $this->postJson('/api/v1/venue/tables', [
            'name' => 'Masa Bir', 'number' => 1,
        ])->assertCreated();

        // Aynı (geçerli/ikinci) şubede aynı no reddedilir.
        $this->postJson('/api/v1/venue/tables', [
            'name' => 'Başka Ad', 'number' => 1,
        ])->assertUnprocessable();
    }

    public function test_durum_guncellenir_gecersiz_durum_reddedilir(): void
    {
        $this->actingAs($this->a['user']);

        $table = Table::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
        ]);

        $res = $this->putJson("/api/v1/venue/tables/{$table->id}/status", ['status' => 'bill_requested'])
            ->assertOk();

        $this->assertSame('bill_requested', $res->json('table.status'));
        $this->assertSame('Hesap istendi', $res->json('table.status_label'));
        $this->assertNotEmpty($res->json('table.status_icon'), 'Durum ikonsuz olamaz (renk körlüğü desteği)');

        $this->putJson("/api/v1/venue/tables/{$table->id}/status", ['status' => 'uydurma_durum'])
            ->assertUnprocessable();
    }

    public function test_toplu_islem_yabanci_kiracinin_masalarini_etkilemez(): void
    {
        $aTable = Table::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
        ]);
        $bTable = Table::factory()->create([
            'tenant_id' => $this->b['tenant']->id,
            'branch_id' => $this->b['branch']->id,
        ]);

        $this->actingAs($this->a['user']);

        $res = $this->postJson('/api/v1/venue/tables/bulk-action', [
            'table_ids' => [$aTable->id, $bTable->id],
            'action' => 'deactivate',
        ])->assertOk();

        $this->assertSame(1, $res->json('affected'));
        $this->assertFalse((bool) Table::withoutTenancy()->find($aTable->id)->is_active);
        $this->assertTrue((bool) Table::withoutTenancy()->find($bTable->id)->is_active, 'B\'nin masası etkilenmemeli');
    }

    public function test_a_kullanicisi_b_nin_masasini_guncelleyemez(): void
    {
        $bTable = Table::factory()->create([
            'tenant_id' => $this->b['tenant']->id,
            'branch_id' => $this->b['branch']->id,
        ]);

        $this->actingAs($this->a['user']);

        $this->putJson("/api/v1/venue/tables/{$bTable->id}", ['name' => 'ele geçirildi'])->assertNotFound();
        $this->putJson("/api/v1/venue/tables/{$bTable->id}/status", ['status' => 'paid'])->assertNotFound();
        $this->deleteJson("/api/v1/venue/tables/{$bTable->id}")->assertNotFound();
    }

    public function test_masa_baska_kiracinin_alanina_tasinamaz(): void
    {
        $bArea = Area::factory()->create([
            'tenant_id' => $this->b['tenant']->id,
            'branch_id' => $this->b['branch']->id,
        ]);

        $aTable = Table::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
        ]);

        $this->actingAs($this->a['user']);

        $this->putJson("/api/v1/venue/tables/{$aTable->id}", ['area_id' => $bArea->id])
            ->assertUnprocessable();

        $this->assertNull(Table::withoutTenancy()->find($aTable->id)->area_id);
    }

    /* ---------------- Açık adisyon koruması (denetim BLOKER #1 + YÜKSEK #2) ---------------- */

    public function test_genel_guncelleme_ucu_acik_adisyonlu_masanin_durumunu_degistirmez(): void
    {
        $table = Table::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'status' => 'occupied',
        ]);
        Order::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'table_id' => $table->id,
            'status' => 'placed',
        ]);

        $this->actingAs($this->a['user']);

        // "Düzenle" formu meta veriyi (ad) günceller; `status` gövdede olsa bile
        // artık VenueTableController::update() bu alanı kabul etmiyor (dead-code
        // korumasız yol kapatıldı) — masa "boş"a çekilemez.
        $res = $this->putJson("/api/v1/venue/tables/{$table->id}", [
            'name' => 'Yeni Ad',
            'status' => 'available',
        ])->assertOk();

        $this->assertSame('Yeni Ad', $res->json('table.name'), 'Meta veri (ad) güncellenmeli');
        $this->assertSame('occupied', $res->json('table.status'), 'Durum, korumasız uçtan DEĞİŞMEMELİ');
        $this->assertSame('occupied', Table::withoutTenancy()->find($table->id)->status->value);
    }

    public function test_acik_adisyonlu_masa_korumali_uctan_da_boşa_cekilemez(): void
    {
        $table = Table::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'status' => 'occupied',
        ]);
        Order::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'table_id' => $table->id,
            'status' => 'placed',
        ]);

        $this->actingAs($this->a['user']);

        $this->putJson("/api/v1/venue/tables/{$table->id}/status", ['status' => 'available'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('status');

        $this->assertSame('occupied', Table::withoutTenancy()->find($table->id)->status->value);
    }

    public function test_acik_adisyonlu_masa_deaktive_veya_silinemez(): void
    {
        $table = Table::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'status' => 'occupied',
        ]);
        Order::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'table_id' => $table->id,
            'status' => 'placed',
        ]);

        $this->actingAs($this->a['user']);

        // Tekli: deaktivasyon (is_active=false) ve silme reddedilir.
        $this->putJson("/api/v1/venue/tables/{$table->id}", ['is_active' => false])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('is_active');
        $this->deleteJson("/api/v1/venue/tables/{$table->id}")->assertUnprocessable();

        $fresh = Table::withoutTenancy()->find($table->id);
        $this->assertTrue((bool) $fresh->is_active, 'Açık adisyonlu masa pasifleşmemeli');
        $this->assertNotNull($fresh, 'Açık adisyonlu masa silinmemeli');

        // Toplu: aynı guard — atlanır, "affected" artmaz, sebep net döner.
        $res = $this->postJson('/api/v1/venue/tables/bulk-action', [
            'table_ids' => [$table->id],
            'action' => 'deactivate',
        ])->assertOk();
        $this->assertSame(0, $res->json('affected'));
        $this->assertSame([$table->id], $res->json('skipped_open_order_ids'));
        $this->assertTrue((bool) Table::withoutTenancy()->find($table->id)->is_active);

        $res = $this->postJson('/api/v1/venue/tables/bulk-action', [
            'table_ids' => [$table->id],
            'action' => 'delete',
        ])->assertOk();
        $this->assertSame(0, $res->json('affected'));
        $this->assertSame([$table->id], $res->json('skipped_open_order_ids'));
        $this->assertNotNull(Table::withoutTenancy()->find($table->id), 'Toplu silme de engellenmeli');
    }
}
