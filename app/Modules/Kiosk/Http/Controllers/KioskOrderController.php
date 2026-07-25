<?php

namespace App\Modules\Kiosk\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Support\Money;
use App\Modules\Kiosk\Models\KioskDevice;
use App\Modules\Kiosk\Services\KioskActor;
use App\Modules\Kiosk\Services\KioskTokenResolver;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Services\IdempotencyStore;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Payments\Enums\PaymentStatus;
use App\Modules\Payments\Models\Payment;
use App\Modules\Payments\Services\PaymentService;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;

/**
 * Kiosk sipariş + ödeme akışı (Faz 8, §18/§22).
 *
 * POST /kiosk/api/orders
 *   Kimlik YALNIZ kiosk cihaz token'ı; kiracı/şube token'dan çözülür,
 *   istekten asla alınmaz. Sipariş kanal=kiosk açılır (Placed), cihaz
 *   `kiosk_pos` modundaysa tutarın TAMAMI mock POS adapter'ından tahsil
 *   edilir (Payments modülü — GERÇEK ödeme yok):
 *     - onay  → sipariş kesinleşir; fiş (sipariş no) döner.
 *     - red   → sipariş iptal edilir; DÜRÜST hata döner (sahte başarı yok).
 *     - belirsiz (timeout/pending/ağ) → ödeme Pending kalır; istemci
 *       /kiosk/api/payments/query ile netleştirir. Online doğrulama olmadan
 *       ödeme ASLA başarılı sayılmaz (§22).
 *   `counter` modunda ödeme alınmaz; "kasada ödeyin" fişi döner.
 *
 * `Idempotency-Key` desteklenir: sipariş + ödeme girişimi tek atomik iş
 * olarak saklanır; çift dokunma/ağ tekrarı ne siparişi ne tahsilatı çoğaltır.
 */
