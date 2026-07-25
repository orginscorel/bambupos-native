<?php

namespace Tests\Feature\Reports;

use App\Modules\Reports\Models\ReportExport;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Dışa aktarma: kuyruklu üretim (§23), indirme yetkisi ve kiracı izolasyonu.
 * Testte QUEUE_CONNECTION=sync olduğundan job anında koşar.
 */
class ReportExportTest extends TestCase
{
    use InteractsWithOrders, InteractsWithPayments, InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
        Storage::fake('local');
    }

    public function test_csv_disa_aktarma_kuyrukta_uretilir_ve_indirilir(): void
    {
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);
        $orderId = $this->makeOrderWithTotal($a, 12345);
        // Ciro = YALNIZ KAPANAN (ödenmiş) adisyonlar (2026-07-23 düzeltmesi).
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 12345, 'tendered_minor' => 12345,
        ])->assertCreated();

        $export = $this->postJson('/api/v1/reports/exports', [
            'report' => 'sales-daily', 'format' => 'csv',
        ])->assertCreated()->json('export');

        // sync queue: iş bitti, dosya hazır
        $row = $this->getJson('/api/v1/reports/exports')->assertOk()->json('exports.0');
        $this->assertSame('done', $row['status']);
        $this->assertNotNull($row['download_url']);

        $model = ReportExport::query()->withoutGlobalScopes()->findOrFail($export['id']);
        Storage::disk('local')->assertExists($model->file_path);

        $this->get($row['download_url'])
            ->assertOk()
            ->assertHeader('Content-Type', 'text/csv; charset=UTF-8');

        // İçerikte gerçek ciro satırı var (kuruş → TL ondalık)
        $csv = Storage::disk('local')->get($model->file_path);
        $this->assertStringContainsString('123,45', $csv);
    }

    public function test_xlsx_ve_pdf_bicimleri_uretilir(): void
    {
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);
        $this->makeOrderWithTotal($a, 10000);

        foreach (['xlsx', 'pdf'] as $format) {
            $this->postJson('/api/v1/reports/exports', [
                'report' => 'sales-products', 'format' => $format,
            ])->assertCreated();
        }

        $rows = $this->getJson('/api/v1/reports/exports')->assertOk()->json('exports');
        $this->assertSame(['done', 'done'], array_column(array_slice($rows, 0, 2), 'status'));
    }

    public function test_yabanci_kiracinin_disa_aktarmasi_indirilemez(): void
    {
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);
        $this->makeOrderWithTotal($a, 10000);

        $export = $this->postJson('/api/v1/reports/exports', [
            'report' => 'sales-daily', 'format' => 'csv',
        ])->assertCreated()->json('export');

        // TenantContext hâlâ A'nın oturumuna düşmesin diye açık çıkış (bkz.
        // PaymentIsolationTest'teki aynı desen).
        auth('web')->logout();
        $b = $this->makeTenantWithUser();
        $this->actingAs($b['user']);

        // Kiracı scope'u: yabancı kayıt route binding'de 404 (ADR-004)
        $this->get("/api/v1/reports/exports/{$export['id']}/download")->assertNotFound();
    }

    public function test_izinsiz_kullanici_disa_aktaramaz(): void
    {
        $waiter = $this->makeTenantWithUser(['orders.view']);
        $this->actingAs($waiter['user']);

        $this->postJson('/api/v1/reports/exports', [
            'report' => 'sales-daily', 'format' => 'csv',
        ])->assertForbidden();
    }
}
