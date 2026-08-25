<?php

namespace Tests\Feature\Orders;

use App\Modules\Orders\Models\DiscountPreset;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Hazır indirim tanımları + TEK İNDİRİM kuralı.
 *
 * Tanım bir kez yapılır, kasa/sepet tek dokunuşla uygular; gerekçe tanımın
 * adından gelir (raporda gruplanabilir). Adisyonda indirim varken yenisi
 * eklenemez — önce kaldırılır.
 */
class DiscountPresetTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    /** @return array{0: array<string, mixed>, 1: int} */
    private function openOrder(int $unitMinor = 10000, int $qty = 1): array
    {
        $this->seedPermissions();
        $owner = $this->makeTenantWithUser();
        $this->actingAs($owner['user']);

        $table = $this->makeTable($owner);
        $product = $this->makeProduct($owner, ['price_minor' => $unitMinor]);

        $orderId = (int) $this->postJson('/api/v1/orders', [
            'branch_id' => $owner['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => $qty])
            ->assertCreated();

        return [$owner, $orderId];
    }

    public function test_tanim_olusturulur_ve_listelenir(): void
    {
        [$owner] = $this->openOrder();

        $this->postJson('/api/v1/discount-presets', [
            'name' => 'Şehit/Gazi yakını', 'type' => 'percent', 'value_percent' => 20,
        ])->assertCreated()->assertJsonPath('preset.value_label', '%20');

        $this->postJson('/api/v1/discount-presets', [
            'name' => 'Kamu personeli', 'type' => 'percent', 'value_percent' => 10,
        ])->assertCreated();

        $this->getJson('/api/v1/discount-presets')->assertOk()->assertJsonCount(2, 'presets');

        // Aynı ad ikinci kez eklenemez.
        $this->postJson('/api/v1/discount-presets', [
            'name' => 'Kamu personeli', 'type' => 'percent', 'value_percent' => 5,
        ])->assertStatus(422);

        $this->assertSame(2, DiscountPreset::withoutTenancy()->where('tenant_id', $owner['tenant']->id)->count());
    }

    public function test_tanimla_indirim_uygulanir_ve_gerekce_tanim_adidir(): void
    {
        [, $orderId] = $this->openOrder(10000, 1);

        $presetId = (int) $this->postJson('/api/v1/discount-presets', [
            'name' => 'Şehit/Gazi yakını', 'type' => 'percent', 'value_percent' => 20,
        ])->json('preset.id');

        $res = $this->postJson("/api/v1/orders/{$orderId}/discount", ['preset_id' => $presetId])->assertOk();

        $this->assertSame(2000, $res->json('order.discount_minor'));
        $this->assertSame('Şehit/Gazi yakını', $res->json('order.discount_reason'));
        $this->assertSame(8000, $res->json('order.total_minor'));
    }

    public function test_ikinci_indirim_eklenemez_once_kaldirilmali(): void
    {
        [, $orderId] = $this->openOrder(10000, 1);

        $a = (int) $this->postJson('/api/v1/discount-presets', [
            'name' => 'Kamu personeli', 'type' => 'percent', 'value_percent' => 10,
        ])->json('preset.id');
        $b = (int) $this->postJson('/api/v1/discount-presets', [
            'name' => 'Şehit/Gazi yakını', 'type' => 'percent', 'value_percent' => 20,
        ])->json('preset.id');

        $this->postJson("/api/v1/orders/{$orderId}/discount", ['preset_id' => $a])->assertOk();

        // İkinci indirim REDDEDİLİR (üzerine yazmaz).
        $this->postJson("/api/v1/orders/{$orderId}/discount", ['preset_id' => $b])->assertStatus(422);
        $this->assertSame(1000, $this->getJson("/api/v1/orders/{$orderId}")->json('order.discount_minor'));

        // Kaldır → sonra ikincisi uygulanabilir.
        $this->deleteJson("/api/v1/orders/{$orderId}/discount")
            ->assertOk()
            ->assertJsonPath('order.discount_minor', 0)
            ->assertJsonPath('order.total_minor', 10000);

        $this->postJson("/api/v1/orders/{$orderId}/discount", ['preset_id' => $b])
            ->assertOk()
            ->assertJsonPath('order.discount_minor', 2000);
    }

    public function test_indirimsiz_adisyonda_kaldirma_reddedilir(): void
    {
        [, $orderId] = $this->openOrder();

        $this->deleteJson("/api/v1/orders/{$orderId}/discount")->assertStatus(422);
    }

    public function test_sabit_tutar_tanimi_kurus_olarak_uygulanir(): void
    {
        [, $orderId] = $this->openOrder(10000, 1);

        $presetId = (int) $this->postJson('/api/v1/discount-presets', [
            'name' => 'Personel yemeği', 'type' => 'amount', 'value_minor' => 2500,
        ])->assertCreated()->json('preset.id');

        $this->postJson("/api/v1/orders/{$orderId}/discount", ['preset_id' => $presetId])
            ->assertOk()
            ->assertJsonPath('order.discount_minor', 2500)
            ->assertJsonPath('order.total_minor', 7500);
    }
}
