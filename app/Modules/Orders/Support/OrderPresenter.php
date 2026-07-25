<?php

namespace App\Modules\Orders\Support;

use App\Modules\Catalog\Support\Money;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderEvent;
use App\Modules\Orders\Models\OrderItem;

/**
 * Sipariş JSON sunumu (panel API). Tutarlar minor + biçimli ikili gider
 * (ADR-007: biçimleme görüntü katmanının işi ama tek noktadan).
 */
final class OrderPresenter
{
    /** @return array<string, mixed> */
    public static function summary(Order $order): array
    {
        $status = $order->statusEnum();
        $channel = $order->channelEnum();
        $serviceType = $order->serviceTypeEnum();

        $total = (int) $order->total_minor;
        $paid = (int) $order->paid_minor;
        // Ödeme durumu (Board/Detail net göstersin): ödendi / kısmi / bekliyor.
        $paymentState = match (true) {
            $total > 0 && $paid >= $total => 'paid',
            $paid > 0 => 'partial',
            default => 'unpaid',
        };

        return [
            'id' => $order->id,
            'branch_id' => $order->branch_id,
            'table_id' => $order->table_id,
            'table_name' => $order->table?->name,
            'channel' => $channel->value,
            'channel_label' => $channel->label(),
            'channel_icon' => $channel->icon(),
            'channel_variant' => $channel->variant(),
            'service_type' => $serviceType->value,
            'service_type_label' => $serviceType->label(),
            'service_type_icon' => $serviceType->icon(),
            'service_type_variant' => $serviceType->variant(),
            'status' => $status->value,
            'status_label' => $status->label(),
            'status_icon' => $status->icon(),
            'status_variant' => $status->variant(),
            'is_open' => $status->isOpen(),
            'is_split_child' => (bool) $order->is_split_child,
            'debt_receivable_id' => $order->debt_receivable_id,
            'debt_amount_minor' => $order->debt_amount_minor !== null ? (int) $order->debt_amount_minor : null,
            'version' => (int) $order->version,
            'guest_count' => $order->guest_count,
            'note' => $order->note,
            'customer_name' => $order->customer_name,
            'customer_phone' => $order->customer_phone,
            'items_count' => $order->items->filter(fn (OrderItem $i) => $i->isActive())->count(),
            'items_total_minor' => (int) $order->items_total_minor,
            'discount_minor' => (int) $order->discount_minor,
            'discount_percent' => $order->discount_percent !== null ? (float) $order->discount_percent : null,
            'discount_reason' => $order->discount_reason,
            'comp_total_minor' => (int) $order->comp_total_minor,
            'vat_total_minor' => (int) $order->vat_total_minor,
            'service_charge_minor' => (int) $order->service_charge_minor,
            'service_charge_percent' => $order->service_charge_percent !== null ? (float) $order->service_charge_percent : null,
            'rounding_minor' => (int) $order->rounding_minor,
            'total_minor' => (int) $order->total_minor,
            'paid_minor' => $paid,
            'paid_display' => Money::toDecimalString($paid),
            'payment_state' => $paymentState,
            'payment_label' => match ($paymentState) {
                'paid' => 'Ödendi',
                'partial' => 'Kısmi ödendi',
                default => 'Ödeme bekliyor',
            },
            'refunded_minor' => (int) $order->refunded_minor,
            'remaining_minor' => max(0, $total - $paid),
            'total_display' => Money::toDecimalString($total),
            'remaining_display' => Money::toDecimalString(max(0, $total - $paid)),
            'opened_by' => $order->openedBy?->name,
            // KDS ile aynı kural (KdsPresenter): onaya düşene kadar placed_at
            // yok — bu aralıkta created_at'e düş, ekranlar arasında süre
            // hesabı TUTARLI kalsın (aksi halde Siparişler eski açılış anını
            // gösterirken mutfak gerçek "sipariş verildi" anını gösterirdi).
            'placed_at' => ($order->placed_at ?? $order->created_at)?->toIso8601String(),
            'created_at' => $order->created_at?->toIso8601String(),
            'closed_at' => $order->closed_at?->toIso8601String(),
        ];
    }

    /** @return array<string, mixed> */
    public static function detail(Order $order): array
    {
        return array_merge(self::summary($order), [
            'items' => $order->items->map(fn (OrderItem $i) => self::item($i))->values()->all(),
            'events' => $order->events->take(60)->map(fn (OrderEvent $e) => self::event($e))->values()->all(),
        ]);
    }

    /** @return array<string, mixed> */
    public static function item(OrderItem $item): array
    {
        $status = $item->statusEnum();

        return [
            'id' => $item->id,
            'product_id' => $item->product_id,
            'variant_id' => $item->variant_id,
            'status' => $status->value,
            'status_label' => $status->label(),
            'status_icon' => $status->icon(),
            'status_variant' => $status->variant(),
            'is_active' => $status->isActive(),
            'qty' => (int) $item->qty,
            'name' => $item->name,
            'variant_name' => $item->variant_name,
            'unit_price_minor' => (int) $item->unit_price_minor,
            'options_price_minor' => (int) $item->options_price_minor,
            'tax_rate' => (float) $item->tax_rate,
            'station' => $item->station,
            'discount_minor' => (int) $item->discount_minor,
            'is_comp' => (bool) $item->is_comp,
            'comp_reason' => $item->comp_reason,
            'line_total_minor' => (int) $item->line_total_minor,
            'line_total_display' => Money::toDecimalString((int) $item->line_total_minor),
            'note' => $item->note,
            'cancel_reason' => $item->cancel_reason,
            'options' => $item->options->map(fn ($o) => [
                'id' => $o->id,
                'group_name' => $o->group_name,
                'option_name' => $o->option_name,
                'price_minor' => (int) $o->price_minor,
            ])->values()->all(),
        ];
    }

    /** @return array<string, mixed> */
    public static function event(OrderEvent $event): array
    {
        return [
            'id' => $event->id,
            'type' => $event->type,
            'from_status' => $event->from_status,
            'to_status' => $event->to_status,
            'user' => $event->user?->name,
            'payload' => $event->payload,
            'created_at' => $event->created_at?->toIso8601String(),
        ];
    }

    /** Public (QR müşterisi) görünümü: iç kimlikler ve personel sızmaz. */
    /** @return array<string, mixed> */
    public static function publicView(Order $order): array
    {
        $status = $order->statusEnum();

        return [
            'public_token' => $order->public_token,
            'status' => $status->value,
            'status_label' => $status->label(),
            'total_minor' => (int) $order->total_minor,
            'total_display' => Money::toDecimalString((int) $order->total_minor),
            'items' => $order->items->map(fn (OrderItem $i) => [
                'name' => $i->name.($i->variant_name !== null ? ' ('.$i->variant_name.')' : ''),
                'qty' => (int) $i->qty,
                'status' => $i->statusEnum()->value,
                'status_label' => $i->statusEnum()->label(),
                'line_total_minor' => (int) $i->line_total_minor,
                'options' => $i->options->map(fn ($o) => $o->option_name)->values()->all(),
            ])->values()->all(),
            'created_at' => $order->created_at?->toIso8601String(),
        ];
    }
}
