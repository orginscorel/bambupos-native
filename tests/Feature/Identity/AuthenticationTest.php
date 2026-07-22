<?php

namespace Tests\Feature\Identity;

use App\Modules\Identity\Models\AuditLog;
use App\Modules\Identity\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

class AuthenticationTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    public function test_gecerli_bilgilerle_giris_yapilir_ve_denetim_kaydi_dusulur(): void
    {
        $setup = $this->makeTenantWithUser();

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $setup['user']->email,
            'password' => 'password',
        ]);

        $response->assertOk()->assertJsonPath('two_factor', false);
        $this->assertAuthenticatedAs($setup['user']);

        $user = $setup['user']->fresh();
        $this->assertNotNull($user->last_login_at);

        $this->assertDatabaseHas('audit_logs', [
            'action' => 'auth.login',
            'user_id' => $user->id,
            'tenant_id' => $user->tenant_id,
        ]);
    }

    public function test_yanlis_parola_reddedilir_ve_kayda_gecer(): void
    {
        $setup = $this->makeTenantWithUser();

        $this->postJson('/api/v1/auth/login', [
            'email' => $setup['user']->email,
            'password' => 'yanlis-parola',
        ])->assertUnprocessable();

        $this->assertGuest();
        $this->assertDatabaseHas('audit_logs', ['action' => 'auth.login_failed']);
    }

    public function test_bes_basarisiz_denemeden_sonra_giris_kilitlenir(): void
    {
        $setup = $this->makeTenantWithUser();

        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/auth/login', [
                'email' => $setup['user']->email,
                'password' => 'yanlis-parola',
            ])->assertUnprocessable();
        }

        // 6. deneme: DOĞRU parolayla bile 429
        $this->postJson('/api/v1/auth/login', [
            'email' => $setup['user']->email,
            'password' => 'password',
        ])->assertStatus(429);

        $this->assertGuest();
    }

    public function test_pasif_kullanici_giris_yapamaz(): void
    {
        $setup = $this->makeTenantWithUser();
        $setup['user']->forceFill(['is_active' => false])->save();

        $this->postJson('/api/v1/auth/login', [
            'email' => $setup['user']->email,
            'password' => 'password',
        ])->assertUnprocessable();

        $this->assertGuest();
    }

    public function test_askidaki_kiracinin_kullanicisi_giris_yapamaz(): void
    {
        $setup = $this->makeTenantWithUser();
        $setup['tenant']->update(['status' => 'suspended']);

        $this->postJson('/api/v1/auth/login', [
            'email' => $setup['user']->email,
            'password' => 'password',
        ])->assertStatus(403);

        $this->assertGuest();
    }

    public function test_beni_hatirla_remember_token_uretir(): void
    {
        $setup = $this->makeTenantWithUser();

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $setup['user']->email,
            'password' => 'password',
            'remember' => true,
        ])->assertOk();

        // Remember çerezi verilir ve token DB'de mevcut
        $response->assertCookie(auth()->guard('web')->getRecallerName());
        $this->assertNotNull($setup['user']->fresh()->remember_token);
    }

    public function test_cikis_oturumu_gecersiz_kilar(): void
    {
        $setup = $this->makeTenantWithUser();

        $this->actingAs($setup['user'])->postJson('/api/v1/auth/logout')->assertOk();

        $this->assertGuest();
    }

    public function test_oturumsuz_istek_korunan_uca_erisemez(): void
    {
        $this->getJson('/api/v1/products')->assertUnauthorized();
        $this->getJson('/api/v1/staff')->assertUnauthorized();
        $this->getJson('/api/v1/audit-logs')->assertUnauthorized();
    }
}
