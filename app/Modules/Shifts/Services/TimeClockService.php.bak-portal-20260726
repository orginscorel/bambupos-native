<?php

namespace App\Modules\Shifts\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Shifts\Models\ClockDevice;
use App\Modules\Shifts\Models\LocationConsent;
use App\Modules\Shifts\Models\Shift;
use App\Modules\Shifts\Models\ShiftSetting;
use App\Modules\Shifts\Models\TimeEntry;
use App\Modules\Shifts\Models\TimeEntryBreak;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * İşe giriş/çıkış çekirdeği.
 *
 * - PIN ile kimlik: kiracının aktif personeli içinde eşleşme aranır; aynı
 *   PIN birden çok personelde varsa personel kodu (staff_code) istenir —
 *   yanlış kişiye mesai yazılmaz.
 * - Süreler dakika-integer; hesap TEK yerden (finalize) yapılır.
 * - KVKK: konum yalnız işletme ayarı AÇIK + personelin AÇIK rızası varsa
 *   kaydedilir; aksi halde gelen koordinat SESSİZCE ATILIR (asla saklanmaz).
 * - Manuel düzeltme: neden zorunludur ve audit_logs'a eski/yeni değerlerle düşer.
 */
class TimeClockService
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    /* ---------------- Kimlik ---------------- */

    /**
     * PIN'den personel çözer (kiracı bağlamı içinde).
     * Birden çok eşleşmede staff_code zorunlu — belirsiz eşleşme kabul edilmez.
     */
    public function identifyByPin(string $pin, ?string $staffCode = null): User
    {
        $candidates = User::ofCurrentTenant()
            ->where('is_active', true)
            ->whereNotNull('pin_hash')
            ->when($staffCode !== null && $staffCode !== '', fn ($q) => $q->where('staff_code', $staffCode))
            ->get();

        $matches = $candidates->filter(fn (User $u) => Hash::check($pin, (string) $u->pin_hash))->values();

        if ($matches->isEmpty()) {
            throw ValidationException::withMessages(['pin' => ['PIN doğrulanamadı.']]);
        }

        if ($matches->count() > 1) {
            throw ValidationException::withMessages([
                'staff_code' => ['Bu PIN birden fazla personelle eşleşiyor; personel kodunuzu da girin.'],
            ]);
        }

        /** @var User $user */
        $user = $matches->first();

        if ($user->pinIsLocked()) {
            throw ValidationException::withMessages([
                'pin' => ['PIN girişi geçici olarak kilitli. Lütfen daha sonra deneyin.'],
            ])->status(429);
        }

        return $user;
    }

    /* ---------------- Giriş / çıkış / mola ---------------- */

    /**
     * @param  array{branch_id?: ?int, method?: string, device?: ?ClockDevice, ip?: ?string, lat?: ?float, lng?: ?float}  $ctx
     */
    public function clockIn(User $user, array $ctx = []): TimeEntry
    {
        if ($this->openEntryFor($user) !== null) {
            throw ValidationException::withMessages(['action' => ['Zaten açık bir mesai kaydınız var; önce çıkış yapın.']]);
        }

        $shift = $this->matchShift($user);
        [$lat, $lng] = $this->locationIfPermitted($user, $ctx['lat'] ?? null, $ctx['lng'] ?? null);

        $entry = new TimeEntry([
            'branch_id' => $ctx['branch_id'] ?? $shift?->branch_id ?? $user->branch_id,
            'user_id' => $user->id,
            'shift_id' => $shift?->id,
            'clock_in_at' => now(),
            'method_in' => $ctx['method'] ?? 'pin',
            'device_id' => ($ctx['device'] ?? null)?->id,
            'ip_in' => $ctx['ip'] ?? null,
            'status' => TimeEntry::STATUS_OPEN,
        ]);
        $entry->lat_in = $lat;
        $entry->lng_in = $lng;
        $entry->save();

        return $entry;
    }

    /**
     * @param  array{method?: string, ip?: ?string, lat?: ?float, lng?: ?float}  $ctx
     */
    public function clockOut(User $user, array $ctx = []): TimeEntry
    {
        $entry = $this->openEntryFor($user);

        if ($entry === null) {
            throw ValidationException::withMessages(['action' => ['Açık mesai kaydınız yok; önce giriş yapın.']]);
        }

        return DB::transaction(function () use ($entry, $user, $ctx): TimeEntry {
            // Açık mola varsa çıkışla birlikte kapanır.
            $entry->breaks()->whereNull('ended_at')->update(['ended_at' => now()]);

            [$lat, $lng] = $this->locationIfPermitted($user, $ctx['lat'] ?? null, $ctx['lng'] ?? null);

            $entry->clock_out_at = now();
            $entry->method_out = $ctx['method'] ?? 'pin';
            $entry->ip_out = $ctx['ip'] ?? null;
            $entry->lat_out = $lat;
            $entry->lng_out = $lng;
            $entry->status = TimeEntry::STATUS_CLOSED;

            $this->finalize($entry);
            $entry->save();

            return $entry;
        });
    }

    public function breakStart(User $user): TimeEntryBreak
    {
        $entry = $this->openEntryFor($user);

        if ($entry === null) {
            throw ValidationException::withMessages(['action' => ['Açık mesai kaydınız yok.']]);
        }

        if ($entry->openBreak() !== null) {
            throw ValidationException::withMessages(['action' => ['Zaten açık bir molanız var.']]);
        }

        return $entry->breaks()->create(['started_at' => now()]);
    }

    public function breakEnd(User $user): TimeEntryBreak
    {
        $entry = $this->openEntryFor($user);
        $break = $entry?->openBreak();

        if ($break === null) {
            throw ValidationException::withMessages(['action' => ['Açık molanız yok.']]);
        }

        $break->ended_at = now();
        $break->save();

        return $break;
    }

    public function openEntryFor(User $user): ?TimeEntry
    {
        return TimeEntry::query()
            ->where('user_id', $user->id)
            ->where('status', TimeEntry::STATUS_OPEN)
            ->latest('clock_in_at')
            ->first();
    }

    /* ---------------- Hesap (tek yer) ---------------- */

    /**
     * Kapanan kaydın tüm türetilmiş alanlarını hesaplar (dakika):
     * worked = (çıkış-giriş) − molalar; fazla mesai = worked − plan;
     * geç kalma / erken çıkış vardiyaya ve toleransa göre.
     */
    public function finalize(TimeEntry $entry): void
    {
        $settings = $this->settingsFor($entry);

        $breakMin = (int) $entry->breaks()->whereNotNull('ended_at')->get()
            ->sum(fn (TimeEntryBreak $b) => $b->minutes());

        $gross = max(0, (int) $entry->clock_in_at->diffInMinutes($entry->clock_out_at));
        $worked = max(0, $gross - $breakMin);

        $entry->break_total_min = $breakMin;
        $entry->worked_min = $worked;

        $shift = $entry->shift_id !== null
            ? Shift::query()->whereKey($entry->shift_id)->first()
            : null;

        if ($shift !== null) {
            $planned = $shift->plannedMinutes();

            $lateRaw = (int) max(0, $shift->starts_at->diffInMinutes($entry->clock_in_at, false));
            $earlyRaw = (int) max(0, $entry->clock_out_at->diffInMinutes($shift->ends_at, false));

            $entry->planned_min = $planned;
            $entry->late_min = $lateRaw > $settings->late_tolerance_min ? $lateRaw : 0;
            $entry->early_leave_min = $earlyRaw > $settings->early_leave_tolerance_min ? $earlyRaw : 0;
            $entry->overtime_min = max(0, $worked - $planned);
            $entry->missing_min = max(0, $planned - $worked);
        } else {
            // Plansız gün: fazla mesai eşiği işletmenin standart günü.
            $entry->planned_min = null;
            $entry->late_min = 0;
            $entry->early_leave_min = 0;
            $entry->overtime_min = max(0, $worked - (int) $settings->standard_daily_min);
            $entry->missing_min = 0;
        }
    }

    /* ---------------- Manuel düzeltme + onay ---------------- */

    /**
     * Manuel düzeltme (yalnız yönetici): neden ZORUNLU; eski/yeni değerler
     * denetim kaydına düşer; türetilmiş alanlar yeniden hesaplanır.
     *
     * @param  array{clock_in_at?: string, clock_out_at?: string, break_total_min?: int}  $changes
     */
    public function correct(TimeEntry $entry, array $changes, string $reason, User $editor): TimeEntry
    {
        $old = $entry->only(['clock_in_at', 'clock_out_at', 'break_total_min', 'worked_min', 'overtime_min']);

        return DB::transaction(function () use ($entry, $changes, $reason, $editor, $old): TimeEntry {
            if (isset($changes['clock_in_at'])) {
                $entry->clock_in_at = \Carbon\Carbon::parse($changes['clock_in_at']);
            }

            if (isset($changes['clock_out_at'])) {
                $entry->clock_out_at = \Carbon\Carbon::parse($changes['clock_out_at']);
                $entry->status = TimeEntry::STATUS_CLOSED;
            }

            if ($entry->clock_out_at !== null && $entry->clock_out_at->lte($entry->clock_in_at)) {
                throw ValidationException::withMessages(['clock_out_at' => ['Çıkış, girişten sonra olmalıdır.']]);
            }

            // Mola toplamı elle düzeltilirse tek toplam satırına indirgenir.
            if (isset($changes['break_total_min'])) {
                $minutes = max(0, (int) $changes['break_total_min']);
                $entry->breaks()->delete();

                if ($minutes > 0) {
                    $entry->breaks()->create([
                        'started_at' => $entry->clock_in_at,
                        'ended_at' => $entry->clock_in_at->copy()->addMinutes($minutes),
                    ]);
                }
            }

            if ($entry->clock_out_at !== null) {
                $this->finalize($entry);
            }

            $entry->edited_by_id = $editor->id;
            $entry->edited_at = now();
            $entry->edit_reason = $reason;
            // Düzeltme onayı düşürür — yönetici yeniden onaylamalıdır.
            $entry->approved_at = null;
            $entry->approved_by_id = null;
            $entry->save();

            $this->audit->log(
                'shifts.time_entry_corrected',
                $entry,
                $old,
                $entry->only(['clock_in_at', 'clock_out_at', 'break_total_min', 'worked_min', 'overtime_min']) + ['reason' => $reason],
            );

            return $entry;
        });
    }

    public function approve(TimeEntry $entry, User $approver): TimeEntry
    {
        if ($entry->isOpen()) {
            throw ValidationException::withMessages(['status' => ['Açık kayıt onaylanamaz; önce çıkış yapılmalı.']]);
        }

        $entry->approved_at = now();
        $entry->approved_by_id = $approver->id;
        $entry->save();

        $this->audit->log('shifts.time_entry_approved', $entry);

        return $entry;
    }

    /* ---------------- Yardımcılar ---------------- */

    /** Şu ana en yakın uygun vardiya (±4 saat pencere; sqlite/mysql uyumlu). */
    private function matchShift(User $user): ?Shift
    {
        $now = now();

        return Shift::query()
            ->where('user_id', $user->id)
            ->where('starts_at', '<=', $now->copy()->addHours(4))
            ->where('ends_at', '>=', $now->copy()->subHours(4))
            ->get()
            ->sortBy(fn (Shift $s) => abs((int) $s->starts_at->diffInMinutes($now, false)))
            ->first();
    }

    /**
     * KVKK süzgeci: işletme ayarı kapalıysa VEYA personel rızası yoksa
     * koordinatlar atılır (null döner) — hiçbir yerde saklanmaz/loglanmaz.
     *
     * @return array{0: ?float, 1: ?float}
     */
    private function locationIfPermitted(User $user, ?float $lat, ?float $lng): array
    {
        if ($lat === null || $lng === null) {
            return [null, null];
        }

        $settings = ShiftSetting::current();

        if (! $settings->location_tracking_enabled) {
            return [null, null];
        }

        if (! LocationConsent::activeFor((int) $user->id)) {
            return [null, null];
        }

        return [$lat, $lng];
    }

    private function settingsFor(TimeEntry $entry): ShiftSetting
    {
        return ShiftSetting::current();
    }
}
