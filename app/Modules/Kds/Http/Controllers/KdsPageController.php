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
            // Kısıtlı kullanıcı yalnız barista ailesindeyse Barista'ya, aksi
            // (mutfak/karışık) hâlde Mutfak ekranına yönlendir.
            $onlyBarista = $families === ['barista'];

            return redirect()->to($onlyBarista ? '/panel/barista' : '/panel/mutfak');
        }

        $requested = (string) $request->query('istasyon', '');

        if ($requested === '') {
            $allowed = $this->kds->allowedStations($user);
            $requested = ($allowed === null || in_array($default, $allowed, true)) ? $default : '';
        }

        // $default = bu ekranın KULVARI ('kitchen'|'barista'). Kitchen.vue çipleri
        // yalnız bu kulvarın istasyonlarıyla sınırlar; "Tümü" ve kuyruk lane ile
        // daralır (Mutfak barista çiplerini/kalemlerini HİÇ göstermez, tersi de).
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
