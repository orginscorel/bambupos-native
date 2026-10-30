<?php

namespace App\Modules\Orders\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\PinService;
use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Enums\ServiceType;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderItem;
use App\Modules\Orders\Services\IdempotencyStore;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Orders\Support\OrderPresenter;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Panel sipariş API'si (garson ekranları). Tüm sorgular tenant-scope'lu;
 * mutasyonlar OrderService'te (transaction + kilit + sürüm + idempotency).
 */
class OrderController extends Controller
{
    use \App\Modules\Tenancy\Concerns\ScopesToBranch;

    public function __construct(
        private readonly OrderService $orders,
        private readonly IdempotencyStore $idempotency,
        private readonly \App\Modules\Terminal\Services\TerminalPinGate $pinGate,
        // Offline-kuyruk idempotency (op_id gövdede; header'dan bağımsız —
        // bkz. addItem + docs/offline-sync-protocol.md). SADECE addItem'de
        // kullanılır (PROOF); diğer uçlar bugünkü davranışını korur.
        private readonly \App\Support\Idempotency\IdempotentRequest $opIdempotency,
        // setItemStatus'ün KDS durumlarını (accepted/preparing/ready/served)
        // KdsActionController İLE AYNI izin+istasyon-kapsamı kuralıyla
        // uygulaması için (istasyon-yönlendirme denetimi 2026-08-06).
        private readonly \App\Modules\Kds\Services\KdsService $kds,
        // Boş adisyon silindiğinde masa durumunu yeniden hesaplar.
        private readonly \App\Modules\Orders\Services\TableStatusSynchronizer $tableSync,
    ) {
    }

