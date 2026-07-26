<?php

namespace App\Modules\Notify\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Notify\Models\PushSubscription;
use Illuminate\Support\Facades\Log;
use Minishlink\WebPush\Subscription;
use Minishlink\WebPush\WebPush;

/**
 * §8 Web Push gönderimi (VAPID). Redis yok → doğrudan gönderim (best-effort).
 *
 *  - Kullanıcının tüm aboneliklerine tek payload gönderir.
 *  - ÖLÜ abonelik (push servisi 404/410 = expired) budanır.
 *  - VAPID anahtarı yoksa ya da notify.push_enabled=false ise (test) NO-OP.
 *  - Hiçbir hata çağıran akışı düşürmez (dispatcher zaten sarmalar).
 */
class WebPushSender
{
    public function enabled(): bool
    {
        return (bool) config('notify.push_enabled', true)
            && config('notify.vapid.public_key')
            && config('notify.vapid.private_key');
    }

    /**
     * @param  array<string, mixed>  $payload  service worker'ın göstereceği veri
     */
    public function sendToUser(User $user, array $payload): void
    {
        if (! $this->enabled()) {
            return;
        }

        $subscriptions = PushSubscription::query()
            ->where('user_id', $user->getKey())
            ->get();

        if ($subscriptions->isEmpty()) {
            return;
        }

        try {
            $webPush = $this->client();
            $byEndpoint = [];

            foreach ($subscriptions as $sub) {
                $byEndpoint[$sub->endpoint] = $sub;
                $webPush->queueNotification(
                    Subscription::create([
                        'endpoint' => $sub->endpoint,
                        'keys' => ['p256dh' => $sub->p256dh, 'auth' => $sub->auth],
                    ]),
                    json_encode($payload, JSON_UNESCAPED_UNICODE) ?: '{}',
                );
            }

            foreach ($webPush->flush() as $report) {
                $endpoint = $report->getEndpoint();
                $sub = $byEndpoint[$endpoint] ?? null;

                if ($sub === null) {
                    continue;
                }

                if ($report->isSuccess()) {
                    $sub->forceFill(['last_used_at' => now()])->saveQuietly();
                } elseif ($report->isSubscriptionExpired()) {
                    // 404/410 → cihaz aboneliği düşmüş, kalıcı sil (yetim budama).
                    $sub->delete();
                }
            }
        } catch (\Throwable $e) {
            // Push best-effort: ağ/kütüphane hatası bildirimin geri kalanını bozmaz.
            Log::warning('WebPush gönderimi başarısız', ['user_id' => $user->getKey(), 'error' => $e->getMessage()]);
        }
    }

    private function client(): WebPush
    {
        return new WebPush([
            'VAPID' => [
                'subject' => (string) config('notify.vapid.subject'),
                'publicKey' => (string) config('notify.vapid.public_key'),
                'privateKey' => (string) config('notify.vapid.private_key'),
            ],
        ]);
    }
}
