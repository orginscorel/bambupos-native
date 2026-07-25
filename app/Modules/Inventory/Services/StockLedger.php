<?php

namespace App\Modules\Inventory\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\StockLevel;
use App\Modules\Inventory\Models\StockMovement;
use App\Modules\Inventory\Models\Warehouse;
use App\Modules\Inventory\Support\Qty;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Defter çekirdeği (§17.4). STOK YAZAN TEK KAPI BURASIDIR:
 *
 *  - Hareket satırı + denormalize seviye AYNI transaction'da, seviye satırı
 *    KİLİTLİ (lockForUpdate) güncellenir → yarış yok.
 *  - Negatif stok koruması tür bazlıdır: manuel/fire/zayi/transfer eksiye
 *    düşemez; satış/reçete/ikram tüketimi düşebilir (servis akışı durmaz,
 *    eksi stok uyarı panosuna düşer).
 *  - Alış/üretim hareketi kalemin HAREKETLİ ORTALAMA maliyetini günceller
 *    (kuruş, half-up — tek yuvarlama noktası).
 *  - Defter satırı değişmezdir (StockMovement::booted fırlatır); düzeltme
 *    = ters kayıt (`reverse()`).
 */
class StockLedger
{
    /**
     * @param array{
     *   type: MovementType, item: StockItem, warehouse: Warehouse,
     *   qty_milli: int, tenant_id?: int|null, branch_id?: int|null,
     *   unit_cost_minor?: int|null, lot_no?: string|null, expires_at?: string|null,
     *   ref_type?: string|null, ref_id?: int|null, counterpart_id?: int|null,
     *   description?: string|null, user?: User|null,
     *   approved_by?: User|null, occurred_at?: \DateTimeInterface|null,
     *   skip_avg_cost?: bool
     * } $data
     */
    public function record(array $data): StockMovement
    {
        /** @var MovementType $type */
        $type = $data['type'];
        /** @var StockItem $item */
        $item = $data['item'];
        /** @var Warehouse $warehouse */
        $warehouse = $data['warehouse'];

        $qty = (int) $data['qty_milli'];
        $tenantId = (int) ($data['tenant_id'] ?? $item->tenant_id);

        if ($qty === 0) {
            throw ValidationException::withMessages(['qty' => ['Miktar sıfır olamaz.']]);
        }

        // Tür yön kuralı: tek yönlü türlerde işaret zorunlu.
        $direction = $type->direction();

        if ($direction === 1 && $qty < 0) {
            throw ValidationException::withMessages(['qty' => [$type->label().' hareketi giriş (+) olmalı.']]);
        }

        if ($direction === -1 && $qty > 0) {
            $qty = -$qty; // çıkış türlerinde pozitif girdi kullanıcı kolaylığıdır
        }

        if ((int) $warehouse->tenant_id !== $tenantId || (int) $item->tenant_id !== $tenantId) {
            throw ValidationException::withMessages(['warehouse' => ['Depo/kalem kiracı uyuşmazlığı.']]);
        }

        $unitCost = isset($data['unit_cost_minor']) && $data['unit_cost_minor'] !== null
            ? (int) $data['unit_cost_minor']
            : ($qty < 0 ? (int) $item->avg_cost_minor : null);

        return DB::transaction(function () use ($data, $type, $item, $warehouse, $qty, $tenantId, $unitCost): StockMovement {
            // Seviye satırını kilitle (yoksa oluştur).
            $level = StockLevel::withoutTenancy()
                ->where('warehouse_id', $warehouse->getKey())
                ->where('item_id', $item->getKey())
                ->lockForUpdate()
                ->first();

            if ($level === null) {
                $level = new StockLevel;
                $level->tenant_id = $tenantId;
                $level->warehouse_id = $warehouse->getKey();
                $level->item_id = $item->getKey();
                $level->qty_milli = 0;
                $level->save();

                $level = StockLevel::withoutTenancy()->lockForUpdate()->find($level->getKey());
            }

            $newQty = (int) $level->qty_milli + $qty;

            if ($newQty < 0 && ! $type->allowsNegative()) {
                throw ValidationException::withMessages(['qty' => [sprintf(
                    'Yetersiz stok: %s deposunda %s için mevcut %s %s, istenen çıkış %s %s.',
                    $warehouse->name,
                    $item->name,
                    Qty::toDecimalString((int) $level->qty_milli),
                    $item->base_unit,
                    Qty::toDecimalString(abs($qty)),
                    $item->base_unit,
                )]]);
            }

            $movement = new StockMovement;
            $movement->tenant_id = $tenantId;
            $movement->branch_id = $data['branch_id'] ?? $warehouse->branch_id;
            $movement->warehouse_id = $warehouse->getKey();
            $movement->item_id = $item->getKey();
            $movement->type = $type->value;
            $movement->qty_milli = $qty;
            $movement->unit_label = (string) $item->base_unit;
            $movement->unit_cost_minor = $unitCost;
            $movement->total_cost_minor = $unitCost !== null ? Qty::cost($qty, $unitCost) : null;
            $movement->lot_no = $data['lot_no'] ?? null;
            $movement->expires_at = $data['expires_at'] ?? null;
            $movement->ref_type = $data['ref_type'] ?? null;
            $movement->ref_id = $data['ref_id'] ?? null;
            $movement->counterpart_id = $data['counterpart_id'] ?? null;
            $movement->description = $data['description'] ?? null;
            $movement->user_id = ($data['user'] ?? null)?->getKey();
            $movement->approved_by_id = ($data['approved_by'] ?? null)?->getKey();
            $movement->approved_at = isset($data['approved_by']) && $data['approved_by'] !== null ? now() : null;
            $movement->occurred_at = $data['occurred_at'] ?? now();
            $movement->save();

            // Hareketli ortalama maliyet: yalnız maliyetli GİRİŞLER değiştirir.
            if ($qty > 0 && $unitCost !== null && empty($data['skip_avg_cost'])
                && in_array($type, [MovementType::Purchase, MovementType::Production], true)) {
                $this->applyAverageCost($item, $qty, $unitCost, $type);
            }

            $level->qty_milli = $newQty;
            $level->save();

            return $movement;
        });
    }

