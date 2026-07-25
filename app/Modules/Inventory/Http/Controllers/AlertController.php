<?php

namespace App\Modules\Inventory\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Services\AlertService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Uyarı panosu (§17.5) — panel içi liste. */
class AlertController extends Controller
{
    public function index(Request $request, AlertService $alerts): JsonResponse
    {
        $this->authorize('viewAny', StockItem::class);

        return response()->json(['alerts' => $alerts->build((int) $request->user()->tenant_id)]);
    }
}
