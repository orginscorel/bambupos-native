<?php

declare(strict_types=1);

namespace App\Modules\Commission\Services;

use App\Modules\Commission\Models\CommissionScheme;
use App\Modules\Identity\Models\User;
use App\Modules\Orders\Models\Order;
use App\Modules\Shifts\Models\TimeEntry;
use App\Modules\Shifts\Models\TimeEntryBreak;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * PRİM / KOMİSYON hesaplama servisi.
 *
 * Sipariş verisi Orders modülünden YALNIZ OKUNUR (opened_by_id ataması) —
 * PerformanceService mantığıyla tutarlı: satış = kişinin dönemde KAPANMIŞ,
 * iptal edilmemiş siparişlerinin total_minor toplamı. Çalışma süresi
 * (worked_min) Shifts time_entries'ten PortalPerformanceService ile tutarlı
 * (net = brüt − tamamlanmış molalar) türetilir.
 *
 * Tüm sorgular tenant-scope'ludur (BelongsToTenant / ofCurrentTenant). Prim
 * tutarları tam sayı *_minor aritmetiğiyle (intdiv) hesaplanır — yuvarlama
 * sapması yok.
 */
class CommissionService
{
    /**
     * Bir kullanıcının [$from, $to) dönemindeki prim özeti.
     *
     * @return array<string, mixed>
     */
    public function forUser(User $user, Carbon $from, Carbon $to): array
    {
        $sales = $this->salesFor([$user->id], $from, $to)->get($user->id, [
            'sales_minor' => 0,
            'order_count' => 0,
        ]);
        $workedMin = $this->workedMinutesFor([$user->id], $from, $to)->get($user->id, 0);
        $scheme = $this->matchScheme($this->activeSchemes(), $user->position);

        return $this->build($user, $sales, $workedMin, $scheme);
    }

    /**
     * Yönetici raporu: aktif personelin dönem prim özetleri + toplamlar.
     *
     * Verimli: siparişler, çalışma süreleri ve şemalar TOPLU çekilir
     * (kullanıcı başına sorgu YOK), sonra bellekte eşleştirilir.
     *
     * @return array{rows: array<int, array<string, mixed>>, totals: array{sales_minor: int, commission_minor: int}}
     */
    public function report(Carbon $from, Carbon $to, ?int $branchId = null): array
    {
        /** @var Collection<int, User> $users */
        $users = User::ofCurrentTenant()
            ->where('is_active', true)
            ->where('is_terminal', false)
            ->when($branchId !== null, fn ($q) => $q->where('branch_id', $branchId))
            ->orderBy('first_name')
            ->get(['id', 'first_name', 'last_name', 'name', 'position']);

        $ids = $users->pluck('id')->all();

        $salesById = $this->salesFor($ids, $from, $to);
        $workedById = $this->workedMinutesFor($ids, $from, $to);
        $schemes = $this->activeSchemes();

        $rows = [];
        $totalSales = 0;
        $totalCommission = 0;

        foreach ($users as $user) {
            $sales = $salesById->get($user->id, ['sales_minor' => 0, 'order_count' => 0]);
            $workedMin = $workedById->get($user->id, 0);
            $scheme = $this->matchScheme($schemes, $user->position);

            $summary = $this->build($user, $sales, $workedMin, $scheme);

            // Rapor satırı: şema detayı hariç düz özet.
            $rows[] = [
                'user' => $summary['user'],
                'sales_minor' => $summary['sales_minor'],
                'order_count' => $summary['order_count'],
                'worked_min' => $summary['worked_min'],
                'commission_minor' => $summary['commission_minor'],
                'target_minor' => $summary['target_minor'],
                'target_met' => $summary['target_met'],
            ];

            $totalSales += $summary['sales_minor'];
            $totalCommission += $summary['commission_minor'];
        }

        return [
            'rows' => $rows,
            'totals' => [
                'sales_minor' => $totalSales,
                'commission_minor' => $totalCommission,
            ],
        ];
    }

    /**
     * Tek kullanıcının özetini ham girdilerden kurar (forUser + report ortak).
     *
     * @param  array{sales_minor: int, order_count: int}  $sales
     * @return array<string, mixed>
     */
    private function build(User $user, array $sales, int $workedMin, ?CommissionScheme $scheme): array
    {
        $salesMinor = (int) $sales['sales_minor'];
        $orderCount = (int) $sales['order_count'];

        $commissionMinor = $this->commissionMinor($scheme, $salesMinor, $orderCount);
        $targetMinor = $scheme !== null ? (int) $scheme->target_minor : 0;
        $targetMet = $targetMinor > 0 && $salesMinor >= $targetMinor;

        return [
            'user' => [
                'id' => (int) $user->getKey(),
                'name' => $user->name,
                'position' => $user->position,
            ],
            'sales_minor' => $salesMinor,
            'order_count' => $orderCount,
            'worked_min' => $workedMin,
            'scheme' => $scheme !== null ? $this->schemeDto($scheme) : null,
            'commission_minor' => $commissionMinor,
            'target_minor' => $targetMinor,
            'target_met' => $targetMet,
        ];
    }

