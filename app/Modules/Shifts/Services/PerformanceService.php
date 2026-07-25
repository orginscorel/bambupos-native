<?php

namespace App\Modules\Shifts\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Orders\Models\Order;
use Carbon\CarbonImmutable;

/**
 * Personel performans metrikleri — DENGELİ set (prompt §7):
 * yalnız satış tutarı DEĞİL; sipariş sayısı, ortalama servis süresi,
 * iptal oranı, indirim/ikram oranı ve masa devir süresi birlikte okunur.
 *
 * Sipariş verisi Orders modülünden YALNIZ OKUNUR (opened_by_id ataması);
 * hiçbir sipariş kaydına yazılmaz.
 */
class PerformanceService
{
    /**
     * @return array<int, array<string, mixed>>
     */
    public function staffMetrics(CarbonImmutable $from, CarbonImmutable $to): array
    {
        $users = User::ofCurrentTenant()
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'name', 'position']);

        $orders = Order::query()
            ->whereNotNull('opened_by_id')
            ->where('created_at', '>=', $from)
            ->where('created_at', '<', $to)
            ->get([
                'id', 'opened_by_id', 'status', 'channel', 'total_minor',
                'discount_minor', 'comp_total_minor',
                'placed_at', 'closed_at', 'cancelled_at', 'created_at',
            ])
            ->groupBy('opened_by_id');

        return $users->map(function (User $user) use ($orders): array {
            /** @var \Illuminate\Support\Collection<int, Order> $own */
            $own = $orders->get($user->id, collect());

            $total = $own->count();
            $cancelled = $own->filter(fn (Order $o) => $o->cancelled_at !== null)->count();
            $closed = $own->filter(fn (Order $o) => $o->closed_at !== null && $o->cancelled_at === null);
            $discounted = $own->filter(fn (Order $o) => (int) $o->discount_minor > 0)->count();
            $comped = $own->filter(fn (Order $o) => (int) $o->comp_total_minor > 0)->count();

            // Servis süresi: açılış → kapanış (dakika). Masa devri: yalnız
            // masa kanalındaki kapanmış adisyonların aynı süresi.
            $serviceMinutes = $closed
                ->map(fn (Order $o) => max(0, (int) ($o->placed_at ?? $o->created_at)->diffInMinutes($o->closed_at)))
                ->filter(fn (int $m) => $m < 24 * 60); // bariz veri hatalarını dışla

            $tableTurnover = $closed
                ->filter(fn (Order $o) => (string) $o->channel === 'table')
                ->map(fn (Order $o) => max(0, (int) ($o->placed_at ?? $o->created_at)->diffInMinutes($o->closed_at)))
                ->filter(fn (int $m) => $m < 24 * 60);

            return [
                'user' => ['id' => $user->id, 'name' => $user->name, 'position' => $user->position],
                'order_count' => $total,
                'sales_minor' => (int) $closed->sum('total_minor'),
                'avg_service_min' => $serviceMinutes->isEmpty() ? null : (int) round($serviceMinutes->avg()),
                'cancelled_count' => $cancelled,
                'cancel_rate' => $total > 0 ? round($cancelled / $total * 100, 1) : 0.0,
                'discount_rate' => $total > 0 ? round($discounted / $total * 100, 1) : 0.0,
                'comp_rate' => $total > 0 ? round($comped / $total * 100, 1) : 0.0,
                'discount_minor' => (int) $own->sum('discount_minor'),
                'comp_minor' => (int) $own->sum('comp_total_minor'),
                'table_turnover_min' => $tableTurnover->isEmpty() ? null : (int) round($tableTurnover->avg()),
            ];
        })->all();
    }
}
