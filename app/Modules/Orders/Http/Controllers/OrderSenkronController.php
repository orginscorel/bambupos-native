<?php

namespace App\Modules\Orders\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderEvent;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * ADİSYON DEĞİŞİM AKIŞI (2026-10-30) — POS uygulamasının anlık senkronu.
 *
 * Saha bildirimi: masa birleştirmeden sonra başka cihazlar (ve aynı cihazın
 * panosu) kapanmış kaynak adisyonu 5 sn'lik yoklama turuna kadar gösteriyor,
 * personel "adisyon bulunamadı" görüyordu. KDS'nin uzun yoklamasıyla
 * (KdsQueueController::updates) AYNI kalıp:
 *
 *   GET /api/v1/orders/degisim            → ilk çağrı: hemen {imlec, ilk:true}
 *   GET /api/v1/orders/degisim?imlec=N    → olay gelene kadar (en çok ~20 sn)
 *                                           bekler; yoksa 204.
 *
 * İmleç = geçerli şubenin MAX(order_events.id)'si; (tenant_id, branch_id, id)
 * indeksiyle tek satır okunur. İmleç GERİ GİTTİYSE ("geçmişi sıfırla")
 * `sifirlandi: true` döner, istemci her şeyi baştan yükler.
 *
 * KAPSAM: kiracı global kapsamın yanında AÇIKÇA da süzülür; şube daima
 * BranchContext'ten (istekten şube alınmaz). Şubesiz oturum hiçbir olay
 * görmez (pano ile aynı davranış).
 *
 * Yanıt yalnız kimlik + olay türü taşır (tutar/ad yok) — istemci gerekli
 * ekranı kendi ucundan tazeler.
 */
class OrderSenkronController extends Controller
{
    use \App\Modules\Tenancy\Concerns\ScopesToBranch;

    /** Tek yanıtta en çok bu kadar olay; fazlası `tasma` ile tam tazeleme ister. */
    private const OLAY_SINIRI = 200;

    /** Olay yükünde başka bir adisyonu gösteren alanlar (birleştir/taşı/böl). */
    private const ILGILI_ALANLAR = ['target_order_id', 'source_order_id', 'to_order_id', 'from_order_id', 'new_order_id'];

    public function degisim(Request $request): Response
    {
        // Şalter (config/orders.php): kapalıyken 404 → istemci kendini kapatır.
        abort_unless((bool) config('orders.degisim_acik', true), 404);

        $this->authorize('viewAny', Order::class);

        $tenantId = app(TenantContext::class)->tenantId();
        abort_if($tenantId === null, 403);

        $branchId = $this->currentBranchId() ?? 0;

        $ilk = ! $request->has('imlec') || ! is_numeric($request->query('imlec'));
        $imlec = $ilk ? 0 : max(0, (int) $request->query('imlec'));

        $son = $this->imlec($tenantId, $branchId);

        // İlk bağlanış: geçmişi göndermeden yalnız başlangıç imlecini ver.
        if ($ilk) {
            return $this->yanit(['imlec' => $son, 'ilk' => true, 'degisen_adisyonlar' => [], 'olaylar' => []]);
        }

        // İmleç geri gitti: olaylar silinmiş (geçmiş sıfırlama) → tam tazeleme.
        if ($son < $imlec) {
            return $this->yanit(['imlec' => $son, 'sifirlandi' => true, 'degisen_adisyonlar' => [], 'olaylar' => []]);
        }

        // ---- UZUN YOKLAMA (KDS ile aynı) ----
        $bekleSn = min(25, max(0, (int) config('orders.degisim_long_poll_seconds', 20)));

        if ($son <= $imlec && $bekleSn > 0 && ! app()->runningUnitTests()) {
            // OTURUM KİLİDİ: bırakılmazsa aynı cihazın diğer istekleri
            // (kalem ekleme, ödeme) bu istek bitene kadar donar.
            if ($request->hasSession()) {
                $request->session()->save();
            }
            @set_time_limit($bekleSn + 15);

            $bitis = microtime(true) + $bekleSn;
            $araMs = max(200, (int) config('orders.degisim_long_poll_interval_ms', 400));

            while (microtime(true) < $bitis) {
                usleep($araMs * 1000);

                if (connection_aborted() === 1) {
                    return response()->noContent();
                }

                $son = $this->imlec($tenantId, $branchId);
                if ($son !== $imlec) {
                    break;
                }
            }

            if ($son < $imlec) {
                return $this->yanit(['imlec' => $son, 'sifirlandi' => true, 'degisen_adisyonlar' => [], 'olaylar' => []]);
            }
        }

        if ($son <= $imlec) {
            return response()->noContent()->withHeaders([
                'X-Degisim-Imlec' => (string) $son,
                'Cache-Control' => 'no-store, private',
            ]);
        }

        $satirlar = OrderEvent::query()
            ->where('tenant_id', $tenantId)
            ->where('branch_id', $branchId)
            ->where('id', '>', $imlec)
            ->where('id', '<=', $son)
            ->orderBy('id')
            ->limit(self::OLAY_SINIRI + 1)
            ->get(['id', 'order_id', 'type', 'payload']);

        $tasma = $satirlar->count() > self::OLAY_SINIRI;
        if ($tasma) {
            $satirlar = $satirlar->take(self::OLAY_SINIRI);
        }

        $degisen = [];
        $olaylar = [];
        foreach ($satirlar as $e) {
            $orderId = (int) $e->order_id;
            $degisen[$orderId] = true;
            $yuk = is_array($e->payload) ? $e->payload : [];

            $olay = ['id' => (int) $e->id, 'order_id' => $orderId, 'tur' => (string) $e->type];
            foreach (self::ILGILI_ALANLAR as $alan) {
                if (isset($yuk[$alan]) && is_numeric($yuk[$alan]) && (int) $yuk[$alan] > 0) {
                    $degisen[(int) $yuk[$alan]] = true;
                }
            }
            if ($e->type === 'merged_into' && isset($yuk['target_order_id'])) {
                $olay['hedef_adisyon_id'] = (int) $yuk['target_order_id'];
            } elseif (in_array($e->type, ['item_moved_out'], true) && isset($yuk['to_order_id'])) {
                $olay['hedef_adisyon_id'] = (int) $yuk['to_order_id'];
            }
            $olaylar[] = $olay;
        }

        return $this->yanit([
            'imlec' => $son,
            'degisen_adisyonlar' => array_map('intval', array_keys($degisen)),
            'olaylar' => $olaylar,
            'tasma' => $tasma,
        ]);
    }

    private function imlec(int $tenantId, int $branchId): int
    {
        return (int) OrderEvent::query()
            ->where('tenant_id', $tenantId)
            ->where('branch_id', $branchId)
            ->max('id');
    }

    /** @param  array<string, mixed>  $govde */
    private function yanit(array $govde): Response
    {
        return response()->json($govde)->withHeaders(['Cache-Control' => 'no-store, private']);
    }
}