    /* ---------------- Listeleme ---------------- */

    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Order::class);

        // ŞUBE KAPSAMI: geçerli şube (personel kendi, yönetici aktif) ile süzülür.
        // İstekten gelen branch_id yok sayılır — başka şube adisyonu ASLA görünmez.
        // OrderPresenter::summary items (kısmi teslim sayacı) + openedBy (açan
        // personel) erişir → N+1 olmasın diye eager-load edilir.
        $query = Order::query()->with(['table:id,name,number', 'receivable:id,name', 'items', 'openedBy:id,name', 'linkedTables.table:id,name,number'])
            ->where('branch_id', $this->currentBranchId());

        if ($request->filled('status')) {
            $query->where('status', (string) $request->query('status'));
        }

        if ($request->filled('channel')) {
            $query->where('channel', (string) $request->query('channel'));
        }

        if ($request->boolean('open')) {
            $query->whereNotIn('status', OrderStatus::closedValues());
        }

        $orders = $query->latest('id')->paginate(min((int) $request->query('per_page', 50), 200));
        $orders->getCollection()->transform(fn (Order $o): array => OrderPresenter::summary($o));

        return response()->json(['orders' => $orders]);
    }

    /**
     * Masa ızgarası: şubenin masaları + açık adisyon özetleri + masasız
     * kanalların (paket/gel-al/kiosk) açık siparişleri + onay bekleyen QR.
     */
    public function board(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Order::class);

        // ŞUBE KAPSAMI: pano yalnız GEÇERLİ şubenin masa/adisyon/talep'ini gösterir.
        $branchId = $this->currentBranchId() ?? 0;

        $tables = \App\Modules\Tables\Models\Table::query()
            ->with(['area:id,name,floor_id,sort_order', 'area.floor:id,name'])
            ->where('branch_id', $branchId)
            ->where('is_active', true)
            ->orderBy('number')->orderBy('name')
            ->get();

        // Açık adisyonlar + ön-ödemeli (kiosk POS) ama henüz teslim edilmemiş
        // siparişler. Kiosk siparişi başta 'paid' olur; teslim edilene kadar
        // panoda görünmeli (aksi halde kasadan/panodan "kayboluyordu").
        $openOrders = Order::query()
            ->with(['table:id,name,number', 'receivable:id,name', 'items', 'openedBy:id,name', 'linkedTables.table:id,name,number'])
            ->where('branch_id', $branchId)
            ->operationallyVisible()
            ->orderBy('id')
            ->get();

        // MASA KARTI yalnız AÇIK adisyonla dolu görünür: ödenmiş/kapanmış sipariş
        // (paid dine-in = masa boşaldı) masayı İŞGAL ETMEZ. Ön-ödemeli kiosk siparişleri
        // masasızdır (channel_orders'a düşer) → bu filtre onları etkilemez.
        $byTable = $openOrders
            ->whereNotNull('table_id')
            ->filter(fn (Order $o): bool => $o->statusEnum()->isOpen())
            ->groupBy('table_id');

        // BİRLEŞİK MASALAR: kalabalık grup birden çok masaya oturduğunda,
        // birleştirilen masalar hâlâ o adisyona bağlıdır. Bu masalar panoda
        // BOŞ değil, "birleşik" görünür ve tıklanınca ana adisyona gider.
        // Bağ yalnız AÇIK adisyonlar için geçerlidir (kapanan adisyonun bağı
        // kendiliğinden düşer — ayrı temizlik gerekmez).
        $openOrderIds = $openOrders
            ->filter(fn (Order $o): bool => $o->statusEnum()->isOpen())
            ->pluck('id')->all();

        $linkedByTable = \App\Modules\Orders\Models\OrderLinkedTable::query()
            ->whereIn('order_id', $openOrderIds !== [] ? $openOrderIds : [0])
            ->get()
            ->keyBy('table_id');

        // Bugünkü AKTİF (henüz oturtulmamış/iptal olmamış) rezervasyonlar → masa
        // kartında "Rezerve" rozeti + isim/saat. Boş görünen masa aslında birine
        // ayrılmışsa personel bunu panoda görsün (adisyon açmadan önce).
        $tz = \App\Modules\Tenancy\Models\Branch::query()->where('id', $branchId)->value('timezone')
            ?: (string) config('app.timezone');
        $todayLocal = now($tz)->toDateString();
        $resByTable = \Illuminate\Support\Facades\DB::table('reservation_tables as rt')
            ->join('reservations as r', 'r.id', '=', 'rt.reservation_id')
            ->where('r.branch_id', $branchId)
            ->whereIn('r.status', ['requested', 'pending', 'confirmed', 'late', 'arrived'])
            ->get(['rt.table_id', 'r.customer_name', 'r.reserved_at', 'r.duration_minutes', 'r.party_size'])
            ->filter(fn ($x): bool => \Illuminate\Support\Carbon::parse($x->reserved_at)->timezone($tz)->toDateString() === $todayLocal)
            ->groupBy('table_id');

        $tableCards = $tables->map(function ($table) use ($byTable, $resByTable, $linkedByTable, $openOrders, $tz): array {
            $status = $table->status instanceof \App\Modules\Venue\Enums\TableStatus
                ? $table->status
                : \App\Modules\Venue\Enums\TableStatus::tryFrom((string) $table->status) ?? \App\Modules\Venue\Enums\TableStatus::Available;

            $resList = $resByTable->get($table->id);
            $reservation = null;
            if ($resList !== null && $resList->isNotEmpty()) {
                $first = $resList->sortBy('reserved_at')->first();
                $start = \Illuminate\Support\Carbon::parse($first->reserved_at)->timezone($tz);
                $end = $start->copy()->addMinutes((int) ($first->duration_minutes ?: 120));
                $reservation = [
                    'name' => $first->customer_name,
                    'time' => $start->format('H:i'),
                    'time_end' => $end->format('H:i'),
                    'party' => (int) $first->party_size,
                ];
            }

            return [
                'id' => $table->id,
                'name' => $table->name,
                'number' => $table->number,
                'capacity' => $table->capacity,
                'area_name' => $table->area?->name,
                // Alan sekmelerinin sırası işletmenin tanımladığı sıra olmalı
                // (alfabetik değil): "Salon" "Bahçe"nin önünde kalsın.
                'area_sort' => $table->area?->sort_order,
                'floor_name' => $table->area?->floor?->name,
                'status' => $status->value,
                'status_label' => $status->label(),
                'status_icon' => $status->icon(),
                'status_variant' => $status->variant(),
                'reservation' => $reservation,
                'orders' => ($byTable->get($table->id) ?? collect())
                    ->map(fn (Order $o): array => OrderPresenter::summary($o))->values()->all(),
                // Bu masa başka bir adisyona BAĞLI mı (grup birleştirmesi)?
                // Doluysa kart "birleşik" görünür ve ana adisyona yönlendirir.
                'linked_to' => (function () use ($table, $linkedByTable, $openOrders): ?array {
                    $link = $linkedByTable->get($table->id);
                    if ($link === null) {
                        return null;
                    }
                    $main = $openOrders->firstWhere('id', (int) $link->order_id);
                    if ($main === null) {
                        return null;
                    }

                    return [
                        'order_id' => (int) $main->getKey(),
                        'table_name' => $main->table?->name,
                        'remaining_minor' => (int) $main->remaining_minor,
                        'items_count' => (int) $main->items->where('is_active', true)->count(),
                    ];
                })(),
            ];
        });

        // Açık servis talepleri (garson çağır / hesap iste / su iste)
        $serviceRequests = \App\Modules\Orders\Models\ServiceRequest::query()
            ->with('table:id,name,number')
            ->where('branch_id', $branchId)
            ->where('status', 'open')
            ->orderBy('id')
            ->get()
            ->map(fn (\App\Modules\Orders\Models\ServiceRequest $sr): array => [
                'id' => $sr->id,
                'kind' => $sr->kind,
                'kind_label' => $sr->kindLabel(),
                'kind_icon' => $sr->kindIcon(),
                'table_id' => $sr->table_id,
                'table_name' => $sr->table?->name,
                'created_at' => $sr->created_at?->toIso8601String(),
            ])->values()->all();

        /* CARİ KARTLARI (kişiler): sipariş ekranında masaların yanında, ayrı
           bir sekmede durur. Kart "masa" değil KİŞİdir: dolu görünmesi o
           kişinin AÇIK adisyonu olduğu anlamına gelir. Eklenti kapalıysa ya da
           rol şahsı göremiyorsa liste HİÇ üretilmez (boş sekme oluşmaz). */
        $receivableCards = [];

        if (\App\Modules\Settings\Support\Features::enabled((int) $request->user()->tenant_id, 'receivables')
            && $request->user()->hasPermission('receivables.view')) {
            $byReceivable = $openOrders
                ->whereNotNull('receivable_id')
                ->filter(fn (Order $o): bool => $o->statusEnum()->isOpen())
                ->groupBy('receivable_id');

            $receivableCards = \App\Modules\Receivables\Models\Receivable::query()
                ->where('is_active', true)
                // Şubesiz cari kiracı genelidir (ReceivablePolicy deseni).
                ->where(fn ($q) => $q->whereNull('branch_id')->orWhere('branch_id', $branchId))
                ->orderBy('name')
                ->get(['id', 'name', 'phone', 'balance_minor', 'branch_id'])
                /* SIRALAMA (2026-09-06 işletme talebi): 1) AÇIK ADİSYONU olanlar
                   en üstte (kasiyer/garson önce onlara dokunur), 2) sonra BORCU
                   olanlar (tahsilat hatırlatıcısı), 3) gerisi ada göre. Adisyon
                   kapanınca kişi kendiliğinden eski yerine döner — durum
                   veriden okunur, ayrıca işaretleme tutulmaz. */
                ->sortBy([
                    fn ($r) => $byReceivable->get($r->id) === null ? 1 : 0,
                    fn ($r) => (int) $r->balance_minor > 0 ? 0 : 1,
                    fn ($r) => mb_strtolower((string) $r->name, 'UTF-8'),
                ])
                ->values()
                ->map(fn ($r): array => [
                    'id' => (int) $r->id,
                    'name' => $r->name,
                    'phone' => $r->phone,
                    // Kişinin BİRİKMİŞ borcu (bu adisyondan bağımsız defter bakiyesi).
                    'balance_minor' => (int) $r->balance_minor,
                    'orders' => ($byReceivable->get($r->id) ?? collect())
                        ->map(fn (Order $o): array => OrderPresenter::summary($o))->values()->all(),
                ])->values()->all();
        }

        return response()->json([
            'tables' => $tableCards,
            'receivables' => $receivableCards,
            'channel_orders' => $openOrders->whereNull('table_id')->whereNull('receivable_id')
                ->map(fn (Order $o): array => OrderPresenter::summary($o))->values()->all(),
            'pending_approval' => $openOrders->where('status', OrderStatus::PendingApproval->value)
                ->map(fn (Order $o): array => OrderPresenter::summary($o))->values()->all(),
            'service_requests' => $serviceRequests,
        ]);
    }

    public function show(Request $request, Order $order): JsonResponse
    {
        $this->authorize('view', $order);

        // items.addedBy: kalem dökümü olay kaydı eksik satırda ekleyeni okur;
        // önceden satır başına ayrı `users` sorgusu (N+1) atıyordu (2026-10-27).
        $order->load(['items.options', 'items.addedBy:id,name', 'events.user', 'table:id,name,number', 'receivable:id,name', 'openedBy:id,name']);

        $detay = OrderPresenter::detail($order);

        // BİRLEŞTİRİLMİŞ KAYNAK (2026-10-30): adisyon başka bir adisyona
        // birleştirilerek kapandıysa istemci hedefe geçebilsin. Yalnız bu
        // durumda alan eklenir; diğer yanıtlar (ve ETag'leri) değişmez.
        $hedef = $this->birlestirilenHedef($order);
        if ($hedef !== null) {
            $detay['birlestirilen_hedef_id'] = $hedef;
        }

        return response()->json(['order' => $detay]);
    }

    /**
     * Kaynak adisyon `merged_into` ile kapandıysa SON hedefin id'si (hedef de
     * sonradan birleştirildiyse zincir en çok 5 adım izlenir). Kiracı kapsamı
     * global scope'tan; yabancı/silinmiş hedef null döner.
     */
    private function birlestirilenHedef(Order $order): ?int
    {
        $kapali = OrderStatus::closedValues();
        $status = $order->status instanceof \BackedEnum ? $order->status->value : (string) $order->status;
        if (! in_array($status, $kapali, true)) {
            return null;
        }

        $olay = $order->events->firstWhere('type', 'merged_into');
        $hedefId = (int) ($olay?->payload['target_order_id'] ?? 0);
        if ($hedefId <= 0) {
            return null;
        }

        $gorulen = [(int) $order->getKey() => true];
        for ($i = 0; $i < 5; $i++) {
            $hedef = Order::query()->find($hedefId, ['id', 'status']);
            if ($hedef === null) {
                return null;
            }
            $hs = $hedef->status instanceof \BackedEnum ? $hedef->status->value : (string) $hedef->status;
            if (! in_array($hs, $kapali, true)) {
                return $hedefId;
            }
            $sonrakiOlay = \App\Modules\Orders\Models\OrderEvent::query()
                ->where('order_id', $hedefId)->where('type', 'merged_into')
                ->orderByDesc('id')->first(['id', 'payload']);
            $sonraki = (int) ($sonrakiOlay?->payload['target_order_id'] ?? 0);
            if ($sonraki <= 0 || isset($gorulen[$sonraki])) {
                return $hedefId;
            }
            $gorulen[$hedefId] = true;
            $hedefId = $sonraki;
        }

        return $hedefId;
    }

    /* ---------------- Açma ---------------- */

    public function store(Request $request): JsonResponse
    {
        // ATIF (§13, Faz C/B): TERMİNALDE aktif operatör varsa ONA atfet
        // (yeniden PIN sorma — zaten PIN'le giriş yaptı; #183 davranışı
        // KORUNUR); operatör yoksa gövdede PIN gelirse Kasa'daki gibi FALLBACK
        // (PIN'den personel çözülür), hiçbiri yoksa 422 "Önce personel seçin."
        // NORMAL oturumda: policy + oturum kullanıcısı (mevcut davranış
        // DEĞİŞMEZ). Diğer tüm adisyon-mutasyon uçlarıyla (cancel/comp/pay/
        // refund) AYNI desen (actorOrOperator) — önceden yalnız bu uç
        // (openingActor) PIN-fallback'siz kalmıştı (BUG #1).
        $actor = $this->pinGate->actorOrOperator($request, 'orders.create', 'order.open',
            fn () => $this->authorize('create', Order::class));

        $data = $request->validate([
            // branch_id İSTEKTEN ALINMAZ (aşağıda BranchContext'ten atanır) —
            // bu yüzden zorunlu DEĞİL. Terminal/personel şubeyi seçmez; cihaz/
            // kullanıcı zaten bir şubeye bağlıdır. Gelirse yok sayılır.
            'branch_id' => ['sometimes', 'nullable', 'integer'],
            'channel' => ['sometimes', Rule::enum(OrderChannel::class)],
            'service_type' => ['sometimes', Rule::enum(ServiceType::class)],
            'table_id' => ['nullable', 'integer'],
            // CARİ ADİSYONU: masasız, kişiye bağlı adisyon (Borçlar modülü).
            'receivable_id' => ['nullable', 'integer'],
            'guest_count' => ['nullable', 'integer', 'min:1', 'max:200'],
            'note' => ['nullable', 'string', 'max:500'],
            'customer_name' => ['nullable', 'string', 'max:120'],
            'customer_phone' => ['nullable', 'string', 'max:32'],
            'total_minor' => ['sometimes', 'integer', 'min:0'], // Faz-1 uyumluluk (kullanılmaz)
        ]);

        // ŞUBE KAPSAMI: adisyon DAİMA geçerli şubede açılır (personel kendi,
        // yönetici aktif). İstekten gelen branch_id yok sayılır → personel
        // başka şubede adisyon açamaz; başka şube masası da bağlanamaz
        // (OrderService::open masa şube-eşleşmesini zaten doğrular).
        $branch = ($id = $this->currentBranchId()) !== null
            ? Branch::query()->find($id) // scoped: yabancı şube çözülmez
            : null;

        if ($branch === null) {
            throw ValidationException::withMessages(['branch_id' => ['Şube bulunamadı.']]);
        }

        $data['branch_id'] = (int) $branch->id;
        $data['channel'] = $data['channel'] ?? OrderChannel::Table->value;

        /* CARİ ADİSYONU (kişiye açılan adisyon):
           - Borçlar/Şahıslar eklentisi kapalıysa hiç açılamaz,
           - şahsı göremeyen rol adisyonu ona bağlayamaz,
           - kanal CARİYE SABİTLENİR: "masa kanalı + şahıs" gibi çelişkili bir
             kayıt oluşamaz (tek-açık-adisyon kuralı tek slottan yürür). */
        if (($data['receivable_id'] ?? null) !== null) {
            $tenantId = (int) $request->user()->tenant_id;

            if (! \App\Modules\Settings\Support\Features::enabled($tenantId, 'receivables')) {
                throw ValidationException::withMessages([
                    'receivable_id' => ['Borçlar / Şahıslar eklentisi kapalı.'],
                ]);
            }

            abort_unless($request->user()->hasPermission('receivables.view'), 403);

            $data['channel'] = OrderChannel::Account->value;
            $data['table_id'] = null;
        }

        // Rezervasyon ↔ walk-in çakışması (§8): boş görünen masaya YENİ adisyon
        // açılırken masanın yaklaşan/aktif rezervasyonu varsa personel ONAYI
        // (confirm=true) olmadan açma; uyarı döndür (Board onay diyaloğu).
        if (! $request->boolean('confirm')) {
            $warning = $this->reservationConflictWarning($data);

            if ($warning !== null) {
                return response()->json($warning, 409);
            }
        }

        $order = $this->orders->open($data, $actor);

        // Tek-adisyon kuralı: masada zaten açık adisyon varsa YENİSİ
        // açılmaz, var olan İDEMPOTENT biçimde döner (201 DEĞİL, 200 —
        // yeni kaynak oluşmadı).
        $status = $order->wasRecentlyCreated ? 201 : 200;

        // Yeni oturma + masaya bağlıysa: rezervasyonu ilerlet (seated) ya da
        // net çakışma işaretle (ReservationService; idempotent open'da çalışmaz).
        if ($order->wasRecentlyCreated && $order->table_id !== null) {
            $this->progressReservationForWalkIn($order, $actor);
        }

        return response()->json(['order' => OrderPresenter::summary($order->fresh(['table']))], $status);
    }

    /* ---------------- Kalemler ---------------- */

    public function addItem(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'product_id' => ['required', 'integer'],
            'variant_id' => ['nullable', 'integer'],
            'qty' => ['required', 'integer', 'min:1', 'max:100'],
            'option_ids' => ['sometimes', 'array', 'max:30'],
            'option_ids.*' => ['integer'],
            'note' => ['nullable', 'string', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
            // Offline-kuyruk idempotency (PROOF — görev B, docs/offline-sync-protocol.md):
            // istemci işlemi KUYRUĞA eklerken üretir, ağ isteğinden ÖNCE var olur; geç
            // senkronda da AYNI kalır. Idempotency-Key HEADER'ından bağımsızdır.
            // YOKSA (mevcut istemciler) davranış AŞAĞIDA bugünküyle BİREBİR aynıdır.
            'op_id' => ['sometimes', 'nullable', 'uuid'],
        ]);

        $opId = $data['op_id'] ?? null;
        unset($data['op_id']); // OrderService payload'ına sızmasın (bugünkü alan seti korunur)

        // Bugünkü uç: Idempotency-Key header'ıyla çift-dokunma korumalı ekleme.
        // op_id VARSA/YOKSA bu iç akış DEĞİŞMEDEN aynen çalışır.
        $viaHeader = function () use ($order, $data, $request): array {
            [$response, $status, $replayed] = $this->idempotency->run(
                (int) $order->tenant_id,
                $request->header('Idempotency-Key'),
                'orders.items.add',
                function () use ($order, $data, $request): array {
                    $item = $this->orders->addItem($order, $data, $request->user(), $data['expected_version'] ?? null);

                    // EKLENTİ: "Sipariş girilince otomatik hazırlığa gönder".
                    // Açıkken kalem eklenir eklenmez istasyonuna düşer ve o
                    // istasyonun yazıcısında fişi basılır; personelin ayrıca
                    // "Hazırlığa gönder" demesi gerekmez.
                    $this->otomatikIstasyonaGonder($order, $item, (int) $data['qty'], $request->user());

                    return [['order' => $this->freshDetail($order)], 201];
                },
            );

            return [$response, $status, $replayed];
        };

        if ($opId === null || $opId === '') {
            // op_id YOK → bugünkü davranışın AYNISI (kırılmaz).
            [$response, $status, $replayed] = $viaHeader();

            return response()->json($response + ['replayed' => $replayed], $replayed ? 200 : $status);
        }

        // op_id VAR → offline-kuyruk idempotency katmanı sarmalar (aynı op_id
        // ikinci kez gelirse iş TEKRAR ÇALIŞMAZ, ilk yanıt aynen döner).
        [$response, $status, $replayed] = $this->opIdempotency->run(
            (int) $order->tenant_id,
            $opId,
            'order.item.add',
            $data,
            function () use ($viaHeader): array {
                [$response, $status] = $viaHeader();

                return [$response, $status];
            },
        );

        return response()->json($response + ['replayed' => $replayed], $replayed ? 200 : $status);
    }

    /**
     * Adisyon başlığı: kişi sayısı + adisyon notu (yalnız bu iki alan).
     * Tutar/kalem/durum etkilenmez; `orders.update` izni yeter.
     */
    public function updateInfo(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'guest_count' => ['sometimes', 'nullable', 'integer', 'min:1', 'max:200'],
            'note' => ['sometimes', 'nullable', 'string', 'max:500'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->updateOrderInfo($order, $data, $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function updateItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('update', $order);
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'qty' => ['sometimes', 'integer', 'min:1', 'max:100'],
            'note' => ['sometimes', 'nullable', 'string', 'max:255'],
            'option_ids' => ['sometimes', 'array', 'max:30'],
            'option_ids.*' => ['integer'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->updateItem($order, $item, $data, $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /**
     * KALEM NOTU (2026-10-27): hazırlığa gönderilmemiş adede not yaz/sil.
     * PATCH /api/v1/orders/{order}/items/{item}/note  {note: string|null, expected_version?: int}
     * Kısmen gönderilmiş satırda bekleyen adet ayrı satıra bölünür; yanıtta
     * `item_id` notu taşıyan satırdır.
     */
    public function setItemNote(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('update', $order);
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'note' => ['present', 'nullable', 'string', 'max:200'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $hedef = $this->orders->setItemNote(
            $order,
            $item,
            isset($data['note']) ? (string) $data['note'] : null,
            $request->user(),
            $data['expected_version'] ?? null,
        );

        return response()->json(['order' => $this->freshDetail($order), 'item_id' => (int) $hedef->getKey()]);
    }

    public function removeItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('update', $order);
        $this->assertItemBelongs($order, $item);

        // keep_open: son kalem kalksa bile adisyon kapanmasın (kasiyer yerine
        // başka ürün ekleyecek). Varsayılan eski davranış: boşalınca kapat.
        $this->orders->removeItem(
            $order,
            $item,
            $request->user(),
            $this->expectedVersion($request),
            $request->boolean('keep_open'),
        );

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function cancelItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        // Terminalde: aktif operatör varsa ONA atfet (yeniden PIN sorma — zaten
        // PIN'le giriş yaptı); PIN gönderildiyse PIN kapısı. Normal: policy.
        $actor = $this->pinGate->actorOrOperator($request, 'orders.cancel', 'order.item_cancel',
            fn () => $this->authorize('cancel', $order));
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
            'keep_open' => ['sometimes', 'boolean'],
            // Kısmi iptal adedi (2026-10-26): yoksa satırın tamamı iptal olur.
            'qty' => ['nullable', 'integer', 'min:1', 'max:'.(int) $item->qty],
        ]);

        $this->orders->cancelItem(
            $order,
            $item,
            $data['reason'],
            $actor,
            $data['expected_version'] ?? null,
            (bool) ($data['keep_open'] ?? false),
            isset($data['qty']) ? (int) $data['qty'] : null,
        );

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /**
     * Yanlış girilen ürünü doğrusuyla değiştir (tek işlem).
     *
     * Yetki bilinçli olarak `orders.cancel`: bu işlem bir kalemi iptal edip
     * yerine yenisini koyar, yani iptal yetkisi gerektirir. Sadece ekleme
     * yetkisi olan biri yanlışlıkla mutfağa gitmiş kalemi silememeli.
     */
    public function swapItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $actor = $this->pinGate->actorOrOperator($request, 'orders.cancel', 'order.item_swap',
            fn () => $this->authorize('cancel', $order));
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'product_id' => ['required', 'integer'],
            'variant_id' => ['nullable', 'integer'],
            'qty' => ['required', 'integer', 'min:1', 'max:100'],
            'option_ids' => ['sometimes', 'array', 'max:30'],
            'option_ids.*' => ['integer'],
            'note' => ['nullable', 'string', 'max:255'],
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
            /* KISMİ DEĞİŞİM (2026-10-25): eski satırın kaç adedi değişecek.
               Boş/eksikse TÜM satır değişir (eski davranış). */
            'swap_qty' => ['nullable', 'integer', 'min:1'],
        ]);

        $this->orders->swapItem(
            $order,
            $item,
            [
                'product_id' => $data['product_id'],
                'variant_id' => $data['variant_id'] ?? null,
                'qty' => $data['qty'],
                'option_ids' => $data['option_ids'] ?? [],
                'note' => $data['note'] ?? null,
            ],
            $data['reason'],
            $actor,
            $data['expected_version'] ?? null,
            isset($data['swap_qty']) ? (int) $data['swap_qty'] : null,
        );

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function compItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        // Terminalde: aktif operatör varsa ONA atfet (yeniden PIN sorma); PIN
        // gönderildiyse PIN kapısı. Normal: policy.
        $actor = $this->pinGate->actorOrOperator($request, 'orders.comp', 'order.item_comp',
            fn () => $this->authorize('comp', $order));
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
            'qty' => ['nullable', 'integer', 'min:1', 'max:'.(int) $item->qty], // kısmi ikram adedi
        ]);

        $this->orders->compItem($order, $item, $data['reason'], $actor, $data['expected_version'] ?? null, $data['qty'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /**
     * İkramı geri al — yanlış kaleme "ikram" denmişse kalem yeniden ücretli
     * olur. Yetki ikramla AYNI (orders.comp): ikram edebilen geri de alabilir.
     */
    public function uncompItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $actor = $this->pinGate->actorOrOperator($request, 'orders.comp', 'order.item_comp_removed',
            fn () => $this->authorize('comp', $order));
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->ikramiKaldir($order, $item, $actor, $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function setItemStatus(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('update', $order);
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'status' => ['required', Rule::enum(OrderItemStatus::class)],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $to = OrderItemStatus::from($data['status']);
        $user = $request->user();

        // KDS'in yönettiği durumlar (accepted/preparing/ready/served): bu genel
        // adisyon ucu 'orders.update' (garson dahil) ile açıktı ve KdsActionController'ın
        // kds.view/kds.deliver izni + istasyon-kapsamı (assertItemInScope) kontrolünü
        // ATLIYORDU — garson/kasiyer başka istasyonun kalemini bu uçtan doğrudan
        // "hazır"/"servis edildi" işaretleyebiliyordu. KdsService::advanceItem'a delege
        // ederek KDS ekranıyla AYNI kural uygulanır (istasyon-yönlendirme denetimi 2026-08-06).
        if (in_array($to, [OrderItemStatus::Accepted, OrderItemStatus::Preparing, OrderItemStatus::Ready, OrderItemStatus::Served], true)) {
            if ($to === OrderItemStatus::Served) {
                abort_unless($user->hasPermission('kds.deliver'), 403);
            } else {
                abort_unless($user->hasPermission('kds.view'), 403);
            }

            $this->kds->advanceItem($user, $item, $to, $data['expected_version'] ?? null);

            return response()->json(['order' => $this->freshDetail($order)]);
        }

        $this->orders->setItemStatus($order, $item, $to, $user, $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function moveItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('update', $order);
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'table_id' => ['required', 'integer'],
            'expected_version' => ['nullable', 'integer'],
            // KISMİ TAŞIMA (2026-09-10): boş/eksik ise TÜM satır taşınır (eski davranış).
            'qty' => ['nullable', 'integer', 'min:1'],
        ]);

        $target = $this->orders->moveItem($order, $item, (int) $data['table_id'], $request->user(), $data['expected_version'] ?? null, isset($data['qty']) ? (int) $data['qty'] : null);

        return response()->json([
            'order' => $this->freshDetail($order),
            'target_order' => OrderPresenter::summary($target->fresh(['table', 'items'])),
        ]);
    }

    /**
     * SEÇİLİ KALEMLERİ TOPLU TAŞI (2026-09-12).
     *
     * Gövde: item_ids[] + (table_id VEYA receivable_id).
     * Şahsa taşımada tek kalem ucuyla AYNI yetki aranır (receivables.view):
     * şahıs defterine ürün yazmak borç yaratır, herkesin işi değildir.
     */
    public function moveItems(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'item_ids' => ['required', 'array', 'min:1', 'max:200'],
            'item_ids.*' => ['integer'],
            'table_id' => ['nullable', 'integer'],
            'receivable_id' => ['nullable', 'integer'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        if (! empty($data['receivable_id'])) {
            abort_unless(
                $request->user()?->hasPermission('receivables.view') ?? false,
                403,
                'Şahsa taşımak için şahıs (borçlar) yetkisi gerekir.'
            );
        }

        $sonuc = $this->orders->moveItems(
            $order,
            $data['item_ids'],
            isset($data['table_id']) ? (int) $data['table_id'] : null,
            isset($data['receivable_id']) ? (int) $data['receivable_id'] : null,
            $request->user(),
            $data['expected_version'] ?? null,
        );

        return response()->json([
            'order' => $this->freshDetail($order),
            'target_order' => OrderPresenter::summary($sonuc['target']->fresh(['table', 'items'])),
            'moved' => $sonuc['moved'],
        ]);
    }

    /**
     * PARTİYİ KAPAT — yeni el başlar (2026-09-12).
     * Garson da kasa da yapabilir; ikisi de `orders.update` yetkisine sahiptir.
     */
    public function partiyiKapat(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $this->orders->partiyiKapat($order, $request->user(), $this->expectedVersion($request));

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /** Partiye isim ver / adı kaldır — yalnız gösterim (2026-09-12). */
    public function partiyiAdlandir(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'parti_no' => ['required', 'integer', 'min:1'],
            'ad' => ['nullable', 'string', 'max:40'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->partiyiAdlandir(
            $order,
            (int) $data['parti_no'],
            $data['ad'] ?? null,
            $request->user(),
            $data['expected_version'] ?? null,
        );

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /* ---------------- Durum ---------------- */

    public function setStatus(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'status' => ['required', Rule::enum(OrderStatus::class)],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->transition($order, OrderStatus::from($data['status']), $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function approve(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $this->orders->approve($order, $request->user(), $this->expectedVersion($request));

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /** "Mutfağa gönder": gönderilmemiş (placed) kalemleri sent_to_station yapar. */
    /**
     * İSKONTO — kasada tutar yazarak düşüm (kupon/tanımlı indirimden AYRI).
     * Onay eşiği ve tek-indirim kuralı burada YOKTUR; kim/ne zaman/gerekçe
     * kaydedilir, raporda ayrı kalem olarak izlenir.
     */
    public function iskonto(Request $request, Order $order): JsonResponse
    {
        $this->authorize('discount', $order);

        // MANUEL İSKONTO EKLENTİSİ (2026-10-27): tutar yazarak düşüm ve
        // "Hesabı buna indir" yalnız eklenti açıkken. Kaldırmak serbest.
        $this->manuelIskontoKapisi($order);

        $data = $request->validate([
            'amount_minor' => ['required', 'integer', 'min:1'],
            'reason' => ['nullable', 'string', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ], [], ['amount_minor' => 'iskonto tutarı']);

        $this->orders->applyIskonto(
            $order,
            (int) $data['amount_minor'],
            $data['reason'] ?? null,
            $request->user(),
            $data['expected_version'] ?? null,
        );

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /** İskontoyu kaldır. */
    public function removeIskonto(Request $request, Order $order): JsonResponse
    {
        $this->authorize('discount', $order);

        $this->orders->removeIskonto($order, $request->user(), $this->expectedVersion($request));

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /**
     * Yeni eklenen kalemi (eklenti açıksa) istasyona gönderir ve YALNIZ o
     * kalemin, YALNIZ şimdi eklenen adedi kadar fişini bastırır. Yazıcı yoksa/eklenti kapalıysa hiçbir şey
     * yapmaz — sipariş akışı hiçbir durumda bozulmaz.
     */
    private function otomatikIstasyonaGonder(Order $order, \App\Modules\Orders\Models\OrderItem $item, int $eklenenAdet, ?\App\Modules\Identity\Models\User $actor): void
    {
        if (! \App\Modules\Settings\Support\Features::enabled((int) $order->tenant_id, 'auto_send_to_station')) {
            return;
        }

        // Bekleyen adetler gönderim ÖNCESİ okunur (gönderim onları sıfırlar).
        $bekleyen = $this->orders->bekleyenHazirlikAdetleri($order);

        try {
            $this->orders->sendToKitchen($order, $actor);
        } catch (\Throwable $e) {
            // "Gönderilecek yeni kalem yok" gibi durumlar akışı kesmemeli.
        }

        // ADET: aynı ürün mevcut satıra BİRLEŞTİĞİNDE satırın toplamı
        // (2×, 3×…) değil, ŞİMDİ eklenen adet basılır — mutfak yalnız yeni
        // gelen adedi hazırlar.
        if ($bekleyen === []) {
            $bekleyen = [(int) $item->id => max(1, $eklenenAdet)];
        }

        try {
            app(\App\Modules\Printing\Services\PrintService::class)
                ->autoKitchen(
                    $order->fresh(['items', 'table']),
                    array_map('intval', array_keys($bekleyen)),
                    $bekleyen,
                );
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('print.auto_item', ['order' => $order->id, 'item' => $item->id, 'err' => $e->getMessage()]);
        }
    }

    public function sendToKitchen(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        // ŞİMDİ gönderilen kalemler VE adetleri: fiş YALNIZ bunları içermeli.
        // Aksi hâlde (özellikle otomatik gönderim eklentisi açıkken) daha önce
        // basılmış kalemler tekrar basılıyordu.
        //
        // ADET: yalnız "placed" satırlara bakmak YETMEZ — aynı ürün mevcut
        // satıra birleştiğinde (çay ×1 → çay ×2) satır zaten gönderilmiş
        // durumdadır; o eklemeler için hiç fiş çıkmıyordu (2026-10-10 bildirimi).
        // Bekleyen = qty − sent_qty; fişe o adet basılır.
        $bekleyen = $this->orders->bekleyenHazirlikAdetleri($order);
        $gonderilen = array_map('intval', array_keys($bekleyen));

        try {
            $this->orders->sendToKitchen($order, $request->user(), $this->expectedVersion($request));
        } catch (\Illuminate\Validation\ValidationException $e) {
            // "Gönderilecek yeni kalem yok" bir HATA DEĞİLDİR: otomatik
            // gönderim eklentisi açıkken kalemler zaten anında istasyona
            // düşer, personel yine de düğmeye basabilir. Ekrana kırmızı
            // uyarı basmak yerine sessizce mevcut durumu döndürürüz.
            if (! array_key_exists('items', $e->errors())) {
                throw $e;
            }

            return response()->json(['order' => $this->freshDetail($order), 'sent' => 0]);
        }

        // OTOMATİK HAZIRLIK FİŞİ: "hazırlık fişi" işaretli yazıcılar için iş
        // kuyruğa bırakılır; mekândaki ajan basar (yazıcı tanımlı değilse
        // hiçbir şey olmaz — akış bozulmaz).
        try {
            app(\App\Modules\Printing\Services\PrintService::class)
                ->autoKitchen(
                    $order->fresh(['items', 'table']),
                    $gonderilen ?: null,
                    $bekleyen ?: null,
                );
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('print.auto_kitchen', ['order' => $order->id, 'err' => $e->getMessage()]);
        }

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function requestBill(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $this->orders->requestBill($order, $request->user(), $this->expectedVersion($request));

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /**
     * "Ödeme bekleyen" (bill_requested) adisyonu yeniden servise/siparişe
     * döndürür — yanlışlıkla "hesap istendi" denmişse ya da masaya ek sipariş
     * alınacaksa.
     *
     * YETKİ İKİ KADEMELİ (2026-09-06 işletme talebi): adisyona HİÇ ödeme
     * girilmemişse bu yalnızca bir durum geri alma işidir; kazara basan garson
     * kendi hatasını düzeltebilsin diye orders.update yeter. Kısmi ödeme varsa
     * (para hareketi başlamış) iş kasanındır → payments.take şart.
     */
    public function sendBackToService(Request $request, Order $order): JsonResponse
    {
        $paraHareketiVar = (int) $order->paid_minor > 0;
        $izin = $paraHareketiVar ? 'payments.take' : 'orders.update';

        $actor = $this->pinGate->actorOrOperator($request, $izin, 'order.send_to_service',
            fn () => abort_unless(
                $request->user()?->hasPermission($izin) ?? false,
                403,
                $paraHareketiVar
                    ? 'Bu işlem için kasa yetkisi gerekir.'
                    : 'Bu işlem için sipariş yetkisi gerekir.'
            ));

        abort_unless(
            $order->statusEnum() === OrderStatus::BillRequested,
            422,
            'Yalnızca ödeme bekleyen adisyon siparişe geri gönderilebilir.'
        );

        $this->orders->hesapIstegiGeriAl($order, $actor, $this->expectedVersion($request));

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /* ---------------- İndirim / ödeme / iptal / iade (§12.3) ---------------- */

    /** Uygulanmış indirimi kaldırır (tek-indirim kuralının karşılığı). */
    /**
     * MANUEL İSKONTO KAPISI (2026-10-27 işletme talebi): elle tutar/yüzde
     * indirim, kasada iskonto tutarı yazma ve "Hesabı şu tutara indir"
     * `manuel_iskonto` eklentisine bağlıdır. Kapalıyken yalnız hazır
     * indirimler (preset_id) uygulanır. Sunucu tarafı zorlama: eski bir
     * sekme ya da uygulama sürümü düğmeyi gösterse bile istek reddedilir.
     */
    private function manuelIskontoKapisi(Order $order): void
    {
        abort_unless(
            \App\Modules\Settings\Support\Features::enabled((int) $order->tenant_id, 'manuel_iskonto'),
            403,
            'Manuel iskonto eklentisi kapalı. Hazır indirimlerden birini seçin.',
        );
    }

    public function removeDiscount(Request $request, Order $order): JsonResponse
    {
        $this->authorize('discount', $order);

        $this->orders->removeDiscount($order, $request->user(), $this->expectedVersion($request));

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function discount(Request $request, Order $order): JsonResponse
    {
        $this->authorize('discount', $order);

        // Hazır tanım (preset_id) verildiyse tür/değer/gerekçe TANIMDAN gelir —
        // istemci bunları göndermek zorunda değildir ve gönderse bile tanım
        // kazanır (oran/gerekçe istemciden oynatılamaz).
        $preset = null;
        if ($request->filled('preset_id')) {
            $preset = \App\Modules\Orders\Models\DiscountPreset::query()
                ->where('is_active', true)
                ->findOrFail((int) $request->input('preset_id'));
        }

        // HAZIR İNDİRİM her zaman serbest; tanımsız (elle tür/değer) indirim
        // yalnız "Manuel iskonto" eklentisi açıkken (2026-10-27).
        if ($preset === null) {
            $this->manuelIskontoKapisi($order);
        }

        $data = $request->validate([
            'preset_id' => ['nullable', 'integer'],
            'type' => [Rule::requiredIf($preset === null), Rule::in(['percent', 'amount'])],
            'value' => [Rule::requiredIf($preset === null), 'numeric', 'gt:0'],
            'reason' => [Rule::requiredIf($preset === null), 'string', 'min:3', 'max:255'],
            'approver_email' => ['nullable', 'email'],
            'approver_pin' => ['nullable', 'string', 'max:10'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        if ($preset !== null) {
            $data['type'] = $preset->type;
            $data['value'] = $preset->value();
            $data['reason'] = $preset->name;
        }

        // Tanım "onay istemez" işaretliyse eşik atlanır (tanımı yönetici yaptı).
        $preapproved = $preset !== null && ! $preset->requires_approval;

        $approver = $this->resolveApprover($request, $data);

        $this->orders->applyDiscount($order, [
            'type' => $data['type'],
            'value' => $data['type'] === 'percent' ? (float) $data['value'] : (int) $data['value'],
            'reason' => $data['reason'],
            'preapproved' => $preapproved,
            'preset_id' => $preset?->getKey(),
        ], $request->user(), $approver, $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /**
     * ESKİ ödeme ucu (Faz-3 uyumluluk) — Faz-5'ten itibaren kayıt
     * `payments` tablosuna düşer (ADR-010 tek doğruluk kaynağı).
     * 'card' = entegrasyonsuz POS kaydı (kayıt-onaylı, anında).
     * Yeni ekranlar /api/v1/orders/{order}/payments ucunu kullanır.
     */
    public function pay(Request $request, Order $order): JsonResponse
    {
        // Ödeme alma (§13, Faz C): terminal oturumda AKTİF OPERATÖRE atfedilir
        // (PIN gelirse mevcut PIN kapısı). ROL AYRIMI: ödeme YALNIZ payments.take
        // yetkisiyle alınır — garson (orders.update) artık ödeme ALAMAZ; adisyonu
        // "Ödemeye gönder" (request-bill) ile kasaya iletir. Operatör yoksa 422.
        $actor = $this->pinGate->actorOrOperator($request, 'payments.take', 'order.pay',
            fn () => abort_unless(
                $request->user()?->hasPermission('payments.take') ?? false,
                403,
                'Ödeme almak için kasa yetkiniz gerekir. Adisyonu "Ödemeye gönder" ile kasaya iletin.'
            ));

        $data = $request->validate([
            'amount_minor' => ['required', 'integer', 'min:1'],
            'method' => ['required', Rule::in(['cash', 'card'])],
            'expected_version' => ['nullable', 'integer'],
        ]);

        app(\App\Modules\Payments\Services\PaymentService::class)->pay($order, [
            'method' => $data['method'] === 'card'
                ? \App\Modules\Payments\Enums\PaymentMethod::CreditCard->value
                : \App\Modules\Payments\Enums\PaymentMethod::Cash->value,
            'amount_minor' => (int) $data['amount_minor'],
            'provider' => $data['method'] === 'card' ? 'card_present' : null,
        ], $actor, $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /**
     * BOŞ ADİSYONU KAPAT — masaya yanlışlıkla açılıp hiç ürün girilmeden
     * çıkılan adisyon masayı "dolu" gösteriyordu. Ekrandan çıkılırken çağrılır.
     *
     * Fail-safe: YALNIZ gerçekten boş adisyon kapanır (hiç kalem yok, ödeme
     * yok, indirim/iskonto yok, açık durumda). Aksi halde hiçbir şey yapmaz —
     * yanlışlıkla dolu bir adisyonun kapanması mümkün değildir. PIN istemez:
     * ortada iptal edilen bir satış yok, kayıt zaten boş.
     */
    public function discardIfEmpty(Request $request, Order $order): JsonResponse
    {
        // Kural TEK YERDE: OrderService::bosAdisyonuSil (zamanlanmış temizlik
        // işi de aynı metodu çağırır, iki yerde iki farklı kural olmasın).
        if ($request->user() === null) {
            return response()->json(['discarded' => false]);
        }

        $silindi = $this->orders->bosAdisyonuSil($order);

        return response()->json(['discarded' => $silindi, 'deleted' => $silindi]);
    }

    public function cancel(Request $request, Order $order): JsonResponse
    {
        // Terminalde: aktif operatör varsa ONA atfet (yeniden PIN sorma); PIN
        // gönderildiyse PIN kapısı. Normal: policy.
        $actor = $this->pinGate->actorOrOperator($request, 'orders.cancel', 'order.cancel',
            fn () => $this->authorize('cancel', $order));

        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->cancel($order, $data['reason'], $actor, $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /**
     * Adisyonun TAM iadesi — Faz-5'ten itibaren `payments` üzerinden
     * yürür (her başarılı ödemeye iade satırı açılır; ADR-010).
     * payments kaydı olmayan eski adisyonlar için eski yol korunur.
     */
    public function refund(Request $request, Order $order): JsonResponse
    {
        // Terminalde: aktif operatör varsa ONA atfet (yeniden PIN sorma — operatör
        // zaten PIN'le giriş yaptı, yetkisi doğrulanır); PIN gönderildiyse PIN
        // kapısı. Normal oturumda mevcut davranış (policy + oturum kullanıcısı).
        $actor = $this->pinGate->actorOrOperator($request, 'orders.refund', 'order.refund',
            fn () => $this->authorize('refund', $order));

        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $hasPayments = \App\Modules\Payments\Models\Payment::withoutTenancy()
            ->where('order_id', $order->getKey())
            ->where('kind', 'payment')
            ->exists();

        if ($hasPayments) {
            app(\App\Modules\Payments\Services\PaymentService::class)
                ->refundOrderFully($order, $data['reason'], $actor, $data['expected_version'] ?? null);
        } else {
            $this->orders->refund($order, $data['reason'], $actor, $data['expected_version'] ?? null);
        }

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /* ---------------- Taşı / birleştir / böl ---------------- */

    public function move(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'table_id' => ['required', 'integer'],
            'expected_version' => ['nullable', 'integer'],
            /* Hedef masada AÇIK adisyon varsa kalemleri oraya aktar (birleştir).
               Ekran önce uyarır, personel onaylayınca bu bayrakla çağırır. */
            'birlestir' => ['sometimes', 'boolean'],
        ]);

        /* BİRLEŞTİRME AYRI YETKİ: taşıma sırasında hedefteki açık adisyonla
           birleştirmek, adanmış birleştirme ucuyla (orders/{id}/merge) AYNI
           işi yapar; yetki kapısı da aynı olmalı — taşıma yetkisi olan herkes
           bir adisyonu kapatamasın (2026-09-08). */
        if ((bool) ($data['birlestir'] ?? false)) {
            abort_unless(
                $request->user()?->hasPermission('orders.merge_tables') ?? false,
                403,
                'Adisyon birleştirme yetkiniz yok.'
            );
        }

        $sonuc = $this->orders->moveOrder(
            $order,
            (int) $data['table_id'],
            $request->user(),
            $data['expected_version'] ?? null,
            (bool) ($data['birlestir'] ?? false),
        );

        // Birleştirmede kalemler HEDEF adisyona geçer: ekran oraya gitsin diye
        // sonuç adisyonu (id) döndürülür.
        $birlesti = (int) $sonuc->getKey() !== (int) $order->getKey();

        return response()->json([
            'order' => $this->freshDetail($sonuc),
            'birlestirildi' => $birlesti,
            'hedef_adisyon_id' => (int) $sonuc->getKey(),
        ]);
    }

    /** Tek bir kalemi kişinin (cari) adisyonuna taşı. */
    public function moveItemToReceivable(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('update', $order);
        $this->assertItemBelongs($order, $item);

        abort_unless(
            $request->user()?->hasPermission('receivables.view') ?? false,
            403,
            'Şahsa taşımak için şahıs (borçlar) yetkisi gerekir.'
        );

        $data = $request->validate([
            'receivable_id' => ['required', 'integer'],
            'expected_version' => ['nullable', 'integer'],
            // KISMİ TAŞIMA (2026-09-10): boş ise TÜM satır taşınır (eski davranış).
            'qty' => ['nullable', 'integer', 'min:1'],
        ]);

        $target = $this->orders->moveItemToReceivable($order, $item, (int) $data['receivable_id'], $request->user(), $data['expected_version'] ?? null, isset($data['qty']) ? (int) $data['qty'] : null);

        return response()->json([
            'order' => $this->freshDetail($order),
            'target_order' => OrderPresenter::summary($target->fresh(['table', 'items'])),
        ]);
    }

    /**
     * MASADAKİ HESABI CARİYE TAŞI (2026-09-07 işletme talebi).
     * Yetki: adisyon güncelleme + cari görme (kişiye borç bağlanıyor).
     */
    public function moveToReceivable(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        abort_unless(
            $request->user()?->hasPermission('receivables.view') ?? false,
            403,
            'Şahsa taşımak için şahıs (borçlar) yetkisi gerekir.'
        );

        $data = $request->validate([
            'receivable_id' => ['required', 'integer'],
            'expected_version' => ['nullable', 'integer'],
            'birlestir' => ['sometimes', 'boolean'],
        ]);

        /* BİRLEŞTİRME AYRI YETKİ: taşıma sırasında hedefteki açık adisyonla
           birleştirmek, adanmış birleştirme ucuyla (orders/{id}/merge) AYNI
           işi yapar; yetki kapısı da aynı olmalı — taşıma yetkisi olan herkes
           bir adisyonu kapatamasın (2026-09-08). */
        if ((bool) ($data['birlestir'] ?? false)) {
            abort_unless(
                $request->user()?->hasPermission('orders.merge_tables') ?? false,
                403,
                'Adisyon birleştirme yetkiniz yok.'
            );
        }

        $sonuc = $this->orders->moveOrderToReceivable(
            $order,
            (int) $data['receivable_id'],
            $request->user(),
            $data['expected_version'] ?? null,
            (bool) ($data['birlestir'] ?? false),
        );

        $birlesti = (int) $sonuc->getKey() !== (int) $order->getKey();

        return response()->json([
            'order' => $this->freshDetail($sonuc),
            'birlestirildi' => $birlesti,
            'hedef_adisyon_id' => (int) $sonuc->getKey(),
        ]);
    }

    public function merge(Request $request, Order $order): JsonResponse
    {
        // Birleştirme AYRI izin (orders.merge_tables): yalnız Garson + yönetim.
        $this->authorize('mergeTables', $order);
        $this->authorize('update', $order);

        $data = $request->validate([
            'source_order_id' => ['required', 'integer'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $source = Order::query()->find((int) $data['source_order_id']); // scoped

        if ($source === null) {
            throw ValidationException::withMessages(['source_order_id' => ['Kaynak adisyon bulunamadı.']]);
        }

        $this->authorize('mergeTables', $source);
        $this->authorize('update', $source);

        $this->orders->merge($order, $source, $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function split(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'mode' => ['required', Rule::in(['items', 'equal', 'persons'])],
            'item_ids' => ['required_if:mode,items', 'array'],
            'item_ids.*' => ['integer'],
            'ways' => ['required_if:mode,equal', 'integer'],
            'amounts' => ['required_if:mode,persons', 'array'],
            'amounts.*' => ['integer', 'min:0'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        if ($data['mode'] === 'items') {
            $newOrder = $this->orders->splitByItems($order, array_map('intval', $data['item_ids']), $request->user(), $data['expected_version'] ?? null);

            return response()->json([
                'order' => $this->freshDetail($order),
                'new_order' => OrderPresenter::summary($newOrder->fresh(['table', 'items'])),
            ]);
        }

        $shares = $this->orders->splitShares($order, [
            'mode' => $data['mode'],
            'ways' => isset($data['ways']) ? (int) $data['ways'] : null,
            'amounts' => $data['amounts'] ?? [],
        ], $request->user());

        return response()->json(['order' => $this->freshDetail($order), 'shares_minor' => $shares]);
    }

    /* ---------------- Yardımcılar ---------------- */

    private function freshDetail(Order $order): array
    {
        $fresh = Order::query()
            ->with(['items.options', 'events.user', 'table:id,name,number', 'receivable:id,name', 'openedBy:id,name'])
            ->findOrFail($order->getKey());

        return OrderPresenter::detail($fresh);
    }

    private function assertItemBelongs(Order $order, OrderItem $item): void
    {
        if ((int) $item->order_id !== (int) $order->getKey()) {
            abort(404);
        }
    }

    private function expectedVersion(Request $request): ?int
    {
        $v = $request->input('expected_version');

        return $v === null || $v === '' ? null : (int) $v;
    }

    /**
     * Rezervasyon ↔ walk-in çakışma ön-kontrolü (§8). Yalnız masaya
     * BAĞLANACAK (table/qr kanal ya da dine_in) ve masasında HENÜZ açık
     * adisyon OLMAYAN (gerçek yeni oturma) açılışlar denetlenir. Yaklaşan/
     * aktif rezervasyon varsa Board'a onay için uyarı payload'ı döner.
     * En kötü durumda (rezervasyon modülü sorunu) açılışı ENGELLEMEZ.
     *
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>|null
     */
    private function reservationConflictWarning(array $data): ?array
    {
        $channel = OrderChannel::tryFrom((string) $data['channel']) ?? OrderChannel::Table;
        $serviceType = isset($data['service_type'])
            ? (ServiceType::tryFrom((string) $data['service_type']) ?? ServiceType::fromChannel($channel))
            : ServiceType::fromChannel($channel);
        $tableId = (int) ($data['table_id'] ?? 0);

        if ($tableId <= 0 || ! ($channel->usesTable() || $serviceType->requiresTable())) {
            return null;
        }

        // §9: tenant bazlı bayrak — kimlik oturum kullanıcısının kiracısıdır
        // (data['branch_id'] şube id'si; tenant değil).
        if (! \App\Modules\Reservations\Support\ReservationFeature::enabled((int) auth()->user()?->tenant_id)) {
            return null;
        }

        try {
            $table = \App\Modules\Tables\Models\Table::query()
                ->where('branch_id', (int) $data['branch_id'])
                ->find($tableId);

            if ($table === null) {
                return null; // open() zaten alan-bazlı doğrulama hatası verir
            }

            // Zaten açık adisyon varsa açılış İDEMPOTENT (yeni oturma değil) → uyarma.
            $hasOpen = Order::query()
                ->where('table_id', $tableId)
                ->whereNotIn('status', OrderStatus::closedValues())
                ->exists();

            if ($hasOpen) {
                return null;
            }

            $reservation = app(\App\Modules\Reservations\Services\ReservationTableSync::class)
                ->imminentReservationForTable($table);

            if ($reservation === null) {
                return null;
            }

            $time = $reservation->localReservedAt()->format('H:i');

            return [
                'requires_confirmation' => true,
                'reason' => 'reservation_conflict',
                'message' => sprintf('Bu masa %s %s için rezerve — yine de açılsın mı?', $time, $reservation->customer_name),
                'reservation' => [
                    'id' => $reservation->id,
                    'customer_name' => $reservation->customer_name,
                    'reserved_time' => $time,
                    'party_size' => (int) $reservation->party_size,
                    'status' => $reservation->status->value,
                    'status_label' => $reservation->status->label(),
                ],
            ];
        } catch (\Throwable $e) {
            report($e); // rezervasyon denetimi adisyon açılışını bozmasın (fail-open)

            return null;
        }
    }

    /**
     * Walk-in rezervasyonlu masaya oturunca ilgili rezervasyonu ilerletir
     * (seated) ya da net çakışma olarak işaretler (ReservationService).
     * Best-effort: rezervasyon tarafı hata verse de adisyon akışı sürer.
     */
    private function progressReservationForWalkIn(Order $order, ?User $actor): void
    {
        // §9: tenant bazlı bayrak (order->branch_id şube id'si; tenant değil).
        if (! \App\Modules\Reservations\Support\ReservationFeature::enabled((int) ($actor?->tenant_id ?? auth()->user()?->tenant_id))) {
            return;
        }

        try {
            $table = \App\Modules\Tables\Models\Table::query()->find($order->table_id);

            if ($table === null) {
                return;
            }

            $reservation = app(\App\Modules\Reservations\Services\ReservationTableSync::class)
                ->imminentReservationForTable($table);

            if ($reservation !== null) {
                app(\App\Modules\Reservations\Services\ReservationService::class)
                    ->markWalkInSeated($reservation, $actor);
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /**
     * Eşik üstü indirim onayı: yönetici e-posta + PIN (Identity/PinService).
     * Onaylayan AYNI kiracıda olmalı ve personel yönetim yetkisi taşımalı.
     *
     * @param  array<string, mixed>  $data
     */
    private function resolveApprover(Request $request, array $data): ?User
    {
        if (empty($data['approver_email']) || empty($data['approver_pin'])) {
            return null;
        }

        /** @var User|null $approver */
        $approver = User::query()
            ->where('tenant_id', $request->user()->tenant_id)
            ->where('email', $data['approver_email'])
            ->first();

        if ($approver === null) {
            throw ValidationException::withMessages(['approver_email' => ['Onaylayan bulunamadı.']]);
        }

        if (! $approver->hasPermission('staff.manage') || ! $approver->hasPermission('orders.discount')) {
            throw ValidationException::withMessages(['approver_email' => ['Onaylayanın yönetici (personel yönetimi + indirim) yetkisi yok.']]);
        }

        if (! app(PinService::class)->verify($approver, (string) $data['approver_pin'])) {
            throw ValidationException::withMessages(['approver_pin' => ['PIN doğrulanamadı.']]);
        }

        return $approver;
    }
}
