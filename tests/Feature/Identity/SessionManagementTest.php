<?php

namespace Tests\Feature\Identity;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

class SessionManagementTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    private function insertSession(int $userId, string $id, string $ip = '10.0.0.9'): void
    {
        DB::table('sessions')->insert([
            'id' => $id,
            'user_id' => $userId,
            'ip_address' => $ip,
            'user_agent' => 'TestAgent/1.0',
            'payload' => base64_encode(serialize([])),
            'last_activity' => time(),
        ]);
    }

    public function test_kullanici_yalniz_kendi_oturumlarini_listeler(): void
    {
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        $this->insertSession($a['user']->id, 'sess-a-1');
        $this->insertSession($b['user']->id, 'sess-b-1', '10.9.9.9');

        $response = $this->actingAs($a['user'])->getJson('/api/v1/auth/sessions')->assertOk();

        $ips = collect($response->json('sessions'))->pluck('ip_address');

        $this->assertTrue($ips->contains('10.0.0.9'));
        $this->assertFalse($ips->contains('10.9.9.9'));

        // Ham oturum id'si asla dönmez
        $this->assertStringNotContainsString('sess-a-1', $response->getContent());
    }

    public function test_baskasinin_oturumu_sonlandirilamaz_idor(): void
    {
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        $this->insertSession($b['user']->id, 'sess-b-2');

        $hashed = hash('sha256', 'sess-b-2');

        $this->actingAs($a['user'])
            ->deleteJson("/api/v1/auth/sessions/{$hashed}")
            ->assertNotFound();

        $this->assertDatabaseHas('sessions', ['id' => 'sess-b-2']);
    }

    public function test_kendi_oturumu_sonlandirilabilir(): void
    {
        $a = $this->makeTenantWithUser();

        $this->insertSession($a['user']->id, 'sess-a-3');

        $hashed = hash('sha256', 'sess-a-3');

        $this->actingAs($a['user'])
            ->deleteJson("/api/v1/auth/sessions/{$hashed}")
            ->assertOk();

        $this->assertDatabaseMissing('sessions', ['id' => 'sess-a-3']);
    }

    public function test_diger_cihazlardan_cikis_parola_ister_ve_diger_oturumlari_siler(): void
    {
        $a = $this->makeTenantWithUser();

        $this->insertSession($a['user']->id, 'sess-a-4');

        // Yanlış parola → 422, oturumlar durur
        $this->actingAs($a['user'])
            ->postJson('/api/v1/auth/logout-other-devices', ['password' => 'yanlis'])
            ->assertUnprocessable();

        $this->assertDatabaseHas('sessions', ['id' => 'sess-a-4']);

        // Doğru parola → diğer oturumlar silinir
        $this->actingAs($a['user'])
            ->postJson('/api/v1/auth/logout-other-devices', ['password' => 'password'])
            ->assertOk();

        $this->assertDatabaseMissing('sessions', ['id' => 'sess-a-4']);
    }
}
