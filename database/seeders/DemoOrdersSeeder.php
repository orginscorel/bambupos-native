<?php

namespace Database\Seeders;

use App\Modules\Catalog\Models\Product;
use App\Modules\Identity\Models\User;
use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Database\Seeder;

/**
 * §12 demo — MUTFAK + BARİSTA ekranlarının İKİSİ de dolu görünsün diye
 * karışık bir açık adisyon: hem yemek (Mutfak) hem içecek (Barista) kalemi.
 *
 * CatalogSeeder'dan SONRA çalışır (ürünler + istasyon atamaları hazır olmalı).
 * Idempotent ve CANLI VERİYE SAYGILI: şubede zaten açık bir adisyon varsa
 * hiç dokunmaz (yeni sipariş üretmez) — böylece elle oluşturulmuş demo
 * siparişleri ezmez, yalnız hiç açık sipariş yoksa örnek üretir.
 */
class DemoOrdersSeeder extends Seeder
{
    public function run(): void
    {
        $context = app(TenantContext::class);

        $tenant = $context->runWithoutTenancy(
            fn () => Tenant::query()->where('slug', 'demo')->first()
        );

        if ($tenant === null) {
            return;
        }

        // Tenant bağlamı AÇIK: OrderService içeride tenant-scope'a güvenir
        // (Order tenant_id'yi BelongsToTenant bağlamdan doldurur).
        $context->setTenant($tenant);

        try {
            $branch = Branch::query()->where('tenant_id', $tenant->id)->orderBy('id')->first();

            if ($branch === null) {
                return;
            }

            // Zaten açık adisyon varsa dokunma (idempotent + canlıya saygı).
            $hasOpen = Order::query()
                ->where('branch_id', $branch->id)
                ->whereNotIn('status', OrderStatus::closedValues())
                ->exists();

            if ($hasOpen) {
                return;
            }

            $table = Table::query()->where('is_active', true)->orderBy('id')->first();

            if ($table === null) {
                $table = new Table([
                    'name' => 'Masa 1',
                    'number' => 1,
                    'capacity' => 4,
                    'is_active' => true,
                ]);
                $table->tenant_id = $tenant->id;
                $table->branch_id = $branch->id;
                $table->save();
            }

            $food = Product::query()->where('station', 'kitchen')
                ->where('is_active', true)->where('is_available', true)->orderBy('id')->first();
            $drink = Product::query()->where('station', 'barista')
                ->where('is_active', true)->where('is_available', true)->orderBy('id')->first();

            if ($food === null || $drink === null) {
                return; // istasyon atamaları henüz yoksa örnek üretme
            }

            $owner = User::query()->where('tenant_id', $tenant->id)->orderBy('id')->first();

            /** @var OrderService $orders */
            $orders = app(OrderService::class);

            $order = $orders->open([
                'branch_id' => (int) $branch->id,
                'channel' => OrderChannel::Table->value,
                'table_id' => (int) $table->id,
                'guest_count' => 2,
            ], $owner);

            $orders->addItem($order, ['product_id' => $food->id, 'qty' => 1], $owner);
            $orders->addItem($order, ['product_id' => $drink->id, 'qty' => 2], $owner);
        } finally {
            $context->forget();
        }
    }
}
