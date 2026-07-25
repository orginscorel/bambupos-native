<?php

namespace Tests\Feature\Shifts;

use Inertia\Testing\AssertableInertia;

/**
 * Shifts Inertia sayfaları: erişim + yetki + feature-flag kancasının
 * render'ı bozmadığı. Veri istemci tarafında /api/v1/shifts'ten yüklenir.
 */
class ShiftPageTest extends ShiftsTestCase
{
    public function test_vardiya_takvimi_yonetici_icin_acilir(): void
    {
        $ctx = $this->makeTenantWithUser();

        $this->actingAs($ctx['user'])
            ->get('/panel/vardiya')
            ->assertOk()
            ->assertInertia(fn (AssertableInertia $page) => $page->component('Panel/Shifts/Schedule', false));
    }

    public function test_vardiya_takvimi_misafire_kapali(): void
    {
        $this->get('/panel/vardiya')->assertRedirect('/giris');
    }

    public function test_mesai_ayarlari_staff_manage_ister(): void
    {
        $ctx = $this->makeTenantWithUser();
        $limited = $this->addStaff($ctx); // yalnız catalog.view

        $this->actingAs($limited)->get('/panel/mesai/ayarlar')->assertForbidden();
        $this->actingAs($ctx['user'])->get('/panel/mesai/ayarlar')->assertOk();
    }

    public function test_onay_ekrani_staff_manage_ister(): void
    {
        $ctx = $this->makeTenantWithUser();
        $limited = $this->addStaff($ctx);

        $this->actingAs($limited)->get('/panel/mesai/talepler')->assertForbidden();
        $this->actingAs($ctx['user'])->get('/panel/mesai/talepler')->assertOk();
    }
}
