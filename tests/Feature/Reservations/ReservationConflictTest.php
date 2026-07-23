<?php

namespace Tests\Feature\Reservations;

use App\Modules\Tables\Models\Table;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Çakışma önleme + kapasite + masa birleştirme kuralları (prompt §9.3).
 */
class ReservationConflictTest extends TestCase
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

    private function makeTable(array $attrs = []): Table
    {
        return Table::factory()->create(array_merge([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'capacity' => 4,
            'is_joinable' => true,
        ], $attrs));
    }

    private function payload(Table $table, string $at, array $extra = []): array
    {
        return array_merge([
            'branch_id' => $this->a['branch']->id,
            'customer_name' => 'Ali Veli',
            'customer_phone' => '05551112233',
            'reserved_at' => $at,
            'duration_minutes' => 120,
            'buffer_minutes' => 15,
            'party_size' => 2,
            'table_ids' => [$table->id],
            'status' => 'confirmed',
        ], $extra);
    }

    public function test_ayni_masa_ayni_saate_ikinci_rezervasyon_reddedilir(): void
    {
        $table = $this->makeTable();
        $day = now()->addDays(3)->format('Y-m-d');

        $this->postJson('/api/v1/reservations', $this->payload($table, "{$day} 19:00:00"))->assertCreated();

        $this->postJson('/api/v1/reservations', $this->payload($table, "{$day} 19:30:00"))
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['reserved_at']);
    }

    public function test_tampon_suresi_icinde_kalan_saat_de_cakisir(): void
    {
        $table = $this->makeTable();
        $day = now()->addDays(3)->format('Y-m-d');

        // 19:00 + 120dk süre = 21:00; +15dk tampon = 21:15'e kadar dolu.
        $this->postJson('/api/v1/reservations', $this->payload($table, "{$day} 19:00:00"))->assertCreated();

        $this->postJson('/api/v1/reservations', $this->payload($table, "{$day} 21:10:00"))
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['reserved_at']);

        // Tampon bittikten sonra serbest.
        $this->postJson('/api/v1/reservations', $this->payload($table, "{$day} 21:20:00"))->assertCreated();
    }

    public function test_farkli_masa_ayni_saat_serbesttir(): void
    {
        $t1 = $this->makeTable();
        $t2 = $this->makeTable();
        $day = now()->addDays(3)->format('Y-m-d');

        $this->postJson('/api/v1/reservations', $this->payload($t1, "{$day} 19:00:00"))->assertCreated();
        $this->postJson('/api/v1/reservations', $this->payload($t2, "{$day} 19:00:00"))->assertCreated();
    }

    public function test_iptal_edilen_rezervasyon_masayi_tutmaz(): void
    {
        $table = $this->makeTable();
        $day = now()->addDays(3)->format('Y-m-d');

        $id = $this->postJson('/api/v1/reservations', $this->payload($table, "{$day} 19:00:00"))
            ->assertCreated()->json('reservation.id');

        $this->postJson("/api/v1/reservations/{$id}/status", ['status' => 'cancelled'])->assertOk();

        $this->postJson('/api/v1/reservations', $this->payload($table, "{$day} 19:00:00"))->assertCreated();
    }

    public function test_kapasite_yetersizse_reddedilir(): void
    {
        $table = $this->makeTable(['capacity' => 4]);
        $day = now()->addDays(3)->format('Y-m-d');

        $this->postJson('/api/v1/reservations', $this->payload($table, "{$day} 19:00:00", ['party_size' => 6]))
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['party_size']);
    }

    public function test_masa_birlestirme_toplam_kapasiteyi_kullanir(): void
    {
        $t1 = $this->makeTable(['capacity' => 4]);
        $t2 = $this->makeTable(['capacity' => 4]);
        $day = now()->addDays(3)->format('Y-m-d');

        $res = $this->postJson('/api/v1/reservations', $this->payload($t1, "{$day} 19:00:00", [
            'party_size' => 7,
            'table_ids' => [$t1->id, $t2->id],
        ]))->assertCreated()->json('reservation');

        $this->assertCount(2, $res['tables']);
    }

    public function test_birlesmeye_kapali_masa_coklu_secimde_reddedilir(): void
    {
        $t1 = $this->makeTable(['is_joinable' => false]);
        $t2 = $this->makeTable();
        $day = now()->addDays(3)->format('Y-m-d');

        $this->postJson('/api/v1/reservations', $this->payload($t1, "{$day} 19:00:00", [
            'party_size' => 6,
            'table_ids' => [$t1->id, $t2->id],
        ]))->assertUnprocessable()->assertJsonValidationErrors(['table_ids']);
    }

    public function test_guncellemede_kendi_kaydi_cakisma_sayilmaz(): void
    {
        $table = $this->makeTable();
        $day = now()->addDays(3)->format('Y-m-d');

        $id = $this->postJson('/api/v1/reservations', $this->payload($table, "{$day} 19:00:00"))
            ->assertCreated()->json('reservation.id');

        // Aynı masada yarım saat kaydırma: kendisiyle çakışmaz.
        $this->putJson("/api/v1/reservations/{$id}", ['reserved_at' => "{$day} 19:30:00"])
            ->assertOk()
            ->assertJsonPath('reservation.reserved_time', '19:30');
    }
}
