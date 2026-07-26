<?php

namespace App\Modules\Notify\Services;

use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Models\Notification;
use Illuminate\Support\Facades\Log;

/**
 * §8 BİLDİRİM DAĞITICISI — tek giriş kapısı.
 *
 *   notify(type, context) →
 *     1) alıcıları belirle (RecipientResolver: rol/istasyon/şube)
 *     2) her alıcı için tercihe bak (PreferenceResolver: in_app/push)
 *     3) in_app açıksa notifications kaydı (kısa-pencere dedup)
 *     4) push açıksa web push (WebPushSender; ölü abonelik budanır)
 *
 * BEST-EFFORT: bildirim üretimi ANA İŞ AKIŞINI ASLA düşürmez (model olay
 * dinleyicileri + SLA cron buradan çağırır). Hata report/log'lanır, yutulur.
 *
 * Dedup: aynı (alıcı, dedup_key) için kısa pencerede (config) ikinci kayıt
 * yazılmaz — çift-tetik (aynı siparişe hızlı ard arda kalem) tek bildirim olur.
 */
class NotificationDispatcher
{
    public function __construct(
        private readonly RecipientResolver $recipients,
        private readonly PreferenceResolver $preferences,
        private readonly WebPushSender $push,
    ) {}

    /**
     * @param  array{
     *   tenant_id:int, branch_id?:int|null, title:string, body?:?string,
     *   data?:array<string,mixed>, dedup_key?:?string, lane?:?string,
     *   extra_user_ids?:array<int,int>, exclude_user_ids?:array<int,int>
     * }  $context
     * @return int  yazılan (in-app) bildirim sayısı
     */
    public function notify(NotificationType $type, array $context): int
    {
        try {
            return $this->dispatch($type, $context);
        } catch (\Throwable $e) {
            Log::warning('Bildirim dağıtımı başarısız', [
                'type' => $type->value,
                'error' => $e->getMessage(),
            ]);

            return 0;
        }
    }

    /**
     * @param  array<string, mixed>  $context
     */
    private function dispatch(NotificationType $type, array $context): int
    {
        $tenantId = (int) ($context['tenant_id'] ?? 0);

        if ($tenantId <= 0) {
            return 0;
        }

        $branchId = isset($context['branch_id']) ? ($context['branch_id'] !== null ? (int) $context['branch_id'] : null) : null;
        $title = (string) ($context['title'] ?? $type->label());
        $body = isset($context['body']) ? ($context['body'] !== null ? (string) $context['body'] : null) : null;
        $data = (array) ($context['data'] ?? []);
        $dedupKey = isset($context['dedup_key']) ? (string) $context['dedup_key'] : null;

        $recipients = $this->recipients->resolve($type, $tenantId, $branchId, [
            'lane' => $context['lane'] ?? null,
            'extra_user_ids' => $context['extra_user_ids'] ?? [],
        ]);

        // Olay sahibini (ör. molaya çıkan personelin kendisi) alıcı havuzundan
        // çıkar — includeManagers ile geri sızabileceğinden burada kesin süzülür.
        $excludeIds = array_map('intval', (array) ($context['exclude_user_ids'] ?? []));
        if ($excludeIds !== []) {
            $recipients = $recipients->reject(
                fn ($user) => in_array((int) $user->getKey(), $excludeIds, true)
            )->values();
        }

        if ($recipients->isEmpty()) {
            return 0;
        }

        // Dedup penceresi: varsayılan kısa (config); SLA/stok/rezervasyon gibi
        // "bir kez" olaylar uzun pencere geçirir (context['dedup_window']).
        $window = isset($context['dedup_window'])
            ? (int) $context['dedup_window']
            : (int) config('notify.dedup_window_seconds', 60);
        $pushPayload = [
            'type' => $type->value,
            'title' => $title,
            'body' => $body,
            'icon' => $type->icon(),
            'url' => $data['url'] ?? '/panel',
            'tag' => $dedupKey ?? ($type->value.'-'.($data['order_id'] ?? $data['reservation_id'] ?? '')),
        ];

        $written = 0;

        foreach ($recipients as $user) {
            $pref = $this->preferences->for((int) $user->getKey(), $type);

            if (! $pref['in_app'] && ! $pref['push']) {
                continue;
            }

            if ($pref['in_app']) {
                // Kısa-pencere dedup: aynı alıcı+anahtar yakın zamanda yazıldıysa atla.
                $duplicate = $dedupKey !== null && Notification::query()
                    ->where('user_id', $user->getKey())
                    ->where('dedup_key', $dedupKey)
                    ->where('created_at', '>=', now()->subSeconds($window))
                    ->exists();

                if (! $duplicate) {
                    // tenant_id BİLİNÇLİ olarak fillable DEĞİL (BelongsToTenant) → doğrudan
                    // atanır. Cron/bypassed ve bağlamsız yollarda da doğru kiracıya yazılır
                    // (HTTP/model-olay yolunda bağlamdan otomatik atanırdı).
                    $notification = new Notification([
                        'branch_id' => $branchId,
                        'user_id' => $user->getKey(),
                        'type' => $type->value,
                        'title' => $title,
                        'body' => $body,
                        'data' => $data ?: null,
                        'dedup_key' => $dedupKey,
                    ]);
                    $notification->tenant_id = $tenantId;
                    $notification->save();
                    $written++;
                }
            }

            if ($pref['push']) {
                $this->push->sendToUser($user, $pushPayload);
            }
        }

        return $written;
    }
}
