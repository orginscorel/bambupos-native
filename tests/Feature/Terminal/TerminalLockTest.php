<?php

namespace Tests\Feature\Terminal;

use App\Modules\Identity\Models\User;
use App\Modules\Terminal\Models\TerminalDevice;
use App\Modules\Terminal\Services\TerminalProvisioner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * §13 Faz D — ANLIK uzaktan kilit (BUG #3 düzeltmesi): `POST /terminal/heartbeat`
 * artık cihaz kilitliyken `{status:'locked'}` döner VE bu durumu okuyan istemci
 * (useTerminalHeartbeat) `GET /terminal/relock`'a yönlenir — bu uç, token
 * olmadan (yalnız oturumdaki user_id'den) `show()`'daki kilit dalıyla BİREBİR
 * aynı davranışı üretir: oturumu düşürür + kendini-yokla `terminal.locked`
 * sayfasını gösterir.
 */
class TerminalLockTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
    }

    private function makeDevice(string $station = 'kasa'): TerminalDevice
    {
        return $this->asTenant($this->a['tenant'], fn (): TerminalDevice => app(TerminalProvisioner::class)
            ->createDevice('Test Terminal', (int) $this->a['branch']->id, (int) $this->a['tenant']->id, $station));
    }

    /* ---------------- Heartbeat: locked durumu artık okunuyor ---------------- */

    public function test_heartbeat_kilitli_olmayan_cihazda_ok_doner(): void
    {
        $device = $this->makeDevice();
        $this->actingAs(User::find($device->user_id));

        $this->postJson('/terminal/heartbeat')
            ->assertOk()
            ->assertJson(['status' => 'ok']);
    }

    public function test_heartbeat_kilitli_cihazda_locked_doner(): void
    {
        $device = $this->makeDevice();
        $this->actingAs(User::find($device->user_id));

        $device->status = TerminalDevice::STATUS_INACTIVE;
        $device->save();

        $this->postJson('/terminal/heartbeat')
            ->assertOk()
            ->assertJson(['status' => 'locked']);

        // Heartbeat'in kendisi oturumu düşürmez (BUG #3 düzeltmesi istemcide
        // /terminal/relock'a yönlendirme ile tamamlanır) — burada yalnız
        // yanıtın artık doğru okunabilir olduğunu doğruluyoruz.
        $this->assertAuthenticatedAs(User::find($device->user_id));
    }

    /* ---------------- /terminal/relock: token'sız ANINDA kilit sayfası ---------------- */

    public function test_relock_kilitli_cihazda_oturumu_dusurur_ve_kilit_sayfasini_gosterir(): void
    {
        $device = $this->makeDevice();
        $this->actingAs(User::find($device->user_id));

        $device->status = TerminalDevice::STATUS_INACTIVE;
        $device->save();

        $this->get('/terminal/relock')
            ->assertOk()
            ->assertSee('geçici olarak kapalı');

        $this->assertGuest();
    }

    public function test_relock_kilitli_degilse_kendi_ekranina_yonlendirir_oturum_korunur(): void
    {
        $device = $this->makeDevice('kasa');
        $this->actingAs(User::find($device->user_id));

        // Yarış durumu: panelden kilit az önce açıldı — relock'a gelen istek
        // cihazı artık kilitli bulmaz, ekrana geri yönlendirmeli, oturum canlı kalmalı.
        $this->get('/terminal/relock')->assertRedirect('/panel/kasa');

        $this->assertAuthenticatedAs(User::find($device->user_id));
    }

    public function test_relock_terminal_olmayan_normal_kullaniciyi_girise_yonlendirir(): void
    {
        $this->actingAs($this->a['user']);

        $this->get('/terminal/relock')->assertRedirect('/giris');
    }

    public function test_relock_oturumsuz_istekte_login_gerektirir(): void
    {
        $this->get('/terminal/relock')->assertRedirect('/giris');
    }
}
