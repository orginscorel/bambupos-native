<?php

namespace App\Modules\Shifts\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Shifts\Support\ShiftsFeature;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * MAAŞ / BORDRO (§Vardiya) — personel maaş tanımı + otomatik hak ediş.
 *
 * İki model:
 *  - AYLIK SABİT (monthly): tutar dönemden bağımsız sabit (ör. 30.000₺/ay).
 *  - SAATLİK (hourly): saat başı ücret; kazanç time_entries.worked_min'den
 *    (gerçek çalışılan süre) türetilir → ay/gün otomatik hesaplanır.
 *
 * Hak ediş KAYIT TUTMAZ; ekranda seçilen döneme göre anlık hesaplanır (kaynak
 * tek doğruluk = time_entries). Yalnız staff.manage yetkisi erişir.
 */
class PayrollController extends Controller
{
    use \App\Modules\Tenancy\Concerns\ScopesToBranch;

    public function __construct(private readonly AuditLogger $audit)
    {
    }

    private function gate(Request $request): void
    {
        abort_unless(ShiftsFeature::enabled((int) Auth::user()?->tenant_id), 404);
        abort_unless($request->user()->hasPermission('staff.manage'), 403);
    }

    /** GET /api/v1/shifts/payroll?month=YYYY-MM */
    public function index(Request $request): JsonResponse
    {
        $this->gate($request);

        $tenantId = (int) $request->user()->tenant_id;
        // ŞUBE KAPSAMI: yönetici yalnız geçerli şubenin bordrosunu görür (denetim #8'in atlanmış üçüncü ucu).
        $branchId = $this->currentBranchId();
        $month = (string) $request->query('month', now()->format('Y-m'));
        if (preg_match('/^\d{4}-\d{2}$/', $month) !== 1) {
            $month = now()->format('Y-m');
        }

        $start = Carbon::createFromFormat('Y-m-d', $month.'-01')->startOfMonth();
        $end = $start->copy()->endOfMonth();
        $todayStart = now()->startOfDay();
        $todayEnd = now()->endOfDay();

        $staff = User::query()
            ->where('tenant_id', $tenantId)
            ->where('branch_id', $branchId)
            ->where('is_active', true)
            ->where('is_terminal', false)
            ->orderBy('name')
            ->get(['id', 'name', 'position', 'salary_type', 'salary_amount_minor']);

        // Dönem + bugün çalışılan dakika (kapanmış kayıtlar; worked_min).
        $monthMinutes = $this->workedMinutes($tenantId, $branchId, $start, $end);
        $todayMinutes = $this->workedMinutes($tenantId, $branchId, $todayStart, $todayEnd);

        $rows = $staff->map(function (User $u) use ($monthMinutes, $todayMinutes, $start): array {
            $type = $u->salary_type;
            $amount = (int) ($u->salary_amount_minor ?? 0);
            $monthMin = (int) ($monthMinutes[$u->id] ?? 0);
            $todayMin = (int) ($todayMinutes[$u->id] ?? 0);

            $monthEarned = 0;
            $todayEarned = 0;
            $dailyRate = null;

            if ($type === 'monthly' && $amount > 0) {
                $monthEarned = $amount; // sabit
                $dailyRate = intdiv($amount, max(1, $start->daysInMonth));
                $todayEarned = $dailyRate;
            } elseif ($type === 'hourly' && $amount > 0) {
                $monthEarned = (int) round($monthMin * $amount / 60);
                $todayEarned = (int) round($todayMin * $amount / 60);
            }

            return [
                'id' => $u->id,
                'name' => $u->name,
                'position' => $u->position,
                'salary_type' => $type,
                'salary_amount_minor' => $amount ?: null,
                'month_worked_min' => $monthMin,
                'today_worked_min' => $todayMin,
                'month_earned_minor' => $monthEarned,
                'today_earned_minor' => $todayEarned,
                'daily_rate_minor' => $dailyRate,
            ];
        })->values();

        return response()->json([
            'month' => $month,
            'rows' => $rows,
            'totals' => [
                'month_earned_minor' => (int) $rows->sum('month_earned_minor'),
                'today_earned_minor' => (int) $rows->sum('today_earned_minor'),
                'month_worked_min' => (int) $rows->sum('month_worked_min'),
            ],
        ]);
    }

    /** PUT /api/v1/shifts/payroll/{user} — maaş tanımını güncelle. */
    public function update(Request $request, User $user): JsonResponse
    {
        $this->gate($request);

        abort_unless((int) $user->tenant_id === (int) $request->user()->tenant_id, 404);
        // ŞUBE KAPSAMI: başka şubenin bordrosu güncellenemez.
        abort_unless((int) $user->branch_id === $this->currentBranchId(), 404);

        $data = $request->validate([
            'salary_type' => ['nullable', Rule::in(['monthly', 'hourly'])],
            'salary_amount' => ['nullable', 'numeric', 'min:0', 'max:99999999'],
        ]);

        $type = $data['salary_type'] ?? null;
        $amountMinor = ($type !== null && isset($data['salary_amount']))
            ? (int) round(((float) $data['salary_amount']) * 100)
            : null;

        $old = ['type' => $user->salary_type, 'amount' => $user->salary_amount_minor];

        $user->salary_type = $type;
        $user->salary_amount_minor = $amountMinor;
        $user->save();

        $this->audit->log('shifts.payroll_updated', $user,
            $old, ['type' => $type, 'amount' => $amountMinor], (int) $user->tenant_id);

        return response()->json(['ok' => true]);
    }

    /**
     * user_id => toplam worked_min (verilen aralıkta, clock_in_at'e göre).
     *
     * @return array<int, int>
     */
    private function workedMinutes(int $tenantId, ?int $branchId, Carbon $start, Carbon $end): array
    {
        return DB::table('time_entries')
            ->where('tenant_id', $tenantId)
            ->when($branchId !== null, fn ($q) => $q->where('branch_id', $branchId))
            ->whereBetween('clock_in_at', [$start, $end])
            ->groupBy('user_id')
            ->selectRaw('user_id, COALESCE(SUM(worked_min),0) as m')
            ->pluck('m', 'user_id')
            ->map(fn ($v) => (int) $v)
            ->all();
    }
}
