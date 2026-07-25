<?php

namespace Tests\Feature\Kds;

/**
 * §12 İSTASYON YÖNLENDİRME — Mutfak ↔ Barista ayrımı.
 *
 * Karışık bir adisyonda (yemek + içecek) her istasyon ekranı YALNIZ kendi
 * kalemlerini görür; komi ise hepsini görür (ayrı testlerde). Süzme kalem
 * düzeyindedir: aynı siparişin diğer istasyon kalemi ekranda görünmez.
 */
class KdsStationRoutingTest extends KdsTestCase
{
    public function test_mutfak_ve_barista_ekranlari_yalniz_kendi_kalemlerini_gorur(): void
    {
        $this->createOrderWithItems([
            ['station' => 'kitchen', 'name' => 'Köfte'],
            ['station' => 'barista', 'name' => 'Latte'],
        ]);

        $this->actingAs($this->makeUserInA(['kds.view']));
        $branchId = (int) $this->a['branch']->id;

        $stationsOnScreen = function (string $station) use ($branchId) {
            $res = $this->getJson("/api/v1/kds/queue?mode=kitchen&branch_id={$branchId}&station={$station}")
                ->assertOk();

            return collect($res->json('orders'))
                ->flatMap(fn (array $o) => collect($o['items'])->pluck('station'))
                ->unique()->values()->all();
        };

        // Mutfak süzgeci → yalnız 'kitchen' kalemi; Latte GÖRÜNMEZ.
        $this->assertEqualsCanonicalizing(['kitchen'], $stationsOnScreen('kitchen'));

        // Barista süzgeci → yalnız 'barista' kalemi; Köfte GÖRÜNMEZ.
        $this->assertEqualsCanonicalizing(['barista'], $stationsOnScreen('barista'));
    }

    public function test_barista_rotasi_acilir_ve_barista_suzgeciyle_gelir(): void
    {
        $this->actingAs($this->makeUserInA(['kds.view']));

        $this->get('/panel/barista')
            ->assertOk()
            ->assertInertia(fn ($page) => $page
                ->component('Panel/Kds/Kitchen', false)
                ->where('initialStation', 'barista'));
    }

    public function test_mutfak_rotasi_varsayilan_mutfak_suzgeciyle_gelir(): void
    {
        $this->actingAs($this->makeUserInA(['kds.view']));

        $this->get('/panel/mutfak')
            ->assertOk()
            ->assertInertia(fn ($page) => $page
                ->component('Panel/Kds/Kitchen', false)
                ->where('initialStation', 'kitchen'));
    }
}
