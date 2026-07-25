<?php

namespace Tests\Feature\Identity;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Support\HomeScreen;
use App\Modules\Kds\Models\UserStation;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Açılış ekranı çözümleyici: rol + ATANMIŞ istasyon otomatik eşlemesi
 * (KDS §12) ve açık tercihin korunması.
 */
class HomeScreenResolverTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    private function assignStation(Tenant $tenant, User $user, string $key): void
    {
        $this->asTenant($tenant, fn () => UserStation::query()->create([
            'user_id' => $user->getKey(),
            'station_key' => $key,
        ]));
    }

    private function resolveFor(Tenant $tenant, User $user): string
    {
        return $this->asTenant($tenant, fn () => HomeScreen::resolve($user->fresh()));
    }

    public function test_barista_istasyonuna_atanan_kullanici_barista_ekranina_duser(): void
    {
        $s = $this->makeTenantWithUser(['kds.view']);
        $this->assignStation($s['tenant'], $s['user'], 'barista');

        $this->assertSame('/panel/barista', $this->resolveFor($s['tenant'], $s['user']));
    }

    public function test_mutfak_istasyonuna_atanan_kullanici_mutfak_ekranina_duser(): void
    {
        $s = $this->makeTenantWithUser(['kds.view']);
        $this->assignStation($s['tenant'], $s['user'], 'kitchen');

        $this->assertSame('/panel/mutfak', $this->resolveFor($s['tenant'], $s['user']));
    }

    public function test_istasyon_atamasi_yoksa_izinden_turetilir(): void
    {
        $s = $this->makeTenantWithUser(['kds.view']);

        $this->assertSame('/panel/mutfak', $this->resolveFor($s['tenant'], $s['user']));
    }

    public function test_komi_kendi_ekranina_duser(): void
    {
        $s = $this->makeTenantWithUser(['kds.deliver']);

        $this->assertSame('/panel/komi', $this->resolveFor($s['tenant'], $s['user']));
    }

    public function test_acik_tercih_istasyon_otomatiğini_ezmez(): void
    {
        $s = $this->makeTenantWithUser(['kds.view']);
        $this->assignStation($s['tenant'], $s['user'], 'barista');
        $s['user']->update(['default_screen' => 'kds']); // açık tercih: Mutfak

        $this->assertSame('/panel/mutfak', $this->resolveFor($s['tenant'], $s['user']));
    }

    public function test_yonetici_istasyon_atamasina_ragmen_dashboarda_duser(): void
    {
        $s = $this->makeTenantWithUser(['kds.view', 'reports.view']);
        $this->assignStation($s['tenant'], $s['user'], 'barista');

        $this->assertSame('/panel', $this->resolveFor($s['tenant'], $s['user']));
    }

    public function test_otomatik_personel_panele_gelince_kendi_ekranina_yonlenir(): void
    {
        $s = $this->makeTenantWithUser(['kds.view']);
        $this->assignStation($s['tenant'], $s['user'], 'barista');

        $this->actingAs($s['user'])
            ->get('/panel')
            ->assertRedirect('/panel/barista');
    }

    public function test_yonetici_panele_gelince_dashboard_gorunur(): void
    {
        $s = $this->makeTenantWithUser(['reports.view']);

        $this->actingAs($s['user'])->get('/panel')->assertOk();
    }

    public function test_acik_tercih_panelde_yonlendirme_yapmaz(): void
    {
        $s = $this->makeTenantWithUser(['kds.view']);
        $this->assignStation($s['tenant'], $s['user'], 'barista');
        $s['user']->update(['default_screen' => 'dashboard']); // açıkça dashboard

        $this->actingAs($s['user'])->get('/panel')->assertOk();
    }
}
