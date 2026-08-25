<?php

namespace Tests\Feature\Orders;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Adisyon başlığı (kişi sayısı + adisyon notu) sonradan düzeltilebilir.
 *
 * Bu iki alan yalnız adisyon AÇILIRKEN verilebiliyordu; masaya biri
 * katıldığında ya da mutfağa iletilecek bir not çıktığında düzeltmek
 * mümkün değildi. Uç TUTARA DOKUNMAZ — burada da doğrulanır.
 */
class OrderInfoUpdateTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    /** @return array{0: array<string, mixed>, 1: int} */
    private function openOrderWithItem(): array
    {
        $this->seedPermissions();
        $owner = $this->makeTenantWithUser();
        $this->actingAs($owner['user']);

        $table = $this->makeTable($owner);
        $product = $this->makeProduct($owner, ['price_minor' => 10000]);

        $orderId = (int) $this->postJson('/api/v1/orders', [
            'branch_id' => $owner['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 2])
            ->assertCreated();

        return [$owner, $orderId];
    }

    public function test_kisi_sayisi_ve_not_guncellenir_tutar_degismez(): void
    {
        [, $orderId] = $this->openOrderWithItem();

        $before = $this->getJson("/api/v1/orders/{$orderId}")->json('order');

        $res = $this->putJson("/api/v1/orders/{$orderId}/info", [
            'guest_count' => 4,
            'note' => 'Doğum günü — pasta sonda gelsin',
        ])->assertOk();

        $this->assertSame(4, $res->json('order.guest_count'));
        $this->assertSame('Doğum günü — pasta sonda gelsin', $res->json('order.note'));

        // Para alanlarına DOKUNULMADI.
        $this->assertSame($before['items_total_minor'], $res->json('order.items_total_minor'));
        $this->assertSame($before['total_minor'], $res->json('order.total_minor'));
        $this->assertSame($before['remaining_minor'], $res->json('order.remaining_minor'));
    }

    public function test_kisi_sayisi_null_yapilabilir_ve_sinir_disi_reddedilir(): void
    {
        [, $orderId] = $this->openOrderWithItem();

        $this->putJson("/api/v1/orders/{$orderId}/info", ['guest_count' => 4])->assertOk();

        $this->putJson("/api/v1/orders/{$orderId}/info", ['guest_count' => null])
            ->assertOk()
            ->assertJsonPath('order.guest_count', null);

        $this->putJson("/api/v1/orders/{$orderId}/info", ['guest_count' => 0])
            ->assertStatus(422);
        $this->putJson("/api/v1/orders/{$orderId}/info", ['guest_count' => 201])
            ->assertStatus(422);
    }

    public function test_gonderilmeyen_alan_korunur(): void
    {
        [, $orderId] = $this->openOrderWithItem();

        $this->putJson("/api/v1/orders/{$orderId}/info", ['guest_count' => 3, 'note' => 'ilk not'])->assertOk();

        // Yalnız not gönderilir → kişi sayısı OLDUĞU GİBİ kalır.
        $this->putJson("/api/v1/orders/{$orderId}/info", ['note' => 'ikinci not'])
            ->assertOk()
            ->assertJsonPath('order.guest_count', 3)
            ->assertJsonPath('order.note', 'ikinci not');
    }

    public function test_eski_surum_ile_gonderilirse_409_doner(): void
    {
        [, $orderId] = $this->openOrderWithItem();

        $version = (int) $this->getJson("/api/v1/orders/{$orderId}")->json('order.version');

        $this->putJson("/api/v1/orders/{$orderId}/info", [
            'guest_count' => 2,
            'expected_version' => $version - 1,
        ])->assertStatus(409);
    }
}
