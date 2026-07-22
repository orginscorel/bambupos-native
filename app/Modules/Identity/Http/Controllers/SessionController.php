<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Services\AuditLogger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;

/**
 * Aktif cihaz/oturum yönetimi (database session sürücüsü üzerinden).
 * IDOR koruması: her sorgu user_id = oturum sahibi ile süzülür;
 * başka kullanıcının oturum id'si 404 döner.
 */
class SessionController extends Controller
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $currentId = $request->session()->getId();

        $sessions = DB::table('sessions')
            ->where('user_id', $request->user()->getKey())
            ->orderByDesc('last_activity')
            ->get()
            ->map(fn ($session) => [
                'id' => hash('sha256', $session->id), // ham oturum id'si asla dışarı verilmez
                'ip_address' => $session->ip_address,
                'user_agent' => $session->user_agent,
                'last_activity' => date('c', (int) $session->last_activity),
                'current' => hash_equals($session->id, $currentId),
            ]);

        return response()->json(['sessions' => $sessions]);
    }

    /** Tek bir oturumu (hash id ile) sonlandır — yalnız kendi oturumları. */
    public function destroy(Request $request, string $hashedId): JsonResponse
    {
        $sessions = DB::table('sessions')
            ->where('user_id', $request->user()->getKey())
            ->get(['id']);

        $target = $sessions->first(fn ($s) => hash_equals(hash('sha256', $s->id), $hashedId));

        if ($target === null) {
            abort(404);
        }

        DB::table('sessions')->where('id', $target->id)->delete();

        $this->audit->log('auth.session_revoked', $request->user());

        return response()->json(['ok' => true]);
    }

    /** Diğer tüm cihazlardan çıkış (parola doğrulamalı). */
    public function destroyOthers(Request $request): JsonResponse
    {
        $request->validate(['password' => ['required', 'string', 'current_password:web']]);

        Auth::logoutOtherDevices($request->input('password'));

        DB::table('sessions')
            ->where('user_id', $request->user()->getKey())
            ->where('id', '!=', $request->session()->getId())
            ->delete();

        $this->audit->log('auth.other_sessions_revoked', $request->user());

        return response()->json(['ok' => true]);
    }
}
