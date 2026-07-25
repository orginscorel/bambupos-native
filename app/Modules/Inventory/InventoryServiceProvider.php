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
 *  - OrderItem `served` oldu → kalemin reçete tüketimi düşer
 *    (yemek mutfaktan çıktı; ödeme beklemez; ikram da served olur → ikram
 *    tüketimi türü),
 *  - Order `paid` oldu → henüz düşülmemiş aktif kalemler düşer (servis
 *    işaretlemeden kapatılan adisyonların güvenlik ağı).
 *
 * İdempotens ConsumptionService'te (kalem başına defter ref kontrolü);
 * stok hatası sipariş akışını ASLA düşürmez (safe* sarmalayıcılar).
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
            if ($item->wasChanged('status') && (string) $item->status === OrderItemStatus::Served->value) {
                app(ConsumptionService::class)->safeConsumeOrderItem($item);
            }
        });

        Order::updated(function (Order $order): void {
            if ($order->wasChanged('status') && (string) $order->status === OrderStatus::Paid->value) {
                app(ConsumptionService::class)->safeConsumeOrder($order);
            }
        });
    }
}
