<?php

namespace Tests\Feature\Reservations;

use App\Modules\Orders\Models\Order;
use App\Modules\Reservations\Models\Reservation;
use App\Modules\Reservations\Services\ReservationTableSync;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\TenantContext;
use App\Modules\Venue\Enums\TableStatus;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Rezervasyon ↔ masa durumu bağı (prompt §9.4):
 *  - Onaylı ve yaklaşan rezervasyon masayı 'reserved' yapar.
 *  - AKTİF ADİSYONU olan masanın durumu ASLA ezilmez.
 *  - Saat + tolerans geçince 'late' + masa 'reservation_late'.
 *  - Kapanışta (iptal/no-show/masaya alınma) masa serbest bırakılır;
 *    yalnız rezervasyon katmanının koyduğu durum geri alınır.
 */
class ReservationTableSyncTest extends TestCase
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
            'status' => TableStatus::Available,
        ], $attrs));
    }

    private function makeConfirmed(Table $table, array $attrs = []): Reservation
    {
        $r = $this->asTenant($this->a['tenant'], fn () => Reservation::factory()->create(array_merge([
            'branch_id' => $this->a['branch']->id,
            'status' => 'requested',
        ], $attrs)));

        $r->tables()->attach($table->id);

        return $r->fresh('tables');
    }

    public function test_yakin_saate_onay_masayi_rezerve_yapar(): void
    {
        $table = $this->makeTable();
        $r = $this->makeConfirmed($table, ['reserved_at' => now()->addMinutes(30)]);

        $this->postJson("/api/v1/reservations/{$r->id}/status", ['status' => 'confirmed'])->assertOk();

        $this->assertSame(TableStatus::Reserved, $table->fresh()->status);
    }

    public function test_uzak_saate_onay_masaya_hemen_dokunmaz(): void
    {
        $table = $this->makeTable();
        $r = $this->makeConfirmed($table, ['reserved_at' => now()->addDays(2)]);

        $this->postJson("/api/v1/reservations/{$r->id}/status", ['status' => 'confirmed'])->assertOk();

        $this->assertSame(TableStatus::Available, $table->fresh()->status);
    }

    public function test_aktif_adisyonlu_masanin_durumu_ezilmez(): void
    {
        $table = $this->makeTable(['status' => TableStatus::OrderTaken]);

        // Masada AÇIK adisyon var (sipariş alındı).
        $this->asTenant($this->a['tenant'], fn () => Order::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'table_id' => $table->id,
            'status' => 'placed',
        ]));

        $r = $this->makeConfirmed($table, ['reserved_at' => now()->addMinutes(20)]);

        $this->postJson("/api/v1/reservations/{$r->id}/status", ['status' => 'confirmed'])->assertOk();

        // Rezervasyon "gelecek katmanı"dır: canlı operasyonu ezmedi.
        $this->assertSame(TableStatus::OrderTaken, $table->fresh()->status);
    }

    public function test_saat_gecince_cron_late_isaretler(): void
    {
        $table = $this->makeTable();
        $r = $this->makeConfirmed($table, [
            'status' => 'confirmed',
            'reserved_at' => now()->subMinutes(30), // tolerans (15dk) geçti
        ]);

        app(TenantContext::class)->runWithoutTenancy(
            fn () => app(ReservationTableSync::class)->syncUpcoming()
        );

        $this->assertSame('late', $r->fresh()->status->value);
        $this->assertSame(TableStatus::ReservationLate, $table->fresh()->status);
    }

    public function test_iptal_rezerve_masayi_serbest_birakir(): void
    {
        $table = $this->makeTable(['status' => TableStatus::Reserved]);
        $r = $this->makeConfirmed($table, ['status' => 'confirmed', 'reserved_at' => now()->addMinutes(30)]);

        $this->postJson("/api/v1/reservations/{$r->id}/status", ['status' => 'cancelled'])->assertOk();

        $this->assertSame(TableStatus::Available, $table->fresh()->status);
    }

    public function test_serbest_birakma_siparis_turevli_durumu_ezmez(): void
    {
        // Masa bu arada canlı operasyona geçmiş (garson oturttu, sipariş aldı).
        $table = $this->makeTable(['status' => TableStatus::Preparing]);
        $r = $this->makeConfirmed($table, ['status' => 'confirmed', 'reserved_at' => now()->addMinutes(30)]);

        $this->postJson("/api/v1/reservations/{$r->id}/status", ['status' => 'no_show'])->assertOk();

        $this->assertSame(TableStatus::Preparing, $table->fresh()->status);
    }

    public function test_masaya_alinan_musteri_masayi_rezerveden_cikarir(): void
    {
        $table = $this->makeTable(['status' => TableStatus::Reserved]);
        $r = $this->makeConfirmed($table, ['status' => 'confirmed', 'reserved_at' => now()->addMinutes(5)]);

        $this->postJson("/api/v1/reservations/{$r->id}/status", ['status' => 'arrived'])->assertOk();
        $this->postJson("/api/v1/reservations/{$r->id}/status", ['status' => 'seated'])->assertOk();

        // Rezerve kalkar; adisyonu Orders katmanı açınca masa oradan yönetilir.
        $this->assertSame(TableStatus::Available, $table->fresh()->status);
    }
}
