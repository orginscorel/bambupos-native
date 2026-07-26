<?php

namespace Tests\Feature\Reservations;

use App\Modules\Reservations\Models\Reservation;
use App\Modules\Reservations\Models\WaitlistEntry;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Kiracı izolasyonu (ADR-004): yabancı kayıt 404, yabancı şube 422,
 * liste sızıntısı yok.
 */
class ReservationTenantIsolationTest extends TestCase
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

    private function makeReservationFor(array $ctx, array $attrs = []): Reservation
    {
        return $this->asTenant($ctx['tenant'], fn (): Reservation => Reservation::factory()->create(array_merge([
            'branch_id' => $ctx['branch']->id,
        ], $attrs)));
    }

    public function test_yabanci_kiracinin_rezervasyonu_404(): void
    {
        $foreign = $this->makeReservationFor($this->b);

        $this->actingAs($this->a['user']);

        $this->getJson("/api/v1/reservations/{$foreign->id}")->assertNotFound();
        $this->putJson("/api/v1/reservations/{$foreign->id}", ['customer_name' => 'X'])->assertNotFound();
        $this->postJson("/api/v1/reservations/{$foreign->id}/status", ['status' => 'confirmed'])->assertNotFound();
        $this->deleteJson("/api/v1/reservations/{$foreign->id}")->assertNotFound();
    }

    public function test_liste_yalnizca_kendi_kiracisini_gosterir(): void
    {
        $mine = $this->makeReservationFor($this->a);
        $this->makeReservationFor($this->b);

        $this->actingAs($this->a['user']);

        $rows = $this->getJson('/api/v1/reservations')->assertOk()->json('reservations.data');

        $this->assertCount(1, $rows);
        $this->assertSame($mine->id, $rows[0]['id']);
    }

    public function test_yabanci_subeye_rezervasyon_yazilamaz(): void
    {
        $this->actingAs($this->a['user']);

        // ŞUBE KAPSAMI: istekteki yabancı branch_id YOK SAYILIR — kayıt
        // kullanıcının GEÇERLİ (kendi) şubesine düşer, yabancı şubeye ASLA.
        $response = $this->postJson('/api/v1/reservations', [
            'branch_id' => $this->b['branch']->id,
            'customer_name' => 'Sızma Denemesi',
            'reserved_at' => now()->addDay()->format('Y-m-d 19:00:00'),
            'party_size' => 2,
        ])->assertCreated();

        // Yabancı (B) şubesine hiçbir rezervasyon yazılmadı.
        $this->assertSame(0, Reservation::withoutTenancy()
            ->where('branch_id', $this->b['branch']->id)->count());

        // Kendi (A) şubesine yazıldı.
        $this->assertSame($this->a['branch']->id, (int) Reservation::withoutTenancy()
            ->where('id', $response->json('reservation.id'))->value('branch_id'));
    }

    public function test_bekleme_listesi_izolasyonu(): void
    {
        $foreign = $this->asTenant($this->b['tenant'], fn () => WaitlistEntry::factory()->create([
            'branch_id' => $this->b['branch']->id,
        ]));

        $this->actingAs($this->a['user']);

        $this->putJson("/api/v1/reservations/waitlist/{$foreign->id}", ['customer_name' => 'X'])->assertNotFound();
        $this->postJson("/api/v1/reservations/waitlist/{$foreign->id}/status", ['status' => 'seated'])->assertNotFound();

        $rows = $this->getJson('/api/v1/reservations/waitlist')->assertOk()->json('waitlist');
        $this->assertCount(0, $rows);
    }
}
