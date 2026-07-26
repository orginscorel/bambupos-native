<?php

namespace App\Modules\Receivables\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Receivables\Models\Receivable;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/** Borçlar/Cari panel sayfası (Inertia). Veri /api/v1/receivables uçlarından yüklenir. */
class ReceivablePageController extends Controller
{
    public function index(Request $request): Response
    {
        // §9 feature-flag: kapalıysa borçlar/cari hiç yok (ADR: kapalı=404).
        abort_unless(
            \App\Modules\Settings\Support\Features::enabled((int) $request->user()?->tenant_id, 'receivables'),
            404,
        );

        $this->authorize('viewAny', Receivable::class);

        return Inertia::render('Panel/Receivables/Index');
    }
}
