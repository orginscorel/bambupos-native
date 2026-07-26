<?php

namespace App\Modules\Orders\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\ServiceRequest;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Tables\Models\Table;
use App\Modules\Venue\Enums\TableStatus;
use App\Modules\Venue\Services\QrTokenResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\Rule;

/**
 * Servis talepleri.
 *
 * PUBLIC (oturumsuz, `Musteri-Menu` bağlanır):
 *   POST /api/v1/public/service-requests  { token, kind: waiter|bill|water }
 *   - Kimlik YALNIZ masa QR token'ı (ADR-008); hız sınırı token+IP;
 *     aynı masadan aynı tür açık talep 2 dk içinde tekrar açılmaz (dedup).
 *   - kind=bill: masadaki açık adisyon(lar) "Hesap istendi"ye taşınır
 *     (makine izin veriyorsa) → masa durumu da BillRequested olur.
 *   - kind=waiter/water: masa boş/oturuluyorsa "Sipariş bekliyor" olur
 *     (ileri aşamadaki masa durumu GERİLETİLMEZ; talep panoda ayrıca görünür).
 *
 * PANEL: garson panosu açık talepleri board yanıtında görür;
 *   POST /api/v1/orders/service-requests/{serviceRequest}/done kapatır.
 */
class ServiceRequestController extends Controller
{
    public function __construct(
        private readonly QrTokenResolver $resolver,
        private readonly OrderService $orders,
        private readonly \App\Modules\Tenancy\TenantContext $context,
        private readonly \App\Modules\Notify\Services\NotifyEmitter $notify,
    ) {
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string', 'max:64'],
            'kind' => ['required', Rule::in(ServiceRequest::KINDS)],
        ]);

        // Hız sınırı: token+IP (NAT gerçeği); dakikada 5 talep.
        $limiterKey = 'service-req:'.sha1($data['token'].'|'.(string) $request->ip());

        if (RateLimiter::tooManyAttempts($limiterKey, 5)) {
            return response()->json([
                'message' => 'Çok sık istek gönderildi. Personel en kısa sürede ilgilenecek.',
            ], 429)->header('Retry-After', (string) RateLimiter::availableIn($limiterKey));
        }

        RateLimiter::hit($limiterKey, 60);

        $resolution = $this->resolver->resolve($data['token'], $request);

        if ($resolution->status === 'revoked' || $resolution->status === 'inactive') {
            return response()->json(['message' => 'Bu QR kod artık geçerli değil.'], 410);
        }

        if ($resolution->status !== 'ok' || $resolution->table === null) {
            return response()->json(['message' => 'Geçersiz QR kod.'], 404);
        }

        $table = $resolution->table;

        // §9 feature-flag: işletme "Garson/su/hesap çağır"ı kapattıysa uç ÇALIŞMAZ
        // (ADR: kapalı=yok). Menüde buton zaten server-render ile gizlenir; bu, uç
        // düzeyi kesin kapıdır. Kimlik token'dan çözülen kiracıdır (istekten gelmez).
        if (! \App\Modules\Settings\Support\Features::enabled((int) $table->tenant_id, 'service_calls')) {
            return response()->json([
                'message' => 'Bu işletmede masadan servis çağrısı alınmıyor. Lütfen personele seslenin.',
            ], 403);
        }

        // Yazma bağlamı: token'dan çözülen kiracı (ADR-008/ADR-004) —
        // OrderService tenant-scope'lu sorgular kullanır (fail-closed).
        $this->context->setTenant((int) $table->tenant_id);

        try {
            return $this->handleStore($request, $table, $data);
        } finally {
            $this->context->forget();
        }
    }

    /** @param array{token: string, kind: string} $data */
    private function handleStore(Request $request, Table $table, array $data): JsonResponse
    {
        // Dedup: aynı masadan aynı tür AÇIK talep son 2 dk içinde varsa çoğaltma.
        $existing = ServiceRequest::withoutTenancy()
            ->where('tenant_id', $table->tenant_id)
            ->where('table_id', $table->getKey())
            ->where('kind', $data['kind'])
            ->where('status', 'open')
            ->where('created_at', '>=', now()->subMinutes(2))
            ->first();

        if ($existing !== null) {
            return response()->json([
                'request' => $this->presentPublic($existing),
                'deduplicated' => true,
            ]);
        }

        $sr = new ServiceRequest(['kind' => $data['kind'], 'status' => 'open']);
        $sr->tenant_id = $table->tenant_id;
        $sr->branch_id = $table->branch_id;
        $sr->table_id = $table->getKey();
        $sr->save();

        $this->reflectToTable($table, $data['kind']);

        // §8 Bildirim: o şubenin garsonları + yönetici (in-app zil + push).
        // Best-effort — NotifyEmitter yutar, public akış bozulmaz.
        $sr->setRelation('table', $table);
        $this->notify->serviceRequested($sr);

        return response()->json(['request' => $this->presentPublic($sr), 'deduplicated' => false], 201);
    }

    /** Talep türü → masa/sipariş durumu (görev §3 zinciriyle uyumlu). */
    private function reflectToTable(Table $table, string $kind): void
    {
        if ($kind === 'bill') {
            $openOrders = Order::withoutTenancy()
                ->where('tenant_id', $table->tenant_id)
                ->where('table_id', $table->getKey())
                ->whereNotIn('status', OrderStatus::closedValues())
                ->get();

            $transitioned = false;

            foreach ($openOrders as $order) {
                if ($order->statusEnum()->canTransitionTo(OrderStatus::BillRequested)) {
                    $this->orders->transition($order, OrderStatus::BillRequested, null);
                    $transitioned = true;
                }
            }

            if (! $transitioned) {
                // Açık adisyon yoksa/geçiş yoksa masa yine de işaretlenir.
                $table->status = TableStatus::BillRequested;
                $table->save();
            }

            return;
        }

        // waiter / water: yalnız boş/oturuluyor masayı "Sipariş bekliyor" yap;
        // ileri aşamadaki durumu geriletme (talep panoda zaten görünür).
        $current = $table->status instanceof TableStatus ? $table->status : TableStatus::tryFrom((string) $table->status);

        if (in_array($current, [TableStatus::Available, TableStatus::Occupied, TableStatus::Cleaning], true)) {
            $table->status = TableStatus::AwaitingOrder;
            $table->save();
        }
    }

    /** Garson panosu: talebi kapat. */
    public function done(Request $request, ServiceRequest $serviceRequest): JsonResponse
    {
        $this->authorize('viewAny', Order::class); // orders.view yeterli (operasyonel kapatma)
        // ŞUBE KAPSAMI: yalnız geçerli şubenin talebi kapatılabilir.
        abort_unless(
            (int) $serviceRequest->branch_id === (int) app(\App\Modules\Tenancy\BranchContext::class)->currentBranchId(),
            403
        );

        if ($serviceRequest->status !== 'done') {
            $serviceRequest->status = 'done';
            $serviceRequest->handled_by_id = $request->user()->getKey();
            $serviceRequest->handled_at = now();
            $serviceRequest->save();
        }

        return response()->json(['ok' => true]);
    }

    /** @return array<string, mixed> Public görünüm — iç kimlik sızmaz. */
    private function presentPublic(ServiceRequest $sr): array
    {
        return [
            'kind' => $sr->kind,
            'kind_label' => $sr->kindLabel(),
            'status' => $sr->status,
            'created_at' => $sr->created_at?->toIso8601String(),
        ];
    }
}
