<?php

namespace App\Modules\Reporting\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Catalog\Models\Product;
use App\Modules\Ordering\Models\Customer;
use App\Modules\Ordering\Models\Order;
use App\Modules\Tables\Models\Table;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Rapor okuma modeli iskeleti. Tüm sorgular global scope'lu modellerden
 * geçtiği için raporlar yapısal olarak yalnız bağlamdaki kiracıyı toplar;
 * istekten tenant/branch parametresiyle başka kiracı raporu alınamaz.
 */
class ReportController extends Controller
{
    public function summary(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('reports.view'), 403);

        return response()->json([
            'orders' => Order::query()->count(),
            'revenue_minor' => (int) Order::query()->where('status', '!=', 'cancelled')->sum('total_minor'), // ADR-007
            'products' => Product::query()->count(),
            'customers' => Customer::query()->count(),
            'tables' => Table::query()->count(),
        ]);
    }
}
