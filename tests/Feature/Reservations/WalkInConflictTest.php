<?php

namespace Tests\Feature\Reservations;

use App\Modules\Orders\Models\Order;
use App\Modules\Reservations\Models\Reservation;
use App\Modules\Tables\Models\Table;
use App\Modules\Venue\Enums\TableStatus;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Rezervasyon ↔ walk-in çakışması (görev §8):
 *  - Boş görünen ama yaklaşan/aktif rezervasyonu olan masaya adisyon
 *    açılırken personel ONAYI gerekir (409 + requires_confirmation).
 *  - confirm=true ile açılır; onaylı/gecikmiş/gelmiş rezervasyon SEATED olur.
 *  - Onaylanmamış (requested/pending) rezervasyon seated'a geçemez → net
 *    çakışma olarak işaretlenir (yöneticiye görünür).
 *  - Uzak/rezervasyonsuz masa uyarısız açılır; zaten açık adisyonlu masa
 *    idempotent açılır (uyarı yok).
 */
class WalkInConflictTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);
    }

    private function makeReservation(Table $table, array $attrs = []): Reservation
    {
        $r = $this->asTenant($this->a['tenant'], fn () => Reservation::factory()->create(array_merge([
            'branch_id' => $this->a['branch']->id,
            'customer_name' => 'Ahmet Yılmaz',
            'party_size' => 2,
            'status' => 'confirmed',
            'reserved_at' => now()->addMinutes(20),
        ], $attrs)));

        $r->tables()->attach($table->id);

        return $r->fresh('tables');
    }

    private function openTable(Table $table, array $extra = []): \Illuminate\Testing\TestResponse
    {
        return $this->postJson('/api/v1/orders', array_merge([
            'branch_id' => $this->a['branch']->id,
            'channel' => 'table',
            'table_id' => $table->id,
        ], $extra));
    }

    public function test_yaklasan_rezervasyonlu_masada_acilis_onay_ister(): void
    {
        $table = $this->makeTable($this->a, ['status' => TableStatus::Available]);
        $this->makeReservation($table, ['reserved_at' => now()->addMinutes(20)]);

        $res = $this->openTable($table)->assertStatus(409);

        $res->assertJson(['requires_confirmation' => true, 'reason' => 'reservation_conflict']);
        $this->assertSame('Ahmet Yılmaz', $res->json('reservation.customer_name'));

        // Adisyon AÇILMADI.
        $this->assertSame(0, Order::withoutTenancy()->where('table_id', $table->id)->count());
    }

    public function test_onaylayinca_adisyon_acilir_ve_rezervasyon_seated_olur(): void
    {
        $table = $this->makeTable($this->a, ['status' => TableStatus::Available]);
        $r = $this->makeReservation($table, ['status' => 'confirmed', 'reserved_at' => now()->addMinutes(20)]);

        $this->openTable($table, ['confirm' => true])->assertCreated();

        $this->assertSame(1, Order::withoutTenancy()->where('table_id', $table->id)->count());
        $this->assertSame('seated', $r->fresh()->status->value);
        $this->assertNotNull($r->fresh()->seated_at);
    }

    public function test_onaylanmamis_rezervasyon_seated_olamaz_cakisma_isaretlenir(): void
    {
        $table = $this->makeTable($this->a, ['status' => TableStatus::Available]);
        $r = $this->makeReservation($table, ['status' => 'pending', 'reserved_at' => now()->addMinutes(20)]);

        $this->openTable($table, ['confirm' => true])->assertCreated();

        $fresh = $r->fresh();
        $this->assertSame('pending', $fresh->status->value); // seated'a geçemez
        $this->assertStringStartsWith('[ÇAKIŞMA', (string) $fresh->special_note);
    }

    public function test_uzak_rezervasyon_uyari_vermez(): void
    {
        $table = $this->makeTable($this->a, ['status' => TableStatus::Available]);
        $this->makeReservation($table, ['reserved_at' => now()->addDays(2)]);

        $this->openTable($table)->assertCreated();
        $this->assertSame(1, Order::withoutTenancy()->where('table_id', $table->id)->count());
    }

    public function test_rezervasyonsuz_masa_uyari_vermez(): void
    {
        $table = $this->makeTable($this->a, ['status' => TableStatus::Available]);

        $this->openTable($table)->assertCreated();
        $this->assertSame(1, Order::withoutTenancy()->where('table_id', $table->id)->count());
    }

    public function test_zaten_acik_adisyonlu_masa_idempotent_acilir_uyari_yok(): void
    {
        $table = $this->makeTable($this->a, ['status' => TableStatus::Available]);

        // İlk açılış (rezervasyonsuz) → 201.
        $first = $this->openTable($table)->assertCreated();

        // Sonradan rezervasyon eklense bile: masada ZATEN açık adisyon var →
        // ikinci "aç" idempotent (200), uyarı yok.
        $this->makeReservation($table, ['reserved_at' => now()->addMinutes(20)]);

        $second = $this->openTable($table)->assertOk();
        $this->assertSame($first->json('order.id'), $second->json('order.id'));
        $this->assertSame(1, Order::withoutTenancy()->where('table_id', $table->id)->count());
    }
}
