<?php

namespace App\Modules\Kds\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Kds\Services\KdsService;
use App\Modules\Kds\Services\StationRegistry;
use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Orders\Enums\OrderItemStatus;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * KDS Inertia sayfaları: /panel/mutfak (mutfak+bar) ve /panel/komi.
 * Yalnız OPERASYON meta'sı gider — fiyat/ciro yok (prompt §20).
 */
class KdsPageController extends Controller
{
    public function __construct(
        private readonly StationRegistry $stations,
        private readonly KdsService $kds,
    ) {
    }

    /** MUTFAK ekranı (§12): varsayılan süzgeç = Mutfak (tüm yemekler). */
    public function kitchen(Request $request): Response|RedirectResponse
    {
        return $this->screen($request, 'kitchen');
    }

    /** BARİSTA ekranı (§12): aynı ekran, varsayılan süzgeç = Barista (içecekler). */
    public function barista(Request $request): Response|RedirectResponse
    {
        return $this->screen($request, 'barista');
    }

    /** NARGİLE ekranı: 'nargile' eklentisi AÇIKSA ayrı kulvar; kapalıyken 404. */
    public function hookah(Request $request): Response|RedirectResponse
    {
        $tenantId = (int) app(\App\Modules\Tenancy\TenantContext::class)->tenantId();
        abort_unless(\App\Modules\Settings\Support\Features::enabled($tenantId, 'nargile'), 404);

        return $this->screen($request, 'nargile');
    }

    /**
     * Mutfak/Barista ekranı — aynı premium tasarım, yalnız varsayılan istasyon
     * süzgeci değişir. ?istasyon=X açıkça verilirse o kazanır; verilmezse
     * ekranın kendi varsayılanı ($default) uygulanır.
     *
     * §12 İSTASYON-KAPSAMLI ROTA KORUMASI: kullanıcı istasyona atanmışsa
     * (kısıtlı) yalnız KENDİ ailesinin ekranını açabilir — mutfak-atanmış kişi
     * /panel/barista'ya gelirse kendi ekranına (/panel/mutfak) yönlendirilir,
     * ve tersi. Yönetici/çok-istasyonlu (aile [] = kısıt yok) serbest gezer.
     */
    private function screen(Request $request, string $default): Response|RedirectResponse
    {
        $user = $request->user();
        abort_unless($user->hasPermission('kds.view'), 403);

        // $default ('kitchen'|'barista') = bu ekranın istasyon AİLESİ.
        $families = $this->kds->stationFamilies($user);

        if ($families !== [] && ! in_array($default, $families, true)) {
            // Kısıtlı kullanıcıyı KENDİ kulvarına yönlendir (barista/nargile/mutfak).
            if ($families === ['barista']) {
                return redirect()->to('/panel/barista');
            }
            if ($families === ['nargile']) {
                return redirect()->to('/panel/nargile');
            }

            return redirect()->to('/panel/mutfak');
        }

        // VARSAYILAN = "Tümü" (bu ekranın/kulvarın TÜM istasyonları) → hiçbir kalem
        // gizlenmez. Eskiden ekran tek istasyona (ör. 'kitchen') açılıyordu; Izgara/
        // Tatlı/Fırın'a atanan kalemler görünmüyordu ("gözden kaçma"). Personel dilerse
        // ?istasyon=X ile (çiplerle) tek istasyona daraltabilir; ama zorunlu değil.
        $requested = (string) $request->query('istasyon', '');

        // $default = bu ekranın KULVARI ('kitchen'|'barista'|'nargile'). Kuyruk + çipler
        // lane ile sınırlıdır (Mutfak barista/nargile kalemini HİÇ göstermez, tersi de).
        return Inertia::render('Panel/Kds/Kitchen', $this->meta($request) + [
            'initialStation' => $requested,
            'lane' => $default,
            'laneStations' => $this->kds->laneStations($default),
        ]);
    }

    /** Komi ekranı: hazır ürünler → teslim aldım / masaya götürdüm. */
    public function runner(Request $request): Response
    {
        abort_unless($request->user()->hasPermission('kds.deliver'), 403);

        return Inertia::render('Panel/Kds/Runner', $this->meta($request));
    }

    /** @return array<string, mixed> */
    private function meta(Request $request): array
    {
        $user = $request->user();

        return [
            'stations' => $this->stations->all()->all(),
            'allowedStations' => $this->kds->allowedStations($user),
            'itemStatuses' => OrderItemStatus::options(),
            'channels' => OrderChannel::options(),
            'kdsConfig' => [
                'poll_interval_seconds' => (int) config('kds.poll_interval_seconds', 4),
                'default_prep_minutes' => (int) config('kds.default_prep_minutes', 15),
                'late_ratio' => (float) config('kds.late_ratio', 1.5),
                'unassigned_key' => (string) config('kds.unassigned_key', '_none'),
            ],
            'canManageStations' => $user->hasPermission('kds.manage'),
            'canDeliver' => $user->hasPermission('kds.deliver'),
        ];
    }
}