class KioskOrderController extends Controller
{
    public function __construct(
        private readonly KioskTokenResolver $resolver,
        private readonly OrderService $orders,
        private readonly PaymentService $payments,
        private readonly IdempotencyStore $idempotency,
        private readonly KioskActor $actor,
        private readonly TenantContext $context,
    ) {
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string', 'max:64'],
            'order_type' => ['required', 'in:dine_in,takeaway,package'],
            'table_id' => ['required_if:order_type,dine_in', 'nullable', 'integer'],
            'customer_name' => ['nullable', 'string', 'max:120'],
            'note' => ['nullable', 'string', 'max:500'],
            'items' => ['required', 'array', 'min:1', 'max:50'],
            'items.*.product_id' => ['required', 'integer'],
            'items.*.variant_id' => ['nullable', 'integer'],
            'items.*.qty' => ['required', 'integer', 'min:1', 'max:50'],
            'items.*.note' => ['nullable', 'string', 'max:255'],
            'items.*.option_ids' => ['sometimes', 'array', 'max:30'],
            'items.*.option_ids.*' => ['integer'],
        ]);

        // NAT gerçeği (ADR-008): anahtar token+IP ikilisi.
        $limiterKey = 'kiosk-order:'.sha1($data['token'].'|'.(string) $request->ip());
        $perMinute = (int) config('kiosk.order_rate_per_minute', 10);

        if (RateLimiter::tooManyAttempts($limiterKey, $perMinute)) {
            return response()->json([
                'message' => 'Çok sık istek gönderildi. Lütfen biraz bekleyin.',
            ], 429)->header('Retry-After', (string) RateLimiter::availableIn($limiterKey));
        }

        RateLimiter::hit($limiterKey, 60);

        $device = $this->resolveDeviceOrFail($data['token'], $fail);

        if ($device === null) {
            return $fail;
        }

        // Masada servis: masa BU CİHAZIN şubesine ait ve aktif olmalı.
        $tableLabel = null;

        if ($data['order_type'] === 'dine_in') {
            $table = DB::table('tables')
                ->where('tenant_id', $device->tenant_id)
                ->where('branch_id', $device->branch_id)
                ->where('is_active', true)
                ->where('id', (int) $data['table_id'])
                ->first(['id', 'name', 'number']);

            if ($table === null) {
                return response()->json([
                    'message' => 'Seçilen masa bu şubede bulunamadı.',
                    'errors' => ['table_id' => ['Seçilen masa bu şubede bulunamadı.']],
                ], 422);
            }

            $tableLabel = trim((string) $table->name.($table->number !== null ? ' · '.$table->number : ''));
        }

        $this->context->setTenant((int) $device->tenant_id);

        try {
            [$response, $status, $replayed] = $this->idempotency->run(
                (int) $device->tenant_id,
                $request->header('Idempotency-Key'),
                'kiosk.orders.store',
                fn (): array => $this->placeAndPay($device, $data, $tableLabel),
            );
        } finally {
            $this->context->forget();
        }

        return response()->json($response + ['replayed' => $replayed], $replayed ? 200 : $status);
    }

    /**
     * Bekleyen POS ödemesini sağlayıcıdan SORGULAYARAK netleştirir.
     * (Mock'ta ..98 senaryosu: terminal sustu ama işlem aslında onaylı.)
     */
    public function queryPayment(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string', 'max:64'],
            'reference' => ['required', 'string', 'max:40'],
        ]);

        $limiterKey = 'kiosk-payquery:'.sha1($data['token'].'|'.(string) $request->ip());

        if (RateLimiter::tooManyAttempts($limiterKey, 30)) {
            return response()->json(['message' => 'Çok sık istek.'], 429);
        }

        RateLimiter::hit($limiterKey, 60);

        $device = $this->resolveDeviceOrFail($data['token'], $fail);

        if ($device === null) {
            return $fail;
        }

        /** @var Payment|null $payment */
        $payment = Payment::withoutTenancy()
            ->where('tenant_id', $device->tenant_id)
            ->where('branch_id', $device->branch_id)
            ->where('reference', strtoupper(trim($data['reference'])))
            ->where('kind', 'payment')
            ->first();

        if ($payment === null) {
            return response()->json(['message' => 'Ödeme kaydı bulunamadı.'], 404);
        }

        /** @var Order|null $order */
        $order = Order::withoutTenancy()->with('items.options')->find($payment->order_id);

        if ($order === null || $order->channelEnum()->value !== 'kiosk') {
            // Kiosk yalnız kendi kanalının ödemesini sorgulayabilir.
            return response()->json(['message' => 'Ödeme kaydı bulunamadı.'], 404);
        }

        $this->context->setTenant((int) $device->tenant_id);

        try {
            if ($payment->statusEnum() === PaymentStatus::Pending) {
                ['payment' => $payment] = $this->payments->queryAndSettle($payment, null);
                $order = $order->fresh(['items.options']);
            }

            return $this->paymentOutcome($device, $order, $payment);
        } finally {
            $this->context->forget();
        }
    }

    /* =========================================================
     |  İç akış
     * ========================================================= */

    /**
     * Sipariş açılışı + kalemler + (modda varsa) POS tahsilatı.
     * IdempotencyStore sözleşmesi: [yanıt, statusCode] döner.
     *
     * @param  array<string, mixed>  $data
     * @return array{0: array<string, mixed>, 1: int}
     */
    private function placeAndPay(KioskDevice $device, array $data, ?string $tableLabel): array
    {
        $actor = $this->actor->forDevice($device);

        $typeLabel = match ($data['order_type']) {
            'dine_in' => 'Masada servis',
            'takeaway' => 'Gel-al',
            default => 'Paket',
        };

        // Kiosk kanalı masaya bağlanmaz (OrderChannel::usesTable() = false);
        // servis tipi + masa, personelin göreceği nota yazılır (bilinen sınır —
        // rapor: Orders modülü kiosk+masa ilişkisini ileride taşıyabilir).
        $noteParts = array_filter([
            $typeLabel.($tableLabel !== null ? ' · Masa: '.$tableLabel : ''),
            isset($data['note']) && trim((string) $data['note']) !== '' ? trim((string) $data['note']) : null,
        ]);

        // Açılış + kalemler TEK transaction: herhangi bir kalem reddedilirse
        // (yabancı ürün, kanal kapalı, tükendi…) sipariş İZ BIRAKMADAN geri
        // alınır — panelde hayalet boş adisyon kalmaz. Sağlayıcı çağrısı
        // (ödeme) bilinçli olarak transaction DIŞINDADIR (ADR-010).
        $order = DB::transaction(function () use ($device, $data, $actor, $noteParts): Order {
            $order = $this->orders->open([
                'branch_id' => (int) $device->branch_id,
                'channel' => 'kiosk',
                'note' => implode(' — ', $noteParts),
                'customer_name' => $data['customer_name'] ?? null,
            ], $actor);

            foreach ($data['items'] as $itemData) {
                $this->orders->addItem($order, [
                    'product_id' => (int) $itemData['product_id'],
                    'variant_id' => isset($itemData['variant_id']) ? (int) $itemData['variant_id'] : null,
                    'qty' => (int) $itemData['qty'],
                    'note' => $itemData['note'] ?? null,
                    'option_ids' => array_map('intval', $itemData['option_ids'] ?? []),
                ], null);
            }

            return $order;
        });

        $order = $order->fresh(['items.options']);
        $total = (int) $order->total_minor;

        // Kasada ödeme modu veya sıfır tutar: tahsilat kioskta YAPILMAZ.
        if ($device->payment_mode !== KioskDevice::MODE_KIOSK_POS || $total <= 0) {
            return [[
                'result' => 'placed_pay_at_counter',
                'message' => 'Siparişiniz alındı. Lütfen kasada ödeyiniz.',
                'receipt' => $this->receipt($device, $order, null, $data['order_type'], $tableLabel),
            ], 201];
        }

        // Mock POS tahsilatı — tutarın tamamı, tek çekim (ADR-010 akışı).
        ['payment' => $payment] = $this->payments->pay($order, [
            'method' => 'credit_card',
            'amount_minor' => $total,
            'provider' => 'mock',
            'terminal_id' => 'KIOSK-'.$device->getKey(),
            'note' => 'Kiosk: '.$device->name,
        ], $actor);

        $order = $order->fresh(['items.options']);

        $outcome = $this->paymentOutcome($device, $order, $payment);

        return [$outcome->getData(true), $outcome->getStatusCode()];
    }

    /**
     * Ödeme sonucunu DÜRÜSTÇE haritalar (tek yer):
     *  succeeded → fiş; failed → sipariş iptal + 402; pending → 202.
     */
    private function paymentOutcome(KioskDevice $device, Order $order, Payment $payment): JsonResponse
    {
        $payment = $payment->fresh() ?? $payment;

        if ($payment->statusEnum() === PaymentStatus::Succeeded) {
            return response()->json([
                'result' => 'paid',
                'message' => 'Ödeme alındı. Afiyet olsun!',
                'receipt' => $this->receipt($device, $order, $payment, null, null),
            ], 201);
        }

        if ($payment->statusEnum() === PaymentStatus::Pending) {
            return response()->json([
                'result' => 'payment_pending',
                'message' => 'Ödeme doğrulanıyor. Lütfen bekleyin…',
                'reference' => $payment->reference,
            ], 202);
        }

        // Failed / Cancelled: tahsilat yok → siparişi iptal et (mutfağa gitmesin).
        $this->cancelUnpaidQuietly($device, $order);

        $reason = trim((string) ($payment->reason ?? ''));

        return response()->json([
            'result' => 'payment_failed',
            'message' => 'Ödeme alınamadı'.($reason !== '' ? ': '.$reason : '.').' Sipariş gönderilmedi.',
        ], 402);
    }

    /** Ödenmemiş kiosk siparişini iptal eder; edemezse siparişi olduğu gibi bırakır. */
    private function cancelUnpaidQuietly(KioskDevice $device, Order $order): void
    {
        try {
            $fresh = $order->fresh();

            if ($fresh !== null && (int) $fresh->paid_minor === 0 && $fresh->statusEnum()->isOpen()) {
                $this->orders->cancel($fresh, 'Kiosk: ödeme reddedildi', $this->actor->forDevice($device));
            }
        } catch (\Throwable) {
            // İptal edilemeyen sipariş panelde açık kalır; personel çözer (dürüst iz).
        }
    }

    /**
     * Fiş: müşteri ekranına basılacak özet. İç kimliklerden yalnız sipariş
     * numarası (personelin panelde gördüğü #id) yer alır.
     *
     * @return array<string, mixed>
     */
    private function receipt(KioskDevice $device, Order $order, ?Payment $payment, ?string $orderType, ?string $tableLabel): array
    {
        return [
            'order_no' => (int) $order->getKey(),
            'status' => $order->statusEnum()->value,
            'status_label' => $order->statusEnum()->label(),
            'branch' => \App\Modules\Tenancy\Models\Branch::withoutTenancy()->find($device->branch_id)?->name,
            'items' => $order->items->map(fn ($i) => [
                'name' => $i->name.($i->variant_name !== null ? ' ('.$i->variant_name.')' : ''),
                'qty' => (int) $i->qty,
                'line_total_minor' => (int) $i->line_total_minor,
                'options' => $i->options->map(fn ($o) => $o->option_name)->values()->all(),
            ])->values()->all(),
            'total_minor' => (int) $order->total_minor,
            'total_display' => Money::toDecimalString((int) $order->total_minor),
            'paid' => (int) $order->paid_minor >= (int) $order->total_minor && (int) $order->total_minor > 0,
            'pay_at_counter' => $payment === null,
            'payment' => $payment === null ? null : [
                'reference' => $payment->reference,
                'method' => (string) $payment->method,
                'status' => $payment->statusEnum()->value,
                'auth_code' => is_array($payment->meta) ? ($payment->meta['settle']['auth_code'] ?? null) : null,
            ],
            'created_at' => $order->created_at?->toIso8601String(),
        ];
    }

    /**
     * Cihaz token'ını çözer; başarısızsa $fail'e DÜRÜST JSON yanıt koyar.
     */
    private function resolveDeviceOrFail(string $token, ?JsonResponse &$fail): ?KioskDevice
    {
        $res = $this->resolver->resolve($token);

        if ($res['status'] === 'ok') {
            $fail = null;

            return $res['device'];
        }

        $fail = match ($res['status']) {
            'locked' => response()->json(['message' => 'Bu kiosk geçici olarak kilitli. Lütfen personele başvurun.'], 423),
            'revoked', 'inactive' => response()->json(['message' => 'Bu kiosk kaydı artık geçerli değil. Lütfen personele başvurun.'], 410),
            default => response()->json(['message' => 'Geçersiz kiosk.'], 404),
        };

        return null;
    }
}
