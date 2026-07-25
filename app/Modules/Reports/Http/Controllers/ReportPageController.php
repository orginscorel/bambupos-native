<?php

namespace App\Modules\Reports\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Payments\Enums\PaymentMethod;
use App\Modules\Reports\Support\ReportRegistry;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Raporlar ekranı (Inertia). Veri /api/v1/reports uçlarından yüklenir;
 * sözlükler (kanal/yöntem etiketleri, rapor kataloğu) PHP'den prop gider.
 */
class ReportPageController extends Controller
{
    public function index(Request $request): Response
    {
        abort_unless($request->user()->hasPermission('reports.view'), 403);

        return Inertia::render('Panel/Reports/Index', [
            'channels' => OrderChannel::options(),
            'paymentMethods' => array_map(
                fn (PaymentMethod $m) => ['value' => $m->value, 'label' => $m->label()],
                PaymentMethod::cases(),
            ),
            'reportCatalog' => collect(ReportRegistry::all())
                ->map(fn (array $def, string $key) => ['key' => $key, 'title' => $def['title']])
                ->values()
                ->all(),
        ]);
    }
}
