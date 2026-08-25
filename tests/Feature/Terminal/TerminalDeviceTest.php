<?php

namespace Tests\Feature\Terminal;

use App\Modules\Identity\Models\User;
use App\Modules\Kds\Models\UserStation;
use App\Modules\Terminal\Models\TerminalDevice;
use App\Modules\Terminal\Services\TerminalProvisioner;
use App\Modules\Terminal\Support\TerminalLicense;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * §13 İstasyon Cihaz Modu (Faz A): gizli terminal kullanıcısı + opak token
 * oto-giriş + kilitli mod (rota koruması) + panel yönetimi + güvenlik.
 */
class TerminalDeviceTest extends TestCase
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

    private function makeDevice(array $ctx, string $station = 'kitchen', string $name = 'Test Terminal'): TerminalDevice
    {
        return $this->asTenant($ctx['tenant'], fn (): TerminalDevice => app(TerminalProvisioner::class)
            ->createDevice($name, (int) $ctx['branch']->id, (int) $ctx['tenant']->id, $station));
    }

    /* ---------------- Şema + provisioning ---------------- */

    public function test_cihaz_gizli_kullanici_uretir_ve_istasyona_atar(): void
    {
        $device = $this->makeDevice($this->a, 'barista');

        $this->assertMatchesRegularExpression('/^[A-Z2-7]{26}$/', $device->token);

        $user = User::find($device->user_id);
        $this->assertTrue((bool) $user->is_terminal);
        $this->assertTrue((bool) $user->is_active);
        $this->assertSame('barista', $user->terminal_station);
        $this->assertContains('kds.view', $user->permissionKeys());
        $this->assertNotContains('payments.take', $user->permissionKeys());

        $this->assertSame(
            ['barista'],
            UserStation::withoutTenancy()->where('user_id', $user->id)->pluck('station_key')->all(),
        );
    }

    public function test_komi_terminali_teslim_izni_alir_istasyon_atanmaz(): void
    {
        $device = $this->makeDevice($this->a, 'komi');
        $user = User::find($device->user_id);

        $this->assertContains('kds.deliver', $user->permissionKeys());
        $this->assertContains('kds.view', $user->permissionKeys());
        $this->assertSame(0, UserStation::query()->where('user_id', $user->id)->count());
    }

    /* ---------------- Gizlilik / güvenlik ---------------- */

    public function test_terminal_kullanicisi_personel_listesinde_gorunmez(): void
    {
        $device = $this->makeDevice($this->a);

        $this->actingAs($this->a['user']);

        $res = $this->getJson('/api/v1/staff')->assertOk();
        $ids = collect($res->json('data'))->pluck('id')->all();

        $this->assertNotContains($device->user_id, $ids);
        $this->assertContains($this->a['user']->id, $ids);
    }

    public function test_terminal_kullanicisi_normal_giris_yapamaz(): void
    {
        $device = $this->makeDevice($this->a);
        $user = User::find($device->user_id);
        // Bilinen bir parola atansa bile e-posta girişinde ELENMELİDİR.
        $user->forceFill(['password' => bcrypt('secret1234')])->save();

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'secret1234',
        ])->assertStatus(422);
    }

    public function test_terminal_kullanicisi_impersonate_edilemez(): void
    {
        $manager = $this->makeTenantWithUser(['staff.manage', 'staff.view']);
        $device = $this->makeDevice($manager);

        $this->actingAs($manager['user']);

        $this->postJson("/api/v1/staff/{$device->user_id}/impersonate")
            ->assertStatus(422);
    }

    /* ---------------- Token oto-giriş akışı ---------------- */

    public function test_gecerli_token_oto_giris_yapar_ve_istasyon_ekranina_yonlendirir(): void
    {
        $device = $this->makeDevice($this->a, 'kitchen');

        $this->get('/terminal/'.$device->token)
            ->assertRedirect('/panel/mutfak');

        $this->assertAuthenticatedAs(User::find($device->user_id));
    }

    public function test_barista_token_barista_ekranina_yonlendirir(): void
    {
        $device = $this->makeDevice($this->a, 'barista');

        $this->get('/terminal/'.$device->token)->assertRedirect('/panel/barista');
    }

    public function test_komi_token_komi_ekranina_yonlendirir(): void
    {
        $device = $this->makeDevice($this->a, 'komi');

        $this->get('/terminal/'.$device->token)->assertRedirect('/panel/komi');
    }

    public function test_rotasyonlu_token_410_gecersiz_404(): void
    {
        $device = $this->makeDevice($this->a);
        $old = $device->token;
        $device->rotateToken();

        $this->get('/terminal/'.$old)->assertStatus(410);
        $this->get('/terminal/'.str_repeat('A', 26))->assertStatus(404);
    }

    public function test_kilitli_cihaz_kilit_ekrani_gosterir(): void
    {
        $device = $this->makeDevice($this->a);
        $device->status = TerminalDevice::STATUS_INACTIVE;
        $device->save();

        $this->get('/terminal/'.$device->token)
            ->assertOk()
            ->assertSee('geçici olarak kapalı');

        $this->assertGuest();
    }

    /* ---------------- Kilitli mod (rota koruması) ---------------- */

    public function test_terminal_kullanicisi_baska_panel_sayfasina_gidince_kendi_ekranina_doner(): void
    {
        $device = $this->makeDevice($this->a, 'kitchen');
        $user = User::find($device->user_id);

        $this->actingAs($user);

        // Kendi ekranı: engellenmez (yönlendirme yok).
        $this->get('/panel/mutfak')->assertOk();

        // Başka panel sayfası: kendi ekranına redirect.
        $this->get('/panel/personel')->assertRedirect('/panel/mutfak');
        $this->get('/panel')->assertRedirect('/panel/mutfak');
    }

    public function test_terminal_kullanicisi_kds_api_uclarini_kullanabilir(): void
    {
        $device = $this->makeDevice($this->a, 'kitchen');
        $user = User::find($device->user_id);

        $this->actingAs($user);

        // Polling ucu kilitli modda ENGELLENMEZ (JSON/API dokunulmaz).
        $this->getJson('/api/v1/kds/queue')->assertOk();
    }

    /* ---------------- Panel yönetimi ---------------- */

    public function test_yetkili_terminal_ekler_url_ve_qr_doner(): void
    {
        $manager = $this->makeTenantWithUser(['terminals.manage', 'terminals.view']);

        $this->actingAs($manager['user']);

        $res = $this->postJson('/api/v1/terminals/devices', [
            'name' => 'Mutfak Terminal 1',
            'branch_id' => $manager['branch']->id,
            'station' => 'kitchen',
        ])->assertCreated();

        $this->assertStringContainsString('/terminal/', $res->json('device.url'));
        $this->assertStringStartsWith('data:image/svg+xml;base64,', $res->json('device.qr'));
        $this->assertSame('kitchen', $res->json('device.station'));

        // Gizli kullanıcı oluştu.
        $device = TerminalDevice::withoutTenancy()->first();
        $this->assertNotNull(User::find($device->user_id));
    }

    public function test_yetkisiz_terminal_ekleyemez(): void
    {
        $viewer = $this->makeTenantWithUser(['terminals.view']);

        $this->actingAs($viewer['user']);

        $this->postJson('/api/v1/terminals/devices', [
            'name' => 'X',
            'branch_id' => $viewer['branch']->id,
            'station' => 'kitchen',
        ])->assertStatus(403);
    }

    public function test_kiraci_izolasyonu_yabanci_cihaz_404(): void
    {
        $device = $this->makeDevice($this->b);

        $this->actingAs($this->a['user']);

        $this->postJson("/api/v1/terminals/devices/{$device->id}/lock")->assertNotFound();
    }

    public function test_silme_gizli_kullaniciyi_da_kaldirir(): void
    {
        $manager = $this->makeTenantWithUser(['terminals.manage']);
        $device = $this->makeDevice($manager);
        $userId = $device->user_id;

        $this->actingAs($manager['user']);

        $this->deleteJson("/api/v1/terminals/devices/{$device->id}")->assertNoContent();

        $this->assertNull(TerminalDevice::withoutTenancy()->find($device->id));
        $this->assertNull(User::find($userId));
        $this->assertSame(0, UserStation::query()->where('user_id', $userId)->count());
    }

    public function test_token_rotasyonu_eski_adresi_gecersiz_kilar(): void
    {
        $manager = $this->makeTenantWithUser(['terminals.manage']);
        $device = $this->makeDevice($manager);
        $old = $device->token;

        $this->actingAs($manager['user']);

        $res = $this->postJson("/api/v1/terminals/devices/{$device->id}/rotate-token")->assertOk();
        $new = $res->json('device.url');

        $this->assertStringNotContainsString($old, $new);
        $this->get('/terminal/'.$old)->assertStatus(410);
    }

    /* ---------------- Lisans limiti (§13 Faz 3) ---------------- */

    public function test_yeni_kiracinin_varsayilan_lisans_limiti_makul_degerdir(): void
    {
        // TenantFactory terminal_license_limit vermiyor → migration'daki DB
        // varsayılanı (config('terminal.license.default_limit')) devreye girer.
        $this->assertSame(
            (int) config('terminal.license.default_limit'),
            (int) $this->a['tenant']->fresh()->terminal_license_limit,
        );
    }

    public function test_index_ucu_lisans_gostergesini_doner(): void
    {
        $manager = $this->makeTenantWithUser(['terminals.view']);
        $this->makeDevice($manager, 'kitchen');
        $this->makeDevice($manager, 'barista');

        $this->actingAs($manager['user']);

        $res = $this->getJson('/api/v1/terminals/devices')->assertOk();

        $this->assertSame(TerminalLicense::defaultLimit(), $res->json('license.limit'));
        $this->assertSame(2, $res->json('license.used'));
        $this->assertFalse($res->json('license.unlimited'));
        $this->assertSame(TerminalLicense::defaultLimit() - 2, $res->json('license.remaining'));
    }

    public function test_lisans_limiti_asilinca_terminal_eklenemez(): void
    {
        $manager = $this->makeTenantWithUser(['terminals.manage', 'terminals.view']);
        $limit = TerminalLicense::defaultLimit();

        for ($i = 0; $i < $limit; $i++) {
            $this->makeDevice($manager, 'kitchen', "Terminal {$i}");
        }

        $this->actingAs($manager['user']);

        $res = $this->postJson('/api/v1/terminals/devices', [
            'name' => 'Limit Aşan Terminal',
            'branch_id' => $manager['branch']->id,
            'station' => 'kitchen',
        ])->assertStatus(422);

        $res->assertJsonPath('errors.license.0', function (string $msg) use ($limit) {
            return str_contains($msg, "({$limit}/{$limit})") && str_contains($msg, 'Terminal lisans limitiniz doldu');
        });

        // Limit dolunca gerçekten ekLENMEMİŞ olmalı.
        $this->assertSame($limit, TerminalDevice::withoutTenancy()->count());
    }

    public function test_lisans_limiti_null_ise_sinirsizdir(): void
    {
        $manager = $this->makeTenantWithUser(['terminals.manage', 'terminals.view']);
        $manager['tenant']->forceFill(['terminal_license_limit' => null])->save();

        $limit = TerminalLicense::defaultLimit();
        for ($i = 0; $i < $limit; $i++) {
            $this->makeDevice($manager, 'kitchen', "Terminal {$i}");
        }

        $this->actingAs($manager['user']);

        // Varsayılan limiti aşan sayıda cihaz olsa bile sınırsız kiracıda engellenmez.
        $this->postJson('/api/v1/terminals/devices', [
            'name' => 'Sınırsız Ek Terminal',
            'branch_id' => $manager['branch']->id,
            'station' => 'kitchen',
        ])->assertCreated();

        $res = $this->getJson('/api/v1/terminals/devices')->assertOk();
        $this->assertTrue($res->json('license.unlimited'));
        $this->assertNull($res->json('license.limit'));
        $this->assertNull($res->json('license.remaining'));
    }

    public function test_kiraci_ozel_limiti_varsayilani_gecersiz_kilar(): void
    {
        $manager = $this->makeTenantWithUser(['terminals.manage', 'terminals.view']);
        $manager['tenant']->forceFill(['terminal_license_limit' => 1])->save();

        $this->makeDevice($manager, 'kitchen', 'Terminal 1');

        $this->actingAs($manager['user']);

        $this->postJson('/api/v1/terminals/devices', [
            'name' => 'İkinci Terminal',
            'branch_id' => $manager['branch']->id,
            'station' => 'kitchen',
        ])->assertStatus(422);
    }
}
