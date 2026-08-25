<?php

namespace App\Modules\Receivables\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Support\OrderPresenter;
use App\Modules\Receivables\Models\Receivable;
use App\Modules\Receivables\Services\ReceivableService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Borçlar/Cari panel API'si. Tüm sorgular tenant-scope'lu; mutasyonlar
 * ReceivableService'te (transaction + kilit — CashSessionService deseni).
 */
class ReceivableController extends Controller
{
    use \App\Modules\Tenancy\Concerns\ScopesToBranch;

    public function __construct(private readonly ReceivableService $receivables)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Receivable::class);

        // ŞUBE KAPSAMI: geçerli şubenin carileri + kiracı-geneli (şubesiz) cariler.
        $branchId = $this->currentBranchId();
        $query = Receivable::query()
            ->where(fn ($q) => $q->whereNull('branch_id')->orWhere('branch_id', $branchId))
            ->withCount(['orders as open_debt_orders_count' => function ($q): void {
                $q->where('status', 'debt_transferred');
            }]);

        if ($request->filled('q')) {
            $needle = '%'.str_replace(['%', '_'], ['\\%', '\\_'], (string) $request->query('q')).'%';
            $query->where(function ($w) use ($needle): void {
                $w->where('name', 'like', $needle)
                    ->orWhere('phone', 'like', $needle)
                    ->orWhere('email', 'like', $needle);
            });
        }

        if ($request->boolean('only_debtors')) {
            $query->where('balance_minor', '>', 0);
        }

        if (! $request->boolean('include_inactive')) {
            $query->where('is_active', true);
        }

        $receivables = $query->orderByDesc('balance_minor')->orderBy('name')
            ->paginate(min((int) $request->query('per_page', 50), 200));

        $receivables->getCollection()->transform(fn (Receivable $r): array => $this->present($r));

        return response()->json(['receivables' => $receivables]);
    }

    public function show(Request $request, Receivable $receivable): JsonResponse
    {
        $this->authorize('view', $receivable);

        // Kalemler de yüklenir: cari detayında "hangi tarihte ne yenmiş/içilmiş"
        // sorusunun yanıtı burada. Aylardır her gün gelen bir müşteride yalnız
        // adisyon numarası ve tutar görmek işe yaramıyordu — itiraz halinde
        // kalem dökümü olmadan borcun neden o kadar olduğu savunulamıyor.
        $receivable->load(['transactions.performedBy:id,name', 'orders' => function ($q): void {
            $q->where('status', 'debt_transferred')
                ->with(['table:id,name,number', 'items'])
                ->orderByDesc('id');
        }]);

        return response()->json([
            'receivable' => $this->present($receivable),
            'transactions' => $receivable->transactions->map(fn ($t) => [
                'id' => $t->id,
                'type' => $t->type,
                'amount_minor' => (int) $t->amount_minor,
                'method' => $t->method,
                'note' => $t->note,
                'balance_after_minor' => (int) $t->balance_after_minor,
                'order_id' => $t->order_id,
                'performed_by' => $t->performedBy?->name,
                'created_at' => $t->created_at?->toIso8601String(),
            ])->values()->all(),
            'debt_orders' => $receivable->orders->map(fn (Order $o) => array_merge(
                OrderPresenter::summary($o),
                [
                    // Kompakt kalem dökümü (iptal edilenler hariç): adet + ad +
                    // varyant + satır tutarı. Tam detay payload'ı (olaylar,
                    // seçenekler) burada GEREKSİZ ağırlık yapardı.
                    'items' => $o->items
                        ->filter(fn ($i) => $i->statusEnum()->isActive())
                        ->map(fn ($i) => [
                            'id' => $i->id,
                            'qty' => (int) $i->qty,
                            'name' => $i->name,
                            'variant_name' => $i->variant_name,
                            'is_comp' => (bool) $i->is_comp,
                            'line_total_minor' => (int) $i->line_total_minor,
                        ])->values()->all(),
                ],
            ))->values()->all(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Receivable::class);

        $data = $request->validate([
            'name' => ['required', 'string', 'min:2', 'max:150'],
            'phone' => ['nullable', 'string', 'max:32'],
            'email' => ['nullable', 'email', 'max:150'],
            'note' => ['nullable', 'string', 'max:500'],
        ]);

        // ŞUBE KAPSAMI: cari DAİMA geçerli şubede oluşturulur — istekten
        // gelen branch_id ASLA güvenilmez (OrderController/ScheduleController
        // ile aynı desen: türetilir, alınmaz).
        $data['branch_id'] = $this->currentBranchId();

        $receivable = $this->receivables->create($data, $request->user());

        return response()->json(['receivable' => $this->present($receivable)], 201);
    }

    public function update(Request $request, Receivable $receivable): JsonResponse
    {
        $this->authorize('update', $receivable);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'min:2', 'max:150'],
            'phone' => ['nullable', 'string', 'max:32'],
            'email' => ['nullable', 'email', 'max:150'],
            'note' => ['nullable', 'string', 'max:500'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        // ŞUBE KAPSAMI: branch_id bu uçtan hiç değiştirilemez — istekten
        // gelen değer okunmaz/uygulanmaz bile (cari başka şubeye taşınamaz).

        $receivable = $this->receivables->update($receivable, $data);

        return response()->json(['receivable' => $this->present($receivable)]);
    }

    /** Tahsilat (tam/kısmi). Aşırı tahsilat servis katmanında reddedilir. */
    public function collect(Request $request, Receivable $receivable): JsonResponse
    {
        $this->authorize('collect', $receivable);

        $data = $request->validate([
            'amount_minor' => ['required', 'integer', 'min:1'],
            'method' => ['required', Rule::in(['cash', 'card', 'transfer', 'other'])],
            'note' => ['nullable', 'string', 'max:500'],
        ]);

        $this->receivables->collect($receivable, (int) $data['amount_minor'], $data['method'], $data['note'] ?? null, $request->user());

        return response()->json(['receivable' => $this->present($receivable->fresh())]);
    }

    /**
     * "Adisyonu borca taşı" — Payments modülünün orders/{order}/payments
     * deseniyle AYNI: Orders'a ait bir eylem ama Receivables rotasında
     * yaşar (routes/receivables.php — kendi rota dosyam).
     */
    public function transferOrder(Request $request, Order $order): JsonResponse
    {
        $this->authorize('transfer', Receivable::class);

        $data = $request->validate([
            'receivable_id' => ['required', 'integer'],
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $receivable = Receivable::query()->find((int) $data['receivable_id']); // tenant-scoped

        if ($receivable === null) {
            throw ValidationException::withMessages(['receivable_id' => ['Cari bulunamadı.']]);
        }

        $this->receivables->transferOrderToDebt($order, $receivable, $data['reason'], $request->user(), $data['expected_version'] ?? null);

        $fresh = Order::query()
            ->with(['items.options', 'events.user', 'table:id,name,number', 'openedBy:id,name'])
            ->findOrFail($order->getKey());

        return response()->json(['order' => OrderPresenter::detail($fresh)]);
    }

    /** @return array<string, mixed> */
    private function present(Receivable $r): array
    {
        return [
            'id' => $r->id,
            'branch_id' => $r->branch_id,
            'name' => $r->name,
            'phone' => $r->phone,
            'email' => $r->email,
            'note' => $r->note,
            'balance_minor' => (int) $r->balance_minor,
            'balance_display' => \App\Modules\Catalog\Support\Money::toDecimalString((int) $r->balance_minor),
            'is_active' => (bool) $r->is_active,
            'open_debt_orders_count' => (int) ($r->open_debt_orders_count ?? 0),
            'created_at' => $r->created_at?->toIso8601String(),
        ];
    }
}
