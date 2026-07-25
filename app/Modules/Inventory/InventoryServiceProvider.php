<?php

namespace App\Modules\Inventory;

use App\Modules\Inventory\Models\MovementRequest;
use App\Modules\Inventory\Models\PurchaseOrder;
use App\Modules\Inventory\Models\Recipe;
use App\Modules\Inventory\Models\StockCount;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\StockMovement;
use App\Modules\Inventory\Models\Supplier;
use App\Modules\Inventory\Models\Warehouse;
use App\Modules\Inventory\Policies\InventoryPolicy;
use App\Modules\Inventory\Services\ConsumptionService;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderItem;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

/**
 * Inventory modülü (Faz 6).
 *
 * SİPARİŞ ↔ STOK KÖPRÜSÜ: Orders modülü Laravel event'i YAYINLAMAZ (tüm
 * mutasyonlar OrderService + order_events DB günlüğü). Orders koduna
 * dokunmadan bağlanmanın mevcut kancası ELOQUENT MODEL OLAYLARIDIR:
 * OrderService/KdsService her durum değişimini `$item->save()` /
 * `$locked->save()` ile yazar → updated olayı burada dinlenir.
 *
 * STOK DÜŞÜMÜ — TEK BİRİNCİL TETİK = TESLİM/SERVED:
 *  - OrderItem `served` oldu → BİRİNCİL tetik: kalemin reçete tüketimi düşer
 *    (yemek mutfaktan çıktı; ödeme beklemez; ikram da served olur → ikram
 *    tüketimi türü). Her kalem stoktan yalnız burada, tutarlı anda düşer.
 *  - Order `paid` oldu → GÜVENLİK AĞI: yalnız served aşamasından geçmeden
 *    kapanan (kiosk gibi) veya served düşümü başarısız kalemler — defterde
 *    tüketim satırı OLMAYAN aktif kalemler — düşer. Served ile zaten düşmüş
 *    kalem burada TEKRAR düşmez.
 *
 * İdempotens ConsumptionService'te tek kaynakta (hasConsumption: kalem başına
 * defter ref kontrolü) — paid süzgeci + consumeOrderItem içi, çift-tetikte de
 * TAM BİR KEZ; stok hatası sipariş akışını ASLA düşürmez (safe* sarmalayıcılar).
 */
class InventoryServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        // Policy kayıtları (ADR-004 katman 2).
        foreach ([
            Warehouse::class, StockItem::class, StockMovement::class,
            MovementRequest::class, Recipe::class, StockCount::class,
            Supplier::class, PurchaseOrder::class,
        ] as $model) {
            Gate::policy($model, InventoryPolicy::class);
        }

        // Sipariş köprüsü (§17 madde 5).
        OrderItem::updated(function (OrderItem $item): void {
            if (! $item->wasChanged('status')) {
                return;
            }

            $status = (string) $item->status;

            if ($status === OrderItemStatus::Served->value) {
                app(ConsumptionService::class)->safeConsumeOrderItem($item);
            } elseif ($status === OrderItemStatus::Cancelled->value) {
                // İptal → iade (§17 madde 4): daha önce düşülmüş tüketim,
                // kalemin cancel_reason'ıyla stoğa geri eklenir (idempotent).
                app(ConsumptionService::class)->safeRevertOrderItem($item);
            }
        });

        Order::updated(function (Order $order): void {
            if ($order->wasChanged('status') && (string) $order->status === OrderStatus::Paid->value) {
                app(ConsumptionService::class)->safeConsumeOrder($order);
            }
        });
    }
}
