<?php

namespace Tests\Feature\Identity;

use App\Modules\Identity\Support\Totp;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

class TwoFactorTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    public function test_iki_faktor_kurulur_dogrulanir_ve_login_challenge_ister(): void
    {
        $setup = $this->makeTenantWithUser();

        // 1) Kurulum
        $enable = $this->actingAs($setup['user'])
            ->postJson('/api/v1/auth/two-factor/enable')
            ->assertOk();

        $secret = $enable->json('secret');
        $this->assertNotEmpty($secret);

        // 2) Doğrulama (gerçek TOTP kodu üretilir)
        $code = Totp::code($secret, (int) floor(time() / 30));

        $confirm = $this->actingAs($setup['user'])
            ->postJson('/api/v1/auth/two-factor/confirm', ['code' => $code])
            ->assertOk();

        $this->assertCount(8, $confirm->json('recovery_codes'));

        // 3) Yeni giriş: parola doğru ama oturum AÇILMAZ, challenge istenir
        auth()->logout();
        $this->flushSession();

        $login = $this->postJson('/api/v1/auth/login', [
            'email' => $setup['user']->email,
            'password' => 'password',
        ])->assertOk()->assertJsonPath('two_factor', true);

        $this->assertGuest();

        // 4) Challenge doğru kodla oturum açar
        $code = Totp::code($secret, (int) floor(time() / 30));

        $this->postJson('/api/v1/auth/two-factor-challenge', ['code' => $code])->assertOk();

        $this->assertAuthenticatedAs($setup['user']);
    }

    public function test_yanlis_kodla_challenge_gecilemez(): void
    {
        $setup = $this->makeTenantWithUser();

        $secret = Totp::generateSecret();
        $setup['user']->forceFill([
            'two_factor_secret' => $secret,
            'two_factor_confirmed_at' => now(),
            'two_factor_recovery_codes' => [],
        ])->save();

        $this->postJson('/api/v1/auth/login', [
            'email' => $setup['user']->email,
            'password' => 'password',
        ])->assertOk()->assertJsonPath('two_factor', true);

        $this->postJson('/api/v1/auth/two-factor-challenge', ['code' => '000000'])
            ->assertUnprocessable();

        $this->assertGuest();
    }

    public function test_kurtarma_kodu_bir_kez_kullanilir(): void
    {
        $setup = $this->makeTenantWithUser();

        $secret = Totp::generateSecret();
        $setup['user']->forceFill([
            'two_factor_secret' => $secret,
            'two_factor_confirmed_at' => now(),
            'two_factor_recovery_codes' => ['AAAAA-BBBBB'],
        ])->save();

        $this->postJson('/api/v1/auth/login', [
            'email' => $setup['user']->email,
            'password' => 'password',
        ])->assertOk();

        $this->postJson('/api/v1/auth/two-factor-challenge', ['code' => 'AAAAA-BBBBB'])->assertOk();
        $this->assertAuthenticatedAs($setup['user']);

        // Kod tüketildi
        $this->assertSame([], $setup['user']->fresh()->two_factor_recovery_codes);
    }
}
