<?php

namespace App\Modules\Portal\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Identity\Services\PinService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * Portal "Profilim": kişinin KENDİ bilgilerini güncellemesi + PIN belirle/değiştir.
 *
 * Hedef DAİMA $request->user() — başkasının hesabına dokunulamaz. Tema/bildirim
 * tercihleri paylaşılan uçlardan yönetilir (/api/v1/auth/preferences,
 * /api/v1/notifications/preferences) — portal Vue onları doğrudan çağırır.
 */
class PortalProfileController extends Controller
{
    public function __construct(
        private readonly PinService $pins,
        private readonly AuditLogger $audit,
    ) {
    }

    /** Ad / iletişim bilgilerini günceller (name = first+last otomatik türer). */
    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'first_name' => ['required', 'string', 'max:80'],
            'last_name' => ['nullable', 'string', 'max:80'],
            'phone' => ['nullable', 'string', 'max:32'],
        ]);

        $user = $request->user();
        $user->forceFill($data)->save();

        $this->audit->log('portal.profile_updated', $user);

        return response()->json([
            'user' => [
                'first_name' => $user->first_name,
                'last_name' => $user->last_name,
                'name' => $user->name,
                'phone' => $user->phone,
            ],
        ]);
    }

    /**
     * PIN belirle / değiştir. Mevcut PIN VARSA doğrulanır (mevcut PIN ucu);
     * ilk kez belirlerken gerekmez. Kilit/deneme sınırı PinService'te.
     */
    public function updatePin(Request $request): JsonResponse
    {
        $user = $request->user();
        $hasPin = $user->pin_hash !== null;

        $data = $request->validate([
            'current_pin' => [$hasPin ? 'required' : 'nullable', 'string'],
            'pin' => ['required', 'string'],
        ]);

        if ($hasPin && ! $this->pins->verify($user, (string) ($data['current_pin'] ?? ''))) {
            throw ValidationException::withMessages(['current_pin' => ['Mevcut PIN doğrulanamadı.']]);
        }

        $this->pins->setPin($user, $data['pin']);

        return response()->json(['ok' => true, 'has_pin' => true]);
    }
}