    /**
     * Prim tutarı (minor) — şema tabanına göre.
     *   percent_sales : intdiv(sales × rate_bps, 10000)
     *   per_order     : order_count × per_order_minor
     *   target_bonus  : sales ≥ target_minor ? bonus_minor : 0
     */
    private function commissionMinor(?CommissionScheme $scheme, int $salesMinor, int $orderCount): int
    {
        if ($scheme === null) {
            return 0;
        }

        return match ($scheme->basis) {
            'percent_sales' => intdiv($salesMinor * (int) $scheme->rate_bps, 10000),
            'per_order' => $orderCount * (int) $scheme->per_order_minor,
            'target_bonus' => $salesMinor >= (int) $scheme->target_minor ? (int) $scheme->bonus_minor : 0,
            default => 0,
        };
    }

    /**
     * Kullanıcının siparişlerinden satış toplamı + adedi (opened_by_id bazlı).
     * Yalnız KAPANMIŞ (closed_at aralıkta) ve İPTAL EDİLMEMİŞ siparişler sayılır.
     *
     * @param  array<int, int>  $userIds
     * @return Collection<int, array{sales_minor: int, order_count: int}>  anahtar: user_id
     */
    private function salesFor(array $userIds, Carbon $from, Carbon $to): Collection
    {
        if ($userIds === []) {
            return collect();
        }

        return Order::query()
            ->whereIn('opened_by_id', $userIds)
            ->whereNull('cancelled_at')
            ->whereNotNull('closed_at')
            ->where('closed_at', '>=', $from)
            ->where('closed_at', '<', $to)
            ->get(['opened_by_id', 'total_minor'])
            ->groupBy('opened_by_id')
            ->map(fn (Collection $rows): array => [
                'sales_minor' => (int) $rows->sum('total_minor'),
                'order_count' => $rows->count(),
            ]);
    }

    /**
     * Kullanıcıların dönemdeki NET çalışma dakikası (time_entries).
     * PortalPerformanceService ile tutarlı: kapalı kayıtta finalize edilmiş
     * worked_min, açık kayıtta (şimdi − giriş) − tamamlanmış molalar.
     *
     * @param  array<int, int>  $userIds
     * @return Collection<int, int>  anahtar: user_id, değer: net dakika
     */
    private function workedMinutesFor(array $userIds, Carbon $from, Carbon $to): Collection
    {
        if ($userIds === []) {
            return collect();
        }

        $now = Carbon::now(config('app.timezone'));

        /** @var Collection<int, TimeEntry> $entries */
        $entries = TimeEntry::query()
            ->whereIn('user_id', $userIds)
            ->where('clock_in_at', '>=', $from)
            ->where('clock_in_at', '<', $to)
            ->with('breaks')
            ->get();

        return $entries
            ->groupBy('user_id')
            ->map(fn (Collection $rows): int => (int) $rows->sum(
                fn (TimeEntry $entry): int => $this->liveWorkedMinutes($entry, $now)
            ));
    }

    /**
     * Canlı çalışılan dakika: kapalı kayıtta finalize worked_min, açık kayıtta
     * (şimdi/çıkış − giriş) − tamamlanmış tüm molalar.
     */
    private function liveWorkedMinutes(TimeEntry $entry, Carbon $now): int
    {
        if (! $entry->isOpen() && $entry->worked_min !== null) {
            return (int) $entry->worked_min;
        }

        $end = $entry->clock_out_at ?? $now;
        $gross = max(0, (int) $entry->clock_in_at->diffInMinutes($end));

        $allBreaks = (int) $entry->breaks
            ->filter(fn (TimeEntryBreak $b) => $b->ended_at !== null)
            ->sum(fn (TimeEntryBreak $b) => $b->minutes());

        return max(0, $gross - $allBreaks);
    }

    /**
     * Kiracının aktif prim şemaları. Pozisyona özel şemalar önce gelsin diye
     * position-dolu olanlar başa alınır (en spesifik eşleşme kazansın).
     *
     * @return Collection<int, CommissionScheme>
     */
    private function activeSchemes(): Collection
    {
        return CommissionScheme::query()
            ->where('is_active', true)
            ->orderByRaw('position IS NULL') // pozisyonu olanlar önce
            ->orderBy('id')
            ->get();
    }

    /**
     * Kullanıcının pozisyonuna uyan aktif şema. Önce tam pozisyon eşleşmesi,
     * yoksa position = null (herkese açık) şema; hiçbiri yoksa null.
     *
     * @param  Collection<int, CommissionScheme>  $schemes
     */
    private function matchScheme(Collection $schemes, ?string $position): ?CommissionScheme
    {
        if ($position !== null && $position !== '') {
            $exact = $schemes->first(
                fn (CommissionScheme $s): bool => $s->position !== null
                    && mb_strtolower($s->position) === mb_strtolower($position)
            );

            if ($exact !== null) {
                return $exact;
            }
        }

        return $schemes->first(fn (CommissionScheme $s): bool => $s->position === null);
    }

    /**
     * @return array<string, mixed>
     */
    private function schemeDto(CommissionScheme $scheme): array
    {
        return [
            'id' => (int) $scheme->getKey(),
            'name' => $scheme->name,
            'basis' => $scheme->basis,
            'rate_bps' => (int) $scheme->rate_bps,
            'per_order_minor' => (int) $scheme->per_order_minor,
            'target_minor' => (int) $scheme->target_minor,
            'bonus_minor' => (int) $scheme->bonus_minor,
            'position' => $scheme->position,
            'is_active' => (bool) $scheme->is_active,
        ];
    }
}
