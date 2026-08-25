<?php

namespace App\Modules\Portal\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Shifts\Models\Shift;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Portal "Takvim": kişinin KENDİ yaklaşan vardiyaları (self-servis; izin YOK).
 *
 * Yalnız oturum sahibinin (user_id = auth) vardiyaları döner; şube kapsamı
 * gerekmez (kişi kendi planını her şubede görür). Bugünden itibaren ileriye
 * dönük + bugünün geçmiş vardiyaları da (gün grubu bütünlüğü için) dahildir.
 */
class PortalScheduleController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $tz = config('app.timezone');
        $from = CarbonImmutable::now($tz)->startOfDay();
        $to = $from->addDays(28); // 4 haftalık ufuk

        $shifts = Shift::query()
            ->where('user_id', $user->getKey())
            ->where('starts_at', '>=', $from)
            ->where('starts_at', '<', $to)
            ->with('branch:id,name')
            ->orderBy('starts_at')
            ->get();

        $items = $shifts->map(fn (Shift $s): array => [
            'id' => (int) $s->getKey(),
            'starts_at' => $s->starts_at->toIso8601String(),
            'ends_at' => $s->ends_at->toIso8601String(),
            'position' => $s->position,
            'branch_name' => $s->branch?->name,
            'note' => $s->note,
            'planned_min' => $s->plannedMinutes(),
        ])->values();

        // Güne göre grupla (frontend hazır tüketsin).
        $dayFmt = new \IntlDateFormatter('tr_TR', \IntlDateFormatter::FULL, \IntlDateFormatter::NONE, $tz);
        $grouped = $shifts
            ->groupBy(fn (Shift $s): string => $s->starts_at->copy()->timezone($tz)->format('Y-m-d'))
            ->map(function ($group, string $date) use ($tz, $dayFmt): array {
                $d = CarbonImmutable::parse($date, $tz);
                $today = CarbonImmutable::now($tz)->startOfDay();
                $label = match (true) {
                    $d->isSameDay($today) => 'Bugün',
                    $d->isSameDay($today->addDay()) => 'Yarın',
                    default => (string) ($dayFmt->format($d->toDateTime()) ?: $d->format('d.m.Y')),
                };

                return [
                    'date' => $date,
                    'label' => $label,
                    'items' => $group->map(fn (Shift $s): array => [
                        'id' => (int) $s->getKey(),
                        'starts_at' => $s->starts_at->toIso8601String(),
                        'ends_at' => $s->ends_at->toIso8601String(),
                        'position' => $s->position,
                        'branch_name' => $s->branch?->name,
                        'note' => $s->note,
                        'planned_min' => $s->plannedMinutes(),
                    ])->values()->all(),
                ];
            })
            ->values()
            ->all();

        return response()->json([
            'shifts' => $items,
            'grouped_by_day' => $grouped,
        ]);
    }
}
