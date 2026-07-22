<?php

namespace Tests\Feature\Kds;

/**
 * İstasyon tanımları: 9 yerleşik istasyon + işletmenin KENDİ istasyonları
 * (CRUD, kiracı izolasyonu) + katalog entegrasyonu (ürün → istasyon).
 */
class KdsStationTest extends KdsTestCase
{
    public function test_yerlesik_istasyonlar_listede(): void
    {
        $this->actingAs($this->makeUserInA(['kds.view']));

        $keys = collect($this->getJson('/api/v1/kds/stations')->assertOk()->json('stations'))->pluck('key');

        foreach (['kitchen', 'cold_kitchen', 'grill', 'oven', 'dessert', 'coffee', 'bar', 'hookah', 'packaging'] as $key) {
            $this->assertTrue($keys->contains($key), "Yerleşik istasyon eksik: {$key}");
        }
    }

    public function test_isletme_kendi_istasyonunu_ekler_ve_yonetir(): void
    {
        $this->actingAs($this->makeUserInA(['kds.view', 'kds.manage']));

        // Ekle — anahtar addan türetilir
        $station = $this->postJson('/api/v1/kds/stations', ['name' => 'Pizza Fırını'])
            ->assertCreated()->json('station');
        $this->assertSame('pizza_firini', $station['key']);

        // Listede görünür
        $keys = collect($this->getJson('/api/v1/kds/stations')->json('stations'))->pluck('key');
        $this->assertTrue($keys->contains('pizza_firini'));

        // Aynı ad tekrar: anahtar çakışmaz
        $second = $this->postJson('/api/v1/kds/stations', ['name' => 'Pizza Fırını'])
            ->assertCreated()->json('station');
        $this->assertSame('pizza_firini_2', $second['key']);

        // Pasifleştir + sil
        $this->putJson("/api/v1/kds/stations/{$station['id']}", ['is_active' => false])->assertOk();
        $this->deleteJson("/api/v1/kds/stations/{$station['id']}")->assertOk();
    }

    public function test_urunu_olan_istasyon_silinemez(): void
    {
        $this->actingAs($this->a['user']);

        $station = $this->postJson('/api/v1/kds/stations', ['name' => 'Nargile Bahçe'])
            ->assertCreated()->json('station');

        $this->makeProduct($this->a, ['name' => 'Nargile', 'station' => $station['key']]);

        $this->deleteJson("/api/v1/kds/stations/{$station['id']}")->assertUnprocessable();
    }

    public function test_istasyonlar_kiraciya_ozeldir(): void
    {
        // A kendi istasyonunu ekler
        $this->actingAs($this->a['user']);
        $stationA = $this->postJson('/api/v1/kds/stations', ['name' => 'Ozel A'])->assertCreated()->json('station');
        auth('web')->logout();

        // B listesinde A'nın istasyonu YOK; id ile de erişemez (404)
        $b = $this->makeTenantWithUser();
        $this->actingAs($b['user']);

        $keys = collect($this->getJson('/api/v1/kds/stations')->json('stations'))->pluck('key');
        $this->assertFalse($keys->contains('ozel_a'));

        $this->putJson("/api/v1/kds/stations/{$stationA['id']}", ['name' => 'Ele geçirdim'])->assertNotFound();
        $this->deleteJson("/api/v1/kds/stations/{$stationA['id']}")->assertNotFound();
    }

    public function test_katalog_urun_formu_istasyonlari_sunar_ve_dogrular(): void
    {
        $this->actingAs($this->a['user']);

        // Özel istasyon ekle → ürün formu seçeneklerinde görünür
        $station = $this->postJson('/api/v1/kds/stations', ['name' => 'Pizza Fırını'])->json('station');

        $values = collect($this->getJson('/api/v1/catalog/products/form-options')->assertOk()->json('stations'))
            ->pluck('value');
        $this->assertTrue($values->contains('kitchen'));
        $this->assertTrue($values->contains('pizza_firini'));

        // Ürün geçerli istasyona yönlendirilir
        $this->postJson('/api/v1/catalog/products', [
            'name' => 'Margarita', 'price_minor' => 20000, 'station' => $station['key'],
        ])->assertCreated();

        // Geçersiz istasyon reddedilir
        $this->postJson('/api/v1/catalog/products', [
            'name' => 'Hatalı', 'price_minor' => 10000, 'station' => 'uydurma_istasyon',
        ])->assertUnprocessable();
    }
}
