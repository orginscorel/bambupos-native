<?php

namespace Tests\Feature\Reservations;

use App\Modules\Reservations\Models\Reservation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Durum makinesi geçişleri (prompt §9.2) + manage izni.
 */
class ReservationStatusTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
    }

    private function makeReservation(array $attrs = []): Reservation
    {
        return $this->asTenant($this->a['tenant'], fn (): Reservation => Reservation::factory()->create(array_merge([
            'branch_id' => $this->a['branch']->id,
        ], $attrs)));
    }

    public function test_talep_onaylanir_ve_akis_tamamlanir(): void
    {
        $this->actingAs($this->a['user']);
        $r = $this->makeReservation(['status' => 'requested']);

        foreach (['confirmed', 'arrived', 'seated', 'completed'] as $step) {
            $this->postJson("/api/v1/reservations/{$r->id}/status", ['status' => $step])
                ->assertOk()
                ->assertJsonPath('reservation.status', $step);
        }
    }

    public function test_kapanmis_durumdan_geri_donus_yoktur(): void
    {
        $this->actingAs($this->a['user']);
        $r = $this->makeReservation(['status' => 'completed']);

        $this->postJson("/api/v1/reservations/{$r->id}/status", ['status' => 'confirmed'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['status']);
    }

    public function test_gecersiz_atlama_reddedilir(): void
    {
        $this->actingAs($this->a['user']);
        $r = $this->makeReservation(['status' => 'requested']);

        // Talepten doğrudan "masaya alındı" olmaz (önce onay).
        $this->postJson("/api/v1/reservations/{$r->id}/status", ['status' => 'seated'])
            ->assertUnprocessable();
    }

    public function test_iptal_sebep_kaydeder(): void
    {
        $this->actingAs($this->a['user']);
        $r = $this->makeReservation(['status' => 'confirmed']);

        $this->postJson("/api/v1/reservations/{$r->id}/status", [
            'status' => 'cancelled',
            'reason' => 'Müşteri aradı',
        ])->assertOk()->assertJsonPath('reservation.cancel_reason', 'Müşteri aradı');
    }

    public function test_manage_izni_olmayan_durum_degistiremez(): void
    {
        $limited = $this->makeTenantWithUser(['reservations.view', 'reservations.create']);
        $r = $this->asTenant($limited['tenant'], fn () => Reservation::factory()->create([
            'branch_id' => $limited['branch']->id,
            'status' => 'requested',
        ]));

        $this->actingAs($limited['user']);

        $this->postJson("/api/v1/reservations/{$r->id}/status", ['status' => 'confirmed'])
            ->assertForbidden();
    }

    public function test_kapora_takibi(): void
    {
        $this->actingAs($this->a['user']);
        $r = $this->makeReservation(['status' => 'confirmed', 'deposit_minor' => 50000, 'deposit_status' => 'pending']);

        $this->postJson("/api/v1/reservations/{$r->id}/deposit", ['deposit_status' => 'paid'])
            ->assertOk()
            ->assertJsonPath('reservation.deposit_status', 'paid')
            ->assertJsonPath('reservation.deposit_minor', 50000);
    }
}
