<?php

namespace App\Modules\Inventory\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Enums\PurchaseStatus;
use App\Modules\Inventory\Models\PurchaseOrder;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\StockLevel;
use App\Modules\Inventory\Models\Supplier;
use App\Modules\Inventory\Models\SupplierPrice;
use App\Modules\Inventory\Models\Warehouse;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Satın alma (§17.6): mal kabul → alış defter kaydı + ortalama maliyet
 * + fiyat geçmişi; iade → purchase_return; ödeme/vade takibi.
 */
class PurchasingService
{
    public function __construct(
        private readonly StockLedger $ledger,
        private readonly AuditLogger $audit,
    ) {
    }

    /**
     * Mal kabul. Satır bazında teslim alınan miktar + (varsa) lot/SKT.
     *
     * @param array<int, array{line_id: int, qty_milli: int, lot_no?: string|null, expires_at?: string|null, unit_price_minor?: int|null}> $received
     */
    public function receive(PurchaseOrder $po, array $received, ?int $warehouseId, User $actor): PurchaseOrder
    {
        if (! $po->statusEnum()->receivable()) {
            throw ValidationException::withMessages(['status' => ['Bu belge mal kabule uygun değil (durum: '.$po->statusEnum()->label().').']]);
        }

        $warehouse = Warehouse::withoutTenancy()
            ->where('tenant_id', $po->tenant_id)
            ->find($warehouseId ?? $po->warehouse_id);

        if ($warehouse === null) {
            throw ValidationException::withMessages(['warehouse_id' => ['Mal kabul deposu seçilmeli.']]);
        }

        return DB::transaction(function () use ($po, $received, $warehouse, $actor): PurchaseOrder {
            $anything = false;

            foreach ($received as $row) {
                $line = $po->lines()->lockForUpdate()->find((int) $row['line_id']);
                $qty = (int) ($row['qty_milli'] ?? 0);

                if ($line === null || $qty <= 0) {
                    continue;
                }

                $outstanding = (int) $line->qty_milli - (int) $line->received_qty_milli;

                if ($qty > $outstanding) {
                    throw ValidationException::withMessages(['received' => [sprintf(
                        'Satır #%d için kalan %s birimden fazlası teslim alınamaz.',
                        $line->getKey(),
                        \App\Modules\Inventory\Support\Qty::toDecimalString($outstanding),
                    )]]);
                }

                $item = StockItem::withoutTenancy()->findOrFail($line->item_id);
                $unitPrice = (int) ($row['unit_price_minor'] ?? $line->unit_price_minor);

                $this->ledger->record([
                    'type' => MovementType::Purchase,
                    'item' => $item,
                    'warehouse' => $warehouse,
                    'qty_milli' => $qty,
                    'tenant_id' => (int) $po->tenant_id,
                    'branch_id' => $po->branch_id,
                    'unit_cost_minor' => $unitPrice,
                    'lot_no' => $row['lot_no'] ?? null,
                    'expires_at' => $row['expires_at'] ?? null,
                    'ref_type' => 'purchase_order',
                    'ref_id' => $po->getKey(),
                    'description' => sprintf('SA #%d — %s mal kabul', $po->getKey(), $item->name),
                    'user' => $actor,
                    'approved_by' => $actor,
                ]);

                $line->received_qty_milli = (int) $line->received_qty_milli + $qty;
                $line->save();

                // Fiyat geçmişi (tedarikçi × kalem).
                $price = new SupplierPrice;
                $price->tenant_id = $po->tenant_id;
                $price->supplier_id = $po->supplier_id;
                $price->item_id = $item->getKey();
                $price->unit_price_minor = $unitPrice;
                $price->recorded_at = now();
                $price->save();

                $anything = true;
            }

            if (! $anything) {
                throw ValidationException::withMessages(['received' => ['Teslim alınacak satır girilmedi.']]);
            }

            $this->deriveReceiveStatus($po);

            $this->audit->log('inventory.purchase_received', $po, null, [
                'warehouse_id' => $warehouse->getKey(),
                'performed_by' => $actor->getKey(),
            ]);

            return $po->refresh()->load('lines.item');
        });
    }

