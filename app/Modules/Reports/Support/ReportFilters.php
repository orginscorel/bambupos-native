<?php

namespace App\Modules\Reports\Support;

use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Rapor filtreleri: tarih aralığı + şube + saat dilimi (değer nesnesi).
 *
 * - Kiracı kimliği YALNIZ TenantContext'ten gelir (ADR-004); istekten gelen
 *   tenant parametresi yok sayılır. branch_id istekten gelebilir ama
 *   kiracının şubeleriyle doğrulanır — yabancı şube 422.
 * - Tarihler ŞUBE saat diliminde yorumlanır (branches.timezone), sorgular
 *   UTC kolonlara çevrilmiş sınırlarla koşar. Gün/saat kovalama SQL
 *   ifadeleri sabit ofsetle üretilir (TR'de DST yok; aralık içi kayma
 *   ihmal edilebilir).
 * - dayExpr/hourExpr'e verilen kolon adları HER ZAMAN kod sabitidir,
 *   kullanıcı girdisi asla değildir.
 */
final class ReportFilters
{
    public readonly int $tenantId;

    public readonly ?int $branchId;      // null = tüm şubeler

    public readonly string $timezone;

    public readonly string $from;        // Y-m-d (şube tz)

    public readonly string $to;          // Y-m-d (şube tz, dahil)

    public readonly CarbonImmutable $fromUtc;

    public readonly CarbonImmutable $toUtc;       // aralık sonu (hariç sınır)

    public readonly CarbonImmutable $prevFromUtc; // önceki eşit-uzunluk dönem

    public readonly CarbonImmutable $prevToUtc;

    private readonly int $offsetSeconds;

    private readonly string $driver;

    private function __construct(
        int $tenantId,
        ?int $branchId,
        string $timezone,
        CarbonImmutable $fromDay,
        CarbonImmutable $toDay,
    ) {
        $this->tenantId = $tenantId;
        $this->branchId = $branchId;
        $this->timezone = $timezone;
        $this->from = $fromDay->toDateString();
        $this->to = $toDay->toDateString();

        $this->fromUtc = $fromDay->startOfDay()->utc();
        $this->toUtc = $toDay->addDay()->startOfDay()->utc();

        $lengthDays = (int) $fromDay->diffInDays($toDay) + 1;
        $this->prevFromUtc = $this->fromUtc->subDays($lengthDays);
        $this->prevToUtc = $this->fromUtc;

        $this->offsetSeconds = $fromDay->startOfDay()->utcOffset() * 60;
        $this->driver = DB::connection()->getDriverName();
    }

    /**
     * İstekten kur. Varsayılan aralık: son 7 gün (bugün dahil).
     * branch=all → tüm şubeler; branch_id → kiracının şubesi olmalı (422).
     */
    public static function fromRequest(Request $request, string $defaultRange = '7d'): self
    {
        $tenantId = (int) app(TenantContext::class)->tenantId();

        [$branchId, $timezone] = self::resolveBranch($request, $tenantId);

        $today = CarbonImmutable::now($timezone)->startOfDay();

        [$from, $to] = match ($defaultRange) {
            'today' => [$today, $today],
            default => [$today->subDays(6), $today],
        };

        foreach (['from', 'to'] as $key) {
            $raw = (string) $request->query($key, '');
            if ($raw === '') {
                continue;
            }
            if (! preg_match('/^\d{4}-\d{2}-\d{2}$/', $raw)) {
                throw ValidationException::withMessages([$key => ['Tarih biçimi YYYY-AA-GG olmalı.']]);
            }
            ${$key} = CarbonImmutable::parse($raw, $timezone)->startOfDay();
        }

        if ($from->gt($to)) {
            [$from, $to] = [$to, $from];
        }

        // Uç sınır: tek istekte en çok 1 yıl (rapor sorgusu web isteğini boğmasın).
        if ($from->diffInDays($to) > 366) {
            throw ValidationException::withMessages(['to' => ['Aralık en çok 1 yıl olabilir.']]);
        }

        return new self($tenantId, $branchId, $timezone, $from, $to);
    }

