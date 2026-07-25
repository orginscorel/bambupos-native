<?php

namespace App\Modules\Inventory\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Enums\PurchaseStatus;
use App\Modules\Inventory\Enums\WarehouseType;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Support\InventoryFeature;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Stok panel ekranları (Inertia). Enum sözlükleri PHP'den prop gider
 * (tek kaynak); veri /api/v1/inventory uçlarından yüklenir.
 *
 * Feature-flag (§9): tüm ekranlar InventoryFeature kapısından geçer;
 * kapalıysa 404 (ADR: kapalı=render edilmez).
 */
class InventoryPageController extends Controller
{
    public function items(): Response
    {
        return $this->page('Panel/Inventory/Items');
    }

    public function movements(): Response
    {
        return $this->page('Panel/Inventory/Movements');
    }

    public function recipes(): Response
    {
        return $this->page('Panel/Inventory/Recipes');
    }

    public function counts(): Response
    {
        return $this->page('Panel/Inventory/Counts');
    }

    public function suppliers(): Response
    {
        return $this->page('Panel/Inventory/Suppliers');
    }

    public function purchasing(): Response
    {
        return $this->page('Panel/Inventory/Purchasing');
    }

    public function alerts(): Response
    {
        return $this->page('Panel/Inventory/Alerts');
    }

    public function reports(): Response
    {
        return $this->page('Panel/Inventory/Reports');
    }

    private function page(string $component): Response
    {
        abort_unless(InventoryFeature::enabled((int) (auth()->user()?->tenant_id ?? 0)), 404);

        $this->authorize('viewAny', StockItem::class);

        return Inertia::render($component, [
            'movementTypes' => MovementType::options(),
            'warehouseTypes' => WarehouseType::options(),
            'purchaseStatuses' => PurchaseStatus::options(),
            'canAdjust' => (bool) auth()->user()?->hasPermission('stock.adjust'),
        ]);
    }
}
