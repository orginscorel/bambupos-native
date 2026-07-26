<?php

namespace Tests\Feature\Portal;

/**
 * Host-farkındalık: portal rotaları YALNIZ portal host'unda (Route::domain)
 * eşleşir; panel host DEĞİŞMEZ. Test için Host header ile erişilir (DNS yok).
 */
class PortalHostRoutingTest extends PortalTestCase
{
    public function test_portal_host_kok_mesaime_yonlendirir(): void
    {
        // Kimlikten bağımsız: HandlePortalHost middleware kökü /mesaim'e taşır.
        $this->get($this->portalUrl('/'))->assertRedirect('/mesaim');
    }

    public function test_giris_yapmis_personel_portal_ekranini_gorur(): void
    {
        $ctx = $this->makeTenantWithUser();

        $this->actingAs($ctx['user'])
            ->get($this->portalUrl('/mesaim'))
            ->assertOk()
            ->assertInertia(fn ($page) => $page->component('Portal/Shift', false));
    }

    public function test_misafir_portalda_girise_yonlenir(): void
    {
        $this->get($this->portalUrl('/mesaim'))->assertRedirect('/giris');
    }

    public function test_panel_hostunda_portal_yollari_tanimli_degil(): void
    {
        $ctx = $this->makeTenantWithUser();

        // Portal yolları panel host'unda ROTA DEĞİL → 404 (izolasyon).
        $this->actingAs($ctx['user'])
            ->get($this->panelUrl('/mesaim'))
            ->assertNotFound();
    }

    public function test_panel_hostunda_kok_davranisi_degismez(): void
    {
        // Misafir panel host kökü → giriş rotasına (portal değil).
        $this->get($this->panelUrl('/'))->assertRedirect('/giris');
    }
}
