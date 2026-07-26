<?php

namespace App\Modules\Notify\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Models\NotificationPreference;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * §8 Kişi-bazlı bildirim tercihleri (Profil > Bildirimler). Kullanıcı her olay
 * tipi için in-app / push kanalını ayrı ayrı açıp kapatır. Satır yoksa katalog
 * varsayılanı geçerli (NotificationType::default*).
 */
class NotificationPreferenceController extends Controller
{
    /** Katalog (gruplu) + kullanıcının mevcut tercihleri (etkili değerlerle). */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $saved = NotificationPreference::query()
            ->where('user_id', $user->getKey())
            ->get()
            ->keyBy('type');

        $catalog = array_map(function (array $entry) use ($saved): array {
            $row = $saved->get($entry['key']);

            return [
                ...$entry,
                'in_app' => $row ? (bool) $row->in_app : $entry['default_in_app'],
                'push' => $row ? (bool) $row->push : $entry['default_push'],
            ];
        }, NotificationType::catalog());

        return response()->json(['types' => $catalog]);
    }

    /** Tercihleri kaydet (kısmi: gelen tipler upsert edilir). */
    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'preferences' => ['required', 'array'],
            'preferences.*.type' => ['required', 'string', Rule::in(array_column(NotificationType::catalog(), 'key'))],
            'preferences.*.in_app' => ['required', 'boolean'],
            'preferences.*.push' => ['required', 'boolean'],
        ]);

        $user = $request->user();

        foreach ($data['preferences'] as $pref) {
            NotificationPreference::query()->updateOrCreate(
                ['user_id' => $user->getKey(), 'type' => $pref['type']],
                [
                    'tenant_id' => $user->tenant_id,
                    'in_app' => $pref['in_app'],
                    'push' => $pref['push'],
                ],
            );
        }

        return response()->json(['ok' => true]);
    }
}
