<?php

namespace App\Modules\Reports\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Reports\Jobs\GenerateReportExport;
use App\Modules\Reports\Models\ReportExport;
use App\Modules\Reports\Support\ReportFilters;
use App\Modules\Reports\Support\ReportRegistry;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Rapor dışa aktarmaları: kayıt aç → queue job üret → hazır olunca indir.
 * Dosyalar web'e açık DEĞİLDİR; yalnız bu uçtan, izin + kiracı scope
 * denetiminden geçerek akıtılır.
 */
class ExportController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('reports.view'), 403);

        $exports = ReportExport::query()
            ->orderByDesc('id')
            ->limit(30)
            ->get()
            ->map(fn (ReportExport $e) => $this->present($e));

        return response()->json(['exports' => $exports]);
    }

    public function store(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('reports.view'), 403);

        $validated = $request->validate([
            'report' => ['required', 'string', 'max:60'],
            'format' => ['required', 'in:csv,xlsx,pdf'],
        ]);

        abort_unless(ReportRegistry::exists($validated['report']), 422);

        $filters = ReportFilters::fromRequest($request);

        $export = ReportExport::query()->create([
            'branch_id' => $filters->branchId,
            'user_id' => $request->user()->getKey(),
            'report_key' => $validated['report'],
            'format' => $validated['format'],
            'params' => $filters->toArray(),
            'status' => 'queued',
        ]);

        GenerateReportExport::dispatch($export->getKey());

        return response()->json(['export' => $this->present($export)], 201);
    }

    public function download(Request $request, ReportExport $export): StreamedResponse
    {
        abort_unless($request->user()->hasPermission('reports.view'), 403);
        abort_unless($export->isReady(), 404);

        $disk = Storage::disk((string) config('reports.export_disk', 'local'));
        abort_unless($disk->exists((string) $export->file_path), 404);

        $mime = match ($export->format) {
            'csv' => 'text/csv; charset=UTF-8',
            'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            default => 'application/pdf',
        };

        return $disk->download((string) $export->file_path, $export->fileName(), [
            'Content-Type' => $mime,
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }

    private function present(ReportExport $e): array
    {
        $titles = ReportRegistry::exists($e->report_key) ? ReportRegistry::get($e->report_key)['title'] : $e->report_key;

        return [
            'id' => $e->getKey(),
            'report' => $e->report_key,
            'title' => $titles,
            'format' => $e->format,
            'status' => $e->status,
            'rows_count' => $e->rows_count,
            'error' => $e->error,
            'from' => $e->params['from'] ?? null,
            'to' => $e->params['to'] ?? null,
            'created_at' => $e->created_at?->toIso8601String(),
            'finished_at' => $e->finished_at?->toIso8601String(),
            'download_url' => $e->isReady() ? "/api/v1/reports/exports/{$e->getKey()}/download" : null,
        ];
    }
}