    /** @return array{0: ?int, 1: string} [branchId, timezone] */
    private static function resolveBranch(Request $request, int $tenantId): array
    {
        $branches = Branch::query()
            ->withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->get(['id', 'timezone']);

        $raw = (string) $request->query('branch_id', '');

        if ($raw === 'all') {
            return [null, (string) ($branches->first()->timezone ?? config('app.timezone'))];
        }

        $requested = $raw === ''
            ? (int) ($request->session()->get('panel.active_branch_id') ?: ($request->user()?->branch_id ?? 0))
            : (int) $raw;

        $branch = $branches->firstWhere('id', $requested) ?? $branches->first();

        if ($raw !== '' && $branch?->id !== $requested) {
            throw ValidationException::withMessages(['branch_id' => ['Geçersiz şube.']]);
        }

        return [
            $branch?->id,
            (string) ($branch->timezone ?? config('app.timezone')),
        ];
    }

    /* ---------------- SQL yardımcıları (kolon adları kod sabitidir) -------- */

    /** Şube gününe indirgenmiş 'Y-m-d' ifadesi. */
    public function dayExpr(string $column): string
    {
        return $this->driver === 'sqlite'
            ? "strftime('%Y-%m-%d', {$column}, '{$this->offsetSeconds} seconds')"
            : "DATE_FORMAT({$column} + INTERVAL {$this->offsetSeconds} SECOND, '%Y-%m-%d')";
    }

    /** Şube saatine indirgenmiş 0-23 saat ifadesi. */
    public function hourExpr(string $column): string
    {
        return $this->driver === 'sqlite'
            ? "CAST(strftime('%H', {$column}, '{$this->offsetSeconds} seconds') AS INTEGER)"
            : "HOUR({$column} + INTERVAL {$this->offsetSeconds} SECOND)";
    }

    /** İki zaman kolonu arasındaki fark, DAKİKA (ondalık). */
    public function minutesExpr(string $fromColumn, string $toColumn): string
    {
        return $this->driver === 'sqlite'
            ? "(julianday({$toColumn}) - julianday({$fromColumn})) * 1440.0"
            : "TIMESTAMPDIFF(SECOND, {$fromColumn}, {$toColumn}) / 60.0";
    }

    /** Ortak WHERE seti: kiracı + (varsa) şube + tarih aralığı. */
    public function apply(\Illuminate\Database\Query\Builder $query, string $table, string $dateColumn = 'created_at'): \Illuminate\Database\Query\Builder
    {
        $query->where("{$table}.tenant_id", $this->tenantId)
            ->where("{$table}.{$dateColumn}", '>=', $this->fromUtc)
            ->where("{$table}.{$dateColumn}", '<', $this->toUtc);

        if ($this->branchId !== null) {
            $query->where("{$table}.branch_id", $this->branchId);
        }

        return $query;
    }

    /** Önceki dönem için aynı filtreler. */
    public function applyPrevious(\Illuminate\Database\Query\Builder $query, string $table, string $dateColumn = 'created_at'): \Illuminate\Database\Query\Builder
    {
        $query->where("{$table}.tenant_id", $this->tenantId)
            ->where("{$table}.{$dateColumn}", '>=', $this->prevFromUtc)
            ->where("{$table}.{$dateColumn}", '<', $this->prevToUtc);

        if ($this->branchId !== null) {
            $query->where("{$table}.branch_id", $this->branchId);
        }

        return $query;
    }

    /** Dışa aktarma job'ı için serileştirme. */
    public function toArray(): array
    {
        return [
            'tenant_id' => $this->tenantId,
            'branch_id' => $this->branchId,
            'timezone' => $this->timezone,
            'from' => $this->from,
            'to' => $this->to,
        ];
    }

    /** Job tarafında (istek yokken) yeniden kurulum. */
    public static function fromArray(array $data): self
    {
        $tz = (string) ($data['timezone'] ?? 'Europe/Istanbul');

        return new self(
            (int) $data['tenant_id'],
            isset($data['branch_id']) && $data['branch_id'] !== null ? (int) $data['branch_id'] : null,
            $tz,
            CarbonImmutable::parse((string) $data['from'], $tz)->startOfDay(),
            CarbonImmutable::parse((string) $data['to'], $tz)->startOfDay(),
        );
    }
}
