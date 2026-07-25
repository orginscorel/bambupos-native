<?php

namespace App\Modules\Inventory\Services;

use App\Modules\Catalog\Models\Product;
use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Models\Recipe;
use App\Modules\Inventory\Models\StockCount;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\StockLevel;
use App\Modules\Inventory\Models\StockMovement;
use App\Modules\Inventory\Support\Qty;
use Illuminate\Support\Collection;

/**
 * Uyarı panosu (§17.5) — panel içi liste (kabuk bildirim merkezi henüz
 * içeriksiz iskelet; gerçek bildirim altyapısı kurulunca buraya bağlanır).
 *
 * Uyarılar SORGUyla anlık hesaplanır; ayrı tablo/senkron derdi yok.
 */
class AlertService
{
    /** @return array<string, array<int, array<string, mixed>>> */
    public function build(int $tenantId): array
    {
        $items = StockItem::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->get();

        $onHand = StockLevel::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->selectRaw('item_id, SUM(qty_milli) as total')
            ->groupBy('item_id')
            ->pluck('total', 'item_id');

        return [
            'critical' => $this->thresholdAlerts($items, $onHand),
            'negative' => $this->negativeAlerts($tenantId),
            'expiry' => $this->expiryAlerts($tenantId),
            'depletion' => $this->depletionAlerts($tenantId, $items, $onHand),
            'abnormal' => $this->abnormalConsumption($tenantId, $items),
            'missing_recipes' => $this->missingRecipes($tenantId),
            'count_diffs' => $this->recentCountDiffs($tenantId),
        ];
    }

    /** Min / kritik seviye altı. */
    private function thresholdAlerts(Collection $items, Collection $onHand): array
    {
        $rows = [];

        foreach ($items as $item) {
            $current = (int) ($onHand[$item->getKey()] ?? 0);
            $min = (int) $item->min_qty_milli;
            $critical = (int) $item->critical_qty_milli;

            if ($critical > 0 && $current <= $critical) {
                $severity = 'critical';
            } elseif ($min > 0 && $current <= $min) {
                $severity = 'low';
            } else {
                continue;
            }

            $rows[] = [
                'item_id' => $item->getKey(),
                'name' => $item->name,
                'severity' => $severity,
                'on_hand' => Qty::toDecimalString($current),
                'min' => Qty::toDecimalString($min),
                'critical' => Qty::toDecimalString($critical),
                'unit' => $item->base_unit,
            ];
        }

        usort($rows, fn ($a, $b) => strcmp($a['severity'], $b['severity'])); // critical önce
        return $rows;
    }

    /** Depo bazında eksi stok (tüketim türleri eksiye düşebildiği için). */
    private function negativeAlerts(int $tenantId): array
    {
        return StockLevel::withoutTenancy()
            ->with(['item:id,name,base_unit', 'warehouse:id,name'])
            ->where('tenant_id', $tenantId)
            ->where('qty_milli', '<', 0)
            ->get()
            ->map(fn (StockLevel $l) => [
                'item_id' => $l->item_id,
                'name' => $l->item?->name ?? '—',
                'warehouse' => $l->warehouse?->name ?? '—',
                'on_hand' => Qty::toDecimalString((int) $l->qty_milli),
                'unit' => $l->item?->base_unit ?? '',
            ])->values()->all();
    }

    /** Yaklaşan SKT: 7 gün içinde dolan lotlar (kalemde stok varsa). */
    private function expiryAlerts(int $tenantId): array
    {
        $soon = now()->addDays(7)->toDateString();

        $lots = StockMovement::withoutTenancy()
            ->with('item:id,name,base_unit')
            ->where('tenant_id', $tenantId)
            ->where('type', MovementType::Purchase->value)
            ->whereNotNull('expires_at')
            ->where('expires_at', '<=', $soon)
            ->orderBy('expires_at')
            ->limit(50)
            ->get();

        if ($lots->isEmpty()) {
            return [];
        }

        $onHand = StockLevel::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->whereIn('item_id', $lots->pluck('item_id')->unique())
            ->selectRaw('item_id, SUM(qty_milli) as total')
            ->groupBy('item_id')
            ->pluck('total', 'item_id');

        return $lots
            ->filter(fn (StockMovement $m) => (int) ($onHand[$m->item_id] ?? 0) > 0)
            ->map(fn (StockMovement $m) => [
                'item_id' => $m->item_id,
                'name' => $m->item?->name ?? '—',
                'lot_no' => $m->lot_no,
                'expires_at' => $m->expires_at?->toDateString(),
                'expired' => $m->expires_at !== null && $m->expires_at->isPast(),
                'qty' => Qty::toDecimalString((int) $m->qty_milli),
                'unit' => $m->item?->base_unit ?? '',
            ])->values()->all();
    }

