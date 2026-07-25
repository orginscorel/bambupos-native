<?php

namespace Tests\Feature\Kiosk;

use App\Modules\Kiosk\Models\KioskDevice;
use App\Modules\Orders\Models\Order;
use App\Modules\Payments\Models\Payment;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Kiosk sipariş + mock POS ödemesi:
 *  - kanal = kiosk, kiosk fiyatı uygulanır, kiracı/şube token'dan gelir;
 *  - onay → sipariş kesinleşir (fiş), red → iptal + dürüst 402,
 *    belirsiz → Pending + sorguyla netleşir (sahte başarı YOK — §22);
 *  - kasada-ödeme modu tahsilatsız Placed bırakır;
 *  - kiracı izolasyonu: yabancı masa/ürün 422; idempotency çoğaltmaz.
 */
class KioskOrderTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    private array $b;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->b = $this->makeTenantWithUser();
    }

    private function makeDevice(array $ctx, array $attrs = []): KioskDevice
    {
        return $this->asTenant($ctx['tenant'], function () use ($ctx, $attrs): KioskDevice {
            $device = new KioskDevice(array_merge([
                'name' => 'Test Kiosk',
                'status' => KioskDevice::STATUS_ACTIVE,
                'payment_mode' => KioskDevice::MODE_KIOSK_POS,
            ], $attrs));
            $device->branch_id = (int) $ctx['branch']->id;
            $device->save();

            return $device;
        });
    }

    public function test_onayli_odeme_siparisi_kesinlestirir_kanal_kiosk(): void
    {
        $device = $this->makeDevice($this->a);
        // Mock senaryosu: son iki hane ..00 → APPROVED
        $product = $this->makeProduct($this->a, [
            'name' => 'Kiosk Burger', 'price_minor' => 15000, 'kiosk_price_minor' => 12500,
        ]);

        $res = $this->postJson('/kiosk/api/orders', [
            'token' => $device->token,
            'order_type' => 'takeaway',
            'customer_name' => 'Kiosk Müşterisi',
            'items' => [['product_id' => $product->id, 'qty' => 2]],
        ])->assertCreated();

        $this->assertSame('paid', $res->json('result'));
        $this->assertTrue($res->json('receipt.paid'));
        $this->assertSame(2 * 12500, $res->json('receipt.total_minor')); // KİOSK fiyatı
        $this->assertNotEmpty($res->json('receipt.payment.reference'));
        $this->assertNotEmpty($res->json('receipt.payment.auth_code'));

        $order = Order::withoutTenancy()->find($res->json('receipt.order_no'));
        $this->assertSame('kiosk', $order->channel);                       // kanal işareti
        $this->assertSame((int) $this->a['tenant']->id, (int) $order->tenant_id);
        $this->assertSame((int) $this->a['branch']->id, (int) $order->branch_id);
        $this->assertSame('paid', $order->status);
        $this->assertSame(2 * 12500, (int) $order->paid_minor);

        // Para değişmezi: başarılı ödeme satırı adisyonla eşleşir (mock sağlayıcı)
        $payment = Payment::withoutTenancy()->where('order_id', $order->id)->first();
        $this->assertSame('succeeded', $payment->status);
        $this->assertSame('mock', $payment->provider);
        $this->assertSame(2 * 12500, (int) $payment->amount_minor);

        // Yanıt çerez bırakmaz (§18)
        $res->assertHeaderMissing('Set-Cookie');
    }

    public function test_kart_reddi_dusrust_hata_ve_siparis_iptali(): void
    {
        $device = $this->makeDevice($this->a);
        // ..99 → DECLINED (mock)
        $product = $this->makeProduct($this->a, ['price_minor' => 10099, 'kiosk_price_minor' => null]);

        $res = $this->postJson('/kiosk/api/orders', [
            'token' => $device->token,
            'order_type' => 'takeaway',
            'items' => [['product_id' => $product->id, 'qty' => 1]],
        ])->assertStatus(402);

        $this->assertSame('payment_failed', $res->json('result'));
        $this->assertStringContainsString('Ödeme alınamadı', $res->json('message'));

        // Sipariş mutfağa gitmez: iptal edildi, tahsilat yok
        $order = Order::withoutTenancy()->where('channel', 'kiosk')->first();
        $this->assertSame('cancelled', $order->status);
        $this->assertSame(0, (int) $order->paid_minor);
    }

    public function test_belirsiz_odeme_sorguyla_netlesir_sahte_basari_yok(): void
    {
        $device = $this->makeDevice($this->a);
        // ..98 → terminal TIMEOUT (durum bilinmiyor); sorgu APPROVED döner
        $product = $this->makeProduct($this->a, ['price_minor' => 10098]);

        $res = $this->postJson('/kiosk/api/orders', [
            'token' => $device->token,
            'order_type' => 'takeaway',
            'items' => [['product_id' => $product->id, 'qty' => 1]],
        ])->assertStatus(202);

        $this->assertSame('payment_pending', $res->json('result'));
        $reference = $res->json('reference');
        $this->assertNotEmpty($reference);

        // Belirsizlik sırasında sipariş ödenmiş SAYILMAZ
        $order = Order::withoutTenancy()->where('channel', 'kiosk')->first();
        $this->assertSame(0, (int) $order->paid_minor);

        // Sorgu ucu sağlayıcıdan doğrular → ödeme kesinleşir
        $q = $this->postJson('/kiosk/api/payments/query', [
            'token' => $device->token, 'reference' => $reference,
        ])->assertCreated();

        $this->assertSame('paid', $q->json('result'));
        $this->assertSame('paid', Order::withoutTenancy()->find($order->id)->status);
    }

    public function test_kasada_odeme_modu_tahsilatsiz_placed(): void
    {
        $device = $this->makeDevice($this->a, ['payment_mode' => KioskDevice::MODE_COUNTER]);
        $table = $this->makeTable($this->a, ['name' => 'Bahçe', 'number' => 7]);
        $product = $this->makeProduct($this->a, ['price_minor' => 9000]);

        $res = $this->postJson('/kiosk/api/orders', [
            'token' => $device->token,
            'order_type' => 'dine_in',
            'table_id' => $table->id,
            'items' => [['product_id' => $product->id, 'qty' => 1]],
        ])->assertCreated();

        $this->assertSame('placed_pay_at_counter', $res->json('result'));
        $this->assertTrue($res->json('receipt.pay_at_counter'));

        $order = Order::withoutTenancy()->where('channel', 'kiosk')->first();
        $this->assertSame('placed', $order->status);
        $this->assertSame(0, (int) $order->paid_minor);
        // #1: "Masada" siparişi seçili masaya BAĞLANIR (masaya-bağla mekanizması) —
        // servis tipi yapısal kolonda, masa artık nota GÖMÜLMEZ (#3).
        $this->assertSame((int) $table->id, (int) $order->table_id);
        $this->assertSame('dine_in', $order->service_type);
        $this->assertNull($order->note);
        $this->assertSame(0, Payment::withoutTenancy()->count());
    }

    public function test_masada_kiosk_siparisi_masanin_acik_adisyonuna_eklenir(): void
    {
        // #1: Masada TEK açık adisyon — masada zaten açık adisyon varsa
        // kiosk "Masada" siparişi YENİ adisyon açmaz, ONA kalem ekler.
        $device = $this->makeDevice($this->a, ['payment_mode' => KioskDevice::MODE_COUNTER]);
        $table = $this->makeTable($this->a, ['name' => 'Salon 3', 'number' => 3]);
        $product = $this->makeProduct($this->a, ['price_minor' => 8000]);

        // Garson masada adisyon açar (masa siparişi).
        $this->actingAs($this->a['user']);
        $open = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id,
            'channel' => 'table',
            'table_id' => $table->id,
        ])->assertCreated();
        $existingId = (int) $open->json('order.id');

        // Kiosk "Masada" siparişi AYNI masaya gelir → var olan adisyona eklenir.
        $res = $this->postJson('/kiosk/api/orders', [
            'token' => $device->token,
            'order_type' => 'dine_in',
            'table_id' => $table->id,
            'items' => [['product_id' => $product->id, 'qty' => 2]],
        ])->assertCreated();

        $this->assertSame($existingId, (int) $res->json('receipt.order_no'));

        // Masada YALNIZ TEK açık adisyon var (yenisi açılmadı).
        $openCount = Order::withoutTenancy()
            ->where('table_id', $table->id)
            ->whereNotIn('status', ['paid', 'cancelled', 'refunded', 'debt_transferred'])
            ->count();
        $this->assertSame(1, $openCount);

        $order = Order::withoutTenancy()->find($existingId);
        $this->assertSame(1, (int) $order->items()->count()); // tek kalem satırı (qty=2)
        $this->assertSame(2, (int) $order->items()->first()->qty);
    }

    public function test_masada_kiosk_pos_modunda_bile_tahsil_etmez_kasada_oder(): void
    {
        // #2: Cihaz kiosk_pos olsa da "Masada" siparişi kioskta ÖDENMEZ —
        // hesap masada/kasada tüm adisyon üzerinden kapanır (ciro şişmez).
        $device = $this->makeDevice($this->a); // MODE_KIOSK_POS (varsayılan)
        $table = $this->makeTable($this->a, ['name' => 'Teras', 'number' => 9]);
        $product = $this->makeProduct($this->a, ['price_minor' => 12000]);

        $res = $this->postJson('/kiosk/api/orders', [
            'token' => $device->token,
            'order_type' => 'dine_in',
            'table_id' => $table->id,
            'items' => [['product_id' => $product->id, 'qty' => 1]],
        ])->assertCreated();

        $this->assertSame('placed_pay_at_counter', $res->json('result'));
        $this->assertTrue($res->json('receipt.pay_at_counter'));

        $order = Order::withoutTenancy()->where('channel', 'kiosk')->first();
        $this->assertSame('placed', $order->status);
        $this->assertSame(0, (int) $order->paid_minor);
        $this->assertSame((int) $table->id, (int) $order->table_id);
        $this->assertSame(0, Payment::withoutTenancy()->count());
    }

    public function test_odenmis_kiosk_siparisi_panoda_ve_mutfakta_gorunur_ve_servis_tipi_yapisal(): void
    {
        $device = $this->makeDevice($this->a);
        $product = $this->makeProduct($this->a, ['price_minor' => 12500, 'kiosk_price_minor' => 12500]);

        $res = $this->postJson('/kiosk/api/orders', [
            'token' => $device->token,
            'order_type' => 'takeaway',
            'items' => [['product_id' => $product->id, 'qty' => 1]],
        ])->assertCreated();

        $this->assertSame('paid', $res->json('result'));
        $orderId = (int) $res->json('receipt.order_no');

        // Servis tipi YAPISAL kolonda (nota gömülü değil sadece).
        $order = Order::withoutTenancy()->find($orderId);
        $this->assertSame('takeaway', $order->service_type);
        $this->assertSame('paid', $order->status);

        // Ön-ödemeli ama teslim edilmemiş → Siparişler panosunda görünür.
        $this->actingAs($this->a['user']);
        $board = $this->getJson('/api/v1/orders/board?branch_id='.$this->a['branch']->id)->assertOk();
        $channel = collect($board->json('channel_orders'))->firstWhere('id', $orderId);
        $this->assertNotNull($channel, 'Ödenmiş kiosk siparişi panoda görünmüyor');
        $this->assertSame('paid', $channel['payment_state']);
        $this->assertSame('takeaway', $channel['service_type']);

        // Mutfağa da düşer (kalem hâlâ hazırlanacak).
        $queue = $this->getJson('/api/v1/kds/queue?branch_id='.$this->a['branch']->id)->assertOk();
        $ids = collect($queue->json('orders'))->pluck('id');
        $this->assertTrue($ids->contains($orderId), 'Ödenmiş kiosk siparişi mutfak kuyruğunda yok');

        // Tüm kalemler servis edilince panodan/mutfaktan düşer (teslim edildi).
        $itemId = (int) $order->items()->first()->id;
        $this->postJson("/api/v1/kds/items/{$itemId}/status", ['to' => 'served'])->assertOk();

        $board2 = $this->getJson('/api/v1/orders/board?branch_id='.$this->a['branch']->id)->assertOk();
        $this->assertNull(collect($board2->json('channel_orders'))->firstWhere('id', $orderId));
    }

    public function test_yabanci_masa_ve_yabanci_urun_reddedilir(): void
    {
        $device = $this->makeDevice($this->a);
        $foreignTable = $this->makeTable($this->b);
        $foreignProduct = $this->makeProduct($this->b);
        $ownProduct = $this->makeProduct($this->a, ['price_minor' => 5000]);

        // Yabancı masa: cihazın şubesinde yok → 422
        $this->postJson('/kiosk/api/orders', [
            'token' => $device->token,
            'order_type' => 'dine_in',
            'table_id' => $foreignTable->id,
            'items' => [['product_id' => $ownProduct->id, 'qty' => 1]],
        ])->assertUnprocessable();

        // Yabancı ürün: kiracı süzgecinden geçemez → 422
        $this->postJson('/kiosk/api/orders', [
            'token' => $device->token,
            'order_type' => 'takeaway',
            'items' => [['product_id' => $foreignProduct->id, 'qty' => 1]],
        ])->assertUnprocessable();

        $this->assertSame(0, Order::withoutTenancy()->where('status', '!=', 'cancelled')->count());
    }

    public function test_gecersiz_ve_rotasyonlu_token_reddedilir(): void
    {
        $device = $this->makeDevice($this->a);
        $product = $this->makeProduct($this->a);
        $payload = ['order_type' => 'takeaway', 'items' => [['product_id' => $product->id, 'qty' => 1]]];

        $this->postJson('/kiosk/api/orders', $payload + ['token' => 'AAAAAAAAAAAAAAAAAAAAAAAAAA'])->assertNotFound();

        $old = $device->token;
        $this->asTenant($this->a['tenant'], fn () => $device->rotateToken());

        $this->postJson('/kiosk/api/orders', $payload + ['token' => $old])->assertGone();
        $this->postJson('/kiosk/api/orders', $payload + ['token' => $device->token])->assertCreated();
    }

    public function test_idempotency_cift_dokunma_siparis_ve_tahsilat_cogaltmaz(): void
    {
        $device = $this->makeDevice($this->a);
        $product = $this->makeProduct($this->a, ['price_minor' => 10000]);

        $payload = [
            'token' => $device->token,
            'order_type' => 'takeaway',
            'items' => [['product_id' => $product->id, 'qty' => 1]],
        ];
        $headers = ['Idempotency-Key' => 'kiosk-test-1'];

        $first = $this->postJson('/kiosk/api/orders', $payload, $headers)->assertCreated();
        $second = $this->postJson('/kiosk/api/orders', $payload, $headers)->assertOk();

        $this->assertTrue($second->json('replayed'));
        $this->assertSame($first->json('receipt.order_no'), $second->json('receipt.order_no'));
        $this->assertSame(1, Order::withoutTenancy()->count());
        $this->assertSame(1, Payment::withoutTenancy()->where('kind', 'payment')->count());
    }
}
