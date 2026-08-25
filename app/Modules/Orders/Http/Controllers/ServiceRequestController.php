<?php

namespace App\Modules\Orders\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Models\Product;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\ServiceRequest;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Orders\Services\TableStatusSynchronizer;
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
        private readonly TableStatusSynchronizer $tableSync,
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

        // §9 feature-flag: işletme ilgili eklentiyi kapattıysa uç ÇALIŞMAZ (ADR: kapalı=yok).
        // Şarjmatik AYRI eklentidir ('sarjmatik'); garson/su/hesap 'service_calls'. Menüde
        // buton zaten server-render ile gizlenir; bu, uç düzeyi kesin kapıdır.
        $feature = $data['kind'] === 'sarjmatik' ? 'sarjmatik' : 'service_calls';
        if (! \App\Modules\Settings\Support\Features::enabled((int) $table->tenant_id, $feature)) {
            return response()->json([
                'message' => 'Bu işletmede bu talep alınmıyor. Lütfen personele seslenin.',
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
        // Şarjmatik: yalnız talep + bildirim; masa/adisyon durumunu DEĞİŞTİRMEZ.
        if ($kind === 'sarjmatik') {
            return;
        }

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
                // Açık adisyon yok (ya da hiçbiri BillRequested'e geçemedi, ör.
                // zaten PartiallyPaid) — durumu BURADA İCAT ETMEYİZ. TableStatusSynchronizer
                // masa durumunu her zaman AÇIK SİPARİŞLERDEN türetir (kural §Sipariş
                // olayları → masa durumu): açık adisyon yoksa masa Available'a döner
                // (Reserved/OutOfService ezilmez), varsa gerçek en-ileri durumuna göre
                // ayarlanır. Eski davranış burada doğrudan `BillRequested` yazıyordu;
                // adisyonsuz bir masada bu YAZI HİÇBİR sipariş olayınca bir daha
                // tetiklenmediğinden masa sonsuza dek "Hesap istendi" kilidinde kalıyordu.
                $this->tableSync->sync($table);
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

            // Şarjmatik onaylanınca: masanın açık adisyonuna gizli 0₺ "Şarjmatik"
            // kalemi ekle (kayıt + olay günlüğü). Müşteriye görünmez ürün; yalnız
            // burada hizmetin sağlandığını belgeler.
            if ($serviceRequest->kind === 'sarjmatik') {
                $this->provideSarjmatik($serviceRequest, $request->user());
            }
        }

        return response()->json(['ok' => true]);
    }

    /**
     * Şarjmatik hizmetini kayda geçir: gizli 0₺ ürünü masanın açık adisyonuna
     * ekle ("Şarjmatik hizmeti sağlandı" notuyla) + hemen servis edildi işaretle
     * (KDS'i meşgul etmesin). Masanın açık adisyonu yoksa (adisyon açılmadan
     * şarjmatik istenmişse) sessizce atlanır — talebin kapanışı yine de geçerli.
     */
    private function provideSarjmatik(ServiceRequest $sr, \App\Modules\Identity\Models\User $actor): void
    {
        try {
            if ($sr->tenant_id === null || $sr->table_id === null) {
                return;
            }

            $order = Order::query()
                ->where('tenant_id', $sr->tenant_id)
                ->where('table_id', $sr->table_id)
                ->whereNotIn('status', OrderStatus::closedValues())
                ->orderByDesc('id')
                ->first();

            if ($order === null) {
                return; // açık adisyon yok → faturalanacak yer yok
            }

            $product = $this->resolveSarjmatikProduct((int) $sr->tenant_id);

            $item = $this->orders->addItem($order, [
                'product_id' => (int) $product->getKey(),
                'qty' => 1,
                'note' => 'Şarjmatik hizmeti sağlandı',
            ], $actor);

            // Hizmet kalemi hazırlık gerektirmez → doğrudan "servis edildi".
            $this->orders->setItemStatus($order, $item, OrderItemStatus::Served, $actor);
        } catch (\Throwable) {
            // yut — talebin kapanışı bozulmasın
        }
    }

    /**
     * Gizli "Şarjmatik" ürünü: kiracıya bir kez otomatik tanımlanır. Fiyat 0₺;
     * channels=['pos'] → QR menüde GÖRÜNMEZ (public menü 'qr' içermeyen ürünü
     * eler) ama panelde/kasada kullanılabilir.
     */
    private function resolveSarjmatikProduct(int $tenantId): Product
    {
        $product = Product::query()
            ->where('tenant_id', $tenantId)
            ->where('sku', 'SARJMATIK')
            ->first();

        if ($product !== null) {
            return $product;
        }

        $product = new Product();
        $product->tenant_id = $tenantId;
        $product->branch_id = null;
        $product->category_id = null;
        $product->name = 'Şarjmatik';
        $product->sku = 'SARJMATIK';
        $product->description = 'Taşınabilir şarj cihazı hizmeti (gizli servis kalemi).';
        $product->price_minor = 0;
        $product->currency = config('app.currency', 'TRY');
        $product->tax_rate = 0;
        $product->is_active = true;
        $product->is_available = true;
        $product->channels = ['pos'];
        $product->station = null;
        $product->track_stock = false;
        $product->save();

        return $product;
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
