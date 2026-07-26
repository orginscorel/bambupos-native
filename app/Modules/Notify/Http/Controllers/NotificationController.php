<?php

namespace App\Modules\Notify\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * §8 Panel-içi bildirim zili uçları (PanelShell). Yalnız OTURUM SAHİBİNİN
 * bildirimleri (user_id). Kiracı kapsamı Notification global scope'undan.
 */
class NotificationController extends Controller
{
    /** Zil listesi: okunmamış sayısı + son bildirimler. */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $limit = (int) config('notify.bell_list_limit', 30);

        $items = Notification::query()
            ->where('user_id', $user->getKey())
            ->latest('id')
            ->limit($limit)
            ->get();

        $unread = Notification::query()
            ->where('user_id', $user->getKey())
            ->whereNull('read_at')
            ->count();

        return response()->json([
            'unread_count' => $unread,
            'items' => $items->map(fn (Notification $n): array => $this->present($n))->all(),
        ], 200, ['Cache-Control' => 'no-store, private']);
    }

    /** Tek bildirimi okundu işaretle. */
    public function markRead(Request $request, Notification $notification): JsonResponse
    {
        $this->assertOwned($request, $notification);

        if ($notification->read_at === null) {
            $notification->forceFill(['read_at' => now()])->save();
        }

        return response()->json(['ok' => true]);
    }

    /** Hepsini okundu işaretle. */
    public function markAllRead(Request $request): JsonResponse
    {
        Notification::query()
            ->where('user_id', $request->user()->getKey())
            ->whereNull('read_at')
            ->update(['read_at' => now()]);

        return response()->json(['ok' => true]);
    }

    private function assertOwned(Request $request, Notification $notification): void
    {
        abort_unless((int) $notification->user_id === (int) $request->user()->getKey(), 404);
    }

    /**
     * @return array<string, mixed>
     */
    private function present(Notification $n): array
    {
        $type = $n->typeEnum();

        return [
            'id' => (int) $n->getKey(),
            'type' => $n->type,
            'title' => $n->title,
            'body' => $n->body,
            'icon' => $type?->icon() ?? 'bell',
            'url' => $n->data['url'] ?? '/panel',
            'read' => $n->read_at !== null,
            'created_at' => $n->created_at?->toIso8601String(),
        ];
    }
}
