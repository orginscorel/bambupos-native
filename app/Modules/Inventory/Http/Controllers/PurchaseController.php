<?php

namespace App\Modules\Inventory\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Support\Money;
use App\Modules\Inventory\Enums\PurchaseStatus;
use App\Modules\Inventory\Models\PurchaseOrder;
use App\Modules\Inventory\Models\PurchaseOrderLine;
use App\Modules\Inventory\Services\PurchasingService;
use App\Modules\Inventory\Support\Qty;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/** Satın alma uçları (§17.6). Para kuruş-int (ADR-007), miktar milli-int. */
class PurchaseController extends Controller
{
    public function __construct(private readonly PurchasingService $purchasing)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', PurchaseOrder::class);

        $query = PurchaseOrder::query()
            ->with(['supplier:id,name', 'warehouse:id,name'])
            ->withCount('lines')
            ->orderByDesc('id');

        if ($status = $request->query('status')) {
            $query->where('status', (string) $status);
        }

        return response()->json([
            'orders' => $query->limit(100)->get()->map(fn (PurchaseOrder $po) => $this->presentSummary($po)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', PurchaseOrder::class);

        $tenantId = (int) $request->user()->tenant_id;

        $data = $request->validate([
            'supplier_id' => ['required', 'integer', Rule::exists('inv_suppliers', 'id')->where('tenant_id', $tenantId)],
            'warehouse_id' => ['nullable', 'integer', Rule::exists('inv_warehouses', 'id')->where('tenant_id', $tenantId)],
            'expected_at' => ['nullable', 'date'],
            'note' => ['nullable', 'string', 'max:500'],
            'lines' => ['nullable', 'array'],
            'lines.*.item_id' => ['required', 'integer', Rule::exists('inv_items', 'id')->where('tenant_id', $tenantId)],
            'lines.*.qty' => ['required', 'string'],
            'lines.*.unit_price' => ['required', 'string'],
        ]);

        $po = new PurchaseOrder([
            'supplier_id' => (int) $data['supplier_id'],
            'warehouse_id' => $data['warehouse_id'] ?? null,
            'expected_at' => $data['expected_at'] ?? null,
            'note' => $data['note'] ?? null,
        ]);
        $po->branch_id = $request->user()->branch_id;
        $po->status = PurchaseStatus::Draft->value;
        $po->created_by_id = $request->user()->getKey();
        $po->save();

        $this->syncLines($po, $data['lines'] ?? []);

        return response()->json(['order' => $this->presentDetail($po->fresh(['lines.item', 'supplier', 'warehouse']))], 201);
    }

    public function show(PurchaseOrder $purchase): JsonResponse
    {
        $this->authorize('view', $purchase);

        return response()->json(['order' => $this->presentDetail($purchase->load(['lines.item', 'supplier', 'warehouse']))]);
    }

    /** Taslak/teklif aşamasında başlık + satır düzenleme. */
    public function update(Request $request, PurchaseOrder $purchase): JsonResponse
    {
        $this->authorize('update', $purchase);

        if (! in_array($purchase->statusEnum(), [PurchaseStatus::Draft, PurchaseStatus::Quoted], true)) {
            throw ValidationException::withMessages(['status' => ['Sipariş verildikten sonra satırlar değiştirilemez.']]);
        }

        $tenantId = (int) $request->user()->tenant_id;

        $data = $request->validate([
            'warehouse_id' => ['nullable', 'integer', Rule::exists('inv_warehouses', 'id')->where('tenant_id', $tenantId)],
            'expected_at' => ['nullable', 'date'],
            'note' => ['nullable', 'string', 'max:500'],
            'lines' => ['required', 'array', 'min:1'],
            'lines.*.item_id' => ['required', 'integer', Rule::exists('inv_items', 'id')->where('tenant_id', $tenantId)],
            'lines.*.qty' => ['required', 'string'],
            'lines.*.unit_price' => ['required', 'string'],
        ]);

        $purchase->fill([
            'warehouse_id' => $data['warehouse_id'] ?? $purchase->warehouse_id,
            'expected_at' => $data['expected_at'] ?? $purchase->expected_at,
            'note' => $data['note'] ?? $purchase->note,
        ]);
        $purchase->save();

        $purchase->lines()->delete(); // taslak satırları (defter DEĞİL) yeniden kurulur
        $this->syncLines($purchase, $data['lines']);

        return response()->json(['order' => $this->presentDetail($purchase->fresh(['lines.item', 'supplier', 'warehouse']))]);
    }

    /** Durum geçişi: talep→teklif→sipariş→iptal. */
    public function transition(Request $request, PurchaseOrder $purchase): JsonResponse
    {
        $this->authorize('adjust', $purchase);

        $data = $request->validate(['status' => ['required', Rule::in(array_column(PurchaseStatus::cases(), 'value'))]]);

        $po = $this->purchasing->transition($purchase, PurchaseStatus::from($data['status']), $request->user());

        return response()->json(['order' => $this->presentDetail($po->load(['lines.item', 'supplier', 'warehouse']))]);
    }

    /** Mal kabul — stok girer (stock.adjust). */
    public function receive(Request $request, PurchaseOrder $purchase): JsonResponse
    {
        $this->authorize('adjust', $purchase);

        $data = $request->validate([
            'warehouse_id' => ['nullable', 'integer',
                Rule::exists('inv_warehouses', 'id')->where('tenant_id', $request->user()->tenant_id)],
            'lines' => ['required', 'array', 'min:1'],
            'lines.*.line_id' => ['required', 'integer'],
            'lines.*.qty' => ['required', 'string'],
            'lines.*.lot_no' => ['nullable', 'string', 'max:60'],
            'lines.*.expires_at' => ['nullable', 'date'],
        ]);

        $received = array_map(fn (array $l) => [
            'line_id' => (int) $l['line_id'],
            'qty_milli' => Qty::parseToMilli($l['qty']) ?? 0,
            'lot_no' => $l['lot_no'] ?? null,
            'expires_at' => $l['expires_at'] ?? null,
        ], $data['lines']);

        $po = $this->purchasing->receive($purchase, $received, $data['warehouse_id'] ?? null, $request->user());

        return response()->json(['order' => $this->presentDetail($po->load(['supplier', 'warehouse']))]);
    }

    /** Tedarikçiye iade (stock.adjust). */
    public function returnGoods(Request $request, PurchaseOrder $purchase): JsonResponse
    {
        $this->authorize('adjust', $purchase);

        $data = $request->validate([
            'warehouse_id' => ['nullable', 'integer',
                Rule::exists('inv_warehouses', 'id')->where('tenant_id', $request->user()->tenant_id)],
            'reason' => ['required', 'string', 'max:300'],
            'lines' => ['required', 'array', 'min:1'],
            'lines.*.line_id' => ['required', 'integer'],
            'lines.*.qty' => ['required', 'string'],
        ]);

        $returns = array_map(fn (array $l) => [
            'line_id' => (int) $l['line_id'],
            'qty_milli' => Qty::parseToMilli($l['qty']) ?? 0,
        ], $data['lines']);

        $po = $this->purchasing->returnGoods($purchase, $returns, $data['warehouse_id'] ?? null, $data['reason'], $request->user());

        return response()->json(['order' => $this->presentDetail($po->load(['supplier', 'warehouse']))]);
    }

    /** Fatura + ödeme durumu / vade. */
    public function invoice(Request $request, PurchaseOrder $purchase): JsonResponse
    {
        $this->authorize('adjust', $purchase);

        $data = $request->validate([
            'invoice_no' => ['nullable', 'string', 'max:60'],
            'invoice_total' => ['nullable', 'string'],
            'due_date' => ['nullable', 'date'],
            'payment_status' => ['nullable', Rule::in([PurchaseOrder::PAYMENT_UNPAID, PurchaseOrder::PAYMENT_PARTIAL, PurchaseOrder::PAYMENT_PAID])],
            'paid_amount' => ['nullable', 'string'],
        ]);

        if (array_key_exists('invoice_no', $data)) {
            $purchase->invoice_no = $data['invoice_no'];
            $purchase->invoiced_at = $data['invoice_no'] !== null ? now() : null;
        }

        if (array_key_exists('invoice_total', $data) && $data['invoice_total'] !== null) {
            $purchase->invoice_total_minor = Money::parseToMinor($data['invoice_total']) ?? 0;
        }

        if (array_key_exists('due_date', $data)) {
            $purchase->due_date = $data['due_date'];
        }

        if (array_key_exists('paid_amount', $data) && $data['paid_amount'] !== null) {
            $purchase->paid_minor = Money::parseToMinor($data['paid_amount']) ?? 0;
        }

        if (! empty($data['payment_status'])) {
            $purchase->payment_status = $data['payment_status'];
        } elseif ($purchase->invoice_total_minor !== null && (int) $purchase->invoice_total_minor > 0) {
            $purchase->payment_status = (int) $purchase->paid_minor >= (int) $purchase->invoice_total_minor
                ? PurchaseOrder::PAYMENT_PAID
                : ((int) $purchase->paid_minor > 0 ? PurchaseOrder::PAYMENT_PARTIAL : PurchaseOrder::PAYMENT_UNPAID);
        }

        $purchase->save();

        return response()->json(['order' => $this->presentDetail($purchase->load(['lines.item', 'supplier', 'warehouse']))]);
    }

    /** Otomatik önerilen sipariş (min altındakiler, tedarikçiye gruplu). */
    public function suggested(Request $request): JsonResponse
    {
        $this->authorize('viewAny', PurchaseOrder::class);

        return response()->json([
            'suggestions' => $this->purchasing->suggestedOrders((int) $request->user()->tenant_id),
        ]);
    }

    private function syncLines(PurchaseOrder $po, array $lines): void
    {
        foreach ($lines as $lineData) {
            $qtyMilli = Qty::parseToMilli($lineData['qty']);
            $priceMinor = Money::parseToMinor($lineData['unit_price']);

            if ($qtyMilli === null || $qtyMilli <= 0) {
                throw ValidationException::withMessages(['lines' => ['Satır miktarı geçersiz.']]);
            }

            if ($priceMinor === null || $priceMinor < 0) {
                throw ValidationException::withMessages(['lines' => ['Satır birim fiyatı geçersiz.']]);
            }

            $line = new PurchaseOrderLine([
                'item_id' => (int) $lineData['item_id'],
                'qty_milli' => $qtyMilli,
                'unit_price_minor' => $priceMinor,
            ]);
            $line->purchase_order_id = $po->getKey();
            $line->save();
        }
    }

    /** @return array<string, mixed> */
    private function presentSummary(PurchaseOrder $po): array
    {
        return [
            'id' => $po->getKey(),
            'supplier_name' => $po->supplier?->name,
            'warehouse_name' => $po->warehouse?->name,
            'status' => $po->status,
            'status_label' => $po->statusEnum()->label(),
            'status_variant' => $po->statusEnum()->variant(),
            'payment_status' => $po->payment_status,
            'invoice_no' => $po->invoice_no,
            'invoice_total_minor' => $po->invoice_total_minor,
            'paid_minor' => (int) $po->paid_minor,
            'due_date' => $po->due_date?->toDateString(),
            'expected_at' => $po->expected_at?->toDateString(),
            'line_count' => $po->lines_count ?? $po->lines()->count(),
            'created_at' => $po->created_at?->toIso8601String(),
        ];
    }

    /** @return array<string, mixed> */
    private function presentDetail(PurchaseOrder $po): array
    {
        $po->loadMissing('lines.item');

        return $this->presentSummary($po) + [
            'note' => $po->note,
            'warehouse_id' => $po->warehouse_id,
            'supplier_id' => $po->supplier_id,
            'lines' => $po->lines->map(fn (PurchaseOrderLine $l) => [
                'id' => $l->getKey(),
                'item_id' => $l->item_id,
                'item_name' => $l->item?->name,
                'unit' => $l->item?->base_unit,
                'qty_milli' => (int) $l->qty_milli,
                'qty' => Qty::toDecimalString((int) $l->qty_milli),
                'received_qty' => Qty::toDecimalString((int) $l->received_qty_milli),
                'received_qty_milli' => (int) $l->received_qty_milli,
                'returned_qty' => Qty::toDecimalString((int) $l->returned_qty_milli),
                'unit_price_minor' => (int) $l->unit_price_minor,
                'line_total_minor' => Qty::cost((int) $l->qty_milli, (int) $l->unit_price_minor),
            ])->values(),
        ];
    }
}
