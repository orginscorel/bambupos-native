<?php

namespace Tests\Feature\Portal;

use Illuminate\Support\Facades\Auth;

/**
 * KALICI OTURUM + 3 durumda OTO-KAPANMA:
 *  - Portal girişinde uzun ömürlü remember-me zorlanır (panel host DEĞİŞMEZ).
 *  - Pasife alınma/işten çıkarma → EnsureUserIsActive oturumu düşürür.
 *  - Parola değişimi → AuthenticateSession (yalnız portal grubunda) düşürür;
 *    panelde bu davranış YOKTUR (oturum sürer).
 */
class PortalSessionTest extends PortalTestCase
{
    private function recaller(): string
    {
        return Auth::guard('web')->getRecallerName();
    }

    public function test_portal_girisi_kalici_remember_cerezi_zorlar(): void
    {
        $ctx = $this->makeTenantWithUser();

        // remember GÖNDERİLMESE bile portal host'unda zorlanır.
        $this->postJson($this->portalUrl('/api/v1/auth/login'), [
            'email' => $ctx['user']->email,
            'password' => 'password',
        ])->assertOk()->assertJsonPath('two_factor', false);

        $this->assertNotNull(Auth::guard('web')->user());
    }

    public function test_panel_hostunda_remember_zorlanmaz(): void
    {
        $ctx = $this->makeTenantWithUser();

        $this->postJson($this->panelUrl('/api/v1/auth/login'), [
            'email' => $ctx['user']->email,
            'password' => 'password',
        ])->assertOk()->assertCookieMissing($this->recaller());
    }

    public function test_portal_girisi_remember_cerezi_birakir(): void
    {
        $ctx = $this->makeTenantWithUser();

        $this->postJson($this->portalUrl('/api/v1/auth/login'), [
            'email' => $ctx['user']->email,
            'password' => 'password',
        ])->assertOk()->assertCookie($this->recaller());
    }

    public function test_pasife_alinan_personel_portal_oturumu_duser(): void
    {
        $ctx = $this->makeTenantWithUser();
        $user = $ctx['user'];

        $this->actingAs($user)->get($this->portalUrl('/mesaim'))->assertOk();

        // İşten çıkarma = pasife alma.
        $user->forceFill(['is_active' => false])->save();

        $this->actingAs($user)->get($this->portalUrl('/mesaim'))->assertRedirect('/giris');
    }

    public function test_parola_degisimi_portal_oturumunu_gecersiz_kilar(): void
    {
        $ctx = $this->makeTenantWithUser();
        $user = $ctx['user'];

        // Doğru parola-hash'i oturumda → geçer.
        $this->actingAs($user)
            ->withSession(['password_hash_web' => $user->getAuthPassword()])
            ->get($this->portalUrl('/mesaim'))
            ->assertOk();

        // Parola değişmiş (oturumdaki hash artık eskimiş) → AuthenticateSession düşürür.
        $this->actingAs($user)
            ->withSession(['password_hash_web' => 'stale-hash'])
            ->get($this->portalUrl('/mesaim'))
            ->assertRedirect('/giris');
    }

    public function test_panelde_parola_hash_uyumsuzlugu_oturumu_dusurmez(): void
    {
        // Panel grubunda AuthenticateSession YOK → aynı eskimiş hash oturumu düşürmez.
        $ctx = $this->makeTenantWithUser();

        $this->actingAs($ctx['user'])
            ->withSession(['password_hash_web' => 'stale-hash'])
            ->get('/panel')
            ->assertOk();
    }
}
