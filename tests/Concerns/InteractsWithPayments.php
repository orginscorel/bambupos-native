<?php

namespace Tests\Concerns;

use App\Modules\Orders\Models\Order;
use App\Modules\Payments\Enums\PaymentStatus;
use App\Modules\Payments\Models\CashRegister;
use App\Modules\Payments\Models\CashSession;
use App\Modules\Payments\Models\Payment;
use App\Modules\Payments\Services\CashSessionService;

/**
 * Ödeme testleri yardımcıları (InteractsWithTenancy + InteractsWithOrders
 * ile birlikte kullanılır).
 */
trait InteractsWithPayments
{
    /**
     * Masa + ürün + adisyon kurar; ürün fiyatı = $priceMinor, adet = $qty.
     *
     * @param  array{tenant: mixed, branch: mixed}  $ctx
     */
    protected function makeOrderWithTotal(array $ctx, int $priceMinor, int $qty = 1): int
    {
        $table = $this->makeTable($ctx);
        $product = $this->makeProduct($ctx, ['price_minor' => $priceMinor]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $ctx['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertCreated()->json('order.id');

        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => $qty])->assertCreated();

        return (int) $orderId;
    }

    /** @param array{tenant: mixed, branch: mixed} $ctx */
    protected function makeRegister(array $ctx, string $name = 'Ana Kasa'): CashRegister
    {
        return $this->asTenant($ctx['tenant'], function () use ($ctx, $name): CashRegister {
            $register = new CashRegister(['name' => $name, 'is_active' => true]);
            $register->branch_id = $ctx['branch']->id;
            $register->save();

            return $register;
        });
    }

    /** @param array{tenant: mixed, branch: mixed, user: mixed} $ctx */
    protected function openSessionFor(array $ctx, CashRegister $register, int $openingMinor = 10000): CashSession
    {
        return app(CashSessionService::class)->open($register, $openingMinor, $ctx['user']);
    }

    /**
     * PARA DEĞİŞMEZİ #1 doğrulaması: payments tablosundan türetilen
     * toplamlar orders.paid_minor / refunded_minor'a EŞİT olmalı.
     */
    protected function assertMoneyInvariant(int $orderId): void
    {
        $order = Order::withoutTenancy()->findOrFail($orderId);

        $collected = (int) Payment::withoutTenancy()
            ->where('order_id', $orderId)
            ->where('kind', 'payment')
            ->whereIn('status', [
                PaymentStatus::Succeeded->value,
                PaymentStatus::PartiallyRefunded->value,
                PaymentStatus::Refunded->value,
            ])
            ->sum('amount_minor');

        $refunded = (int) Payment::withoutTenancy()
            ->where('order_id', $orderId)
            ->where('kind', 'refund')
            ->where('status', PaymentStatus::Succeeded->value)
            ->sum('amount_minor');

        $this->assertSame($collected, (int) $order->paid_minor,
            "DEĞİŞMEZ İHLALİ: SUM(payments başarılı)={$collected} != orders.paid_minor={$order->paid_minor}");
        $this->assertSame($refunded, (int) $order->refunded_minor,
            "DEĞİŞMEZ İHLALİ: SUM(iade)={$refunded} != orders.refunded_minor={$order->refunded_minor}");
    }

    /** İmzalı mock callback isteği gönderir. */
    protected function postSignedCallback(array $payload, ?int $timestamp = null, ?string $signature = null): \Illuminate\Testing\TestResponse
    {
        $body = json_encode($payload);
        $ts = (string) ($timestamp ?? time());

        return $this->call(
            'POST',
            '/api/v1/public/payments/callback/mock',
            [],
            [],
            [],
            [
                'HTTP_X-POS-TIMESTAMP' => $ts,
                'HTTP_X-POS-SIGNATURE' => $signature ?? \App\Modules\Payments\Providers\MockPosProvider::sign($ts, $body),
                'CONTENT_TYPE' => 'application/json',
                'HTTP_ACCEPT' => 'application/json',
            ],
            $body,
        );
    }
}
