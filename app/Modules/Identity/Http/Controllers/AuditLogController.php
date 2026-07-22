<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\AuditLog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Denetim kayıtları SALT OKUNUR uçtan sunulur (audit.view izni).
 * Değiştirme/silme rotası YOKTUR; model düzeyinde de yasaktır.
 */
class AuditLogController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('audit.view'), 403);

        $query = AuditLog::query()->latest('id');

        if ($request->filled('action')) {
            $query->where('action', $request->string('action'));
        }

        if ($request->filled('user_id')) {
            $query->where('user_id', $request->integer('user_id'));
        }

        return response()->json(['audit_logs' => $query->paginate(50)]);
    }
}
