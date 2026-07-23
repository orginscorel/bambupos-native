<?php

namespace App\Modules\Kds\Support;

use App\Modules\Kds\Models\ItemPickup;
use App\Modules\Kds\Services\StationRegistry;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderItem;

/**
 * KDS JSON sunumu — YALNIZ OPERASYON BİLGİSİ (prompt §20).
 *
 * Mutfak/bar/komi ekranı fiyat, tutar, indirim, ciro GÖRMEZ: bu sınıf
 * hiçbir `*_minor` / para alanı üretmez (KdsFinancialLeakTest bunu korur).
 */
final class KdsPresenter
{
    public function __construct(private readonly StationRegistry $stations)
    {
    }

    /**
     * Mutfak sipariş kartı: masa, garson, bekleme, not, alerjen, kanal.
     *
     * @param  \Illuminate\Support\Collection<int|string, ItemPickup>  $pickups  order_item_id => pickup
     * @return array<string, mixed>
     */
    public function orderCard(Order $order, iterable $visibleItems, $pickups): array
    {
        $status = $order->statusEnum();
        $channel = $order->channelEnum();

        return [
            'id' => $order->id,
            'version' => (int) $order->version,
            'table_name' => $order->table?->name,
            'table_number' => $order->table?->number,
            'area_name' => $order->table?->area?->name,
            'channel' => $channel->value,
            'channel_label' => $channel->label(),
            'channel_icon' => $channel->icon(),
            'channel_variant' => $channel->variant(),
            'status' => $status->value,
            'status_label' => $status->label(),
            'status_icon' => $status->icon(),
            'status_variant' => $status->variant(),
            'note' => $order->note,
            'guest_count' => $order->guest_count,
            'waiter' => $order->openedBy?->name,
            'customer_name' => $order->customer_name,
            'placed_at' => ($order->placed_at ?? $order->created_at)?->toIso8601String(),
            'items' => collect($visibleItems)
                ->map(fn (OrderItem $i): array => $this->item($i, $pickups[$i->id] ?? null))
                ->values()->all(),
        ];
    }

    /** @return array<string, mixed> */
    public function item(OrderItem $item, ?ItemPickup $pickup): array
    {
        $status = $item->statusEnum();
        $target = $item->product?->prep_minutes ?? (int) config('kds.default_prep_minutes', 15);

        // ALERJEN uyarısı yalnız kind=allergen; diyet etiketi (vegan vb.)
        // ayrı ve nötr gösterilir — mutfakta ikisi karışmamalı.
        $tags = $item->product?->allergens ?? collect();

        $allergens = $tags->where('kind', 'allergen')
            ->map(fn ($a): array => ['name' => $a->name, 'icon' => $a->icon, 'color' => $a->color])
            ->values()->all();

        $diets = $tags->where('kind', '!=', 'allergen')->pluck('name')->values()->all();

        return [
            'id' => $item->id,
            'order_id' => $item->order_id,
            'qty' => (int) $item->qty,
            'name' => $item->name,
            'variant_name' => $item->variant_name,
            // Kart görseli: yalnız görsel yol — fiyat/ciro alanı DEĞİL (KdsFinancialLeakTest).
            'image_url' => $item->product?->images?->first()?->url,
            'note' => $item->note,
            'status' => $status->value,
            'status_label' => $status->label(),
            'status_icon' => $status->icon(),
            'status_variant' => $status->variant(),
            'station' => $item->station,
            'station_label' => $this->stations->labelFor($item->station) ?? 'İstasyonsuz',
            'target_minutes' => max(1, (int) $target),
            'created_at' => $item->created_at?->toIso8601String(),
            // Hazır'a geçiş anı yaklaşık son güncelleme zamanıdır (komi önceliği).
            'updated_at' => $item->updated_at?->toIso8601String(),
            'allergens' => $allergens,
            'diets' => $diets,
            'options' => $item->options
                ->map(fn ($o): string => $o->option_name)
                ->values()->all(),
            'picked_up_at' => $pickup?->created_at?->toIso8601String(),
            'picked_up_by' => $pickup?->user?->name,
        ];
    }

    /**
     * Komi satırı: hazır kalem + masa/salon + hazırlayan istasyon bağlamı.
     *
     * @return array<string, mixed>
     */
    public function runnerRow(OrderItem $item, Order $order, ?ItemPickup $pickup): array
    {
        return $this->item($item, $pickup) + [
            'order_version' => (int) $order->version,
            'table_name' => $order->table?->name,
            'table_number' => $order->table?->number,
            'area_name' => $order->table?->area?->name,
            'channel' => $order->channelEnum()->value,
            'channel_label' => $order->channelEnum()->label(),
            'channel_icon' => $order->channelEnum()->icon(),
            'channel_variant' => $order->channelEnum()->variant(),
            'order_note' => $order->note,
            'waiter' => $order->openedBy?->name,
        ];
    }
}
