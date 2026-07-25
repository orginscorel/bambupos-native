<?php

namespace App\Modules\Reports\Jobs;

use App\Modules\Reports\Models\ReportExport;
use App\Modules\Reports\Support\ExportBuilder;
use App\Modules\Reports\Support\ReportFilters;
use App\Modules\Reports\Support\ReportRegistry;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

/**
 * Rapor dışa aktarmasını KUYRUKTA üretir (prompt §23: büyük rapor web
 * isteğinde üretilmez). Kiracı bağlamı job içinde açıkça kurulur; dosya
 * kiracıya özel klasöre yazılır ve YALNIZ download ucundan (izin + kiracı
 * scope) okunur — web'e açık değildir.
 */
class GenerateReportExport implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 2;

    public int $timeout = 300;

    public function __construct(public readonly int $exportId)
    {
    }

    public function handle(TenantContext $context): void
    {
        /** @var ReportExport|null $export */
        $export = ReportExport::query()->withoutGlobalScopes()->find($this->exportId);

        if ($export === null || $export->status === 'done') {
            return;
        }

        $tenant = Tenant::query()->find($export->tenant_id);
        if ($tenant === null) {
            return;
        }

        // Kiracı bağlamı ÖNCE kurulur: model kaydetme sorguları da tenant
        // scope'undan geçer (fail closed).
        $context->setTenant($tenant);

        try {
            $export->forceFill(['status' => 'processing'])->save();

            $filters = ReportFilters::fromArray((array) $export->params);
            $data = ReportRegistry::run($export->report_key, $filters);
            [$headers, $rows] = ExportBuilder::tabulate($export->report_key, $data);

            $def = ReportRegistry::get($export->report_key);
            $disk = Storage::disk((string) config('reports.export_disk', 'local'));
            $dir = trim((string) config('reports.export_dir', 'reports'), '/')."/{$export->tenant_id}";
            $disk->makeDirectory($dir);

            $relative = "{$dir}/export-{$export->id}.{$export->format}";
            $absolute = $disk->path($relative);

            $subtitle = sprintf('%s – %s · %s', $filters->from, $filters->to, config('app.name', 'QR Menü'));

            match ($export->format) {
                'csv' => ExportBuilder::writeCsv($absolute, $headers, $rows),
                'xlsx' => ExportBuilder::writeXlsx($absolute, $headers, $rows, $def['title']),
                'pdf' => ExportBuilder::writePdf($absolute, $headers, $rows, $def['title'], $subtitle),
                default => throw new \RuntimeException('Bilinmeyen dışa aktarma biçimi.'),
            };

            $export->forceFill([
                'status' => 'done',
                'file_path' => $relative,
                'rows_count' => count($rows),
                'error' => null,
                'finished_at' => now(),
            ])->save();
        } catch (\Throwable $e) {
            // Ayrıntı log'a; kullanıcıya sızıntısız kısa mesaj.
            Log::error('Rapor dışa aktarma başarısız', [
                'export_id' => $export->id,
                'report' => $export->report_key,
                'error' => $e->getMessage(),
            ]);

            $export->forceFill([
                'status' => 'failed',
                'error' => 'Rapor üretilemedi; tekrar deneyin.',
                'finished_at' => now(),
            ])->save();

            throw $e;
        } finally {
            $context->forget();
        }
    }
}
