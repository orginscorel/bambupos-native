<?php

namespace Tests\Feature\Kds;

/**
 * KDS yetkileri (prompt §20): mutfak kullanıcısı yalnız operasyon görür —
 * fiyat/ciro/rapor uçlarına ve sipariş (finanslı) API'sine erişemez.
 */
class KdsAuthorizationTest extends KdsTestCase
{
    public function test_kds_izni_olmayan_ekrani_acamaz(): void
    {
        $garson = $this->makeUserInA(['orders.view']);
        $this->actingAs($garson);

        $this->get('/panel/mutfak')->assertForbidden();
        $this->get('/panel/komi')->assertForbidden();
        $this->getJson('/api/v1/kds/queue')->assertForbidden();
        $this->getJson('/api/v1/kds/updates?cursor=0')->assertForbidden();
    }

    public function test_mutfak_kullanicisi_finansli_uclara_erisemez(): void
    {
        $mutfak = $this->makeUserInA(['kds.view']);
        $this->actingAs($mutfak);

        // KDS ekranı açılır
        $this->get('/panel/mutfak')->assertOk();

        // Finans içeren sipariş API'si: orders.view yok → 403
        $this->getJson('/api/v1/orders')->assertForbidden();
        $this->getJson('/api/v1/orders/board')->assertForbidden();

        // Raporlar: reports.view yok → 403
        $this->getJson('/api/v1/reports/summary')->assertForbidden();

        // Komi ekranı: kds.deliver yok → 403
        $this->get('/panel/komi')->assertForbidden();
        $this->getJson('/api/v1/kds/queue?mode=runner')->assertForbidden();

        // Servis işareti (served) kds.deliver ister
        $setup = null; // sipariş sahibiyle kurulmalı
        auth('web')->logout();
        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);
        $this->actingAs($mutfak);
        $this->postJson("/api/v1/kds/items/{$setup['item_ids'][0]}/status", ['to' => 'ready'])->assertOk();
        $this->postJson("/api/v1/kds/items/{$setup['item_ids'][0]}/status", ['to' => 'served'])->assertForbidden();
        $this->postJson("/api/v1/kds/items/{$setup['item_ids'][0]}/pickup")->assertForbidden();
    }

    public function test_komi_kullanicisi_mutfak_kuyrugunu_goremez_ama_komiyi_gorur(): void
    {
        $komi = $this->makeUserInA(['kds.deliver']);
        $this->actingAs($komi);

        $this->get('/panel/komi')->assertOk();
        $this->getJson('/api/v1/kds/queue?mode=runner')->assertOk();

        // Mutfak ekranı/kuyruğu kds.view ister
        $this->get('/panel/mutfak')->assertForbidden();
        $this->getJson('/api/v1/kds/queue')->assertForbidden();
    }

    public function test_istasyon_yonetimi_kds_manage_ister(): void
    {
        $mutfak = $this->makeUserInA(['kds.view']);
        $this->actingAs($mutfak);

        // Listeleme serbest (süzgeç çipleri için) ama değişiklik yasak
        $this->getJson('/api/v1/kds/stations')->assertOk();
        $this->postJson('/api/v1/kds/stations', ['name' => 'Pizza Fırını'])->assertForbidden();
        $this->getJson('/api/v1/kds/station-assignments')->assertForbidden();
        $this->putJson("/api/v1/kds/station-assignments/{$mutfak->id}", ['station_keys' => []])->assertForbidden();

        // kds.manage olan yönetebilir
        $this->actingAs($this->makeUserInA(['kds.view', 'kds.manage']));
        $this->postJson('/api/v1/kds/stations', ['name' => 'Pizza Fırını'])->assertCreated();
    }

    public function test_yonetici_baska_kiracinin_personeline_atama_yapamaz(): void
    {
        $b = $this->makeTenantWithUser();

        $this->actingAs($this->makeUserInA(['kds.view', 'kds.manage']));

        $this->putJson("/api/v1/kds/station-assignments/{$b['user']->id}", [
            'station_keys' => ['bar'],
        ])->assertNotFound();
    }
}
