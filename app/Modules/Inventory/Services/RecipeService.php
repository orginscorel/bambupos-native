<?php

namespace App\Modules\Inventory\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Inventory\Models\Recipe;
use App\Modules\Inventory\Models\RecipeLine;
use App\Modules\Inventory\Models\StockItem;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Reçete yönetimi (§17.3): versiyonlama + şube/varyant çözümü.
 */
class RecipeService
{
    /**
     * SATIŞ ANINDA reçete çözümü — en özelden genele:
     *   1. şube + varyant   2. şube (varyantsız)
     *   3. genel + varyant  4. genel (varyantsız)
     */
    public function resolveForSale(int $tenantId, int $productId, ?int $variantId, ?int $branchId): ?Recipe
    {
        $candidates = Recipe::withoutTenancy()
            ->with('lines')
            ->where('tenant_id', $tenantId)
            ->where('product_id', $productId)
            ->where('is_active', true)
            ->get();

        $rank = function (Recipe $r) use ($variantId, $branchId): ?int {
            $branchMatch = $r->branch_id === null ? 0 : (((int) $r->branch_id === (int) $branchId) ? 1 : -1);
            $variantMatch = $r->variant_id === null ? 0 : (((int) $r->variant_id === (int) $variantId) ? 1 : -1);

            if ($branchMatch === -1 || $variantMatch === -1) {
                return null; // başka şubenin/varyantın reçetesi — aday değil
            }

            return $branchMatch * 2 + $variantMatch; // 3,2,1,0
        };

        return $candidates
            ->map(fn (Recipe $r) => ['recipe' => $r, 'rank' => $rank($r)])
            ->filter(fn (array $row) => $row['rank'] !== null)
            ->sortByDesc('rank')
            ->first()['recipe'] ?? null;
    }

    /**
     * Reçete kaydet = YENİ SÜRÜM: aynı hedefin aktif sürümü pasife alınır,
     * version+1 ile yeni başlık + satırlar yazılır (tarihçe korunur).
     *
     * @param array{
     *   product_id?: int|null, variant_id?: int|null, item_id?: int|null,
     *   branch_id?: int|null, yield_qty_milli?: int, waste_percent?: float,
     *   note?: string|null,
     *   lines: array<int, array{item_id: int, qty_milli: int, unit_entry?: string, waste_percent?: float, warehouse_id?: int|null}>
     * } $data
     */
    public function saveVersion(int $tenantId, array $data, ?User $actor): Recipe
    {
        $productId = $data['product_id'] ?? null;
        $targetItemId = $data['item_id'] ?? null;

        if (($productId === null) === ($targetItemId === null)) {
            throw ValidationException::withMessages(['product_id' => ['Reçete hedefi ya bir ürün ya da bir yarı mamul stok kalemi olmalı.']]);
        }

        if (($data['lines'] ?? []) === []) {
            throw ValidationException::withMessages(['lines' => ['Reçetede en az bir bileşen olmalı.']]);
        }

        // Bileşenler bu kiracının kalemleri mi? (policy'den bağımsız 2. savunma)
        $itemIds = array_map(fn (array $l) => (int) $l['item_id'], $data['lines']);
        $validCount = StockItem::withoutTenancy()
            ->where('tenant_id', $tenantId)->whereIn('id', $itemIds)->count();

        if ($validCount !== count(array_unique($itemIds))) {
            throw ValidationException::withMessages(['lines' => ['Bileşenlerden bazıları bulunamadı.']]);
        }

        // Yarı mamul kendi reçetesinde bileşen olamaz (döngü koruması).
        if ($targetItemId !== null && in_array((int) $targetItemId, $itemIds, true)) {
            throw ValidationException::withMessages(['lines' => ['Yarı mamul kendi reçetesinde bileşen olamaz.']]);
        }

        return DB::transaction(function () use ($tenantId, $data, $actor, $productId, $targetItemId): Recipe {
            $scope = Recipe::withoutTenancy()
                ->where('tenant_id', $tenantId)
                ->where('product_id', $productId)
                ->where('variant_id', $data['variant_id'] ?? null)
                ->where('item_id', $targetItemId)
                ->where('branch_id', $data['branch_id'] ?? null);

            $lastVersion = (int) (clone $scope)->max('version');
            (clone $scope)->where('is_active', true)->update(['is_active' => false]);

            $recipe = new Recipe([
                'product_id' => $productId,
                'variant_id' => $data['variant_id'] ?? null,
                'item_id' => $targetItemId,
                'branch_id' => $data['branch_id'] ?? null,
                'yield_qty_milli' => max(1, (int) ($data['yield_qty_milli'] ?? 1000)),
                'waste_percent' => (float) ($data['waste_percent'] ?? 0),
                'note' => $data['note'] ?? null,
            ]);
            $recipe->tenant_id = $tenantId;
            $recipe->version = $lastVersion + 1;
            $recipe->is_active = true;
            $recipe->created_by_id = $actor?->getKey();
            $recipe->save();

            foreach (array_values($data['lines']) as $i => $lineData) {
                $line = new RecipeLine([
                    'item_id' => (int) $lineData['item_id'],
                    'qty_milli' => (int) $lineData['qty_milli'],
                    'unit_entry' => in_array($lineData['unit_entry'] ?? 'base', ['base', 'sub'], true) ? ($lineData['unit_entry'] ?? 'base') : 'base',
                    'waste_percent' => (float) ($lineData['waste_percent'] ?? 0),
                    'warehouse_id' => $lineData['warehouse_id'] ?? null,
                    'sort_order' => $i,
                ]);
                $line->tenant_id = $tenantId;
                $line->recipe_id = $recipe->getKey();

                if ($line->qty_milli <= 0) {
                    throw ValidationException::withMessages(['lines' => ['Bileşen miktarı pozitif olmalı.']]);
                }

                $line->save();
            }

            return $recipe->load('lines');
        });
    }
}
