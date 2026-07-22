<?php

namespace Tests\Feature\Venue;

use App\Modules\Venue\Models\Area;
use App\Modules\Venue\Models\Floor;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Alan hiyerarşisi (şube → kat → alan) CRUD + kiracı izolasyonu:
 * A'nın kullanıcısı B'nin şube/kat/alanını göremez, değiştiremez.
 */
class VenueStructureTest extends TestCase
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

    /* ---------------- ŞUBE ---------------- */

    public function test_sube_listesinde_yalniz_kendi_kiracisinin_subeleri_doner(): void
    {
        $response = $this->actingAs($this->a['user'])->getJson('/api/v1/venue/branches')->assertOk();

        $ids = collect($response->json('branches'))->pluck('id');

        $this->assertTrue($ids->contains($this->a['branch']->id));
        $this->assertFalse($ids->contains($this->b['branch']->id));
    }

    public function test_a_kullanicisi_b_nin_subesini_guncelleyemez_silemez(): void
    {
        $this->actingAs($this->a['user']);

        $this->putJson("/api/v1/venue/branches/{$this->b['branch']->id}", ['name' => 'ele geçirildi'])
            ->assertNotFound();
        $this->deleteJson("/api/v1/venue/branches/{$this->b['branch']->id}")->assertNotFound();

        $this->assertDatabaseHas('branches', [
            'id' => $this->b['branch']->id,
            'name' => $this->b['branch']->name,
        ]);
    }

    public function test_sube_olusturma_ve_guncelleme(): void
    {
        $this->actingAs($this->a['user']);

        $created = $this->postJson('/api/v1/venue/branches', [
            'name' => 'Sahil Tesisi',
            'code' => 'SAHIL',
        ])->assertCreated()->json('branch');

        $this->assertSame((int) $this->a['tenant']->id, (int) $created['tenant_id']);

        $this->putJson("/api/v1/venue/branches/{$created['id']}", ['name' => 'Sahil Kafeterya'])
            ->assertOk()
            ->assertJsonPath('branch.name', 'Sahil Kafeterya');
    }

    public function test_masasi_olan_sube_silinemez(): void
    {
        $this->actingAs($this->a['user']);

        \App\Modules\Tables\Models\Table::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
        ]);

        $this->deleteJson("/api/v1/venue/branches/{$this->a['branch']->id}")->assertUnprocessable();
    }

    /* ---------------- KAT ---------------- */

    public function test_kat_olusturma_b_nin_subesine_yapilamaz(): void
    {
        $this->actingAs($this->a['user']);

        $this->postJson('/api/v1/venue/floors', [
            'branch_id' => $this->b['branch']->id,
            'name' => 'Sızma Katı',
        ])->assertUnprocessable();

        $this->assertDatabaseMissing('venue_floors', ['name' => 'Sızma Katı']);
    }

    public function test_a_kullanicisi_b_nin_katini_goremez_silemez(): void
    {
        $bFloor = Floor::factory()->create([
            'tenant_id' => $this->b['tenant']->id,
            'branch_id' => $this->b['branch']->id,
        ]);

        $this->actingAs($this->a['user']);

        $ids = collect($this->getJson('/api/v1/venue/floors')->assertOk()->json('floors'))->pluck('id');
        $this->assertFalse($ids->contains($bFloor->id));

        $this->deleteJson("/api/v1/venue/floors/{$bFloor->id}")->assertNotFound();
        $this->assertDatabaseHas('venue_floors', ['id' => $bFloor->id]);
    }

    /* ---------------- ALAN ---------------- */

    public function test_alan_hiyerarsisi_kurulur_kat_baska_subeden_secilemez(): void
    {
        $this->actingAs($this->a['user']);

        $floor = $this->postJson('/api/v1/venue/floors', [
            'branch_id' => $this->a['branch']->id,
            'name' => 'Zemin Kat',
        ])->assertCreated()->json('floor');

        $area = $this->postJson('/api/v1/venue/areas', [
            'branch_id' => $this->a['branch']->id,
            'floor_id' => $floor['id'],
            'name' => 'Teras',
            'type' => 'terrace',
        ])->assertCreated()->json('area');

        $this->assertSame((int) $floor['id'], (int) $area['floor_id']);

        // Başka şubenin katı bu şubede kullanılamaz
        $otherBranch = \App\Modules\Tenancy\Models\Branch::factory()->create(['tenant_id' => $this->a['tenant']->id]);

        $this->postJson('/api/v1/venue/areas', [
            'branch_id' => $otherBranch->id,
            'floor_id' => $floor['id'],
            'name' => 'Bahçe',
        ])->assertUnprocessable();
    }

    public function test_a_kullanicisi_b_nin_alanina_erisemez(): void
    {
        $bArea = Area::factory()->create([
            'tenant_id' => $this->b['tenant']->id,
            'branch_id' => $this->b['branch']->id,
        ]);

        $this->actingAs($this->a['user']);

        $ids = collect($this->getJson('/api/v1/venue/areas')->assertOk()->json('areas'))->pluck('id');
        $this->assertFalse($ids->contains($bArea->id));

        $this->putJson("/api/v1/venue/areas/{$bArea->id}", ['name' => 'X'])->assertNotFound();
        $this->deleteJson("/api/v1/venue/areas/{$bArea->id}")->assertNotFound();
    }

    public function test_ayni_subede_ayni_adli_alan_reddedilir(): void
    {
        $this->actingAs($this->a['user']);

        $payload = ['branch_id' => $this->a['branch']->id, 'name' => 'Teras'];

        $this->postJson('/api/v1/venue/areas', $payload)->assertCreated();
        $this->postJson('/api/v1/venue/areas', $payload)->assertUnprocessable();
    }

    /* ---------------- YETKİ ---------------- */

    public function test_izinsiz_kullanici_sube_ve_masa_yonetimine_erisemez(): void
    {
        $limited = $this->makeTenantWithUser(['catalog.view']); // tables/branches izni yok

        $this->actingAs($limited['user']);

        $this->getJson('/api/v1/venue/branches')->assertForbidden();
        $this->postJson('/api/v1/venue/branches', ['name' => 'X'])->assertForbidden();
        $this->getJson('/api/v1/venue/tables')->assertForbidden();
        $this->getJson('/api/v1/venue/areas')->assertForbidden();
    }

    public function test_branches_view_izni_yonetime_yetmez(): void
    {
        $viewer = $this->makeTenantWithUser(['branches.view']);

        $this->actingAs($viewer['user']);

        $this->getJson('/api/v1/venue/branches')->assertOk();
        $this->postJson('/api/v1/venue/branches', ['name' => 'Yeni'])->assertForbidden();
        $this->putJson("/api/v1/venue/branches/{$viewer['branch']->id}", ['name' => 'X'])->assertForbidden();
    }
}