    /** Depolar arası transfer: iki bağlı satır (çıkış eksiye düşemez). */
    public function transfer(StockItem $item, Warehouse $from, Warehouse $to, int $qtyMilli, ?User $user, ?string $description = null): array
    {
        if ($from->getKey() === $to->getKey()) {
            throw ValidationException::withMessages(['warehouse' => ['Kaynak ve hedef depo aynı olamaz.']]);
        }

        if ($qtyMilli <= 0) {
            throw ValidationException::withMessages(['qty' => ['Transfer miktarı pozitif olmalı.']]);
        }

        return DB::transaction(function () use ($item, $from, $to, $qtyMilli, $user, $description): array {
            $out = $this->record([
                'type' => MovementType::TransferOut,
                'item' => $item,
                'warehouse' => $from,
                'qty_milli' => -$qtyMilli,
                'unit_cost_minor' => (int) $item->avg_cost_minor,
                'description' => $description ?? sprintf('%s → %s transfer', $from->name, $to->name),
                'user' => $user,
            ]);

            $in = $this->record([
                'type' => MovementType::TransferIn,
                'item' => $item,
                'warehouse' => $to,
                'qty_milli' => $qtyMilli,
                'unit_cost_minor' => (int) $item->avg_cost_minor,
                'counterpart_id' => $out->getKey(),
                'description' => $description ?? sprintf('%s → %s transfer', $from->name, $to->name),
                'user' => $user,
            ]);

            return [$out, $in];
        });
    }

    /** Yanlış kaydın düzeltmesi: karşı işaretli YENİ satır (silme yok). */
    public function reverse(StockMovement $movement, ?User $user, string $reason): StockMovement
    {
        $item = StockItem::withoutTenancy()->findOrFail($movement->item_id);
        $warehouse = Warehouse::withoutTenancy()->findOrFail($movement->warehouse_id);

        return $this->record([
            'type' => MovementType::ManualAdjust,
            'item' => $item,
            'warehouse' => $warehouse,
            'qty_milli' => -(int) $movement->qty_milli,
            'tenant_id' => (int) $movement->tenant_id,
            'unit_cost_minor' => $movement->unit_cost_minor,
            'ref_type' => 'reversal',
            'ref_id' => $movement->getKey(),
            'description' => 'Ters kayıt (#'.$movement->getKey().'): '.$reason,
            'user' => $user,
            'approved_by' => $user,
        ]);
    }

    /**
     * Tutarlılık denetimi: defter toplamı == seviye. (Test + bakım komutu.)
     */
    public function ledgerBalance(int $warehouseId, int $itemId): int
    {
        return (int) StockMovement::withoutTenancy()
            ->where('warehouse_id', $warehouseId)
            ->where('item_id', $itemId)
            ->sum('qty_milli');
    }

    /** Hareketli ortalama: (eldeki×ort + giren×fiyat) / (eldeki+giren). */
    private function applyAverageCost(StockItem $item, int $qtyMilli, int $unitCostMinor, MovementType $type): void
    {
        $locked = StockItem::withoutTenancy()->lockForUpdate()->findOrFail($item->getKey());

        $onHand = max(0, (int) $locked->levels()->sum('qty_milli'));
        $currentAvg = (int) $locked->avg_cost_minor;

        $newAvg = $onHand + $qtyMilli > 0
            ? (int) round((($onHand * $currentAvg) + ($qtyMilli * $unitCostMinor)) / ($onHand + $qtyMilli), 0, PHP_ROUND_HALF_UP)
            : $unitCostMinor;

        $locked->avg_cost_minor = $newAvg;

        if ($type === MovementType::Purchase) {
            $locked->last_cost_minor = $unitCostMinor;
            $locked->last_purchase_at = now();
        }

        $locked->save();

        // Bellekteki örneği tazele (aynı istek içindeki sonraki hesaplar için).
        $item->avg_cost_minor = $newAvg;
        $item->last_cost_minor = $locked->last_cost_minor;
    }
}
