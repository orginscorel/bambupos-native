<?php

namespace App\Modules\Orders\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Services\IdempotencyStore;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Orders\Support\OrderPresenter;
use App\Modules\Tenancy\TenantContext;
use App\Modules\Venue\Services\QrTokenResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;

/**
 * PUBLIC (oturumsuz) QR sipariş ucu — `Musteri-Menu` ajanı buraya bağlanır.
 *
 * POST /api/v1/public/orders
 *   Kimlik: YALNIZ masa QR token'ı (ADR-008); istekten tenant/branch/table
 *   id'si asla kabul edilmez. Sipariş "Onay bekliyor" durumunda açılır,
 *   garson panelde onaylar. `Idempotency-Key` başlığı desteklenir (çift
 *   dokunma / ağ tekrarı sipariş çoğaltmaz).
 *
 * GET /api/v1/public/orders/{publicToken}?token={qrToken}
 *   Müşterinin sipariş durumu takibi (10 sn polling — ADR-006). Çift
 *   anahtar (sipariş public_token + masanın QR token'ı) ister.
 */
class PublicOrderController extends Controller
{
    public function __construct(
        private readonly QrTokenResolver $resolver,
        private readonly OrderService $orders,
        private readonly IdempotencyStore $idempotency,
        private readonly TenantContext $context,
    ) {
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string', 'max:64'],
            'note' => ['nullable', 'string', 'max:500'],
            'customer_name' => ['nullable', 'string', 'max:120'],
            'items' => ['required', 'array', 'min:1', 'max:50'],
            'items.*.product_id' => ['required', 'integer'],
            'items.*.variant_id' => ['nullable', 'integer'],
            'items.*.qty' => ['required', 'integer', 'min:1', 'max:50'],
            'items.*.note' => ['nullable', 'string', 'max:255'],
            'items.*.option_ids' => ['sometimes', 'array', 'max:30'],
            'items.*.option_ids.*' => ['integer'],
        ]);

        // NAT gerçeği (ADR-008): anahtar token+IP ikilisi, IP tek başına değil.
        $limiterKey = 'public-order:'.sha1($data['token'].'|'.(string) $request->ip());
        $perMinute = (int) config('orders.public_rate_per_minute', 10);

        if (RateLimiter::tooManyAttempts($limiterKey, $perMinute)) {
            return response()->json([
                'message' => 'Çok sık istek gönderildi. Lütfen biraz bekleyin.',
            ], 429)->header('Retry-After', (string) RateLimiter::availableIn($limiterKey));
        }

        RateLimiter::hit($limiterKey, 60);

        $resolution = $this->resolver->resolve($data['token'], $request);

        if ($resolution->status === 'revoked' || $resolution->status === 'inactive') {
            return response()->json(['message' => 'Bu QR kod artık geçerli değil. Lütfen personelden yeni kodu isteyin.'], 410);
        }

        if ($resolution->status !== 'ok' || $resolution->table === null) {
            // Şube token'ı ile sipariş verilemez (masa gerekir).
            return response()->json(['message' => 'Geçersiz QR kod.'], 404);
        }

        $table = $resolution->table;

        // §9 feature-flag: işletme "QR menüden sipariş"i kapattıysa menü yalnız
        // görüntülenir, sipariş ALINMAZ (ADR: kapalı=yok). Kimlik token'dan
        // çözülen kiracıdır (istekten asla gelmez).
        if (! \App\Modules\Settings\Support\Features::enabled((int) $table->tenant_id, 'qr_ordering')) {
            return response()->json([
                'message' => 'Bu işletmede QR menüden sipariş alınmıyor. Lütfen personelden yardım isteyin.',
            ], 403);
        }

        // Yazma bağlamı: token'dan çözülen kiracı (ADR-008/ADR-004).
        $this->context->setTenant((int) $table->tenant_id);

        try {
            [$response, $status, $replayed] = $this->idempotency->run(
                (int) $table->tenant_id,
                $request->header('Idempotency-Key'),
                'public.orders.store',
                function () use ($table, $data): array {
                    $order = $this->orders->createPublicOrder($table, $data);
                    $order->load(['items.options']);

                    return [['order' => OrderPresenter::publicView($order)], 201];
                },
            );
        } finally {
            $this->context->forget();
        }

        return response()->json($response + ['replayed' => $replayed], $replayed ? 200 : $status);
    }

    public function show(Request $request, string $publicToken): JsonResponse
    {
        $qrToken = (string) $request->query('token', '');

        $resolution = $this->resolver->resolve($qrToken, $request);

        if ($resolution->status !== 'ok' || $resolution->table === null) {
            return response()->json(['message' => 'Geçersiz istek.'], 404);
        }

        $order = Order::withoutTenancy()
            ->with(['items.options'])
            ->where('tenant_id', $resolution->table->tenant_id)
            ->where('table_id', $resolution->table->getKey())
            ->where('public_token', strtoupper(trim($publicToken)))
            ->first();

        if ($order === null) {
            return response()->json(['message' => 'Sipariş bulunamadı.'], 404);
        }

        return response()->json(['order' => OrderPresenter::publicView($order)])
            ->header('X-LiteSpeed-Cache-Control', 'no-cache'); // durum canlıdır, cache'lenmez
    }
}
