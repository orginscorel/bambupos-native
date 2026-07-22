<?php

namespace Tests\Feature\Identity;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

class PasswordResetTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    public function test_sifirlama_istegi_epostanin_varligini_sizdirmaz(): void
    {
        $setup = $this->makeTenantWithUser();

        $existing = $this->postJson('/api/v1/auth/forgot-password', ['email' => $setup['user']->email])->assertOk();
        $missing = $this->postJson('/api/v1/auth/forgot-password', ['email' => 'yok@ornek.test'])->assertOk();

        $this->assertSame($existing->json('message'), $missing->json('message'));
    }

    public function test_sifirlama_istegi_rate_limitlidir(): void
    {
        for ($i = 0; $i < 3; $i++) {
            $this->postJson('/api/v1/auth/forgot-password', ['email' => 'ratelimit@ornek.test'])->assertOk();
        }

        $this->postJson('/api/v1/auth/forgot-password', ['email' => 'ratelimit@ornek.test'])->assertStatus(429);
    }

    public function test_gecerli_token_ile_parola_sifirlanir(): void
    {
        $setup = $this->makeTenantWithUser();

        $token = Password::broker()->createToken($setup['user']);

        $this->postJson('/api/v1/auth/reset-password', [
            'token' => $token,
            'email' => $setup['user']->email,
            'password' => 'yeni-guclu-parola-42',
            'password_confirmation' => 'yeni-guclu-parola-42',
        ])->assertOk();

        $this->assertTrue(Hash::check('yeni-guclu-parola-42', $setup['user']->fresh()->password));
        $this->assertDatabaseHas('audit_logs', ['action' => 'auth.password_reset', 'user_id' => $setup['user']->id]);
    }

    public function test_gecersiz_token_reddedilir(): void
    {
        $setup = $this->makeTenantWithUser();

        $this->postJson('/api/v1/auth/reset-password', [
            'token' => 'gecersiz-token',
            'email' => $setup['user']->email,
            'password' => 'yeni-guclu-parola-42',
            'password_confirmation' => 'yeni-guclu-parola-42',
        ])->assertUnprocessable();
    }

    public function test_kisa_parola_kabul_edilmez(): void
    {
        $setup = $this->makeTenantWithUser();

        $token = Password::broker()->createToken($setup['user']);

        $this->postJson('/api/v1/auth/reset-password', [
            'token' => $token,
            'email' => $setup['user']->email,
            'password' => 'kisa',
            'password_confirmation' => 'kisa',
        ])->assertUnprocessable();
    }
}
