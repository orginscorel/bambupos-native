<?php

namespace Tests\Feature\Orders;

use App\Modules\Orders\Models\ServiceRequest;
use App\Modules\Tables\Models\Table;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Public servis talebi ucu (garson çağır / hesap iste / su iste):
 * token doğrulama, masa/sipariş yansıması, dedup, hız sınırı, panel kapatma.
 */
class PublicServiceRequestTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
    }

    public function test_garson_cagirma_talep_acar_ve_masayi_isaretler(): void
    {
        $table = $this->makeTable($this->a);

        $res = $this->postJson('/api/v1/public/service-requests', [
            'token' => $table->qr_token, 'kind' => 'waiter',
        ])->assertCreated();

        $this->assertSame('waiter', $res->json('request.kind'));
        $this->assertFalse($res->json('deduplicated'));
        $this->assertArrayNotHasKey('id', $res->json('request')); // iç kimlik sızmaz

        $this->assertSame('awaiting_order', Table::withoutTenancy()->find($table->id)->status->value);
        $this->assertSame(1, ServiceRequest::withoutTenancy()->where('table_id', $table->id)->count());
    }

    public function test_hesap_isteme_acik_adisyonu_ve_masayi_hesap_istendi_yapar(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a);

        $this->actingAs($this->a['user']);
        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1]);

        auth('web')->logout();

        $this->postJson('/api/v1/public/service-requests', [
            'token' => $table->qr_token, 'kind' => 'bill',
        ])->assertCreated();

        $this->assertSame('bill_requested', Table::withoutTenancy()->find($table->id)->status->value);

        $this->actingAs($this->a['user']);
        $this->assertSame('bill_requested', $this->getJson("/api/v1/orders/{$orderId}")->json('order.status'));
    }

    /**
     * FAZ2 regresyon: açık adisyon YOKKEN "hesap istiyorum" gönderilirse masa
     * TableStatusSynchronizer'ı bypass edip doğrudan "Hesap istendi"ye
     * yazılmamalı — aksi halde hiçbir sipariş olayı bu durumu bir daha
     * tetiklemeyeceğinden masa sonsuza dek kilitli kalır. Adisyon yoksa
     * senkronizatör masayı Available'da tutar/döndürür.
     */
    public function test_bosta_masada_hesap_istegi_masayi_hesap_istendide_kilitlemez(): void
    {
        $table = $this->makeTable($this->a, ['status' => 'available']);

        // Açık adisyon YOK — masaya doğrudan "hesap istiyorum" gelir.
        $this->postJson('/api/v1/public/service-requests', [
            'token' => $table->qr_token, 'kind' => 'bill',
        ])->assertCreated();

        $fresh = Table::withoutTenancy()->find($table->id);
        $this->assertNotSame('bill_requested', $fresh->status->value);
        $this->assertSame('available', $fresh->status->value);

        // Servis talebi kaydı yine de oluşur (personel panoda görür); yalnız
        // masa durumu icat edilmez.
        $this->assertSame(1, ServiceRequest::withoutTenancy()->where('table_id', $table->id)->where('kind', 'bill')->count());

        // Masa rezerve/servis dışıysa senkronizatör onu da EZMEZ (mevcut kural).
        $reserved = $this->makeTable($this->a, ['status' => 'reserved']);
        $this->postJson('/api/v1/public/service-requests', [
            'token' => $reserved->qr_token, 'kind' => 'bill',
        ])->assertCreated();
        $this->assertSame('reserved', Table::withoutTenancy()->find($reserved->id)->status->value);
    }

    public function test_ayni_tur_acik_talep_iki_dakika_icinde_cogaltilmaz(): void
    {
        $table = $this->makeTable($this->a);

        $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'water'])->assertCreated();
        $res = $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'water'])->assertOk();

        $this->assertTrue($res->json('deduplicated'));
        $this->assertSame(1, ServiceRequest::withoutTenancy()->where('table_id', $table->id)->count());

        // Farklı tür ayrı talep açar
        $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'waiter'])->assertCreated();
        $this->assertSame(2, ServiceRequest::withoutTenancy()->where('table_id', $table->id)->count());
    }

    public function test_hiz_siniri_uygulanir(): void
    {
        $table = $this->makeTable($this->a);

        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'waiter']);
        }

        $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'waiter'])
            ->assertStatus(429);
    }

    public function test_ozellik_kapaliysa_403_ve_talep_olusmaz(): void
    {
        $table = $this->makeTable($this->a);

        \App\Modules\Settings\Support\Features::set((int) $this->a['tenant']->id, 'service_calls', false);

        $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'waiter'])
            ->assertStatus(403);

        $this->assertSame(0, ServiceRequest::withoutTenancy()->where('table_id', $table->id)->count());
    }

    public function test_gecersiz_token_ve_tur_reddedilir(): void
    {
        $table = $this->makeTable($this->a);

        $this->postJson('/api/v1/public/service-requests', ['token' => 'AAAAAAAAAAAAAAAAAAAAAAAAAA', 'kind' => 'waiter'])
            ->assertNotFound();

        $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'pizza'])
            ->assertUnprocessable();

        $old = $table->qr_token;
        $table->rotateQrToken();
        $this->postJson('/api/v1/public/service-requests', ['token' => $old, 'kind' => 'waiter'])->assertStatus(410);
    }

    public function test_sarjmatik_onaylaninca_acik_adisyona_gizli_sifir_tl_kalem_eklenir(): void
    {
        \App\Modules\Settings\Support\Features::set((int) $this->a['tenant']->id, 'sarjmatik', true);

        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a);

        // Masada açık adisyon (bir kalemli)
        $this->actingAs($this->a['user']);
        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1]);
        auth('web')->logout();

        // Müşteri QR'dan şarjmatik ister
        $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'sarjmatik'])
            ->assertCreated();
        $srId = ServiceRequest::withoutTenancy()->where('table_id', $table->id)->where('kind', 'sarjmatik')->first()->id;

        // Personel onaylar (İlgilenildi)
        $this->actingAs($this->a['user']);
        $this->postJson("/api/v1/orders/service-requests/{$srId}/done")->assertOk();

        // Gizli 0₺ Şarjmatik ürünü tanımlandı ve QR menüde görünmez (channels=['pos'])
        $hidden = \App\Modules\Catalog\Models\Product::withoutTenancy()
            ->where('tenant_id', $this->a['tenant']->id)->where('sku', 'SARJMATIK')->first();
        $this->assertNotNull($hidden);
        $this->assertSame(0, (int) $hidden->price_minor);
        $this->assertSame(['pos'], $hidden->channels);

        // Adisyona gizli kalem eklendi (servis edildi olarak)
        $item = \App\Modules\Orders\Models\OrderItem::withoutTenancy()
            ->where('order_id', $orderId)->where('product_id', $hidden->id)->first();
        $this->assertNotNull($item);
        $this->assertSame(0, (int) $item->line_total_minor);
        $this->assertSame('served', $item->status);

        // Olay günlüğünde kalem ekleme kaydı var
        $this->assertTrue(
            \App\Modules\Orders\Models\OrderEvent::withoutTenancy()
                ->where('order_id', $orderId)->where('order_item_id', $item->id)->exists()
        );
    }

    public function test_panel_talebi_kapatir_ve_yabanci_kiraci_kapatamaz(): void
    {
        $table = $this->makeTable($this->a);

        $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'waiter'])->assertCreated();
        $srId = ServiceRequest::withoutTenancy()->where('table_id', $table->id)->first()->id;

        // Yabancı kiracı 404
        $b = $this->makeTenantWithUser();
        $this->actingAs($b['user']);
        $this->postJson("/api/v1/orders/service-requests/{$srId}/done")->assertNotFound();

        // Panoda görünür + sahibi kapatır
        $this->actingAs($this->a['user']);
        $boardRequests = $this->getJson('/api/v1/orders/board')->json('service_requests');
        $this->assertCount(1, $boardRequests);
        $this->assertSame('Garson çağırıyor', $boardRequests[0]['kind_label']);

        $this->postJson("/api/v1/orders/service-requests/{$srId}/done")->assertOk();
        $this->assertSame('done', ServiceRequest::withoutTenancy()->find($srId)->status);
        $this->assertSame([], $this->getJson('/api/v1/orders/board')->json('service_requests'));
    }
}
