<?php

namespace Tests\Feature\Reservations;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Bekleme listesi: sıra + tahmini süre + durum akışı.
 */
class WaitlistTest extends TestCase
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

    private function join(string $name, int $party = 2, array $extra = []): array
    {
        return $this->postJson('/api/v1/reservations/waitlist', array_merge([
            'branch_id' => $this->a['branch']->id,
            'customer_name' => $name,
            'party_size' => $party,
        ], $extra))->assertCreated()->json('entry');
    }

    public function test_sira_ve_tahmini_bekleme_suresi(): void
    {
        $first = $this->join('Birinci');
        $second = $this->join('İkinci');

        $slot = (int) config('reservations.waitlist_slot_minutes', 15);

        $this->assertSame(1, $first['position']);
        $this->assertSame(2, $second['position']);
        $this->assertSame(2 * $slot, $second['estimated_wait_minutes']);
    }

    public function test_personel_tahmini_otomatik_tahmini_ezer(): void
    {
        $entry = $this->join('Misafir', 2, ['quoted_wait_minutes' => 40]);

        $this->assertSame(40, $entry['estimated_wait_minutes']);
    }

    public function test_cagirma_ve_masaya_alma_akisi(): void
    {
        $entry = $this->join('Misafir');

        // "Masanız hazır" bildirimi (müşteri geldi çağrısı)
        $this->postJson("/api/v1/reservations/waitlist/{$entry['id']}/status", ['status' => 'notified'])
            ->assertOk()
            ->assertJsonPath('entry.status', 'notified');

        $this->postJson("/api/v1/reservations/waitlist/{$entry['id']}/status", ['status' => 'seated'])
            ->assertOk()
            ->assertJsonPath('entry.status', 'seated');

        // Kapanmış girdiden geri dönüş yok.
        $this->postJson("/api/v1/reservations/waitlist/{$entry['id']}/status", ['status' => 'waiting'])
            ->assertUnprocessable();
    }

    public function test_masaya_alinan_siradan_duser(): void
    {
        $first = $this->join('Birinci');
        $this->join('İkinci');

        $this->postJson("/api/v1/reservations/waitlist/{$first['id']}/status", ['status' => 'seated'])->assertOk();

        $rows = $this->getJson('/api/v1/reservations/waitlist')->assertOk()->json('waitlist');

        $open = array_values(array_filter($rows, fn (array $r) => $r['status'] === 'waiting'));
        $this->assertCount(1, $open);
        $this->assertSame('İkinci', $open[0]['customer_name']);
        $this->assertSame(1, $open[0]['position']);
    }
}