    /** Bitiş tahmini: son 7 gün tüketim hızına göre ≤ 7 günlük stok kalanlar. */
    private function depletionAlerts(int $tenantId, Collection $items, Collection $onHand): array
    {
        $consumption = $this->consumptionTotals($tenantId, now()->subDays(7));
        $rows = [];

        foreach ($items as $item) {
            $used = (int) ($consumption[$item->getKey()] ?? 0);
            $current = (int) ($onHand[$item->getKey()] ?? 0);

            if ($used <= 0 || $current <= 0) {
                continue;
            }

            $daysLeft = $current / ($used / 7);

            if ($daysLeft <= 7) {
                $rows[] = [
                    'item_id' => $item->getKey(),
                    'name' => $item->name,
                    'on_hand' => Qty::toDecimalString($current),
                    'unit' => $item->base_unit,
                    'daily_use' => Qty::toDecimalString((int) round($used / 7)),
                    'days_left' => round($daysLeft, 1),
                ];
            }
        }

        usort($rows, fn ($a, $b) => $a['days_left'] <=> $b['days_left']);
        return $rows;
    }

    /** Anormal tüketim: son 7 gün, önceki 7 günün 2 katından fazla. */
    private function abnormalConsumption(int $tenantId, Collection $items): array
    {
        $recent = $this->consumptionTotals($tenantId, now()->subDays(7));
        $previous = $this->consumptionTotals($tenantId, now()->subDays(14), now()->subDays(7));
        $rows = [];

        foreach ($recent as $itemId => $used) {
            $before = (int) ($previous[$itemId] ?? 0);

            if ($before <= 0 || (int) $used < $before * 2) {
                continue;
            }

            $item = $items->firstWhere('id', $itemId);

            if ($item === null) {
                continue;
            }

            $rows[] = [
                'item_id' => $itemId,
                'name' => $item->name,
                'recent' => Qty::toDecimalString((int) $used),
                'previous' => Qty::toDecimalString($before),
                'unit' => $item->base_unit,
                'ratio' => round((int) $used / max(1, $before), 1),
            ];
        }

        return $rows;
    }

    /**
     * Reçete–satış farkı: aktif, stok takipli satışta olup AKTİF REÇETESİ
     * OLMAYAN ürünler — satış olur ama stok düşmez (sessiz sızıntı).
     */
    private function missingRecipes(int $tenantId): array
    {
        $withRecipe = Recipe::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->whereNotNull('product_id')
            ->pluck('product_id')
            ->unique();

        return Product::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->whereNotIn('id', $withRecipe->all())
            ->orderBy('name')
            ->limit(50)
            ->get(['id', 'name'])
            ->map(fn (Product $p) => ['product_id' => $p->id, 'name' => $p->name])
            ->all();
    }

    /** Son 14 günün onaylanmış sayım farkları. */
    private function recentCountDiffs(int $tenantId): array
    {
        return StockCount::withoutTenancy()
            ->with(['lines' => fn ($q) => $q->where('diff_qty_milli', '!=', 0), 'lines.item:id,name,base_unit', 'warehouse:id,name'])
            ->where('tenant_id', $tenantId)
            ->where('status', StockCount::STATUS_APPROVED)
            ->where('approved_at', '>=', now()->subDays(14))
            ->orderByDesc('approved_at')
            ->limit(10)
            ->get()
            ->flatMap(fn (StockCount $c) => $c->lines->map(fn ($l) => [
                'count_id' => $c->getKey(),
                'warehouse' => $c->warehouse?->name ?? '—',
                'item' => $l->item?->name ?? '—',
                'diff' => Qty::toDecimalString((int) $l->diff_qty_milli),
                'unit' => $l->item?->base_unit ?? '',
                'approved_at' => $c->approved_at?->toIso8601String(),
            ]))
            ->values()
            ->all();
    }

    /** @return \Illuminate\Support\Collection<int|string, int|string> item_id → |tüketim| */
    private function consumptionTotals(int $tenantId, \DateTimeInterface $from, ?\DateTimeInterface $until = null): Collection
    {
        $types = [
            MovementType::RecipeConsumption->value,
            MovementType::CompConsumption->value,
            MovementType::Sale->value,
        ];

        return StockMovement::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->whereIn('type', $types)
            ->where('occurred_at', '>=', $from)
            ->when($until !== null, fn ($q) => $q->where('occurred_at', '<', $until))
            ->selectRaw('item_id, SUM(-qty_milli) as total')
            ->groupBy('item_id')
            ->pluck('total', 'item_id');
    }
}
