<?php

namespace App\Modules\Portal\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Notify\Services\NotifyEmitter;
use App\Modules\Portal\Services\PortalShiftService;
use App\Modules\Shifts\Models\TimeEntryBreak;
use App\Modules\Shifts\Services\TimeClockService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Portal "Mesaim": kişinin KENDİ mesai/mola uçları — PIN'SİZ.
 *
 * Device-clock (§13) ortak tablette PIN ister çünkü kim olduğu belirsizdir.
 * Portalda ise oturum SAHİBİ eylemi yapar → kimlik zaten oturumdan gelir,
 * ayrıca PIN sorulmaz. Mola/tuvalet başlat-bitir §8 NotifyEmitter ile
 * yöneticiye + o an mesaide olan diğer personele bildirilir (şube-izole).
 */
class PortalClockController extends Controller
{
    public function __construct(
        private readonly TimeClockService $clock,
        private readonly PortalShiftService $shifts,
        private readonly NotifyEmitter $notify,
    ) {
    }

    /** Anlık durum (Mesaim ekranı ilk yükleme + poll). */
    public function state(Request $request): JsonResponse
    {
        return response()->json($this->shifts->state($request->user()));
    }

    /** Mesai başlat (clock in). */
    public function clockIn(Request $request): JsonResponse
    {
        $this->clock->clockIn($request->user(), [
            'method' => 'portal',
            'ip' => $request->ip(),
        ]);

        return $this->stateResponse($request);
    }

    /** Mesai bitir (clock out). */
    public function clockOut(Request $request): JsonResponse
    {
        $this->clock->clockOut($request->user(), [
            'method' => 'portal',
            'ip' => $request->ip(),
        ]);

        return $this->stateResponse($request);
    }

    /** Mola başlat (normal veya tuvalet). */
    public function breakStart(Request $request): JsonResponse
    {
        $data = $request->validate([
            'kind' => ['nullable', 'in:break,toilet'],
        ]);

        $kind = ($data['kind'] ?? TimeEntryBreak::KIND_BREAK) === TimeEntryBreak::KIND_TOILET
            ? TimeEntryBreak::KIND_TOILET
            : TimeEntryBreak::KIND_BREAK;

        $break = $this->clock->breakStart($request->user(), $kind);

        // §8: yönetici + o an mesaide olan diğer personel bilgilendirilir.
        $this->notify->staffBreak($request->user(), $break, 'start');

        return $this->stateResponse($request);
    }

    /** Mola bitir. */
    public function breakEnd(Request $request): JsonResponse
    {
        $break = $this->clock->breakEnd($request->user());

        $this->notify->staffBreak($request->user(), $break, 'end');

        return $this->stateResponse($request);
    }

    private function stateResponse(Request $request): JsonResponse
    {
        return response()->json($this->shifts->state($request->user()));
    }
}