    /**
     * Tedarikçiye iade: teslim alınandan fazlası iade edilemez.
     *
     * @param array<int, array{line_id: int, qty_milli: int}> $returns
     */
    public function returnGoods(PurchaseOrder $po, array $returns, ?int $warehouseId, string $reason, User $actor): PurchaseOrder
    {
        $warehouse = Warehouse::withoutTenancy()
            ->where('tenant_id', $po->tenant_id)
            ->find($warehouseId ?? $po->warehouse_id);

        if ($warehouse === null) {
            throw ValidationException::withMessages(['warehouse_id' => ['İade deposu seçilmeli.']]);
        }

        return DB::transaction(function () use ($po, $returns, $warehouse, $reason, $actor): PurchaseOrder {
            $anything = false;

            foreach ($returns as $row) {
                $line = $po->lines()->lockForUpdate()->find((int) $row['line_id']);
                $qty = (int) ($row['qty_milli'] ?? 0);

                if ($line === null || $qty <= 0) {
                    continue;
                }

                $returnable = (int) $line->received_qty_milli - (int) $line->returned_qty_milli;

                if ($qty > $returnable) {
                    throw ValidationException::withMessages(['returns' => ['Teslim alınandan fazlası iade edilemez.']]);
                }

                $item = StockItem::withoutTenancy()->findOrFail($line->item_id);

                $this->ledger->record([
                    'type' => MovementType::PurchaseReturn,
                    'item' => $item,
                    'warehouse' => $warehouse,
                    'qty_milli' => -$qty,
                    'tenant_id' => (int) $po->tenant_id,
                    'branch_id' => $po->branch_id,
                    'unit_cost_minor' => (int) $line->unit_price_minor,
                    'ref_type' => 'purchase_order',
                    'ref_id' => $po->getKey(),
                    'description' => sprintf('SA #%d — %s tedarikçi iadesi: %s', $po->getKey(), $item->name, $reason),
                    'user' => $actor,
                    'approved_by' => $actor,
                ]);

                $line->returned_qty_milli = (int) $line->returned_qty_milli + $qty;
                $line->save();
                $anything = true;
            }

            if (! $anything) {
                throw ValidationException::withMessages(['returns' => ['İade edilecek satır girilmedi.']]);
            }

            $this->audit->log('inventory.purchase_returned', $po, null, [
                'reason' => $reason,
                'performed_by' => $actor->getKey(),
            ]);

            return $po->refresh()->load('lines.item');
        });
    }

    /**
     * Otomatik önerilen sipariş: min altına düşen kalemler; öneri miktarı
     * maks (yoksa min ×2) seviyesine tamamlar; varsayılan tedarikçiye
     * gruplanır.
     *
     * @return array<int, array{supplier: array{id: int|null, name: string}, items: array<int, array<string, mixed>>}>
     */
    public function suggestedOrders(int $tenantId): array
    {
        $items = StockItem::withoutTenancy()
            ->with('defaultSupplier')
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->where('min_qty_milli', '>', 0)
            ->get();

        if ($items->isEmpty()) {
            return [];
        }

        $onHand = StockLevel::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->selectRaw('item_id, SUM(qty_milli) as total')
            ->groupBy('item_id')
            ->pluck('total', 'item_id');

        $groups = [];

        foreach ($items as $item) {
            $current = (int) ($onHand[$item->getKey()] ?? 0);

            if ($current > (int) $item->min_qty_milli) {
                continue;
            }

            $target = $item->max_qty_milli !== null && (int) $item->max_qty_milli > 0
                ? (int) $item->max_qty_milli
                : (int) $item->min_qty_milli * 2;

            $suggest = max(0, $target - $current);

            if ($suggest === 0) {
                continue;
            }

            $supplierId = $item->default_supplier_id;
            $key = $supplierId ?? 0;

            $groups[$key] ??= [
                'supplier' => [
                    'id' => $supplierId,
                    'name' => $item->defaultSupplier?->name ?? 'Tedarikçisi atanmamış',
                ],
                'items' => [],
            ];

            $groups[$key]['items'][] = [
                'item_id' => $item->getKey(),
                'name' => $item->name,
                'base_unit' => $item->base_unit,
                'on_hand_milli' => $current,
                'min_qty_milli' => (int) $item->min_qty_milli,
                'suggested_qty_milli' => $suggest,
                'last_cost_minor' => $item->last_cost_minor,
                'estimated_total_minor' => $item->last_cost_minor !== null
                    ? \App\Modules\Inventory\Support\Qty::cost($suggest, (int) $item->last_cost_minor)
                    : null,
            ];
        }

        return array_values($groups);
    }

    /** Durum geçişi (talep→teklif→sipariş / iptal). */
    public function transition(PurchaseOrder $po, PurchaseStatus $to, User $actor): PurchaseOrder
    {
        $from = $po->statusEnum();

        if (! $from->canTransitionTo($to)) {
            throw ValidationException::withMessages(['status' => [sprintf('"%s" durumundan "%s" durumuna geçilemez.', $from->label(), $to->label())]]);
        }

        if ($to === PurchaseStatus::Ordered) {
            if ($po->lines()->count() === 0) {
                throw ValidationException::withMessages(['status' => ['Boş belge siparişe çevrilemez.']]);
            }

            $po->ordered_at = now();

            // Vade: tedarikçinin vade günü + bugün (fatura girilince değişebilir).
            $supplier = Supplier::withoutTenancy()->find($po->supplier_id);

            if ($po->due_date === null && $supplier !== null && (int) $supplier->payment_term_days > 0) {
                $po->due_date = now()->addDays((int) $supplier->payment_term_days)->toDateString();
            }
        }

        $po->status = $to->value;
        $po->save();

        $this->audit->log('inventory.purchase_status', $po, ['status' => $from->value], ['status' => $to->value, 'performed_by' => $actor->getKey()]);

        return $po;
    }

    private function deriveReceiveStatus(PurchaseOrder $po): void
    {
        $lines = $po->lines()->get();
        $fully = $lines->every(fn ($l) => (int) $l->received_qty_milli >= (int) $l->qty_milli);

        $po->status = $fully ? PurchaseStatus::Received->value : PurchaseStatus::PartiallyReceived->value;
        $po->save();
    }
}
