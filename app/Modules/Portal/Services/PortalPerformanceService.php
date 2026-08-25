<?php

namespace App\Modules\Portal\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Kds\Models\ItemPickup;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderEvent;
use App\Modules\Shifts\Models\TimeEntry;
use App\Modules\Shifts\Models\TimeEntryBreak;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Portal "Raporlarım" KİŞİSEL performans analitiği.
 *
 * Auth kullanıcının KENDİ verisi; tenant + kişi bazlı türetilir. Kişi kendi
 * verisini HER şubede görür (BranchContext'e göre süzülmez — kişi bazlı yeter).
 * Tüm süreler DAKİKA-integer; boş dönemde sayımlar 0, ortalamalar null (çökme yok).
 *
 * Kaynaklar:
 *  - worked : time_entries (+ time_entry_breaks) — çalışılan/mola/tuvalet süresi.
 *  - ops    : order_events (ready/served) + kds_item_pickups — üretim/servis akışı.
 *  - orders : PerformanceService mantığının bu kullanıcıya indirgenmiş hali.
 *
 * Tüm model sorguları TenantScope (BelongsToTenant) ile otomatik tenant-scoped'tur.
 */
class PortalPerformanceService
{
    /** Geçerli dönemler. */
    private const PERIODS = ['day', 'week', 'month'];

    /** Ready→served bu dakikayı aşarsa "gecikme" sayılır (servis bekletildi). */
    private const DELAY_THRESHOLD_MIN = 15;

    /** Pozisyon anahtarı → insan-okur Türkçe etiket (role_label için). */
    private const POSITION_LABELS = [
        'garson' => 'Garson',
        'komi' => 'Komi',
        'mutfak' => 'Mutfak',
        'barista' => 'Barista',
        'kasiyer' => 'Kasiyer',
        'kasa' => 'Kasiyer',
        'yonetici' => 'Yönetici',
        'mudur' => 'Müdür',
        'sef' => 'Şef',
    ];

    /**
     * Kullanıcının seçili dönemdeki kişisel performans özeti.
     *
     * @return array<string, mixed>
     */
    public function forUser(User $user, string $period): array
    {
        $period = in_array($period, self::PERIODS, true) ? $period : 'week';

        [$from, $to] = $this->range($period);

        // Dönem içindeki her takvim günü için sıfır-dolgulu iskelet (grafik dostu,
        // boş dönemde de tutarlı). Anahtar: Y-m-d.
        $days = $this->dayKeys($from, $to);

        return [
            'period' => $period,
            'from' => $from->toIso8601String(),
            'to' => $to->toIso8601String(),
            'position' => $user->position,
            'role_label' => $this->roleLabel($user),
            'worked' => $this->worked($user, $from, $to, $days),
            'ops' => $this->ops($user, $from, $to, $days),
            'orders' => $this->orders($user, $from, $to),
        ];
    }

    /**
     * Dönem aralığı [from, to). Zaman dilimi config('app.timezone');
     * hafta Pazartesi başlar (tr).
     *
     * @return array{0: Carbon, 1: Carbon}
     */
    private function range(string $period): array
    {
        $now = Carbon::now(config('app.timezone'))->locale('tr');

        return match ($period) {
            'day' => [
                $from = $now->copy()->startOfDay(),
                $from->copy()->addDay(),
            ],
            'month' => [
                $from = $now->copy()->startOfMonth(),
                $from->copy()->addMonth(),
            ],
            default => [ // week
                $from = $now->copy()->startOfWeek(Carbon::MONDAY)->startOfDay(),
                $from->copy()->addDays(7),
            ],
        };
    }

    /**
     * Dönemdeki takvim günlerinin Y-m-d anahtarları (from dahil, to hariç).
     *
     * @return array<int, string>
     */
    private function dayKeys(Carbon $from, Carbon $to): array
    {
        $keys = [];
        $cursor = $from->copy();

        while ($cursor->lt($to)) {
            $keys[] = $cursor->toDateString();
            $cursor->addDay();
        }

        return $keys;
    }

    /**
     * worked: çalışılan/mola/tuvalet dakikaları + günlük döküm.
     *
     * @param  array<int, string>  $days
     * @return array<string, mixed>
     */
    private function worked(User $user, Carbon $from, Carbon $to, array $days): array
    {
        $now = Carbon::now(config('app.timezone'));

        /** @var Collection<int, TimeEntry> $entries */
        $entries = TimeEntry::query()
            ->where('user_id', $user->id)
            ->where('clock_in_at', '>=', $from)
            ->where('clock_in_at', '<', $to)
            ->with('breaks')
            ->get();

        // Planlı mesai süresi: dönemdeki vardiyaların (mola düşülmüş) toplamı.
        $plannedMin = (int) \App\Modules\Shifts\Models\Shift::query()
            ->where('user_id', $user->id)
            ->where('starts_at', '>=', $from)
            ->where('starts_at', '<', $to)
            ->get(['starts_at', 'ends_at', 'break_min'])
            ->sum(fn (\App\Modules\Shifts\Models\Shift $s): int => $s->plannedMinutes());

        // Günlük sıfır-dolgulu iskelet. sessions = o gün kaç kez mesai
        // başlat→bitir yapılmış (her TimeEntry bir seans). >1 = olası hata.
        $byDay = [];
        foreach ($days as $date) {
            $byDay[$date] = ['date' => $date, 'worked_min' => 0, 'break_min' => 0, 'sessions' => 0];
        }

        $totalMin = 0;
        $breakMin = 0;
        $toiletMin = 0;
        $totalSessions = 0;
        $activeDays = [];

        foreach ($entries as $entry) {
            $worked = $this->liveWorkedMinutes($entry, $now);
            $entryBreak = $this->breakMinutes($entry, TimeEntryBreak::KIND_BREAK);
            $entryToilet = $this->breakMinutes($entry, TimeEntryBreak::KIND_TOILET);

            $totalMin += $worked;
            $breakMin += $entryBreak;
            $toiletMin += $entryToilet;
            $totalSessions++;

            $date = $entry->clock_in_at->toDateString();
            $activeDays[$date] = true;

            if (isset($byDay[$date])) {
                $byDay[$date]['worked_min'] += $worked;
                $byDay[$date]['break_min'] += $entryBreak;
                $byDay[$date]['sessions']++;
            }
        }

        $activeCount = count($activeDays);
        // Aynı gün birden çok mesai açılıp kapatılmış günler (hata/anomali işareti).
        $multiSessionDays = count(array_filter($byDay, static fn (array $d): bool => $d['sessions'] > 1));

        return [
            // total_min = NET fiili çalışma (mola/tuvalet düşülmüş).
            'total_min' => $totalMin,
            'planned_min' => $plannedMin,
            'active_days' => $activeCount,
            'avg_daily_min' => $activeCount > 0 ? (int) round($totalMin / $activeCount) : null,
            'break_min' => $breakMin,
            'toilet_min' => $toiletMin,
            'total_sessions' => $totalSessions,
            'multi_session_days' => $multiSessionDays,
            'by_day' => array_values($byDay),
        ];
    }

    /**
     * ops: üretim (ready) / teslim alma (pickup) / servis (served) akışı +
     * ortalama teslim ve gecikme süreleri + günlük döküm.
     *
     * @param  array<int, string>  $days
     * @return array<string, mixed>
     */
    private function ops(User $user, Carbon $from, Carbon $to, array $days): array
    {
        // (1) Bu kullanıcının ready/served olayları.
        /** @var Collection<int, OrderEvent> $myEvents */
        $myEvents = OrderEvent::query()
            ->where('user_id', $user->id)
            ->whereIn('to_status', ['ready', 'served'])
            ->where('created_at', '>=', $from)
            ->where('created_at', '<', $to)
            ->get(['id', 'order_item_id', 'to_status', 'created_at']);

        $preparedEvents = $myEvents->where('to_status', 'ready');
        $servedEvents = $myEvents->where('to_status', 'served');

        // (2) Bu kullanıcının teslim aldığı (komi) kalemler.
        /** @var Collection<int, ItemPickup> $pickups */
        $pickups = ItemPickup::query()
            ->where('user_id', $user->id)
            ->where('created_at', '>=', $from)
            ->where('created_at', '<', $to)
            ->get(['order_item_id', 'created_at']);

        $preparedCount = $preparedEvents->count();
        $servedCount = $servedEvents->count();
        $takenCount = $pickups->count();

        // (3) Ortalama teslim süresi: teslim aldığım kalem için
        //     pickup.created_at → o kalemin served olayı (herhangi bir kullanıcı).
        $avgDeliveryMin = $this->avgDeliveryMinutes($pickups);

        // (4) Ortalama gecikme: benim servis ettiğim kalem için ready → served.
        $avgDelayMin = $this->avgDelayMinutes($servedEvents);

        // (5) İlgili kalemlerin ready olayları (herhangi kullanıcı) — alma ve
        //     gecikme hesapları için tek sorguda.
        $relatedItemIds = $pickups->pluck('order_item_id')
            ->merge($servedEvents->pluck('order_item_id'))
            ->filter()->unique()->values();
        /** @var \Illuminate\Support\Collection<int|string, Carbon> $readyByItem */
        $readyByItem = $relatedItemIds->isEmpty()
            ? collect()
            : OrderEvent::query()
                ->where('to_status', 'ready')
                ->whereIn('order_item_id', $relatedItemIds)
                ->orderBy('created_at')
                ->get(['order_item_id', 'created_at'])
                ->groupBy('order_item_id')
                ->map(fn ($evts) => $evts->first()->created_at);

        // Ortalama ALMA süresi: ready → benim pickup'ım (komi ne kadar sürede aldı).
        $pickupDurs = [];
        foreach ($pickups as $p) {
            $ready = $readyByItem->get($p->order_item_id);
            if ($ready === null) {
                continue;
            }
            $m = (int) $ready->diffInMinutes($p->created_at, false);
            if ($m >= 0 && $m < 24 * 60) {
                $pickupDurs[] = $m;
            }
        }
        $avgPickupMin = $pickupDurs === [] ? null : (int) round(array_sum($pickupDurs) / count($pickupDurs));

        // GECİKME SAYISI: benim servis ettiğim kalemlerde ready → served eşiği aşan.
        $delayCount = 0;
        foreach ($servedEvents as $e) {
            $ready = $readyByItem->get($e->order_item_id);
            if ($ready === null) {
                continue;
            }
            $m = (int) $ready->diffInMinutes($e->created_at, false);
            if ($m > self::DELAY_THRESHOLD_MIN && $m < 24 * 60) {
                $delayCount++;
            }
        }

        // Günlük döküm (sıfır-dolgulu iskelet).
        $byDay = [];
        foreach ($days as $date) {
            $byDay[$date] = ['date' => $date, 'prepared' => 0, 'taken' => 0, 'served' => 0];
        }

        foreach ($preparedEvents as $e) {
            $date = $e->created_at->toDateString();
            if (isset($byDay[$date])) {
                $byDay[$date]['prepared']++;
            }
        }

        foreach ($servedEvents as $e) {
            $date = $e->created_at->toDateString();
            if (isset($byDay[$date])) {
                $byDay[$date]['served']++;
            }
        }

        foreach ($pickups as $p) {
            $date = $p->created_at->toDateString();
            if (isset($byDay[$date])) {
                $byDay[$date]['taken']++;
            }
        }

        return [
            'prepared_count' => $preparedCount,
            'taken_count' => $takenCount,
            'served_count' => $servedCount,
            'delivered_count' => $servedCount, // komi masaya götürdü = served ile aynı
            'avg_pickup_min' => $avgPickupMin,     // ready → aldığın (ort.)
            'avg_delivery_min' => $avgDeliveryMin, // aldığın → servis (ort.)
            'avg_delay_min' => $avgDelayMin,       // ready → servis (ort.)
            'delay_count' => $delayCount,          // eşiği aşan servis sayısı
            'delay_threshold_min' => self::DELAY_THRESHOLD_MIN,
            'by_day' => array_values($byDay),
        ];
    }

    /**
     * Teslim alınan her kalem için pickup → served (herhangi bir kullanıcı)
     * süresinin ortalaması (dk). Negatif ve 24 saat üstü değerler elenir.
     *
     * @param  Collection<int, ItemPickup>  $pickups
     */
    private function avgDeliveryMinutes(Collection $pickups): ?int
    {
        if ($pickups->isEmpty()) {
            return null;
        }

        $itemIds = $pickups->pluck('order_item_id')->filter()->unique()->values();

        if ($itemIds->isEmpty()) {
            return null;
        }

        // Aynı kalemin served olayları (kim servis etmiş olursa olsun).
        $servedByItem = OrderEvent::query()
            ->where('to_status', 'served')
            ->whereIn('order_item_id', $itemIds)
            ->orderBy('created_at')
            ->get(['order_item_id', 'created_at'])
            ->groupBy('order_item_id');

        $durations = [];

        foreach ($pickups as $pickup) {
            $served = ($servedByItem[$pickup->order_item_id] ?? collect())
                ->first(fn (OrderEvent $e) => $e->created_at->gte($pickup->created_at));

            if ($served === null) {
                continue;
            }

            $min = (int) $pickup->created_at->diffInMinutes($served->created_at);

            if ($min >= 0 && $min < 24 * 60) {
                $durations[] = $min;
            }
        }

        return $durations === [] ? null : (int) round(array_sum($durations) / count($durations));
    }

    /**
     * Servis ettiğim her kalem için ready → served süresinin ortalaması (dk).
     * ready olayı, served'den ÖNCEKİ en yakın "ready"dir. Veri yoksa null.
     *
     * @param  Collection<int, OrderEvent>  $servedEvents
     */
    private function avgDelayMinutes(Collection $servedEvents): ?int
    {
        if ($servedEvents->isEmpty()) {
            return null;
        }

        $itemIds = $servedEvents->pluck('order_item_id')->filter()->unique()->values();

        if ($itemIds->isEmpty()) {
            return null;
        }

        $readyByItem = OrderEvent::query()
            ->where('to_status', 'ready')
            ->whereIn('order_item_id', $itemIds)
            ->orderBy('created_at')
            ->get(['order_item_id', 'created_at'])
            ->groupBy('order_item_id');

        $durations = [];

        foreach ($servedEvents as $served) {
            // served'den önceki (veya eşit) en son ready.
            $ready = ($readyByItem[$served->order_item_id] ?? collect())
                ->filter(fn (OrderEvent $e) => $e->created_at->lte($served->created_at))
                ->last();

            if ($ready === null) {
                continue;
            }

            $min = (int) $ready->created_at->diffInMinutes($served->created_at);

            if ($min >= 0 && $min < 24 * 60) {
                $durations[] = $min;
            }
        }

        return $durations === [] ? null : (int) round(array_sum($durations) / count($durations));
    }

    /**
     * orders: PerformanceService mantığının bu kullanıcıya indirgenmiş hali —
     * açtığı sipariş sayısı + ortalama servis süresi (açılış → kapanış).
     *
     * @return array<string, mixed>
     */
    private function orders(User $user, Carbon $from, Carbon $to): array
    {
        $orders = Order::query()
            ->where('opened_by_id', $user->id)
            ->where('created_at', '>=', $from)
            ->where('created_at', '<', $to)
            ->get(['id', 'status', 'placed_at', 'closed_at', 'cancelled_at', 'created_at']);

        $closed = $orders->filter(
            fn (Order $o) => $o->closed_at !== null && $o->cancelled_at === null
        );

        $serviceMinutes = $closed
            ->map(fn (Order $o) => max(0, (int) ($o->placed_at ?? $o->created_at)->diffInMinutes($o->closed_at)))
            ->filter(fn (int $m) => $m < 24 * 60); // bariz veri hatalarını dışla

        return [
            'order_count' => $orders->count(),
            'avg_service_min' => $serviceMinutes->isEmpty() ? null : (int) round($serviceMinutes->avg()),
        ];
    }

    /** Molaların (tür süzgeciyle) tamamlanmış toplam dakikası. */
    private function breakMinutes(TimeEntry $entry, string $kind): int
    {
        return (int) $entry->breaks
            ->where('kind', $kind)
            ->filter(fn (TimeEntryBreak $b) => $b->ended_at !== null)
            ->sum(fn (TimeEntryBreak $b) => $b->minutes());
    }

    /**
     * Canlı çalışılan dakika: kapalı kayıtta finalize edilmiş worked_min,
     * açık kayıtta (şimdi/çıkış - giriş) - tamamlanmış tüm molalar.
     */
    private function liveWorkedMinutes(TimeEntry $entry, Carbon $now): int
    {
        if (! $entry->isOpen() && $entry->worked_min !== null) {
            return (int) $entry->worked_min;
        }

        $end = $entry->clock_out_at ?? $now;
        $gross = max(0, (int) $entry->clock_in_at->diffInMinutes($end));

        $allBreaks = (int) $entry->breaks
            ->filter(fn (TimeEntryBreak $b) => $b->ended_at !== null)
            ->sum(fn (TimeEntryBreak $b) => $b->minutes());

        return max(0, $gross - $allBreaks);
    }

    /** Pozisyondan insan-okur Türkçe etiket; yoksa ham pozisyon ya da rol adı. */
    private function roleLabel(User $user): ?string
    {
        $position = $user->position;

        if (is_string($position) && $position !== '') {
            $key = mb_strtolower($position);

            return self::POSITION_LABELS[$key] ?? $position;
        }

        // Pozisyon boşsa birincil rol adına düş.
        return $user->roles->first()?->name;
    }
}
