<?php

namespace App\Modules\Notify\Services;

use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Models\NotificationPreference;

/**
 * §8 Tercih çözücü: (kullanıcı, olay tipi) için etkili kanal ayarı. Satır
 * yoksa katalog varsayılanı (NotificationType::default*). İstek-içi memo.
 */
class PreferenceResolver
{
    /** @var array<int, array<string, array{in_app:bool, push:bool}>> user_id → type → kanallar */
    private array $cache = [];

    /**
     * @return array{in_app:bool, push:bool}
     */
    public function for(int $userId, NotificationType $type): array
    {
        if (! isset($this->cache[$userId])) {
            $this->cache[$userId] = NotificationPreference::query()
                ->where('user_id', $userId)
                ->get()
                ->keyBy('type')
                ->map(fn (NotificationPreference $p): array => [
                    'in_app' => (bool) $p->in_app,
                    'push' => (bool) $p->push,
                ])
                ->all();
        }

        return $this->cache[$userId][$type->value] ?? [
            'in_app' => $type->defaultInApp(),
            'push' => $type->defaultPush(),
        ];
    }

    public function flush(): void
    {
        $this->cache = [];
    }
}
