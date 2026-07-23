<?php

namespace Tests\Feature\Reservations;

use App\Modules\Reservations\Models\Reservation;
use App\Modules\Tables\Models\Table;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Public (oturumsuz) QR rezervasyon talebi ucu: kimlik yalnız token
 * (ADR-008), hız sınırı token+IP, kayıt her zaman "talep alındı".
 */
class PublicReservationTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    private array $a;

    private Table $table;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();

        $this->table = Table::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
        ]);
    }

    private function payload(array $extra = []): array
    {
        return array_merge([
            'token' => $this->table->qr_token,
            'customer_name' => 'Ayşe Yılmaz',
            'customer_phone' => '05551234567',
            'customer_email' => 'ayse@example.com',
            'date' => now()->addDays(2)->format('Y-m-d'),
            'time' => '19:30',
            'party_size' => 4,
            'note' => 'Cam kenarı olursa sevinirim',
            'allergy_note' => 'Deniz ürünleri alerjisi',
        ], $extra);
    }

    public function test_gecerli_token_ile_talep_olusur(): void
    {
        $res = $this->postJson('/api/v1/public/reservations', $this->payload())
            ->assertCreated()
            ->json('reservation');

        $this->assertSame('requested', $res['status']);

        $stored = Reservation::withoutTenancy()->latest('id')->first();
        $this->assertSame((int) $this->a['tenant']->id, (int) $stored->tenant_id);
        $this->assertSame((int) $this->a['branch']->id, (int) $stored->branch_id);
        $this->assertSame('qr', $stored->source->value);
        $this->assertSame('Deniz ürünleri alerjisi', $stored->allergy_note);
        $this->assertSame('19:30', $stored->reserved_at->format('H:i'));
    }

    public function test_gecersiz_token_404(): void
    {
        $this->postJson('/api/v1/public/reservations', $this->payload([
            'token' => str_repeat('A', 26),
        ]))->assertNotFound();
    }

    public function test_gecmis_tarih_reddedilir(): void
    {
        $this->postJson('/api/v1/public/reservations', $this->payload([
            'date' => now()->subDay()->format('Y-m-d'),
        ]))->assertUnprocessable();
    }

    public function test_hiz_siniri_uygulanir(): void
    {
        RateLimiter::clear('public-reservation:'.sha1($this->table->qr_token.'|127.0.0.1'));

        $limit = (int) config('reservations.public_rate_per_minute', 5);

        for ($i = 0; $i < $limit; $i++) {
            $this->postJson('/api/v1/public/reservations', $this->payload([
                'time' => sprintf('1%d:00', $i), // çakışma değil, art arda talep
            ]));
        }

        $this->postJson('/api/v1/public/reservations', $this->payload())
            ->assertStatus(429);
    }

    public function test_kimlik_parametreleri_istekten_kabul_edilmez(): void
    {
        // tenant_id / branch_id / table_id göndermek sonucu DEĞİŞTİRMEZ.
        $other = $this->makeTenantWithUser();

        $this->postJson('/api/v1/public/reservations', $this->payload([
            'tenant_id' => $other['tenant']->id,
            'branch_id' => $other['branch']->id,
        ]))->assertCreated();

        $stored = Reservation::withoutTenancy()->latest('id')->first();
        $this->assertSame((int) $this->a['tenant']->id, (int) $stored->tenant_id);
        $this->assertSame((int) $this->a['branch']->id, (int) $stored->branch_id);
    }
}
