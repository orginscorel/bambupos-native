<?php

namespace Tests\Feature\Kds;

use App\Modules\Kds\Models\UserStation;

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

    /** §12 rota koruması: mutfak-atanmış kullanıcı Barista'ya giremez → kendi ekranına döner. */
    public function test_mutfak_atanmis_kullanici_barista_rotasindan_mutfaga_yonlendirilir(): void
    {
        $user = $this->makeUserInA(['kds.view']);
        $this->assignStation($user, 'kitchen');

        $this->actingAs($user)
            ->get('/panel/barista')
            ->assertRedirect('/panel/mutfak');

        // Kendi ekranı serbest.
        $this->get('/panel/mutfak')->assertOk();
    }

    /** §12 rota koruması: barista-atanmış kullanıcı Mutfak'a giremez → kendi ekranına döner. */
    public function test_barista_atanmis_kullanici_mutfak_rotasindan_baristaya_yonlendirilir(): void
    {
        $user = $this->makeUserInA(['kds.view']);
        $this->assignStation($user, 'barista');

        $this->actingAs($user)
            ->get('/panel/mutfak')
            ->assertRedirect('/panel/barista');

        $this->get('/panel/barista')->assertOk();
    }

    /** İçecek ailesi (coffee/bar) da barista sayılır — Mutfak'tan Barista'ya döner. */
    public function test_bar_ailesi_kullanicisi_mutfaktan_baristaya_yonlendirilir(): void
    {
        $user = $this->makeUserInA(['kds.view']);
        $this->assignStation($user, 'bar');

        $this->actingAs($user)
            ->get('/panel/mutfak')
            ->assertRedirect('/panel/barista');
    }

    /** Atanmamış kullanıcı (yönetici/çok-istasyonlu) her iki ekranı da açar. */
    public function test_atanmamis_kullanici_her_iki_ekrani_da_gorur(): void
    {
        $this->actingAs($this->makeUserInA(['kds.view']));

        $this->get('/panel/mutfak')->assertOk();
        $this->get('/panel/barista')->assertOk();
    }

    private function assignStation(\App\Modules\Identity\Models\User $user, string $stationKey): void
    {
        $this->asTenant($this->a['tenant'], fn () => UserStation::query()->create([
            'user_id' => $user->id,
            'station_key' => $stationKey,
        ]));
    }
}
