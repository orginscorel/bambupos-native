<?php

namespace Tests\Feature\Reservations;

use App\Modules\Reservations\Models\Reservation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Alerji notu HASSAS veridir: yalnız reservations.view_sensitive izniyle
 * serileştirilir; izinsiz kullanıcı içeriği HİÇBİR uçta göremez.
 */
class ReservationSensitiveNoteTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
    }

    public function test_yetkisiz_kullanici_alerji_notunu_goremez(): void
    {
        $ctx = $this->makeTenantWithUser([
            'reservations.view', 'reservations.create', 'reservations.update', 'reservations.manage',
        ]);

        $r = $this->asTenant($ctx['tenant'], fn () => Reservation::factory()->create([
            'branch_id' => $ctx['branch']->id,
            'allergy_note' => 'Fıstık alerjisi — anafilaksi riski',
        ]));

        $this->actingAs($ctx['user']);

        // Tekil uç: içerik yok, yalnız bayrak var.
        $show = $this->getJson("/api/v1/reservations/{$r->id}")->assertOk()->json('reservation');
        $this->assertNull($show['allergy_note']);
        $this->assertTrue($show['has_allergy_note']);

        // Liste ucu da sızdırmaz.
        $list = $this->getJson('/api/v1/reservations')->assertOk();
        $this->assertStringNotContainsString('Fıstık alerjisi', $list->getContent());
    }

    public function test_yetkili_kullanici_alerji_notunu_gorur(): void
    {
        $ctx = $this->makeTenantWithUser(); // tüm izinler (sahip gibi)

        $r = $this->asTenant($ctx['tenant'], fn () => Reservation::factory()->create([
            'branch_id' => $ctx['branch']->id,
            'allergy_note' => 'Gluten intoleransı',
        ]));

        $this->actingAs($ctx['user']);

        $this->getJson("/api/v1/reservations/{$r->id}")
            ->assertOk()
            ->assertJsonPath('reservation.allergy_note', 'Gluten intoleransı')
            ->assertJsonPath('reservation.has_allergy_note', true);
    }
}
