<?php

namespace App\Modules\Inventory\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Models\StockCount;
use App\Modules\Inventory\Models\StockCountLine;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\StockLevel;
use App\Modules\Inventory\Models\Warehouse;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Sayım akışı: taslak (kör giriş) → gönderim (beklenen snapshot + fark)
 * → onay (count_adjust defter kayıtları, stock.adjust yetkisi).
 */
class CountService
{
    public function __construct(
        private readonly StockLedger $ledger,
        private readonly AuditLogger $audit,
    ) {
    }

    /**
     * @param array<int, array{item_id: int, counted_qty_milli: int|null}> $lines
     */
    public function saveLines(StockCount $count, array $lines): StockCount
    {
        if ($count->status !== StockCount::STATUS_DRAFT) {
            throw ValidationException::withMessages(['count' => ['Yalnız taslak sayımda satır girilebilir.']]);
        }

        DB::transaction(function () use ($count, $lines): void {
            foreach ($lines as $data) {
                $item = StockItem::withoutTenancy()
                    ->where('tenant_id', $count->tenant_id)
                    ->find((int) $data['item_id']);

                if ($item === null) {
                    throw ValidationException::withMessages(['lines' => ['Kalem bulunamadı.']]);
                }

                $counted = $data['counted_qty_milli'];

                if ($counted !== null && (int) $counted < 0) {
                    throw ValidationException::withMessages(['lines' => ['Sayılan miktar negatif olamaz.']]);
                }

                $line = StockCountLine::withoutTenancy()
                    ->where('count_id', $count->getKey())
                    ->where('item_id', $item->getKey())
                    ->first();

                if ($line === null) {
                    $line = new StockCountLine;
                    $line->tenant_id = $count->tenant_id;
                    $line->count_id = $count->getKey();
                    $line->item_id = $item->getKey();
                }

                $line->counted_qty_milli = $counted !== null ? (int) $counted : null;
                $line->save();
            }
        });

        return $count->load('lines.item');
    }

    /** Gönderim: beklenen SNAPSHOT'lanır, fark hesaplanır (kör sayım biter). */
    public function submit(StockCount $count, ?User $actor): StockCount
    {
        if ($count->status !== StockCount::STATUS_DRAFT) {
            throw ValidationException::withMessages(['count' => ['Sayım zaten gönderilmiş.']]);
        }

        return DB::transaction(function () use ($count, $actor): StockCount {
            $lines = StockCountLine::withoutTenancy()
                ->where('count_id', $count->getKey())
                ->whereNotNull('counted_qty_milli')
                ->get();

            if ($lines->isEmpty()) {
                throw ValidationException::withMessages(['count' => ['Sayılmış en az bir kalem olmalı.']]);
            }

            foreach ($lines as $line) {
                $expected = (int) (StockLevel::withoutTenancy()
                    ->where('warehouse_id', $count->warehouse_id)
                    ->where('item_id', $line->item_id)
                    ->value('qty_milli') ?? 0);

                $line->expected_qty_milli = $expected;
                $line->diff_qty_milli = (int) $line->counted_qty_milli - $expected;
                $line->save();
            }

            $count->status = StockCount::STATUS_SUBMITTED;
            $count->submitted_at = now();
            $count->save();

            $this->audit->log('inventory.count_submitted', $count, null, [
                'lines' => $lines->count(),
                'performed_by' => $actor?->getKey(),
            ]);

            return $count->load('lines.item');
        });
    }

    /** Onay: sıfırdan farklı farklar count_adjust olarak deftere işlenir. */
    public function approve(StockCount $count, User $actor): StockCount
    {
        if ($count->status !== StockCount::STATUS_SUBMITTED) {
            throw ValidationException::withMessages(['count' => ['Yalnız gönderilmiş sayım onaylanabilir.']]);
        }

        return DB::transaction(function () use ($count, $actor): StockCount {
            $warehouse = Warehouse::withoutTenancy()->findOrFail($count->warehouse_id);

            foreach ($count->lines()->whereNotNull('counted_qty_milli')->get() as $line) {
                $diff = (int) $line->diff_qty_milli;

                if ($diff === 0) {
                    continue;
                }

                $item = StockItem::withoutTenancy()->findOrFail($line->item_id);

                $this->ledger->record([
                    'type' => MovementType::CountAdjust,
                    'item' => $item,
                    'warehouse' => $warehouse,
                    'qty_milli' => $diff,
                    'tenant_id' => (int) $count->tenant_id,
                    'unit_cost_minor' => (int) $item->avg_cost_minor,
                    'ref_type' => 'count',
                    'ref_id' => $count->getKey(),
                    'description' => sprintf('Sayım #%d farkı (beklenen %s, sayılan %s)',
                        $count->getKey(),
                        \App\Modules\Inventory\Support\Qty::toDecimalString((int) $line->expected_qty_milli),
                        \App\Modules\Inventory\Support\Qty::toDecimalString((int) $line->counted_qty_milli),
                    ),
                    'user' => $actor,
                    'approved_by' => $actor,
                ]);
            }

            $count->status = StockCount::STATUS_APPROVED;
            $count->approved_by_id = $actor->getKey();
            $count->approved_at = now();
            $count->save();

            $this->audit->log('inventory.count_approved', $count, null, [
                'performed_by' => $actor->getKey(),
            ]);

            return $count->load('lines.item');
        });
    }
}
