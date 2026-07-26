<?php

namespace App\Modules\Notify\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Notify\Models\PushSubscription;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * §8 Web Push abonelik uçları. Tarayıcı SW aboneliği kaydedilir/silinir;
 * VAPID public key JS'e verilir. Abonelik OTURUM SAHİBİNE (user_id) bağlıdır.
 */
class PushSubscriptionController extends Controller
{
    /** Frontend'in PushManager.subscribe için ihtiyaç duyduğu public key. */
    public function vapidPublicKey(): JsonResponse
    {
        return response()->json([
            'key' => (string) config('notify.vapid.public_key', ''),
            'enabled' => (bool) config('notify.push_enabled', true) && config('notify.vapid.public_key'),
        ]);
    }

    /** Aboneliği kaydet (upsert — aynı endpoint tekrar gelirse günceller). */
    public function subscribe(Request $request): JsonResponse
    {
        $data = $request->validate([
            'endpoint' => ['required', 'string', 'max:1000', 'url'],
            'keys.p256dh' => ['required', 'string', 'max:255'],
            'keys.auth' => ['required', 'string', 'max:255'],
        ]);

        $user = $request->user();
        $endpoint = $data['endpoint'];

        PushSubscription::query()->updateOrCreate(
            ['endpoint_hash' => PushSubscription::hashEndpoint($endpoint)],
            [
                'tenant_id' => $user->tenant_id,
                'user_id' => $user->getKey(),
                'endpoint' => $endpoint,
                'p256dh' => $data['keys']['p256dh'],
                'auth' => $data['keys']['auth'],
                'ua' => substr((string) $request->userAgent(), 0, 300),
                'last_used_at' => now(),
            ],
        );

        return response()->json(['ok' => true]);
    }

    /** Aboneliği kaldır (cihaz push'u kapattı / SW abonelikten çıktı). */
    public function unsubscribe(Request $request): JsonResponse
    {
        $data = $request->validate([
            'endpoint' => ['required', 'string', 'max:1000'],
        ]);

        PushSubscription::query()
            ->where('user_id', $request->user()->getKey())
            ->where('endpoint_hash', PushSubscription::hashEndpoint($data['endpoint']))
            ->delete();

        return response()->json(['ok' => true]);
    }
}
