<?php

namespace App\Modules\Reports\Services;

use App\Modules\Reports\Support\ReportFilters;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Açık cariler (borç hesapları). Kaynak: Receivables modülü (ADR ile aynı
 * desen — Reports salt-okur read-model, `receivables` TEK DOĞRULUK
 * KAYNAĞI'ndan hesaplanan `balance_minor` alanını yeniden hesaplamadan
 * okur). Gerçek şema (2026-07-23): tablo `receivables`, ad `name`,
 * telefon `phone`, bakiye `balance_minor`, kiracı `tenant_id`.
 *
 * Yine de `Schema::hasTable` koruması KORUNUR: göç herhangi bir sebeple
 * henüz çalışmamışsa (ör. taze bir ortam) rapor ucu 500 DEĞİL, dürüstçe
 * `available=false` döner — uydurma sayı yok.
 *
 * KAPSAM: yalnız GÜNCEL toplam açık bakiye + cari listesi (ad, telefon,
 * bakiye). Hangi adisyondan/ne zaman taşındığı (hareket/ledger düzeyi)
 * `receivable_transactions` + `orders.debt_receivable_id`/
 * `debt_amount_minor` üzerinden mümkündür ama KASITLI olarak kapsam
 * dışıdır (bu servis "kim ne kadar borçlu" sorusuna cevap verir).
 */
class ReceivablesReportService
{
    /** Açık (bakiyesi > 0) cari hesaplar — GÜNCEL toplam (dönem filtresi uygulanmaz). */
    public function openAccounts(ReportFilters $f): array
    {
        $empty = ['available' => false, 'rows' => [], 'total_minor' => null, 'count' => 0];

        if (! Schema::hasTable('receivables')) {
            return $empty;
        }

        $base = DB::table('receivables')
            ->where('tenant_id', $f->tenantId)
            ->where('balance_minor', '>', 0);

        // branch_id NULL olabilir (şubesiz/tenant-genel cari) — şube filtresi
        // uygulanırken bu kayıtlar dışarıda BIRAKILMAZ, her şubede görünür.
        if ($f->branchId !== null) {
            $base->where(fn ($q) => $q->whereNull('branch_id')->orWhere('branch_id', $f->branchId));
        }

        // Toplam/adet: TAM (satır limitinden bağımsız) — dürüst toplam.
        $totals = (clone $base)->selectRaw('COUNT(*) AS c, COALESCE(SUM(balance_minor), 0) AS t')->first();

        $rows = $base->orderByDesc('balance_minor')
            ->limit(200)
            ->get(['name', 'phone', 'balance_minor']);

        return [
            'available' => true,
            'rows' => $rows->map(fn ($r) => [
                'name' => (string) $r->name,
                'phone' => $r->phone !== null ? (string) $r->phone : null,
                'balance_minor' => (int) $r->balance_minor,
            ])->all(),
            'total_minor' => (int) $totals->t,
            'count' => (int) $totals->c,
        ];
    }
}
