<?php

namespace App\Modules\Reports\Support;

use App\Modules\Reports\Services\FinanceReportService;
use App\Modules\Reports\Services\OpsReportService;
use App\Modules\Reports\Services\ProductReportService;
use App\Modules\Reports\Services\ReceivablesReportService;
use App\Modules\Reports\Services\SalesReportService;
use App\Modules\Reports\Services\StaffReportService;

/**
 * Rapor kataloğu: anahtar → servis çağrısı + dışa aktarma tanımı.
 *
 * - Yalnız burada tanımlı anahtarlar çağrılabilir (istekten sınıf/metot adı
 *   asla türetilmez — kapalı liste).
 * - 'columns': dışa aktarmada başlıklar; 'rows': servis çıktısından tablo
 *   satırlarını seçer. '*_minor' alanları dışa aktarmada TL ondalığına
 *   çevrilir (Money::toDecimalString).
 */
final class ReportRegistry
{
    /** @return array<string, array{service: class-string, method: string, title: string, rows: string, columns: array<string, string>}> */
    public static function all(): array
    {
        return [
            'sales-daily' => [
                'service' => SalesReportService::class, 'method' => 'daily',
                'title' => 'Günlük Satış', 'rows' => 'days',
                'columns' => ['date' => 'Tarih', 'orders' => 'Sipariş', 'revenue_minor' => 'Ciro (₺)', 'avg_basket_minor' => 'Ortalama Sepet (₺)'],
            ],
            'sales-hourly' => [
                'service' => SalesReportService::class, 'method' => 'hourly',
                'title' => 'Saatlik Satış', 'rows' => 'hours',
                'columns' => ['hour' => 'Saat', 'orders' => 'Sipariş', 'revenue_minor' => 'Ciro (₺)'],
            ],
            'sales-summary' => [
                'service' => SalesReportService::class, 'method' => 'summary',
                'title' => 'Satış Özeti', 'rows' => '',
                'columns' => [],
            ],
            'sales-categories' => [
                'service' => SalesReportService::class, 'method' => 'categories',
                'title' => 'Kategori Satışları', 'rows' => 'rows',
                'columns' => ['name' => 'Kategori', 'qty' => 'Adet', 'orders' => 'Sipariş', 'revenue_minor' => 'Ciro (₺)'],
            ],
            'sales-products' => [
                'service' => SalesReportService::class, 'method' => 'products',
                'title' => 'Ürün Satışları', 'rows' => 'rows',
                'columns' => ['name' => 'Ürün', 'qty' => 'Adet', 'orders' => 'Sipariş', 'revenue_minor' => 'Ciro (₺)'],
            ],
            'sales-variants' => [
                'service' => SalesReportService::class, 'method' => 'variants',
                'title' => 'Varyant Satışları', 'rows' => 'rows',
                'columns' => ['name' => 'Ürün', 'variant' => 'Varyant', 'qty' => 'Adet', 'revenue_minor' => 'Ciro (₺)'],
            ],
            'sales-tables' => [
                'service' => SalesReportService::class, 'method' => 'tables',
                'title' => 'Masa Satışları', 'rows' => 'rows',
                'columns' => ['name' => 'Masa', 'orders' => 'Sipariş', 'turns' => 'Devir', 'avg_minutes' => 'Ort. Süre (dk)', 'revenue_minor' => 'Ciro (₺)'],
            ],
            'sales-channels' => [
                'service' => SalesReportService::class, 'method' => 'channels',
                'title' => 'Kanal Satışları', 'rows' => 'rows',
                'columns' => ['label' => 'Kanal', 'orders' => 'Sipariş', 'share' => 'Pay (%)', 'revenue_minor' => 'Ciro (₺)'],
            ],

            'finance-summary' => [
                'service' => FinanceReportService::class, 'method' => 'summary',
                'title' => 'Finans Özeti', 'rows' => '',
                'columns' => [],
            ],
            'finance-vat' => [
                'service' => FinanceReportService::class, 'method' => 'vat',
                'title' => 'KDV Dağılımı', 'rows' => 'rows',
                'columns' => ['rate' => 'KDV Oranı (%)', 'gross_minor' => 'Brüt (₺)', 'vat_minor' => 'KDV (₺)', 'net_minor' => 'Net (₺)'],
            ],
            'finance-payment-methods' => [
                'service' => FinanceReportService::class, 'method' => 'paymentMethods',
                'title' => 'Ödeme Yöntemleri', 'rows' => 'rows',
                'columns' => ['label' => 'Yöntem', 'count' => 'İşlem', 'share' => 'Pay (%)', 'amount_minor' => 'Tutar (₺)', 'tips_minor' => 'Bahşiş (₺)'],
            ],
            'finance-cash-sessions' => [
                'service' => FinanceReportService::class, 'method' => 'cashSessions',
                'title' => 'Kasa Oturumları', 'rows' => 'rows',
                'columns' => ['z_number' => 'Z No', 'register' => 'Kasa', 'opened_by' => 'Açan', 'opened_at' => 'Açılış', 'closed_at' => 'Kapanış', 'expected_minor' => 'Beklenen (₺)', 'counted_minor' => 'Sayılan (₺)', 'difference_minor' => 'Fark (₺)'],
            ],
            'finance-open-accounts' => [
                'service' => FinanceReportService::class, 'method' => 'openAccounts',
                'title' => 'Açık Hesaplar', 'rows' => 'open_orders',
                'columns' => ['id' => 'Adisyon', 'table' => 'Masa', 'customer' => 'Müşteri', 'created_at' => 'Açılış', 'total_minor' => 'Tutar (₺)', 'paid_minor' => 'Ödenen (₺)', 'balance_minor' => 'Bakiye (₺)'],
            ],
            'finance-reconciliation' => [
                'service' => FinanceReportService::class, 'method' => 'reconciliation',
                'title' => 'POS / Nakit / Sistem Mutabakatı', 'rows' => '',
                'columns' => [],
            ],

            'product-profitability' => [
                'service' => ProductReportService::class, 'method' => 'profitability',
                'title' => 'Ürün Kârlılığı', 'rows' => 'rows',
                'columns' => ['name' => 'Ürün', 'qty' => 'Adet', 'revenue_minor' => 'Ciro (₺)', 'net_minor' => 'Net (₺)', 'cost_minor' => 'Maliyet (₺)', 'profit_minor' => 'Brüt Kâr (₺)', 'margin' => 'Marj (%)'],
            ],

            'ops-eod' => [
                'service' => OpsReportService::class, 'method' => 'endOfDay',
                'title' => 'Gün Sonu Raporu', 'rows' => '',
                'columns' => [],
            ],
            // Cari/Borçlar modülü (Receivables): şema herhangi bir sebeple
            // yoksa 'available'=false ile boş döner (bkz. ReceivablesReportService).
            'ops-open-receivables' => [
                'service' => ReceivablesReportService::class, 'method' => 'openAccounts',
                'title' => 'Açık Cariler (Borç Hesapları)', 'rows' => 'rows',
                'columns' => ['name' => 'Cari', 'phone' => 'Telefon', 'balance_minor' => 'Bakiye (₺)'],
            ],
            'ops-delayed' => [
                'service' => OpsReportService::class, 'method' => 'delayed',
                'title' => 'Geciken Siparişler', 'rows' => 'rows',
                'columns' => ['id' => 'Adisyon', 'table' => 'Masa', 'status_label' => 'Durum', 'age_minutes' => 'Yaş (dk)', 'total_minor' => 'Tutar (₺)'],
            ],
            'ops-station-prep' => [
                'service' => OpsReportService::class, 'method' => 'stationPrep',
                'title' => 'İstasyon Hazırlama Süreleri', 'rows' => 'rows',
                'columns' => ['station' => 'İstasyon', 'items' => 'Kalem', 'avg_minutes' => 'Ortalama (dk)', 'max_minutes' => 'En Uzun (dk)'],
            ],
            'ops-service-requests' => [
                'service' => OpsReportService::class, 'method' => 'serviceRequests',
                'title' => 'Servis Talepleri', 'rows' => 'rows',
                'columns' => ['label' => 'Talep', 'total' => 'Toplam', 'open' => 'Açık', 'avg_response_minutes' => 'Ort. Yanıt (dk)'],
            ],
            'ops-cancellations' => [
                'service' => OpsReportService::class, 'method' => 'cancellations',
                'title' => 'İptal / İkram Nedenleri', 'rows' => 'order_cancels',
                'columns' => ['reason' => 'Neden', 'count' => 'Adet', 'value_minor' => 'Değer (₺)'],
            ],
            'ops-channel-usage' => [
                'service' => OpsReportService::class, 'method' => 'channelUsage',
                'title' => 'QR / Kiosk Kullanımı', 'rows' => 'channels',
                'columns' => ['label' => 'Kanal', 'orders' => 'Sipariş', 'share' => 'Pay (%)'],
            ],

            'staff-performance' => [
                'service' => StaffReportService::class, 'method' => 'performance',
                'title' => 'Personel Performansı', 'rows' => 'rows',
                'columns' => [
                    'name' => 'Personel', 'orders' => 'Sipariş', 'items' => 'Kalem',
                    'sales_minor' => 'Satış (₺)', 'avg_basket_minor' => 'Ort. Sepet (₺)',
                    'avg_service_minutes' => 'Ort. Servis (dk)', 'discount_minor' => 'İndirim (₺)',
                    'comp_count' => 'İkram', 'comp_minor' => 'İkram Değeri (₺)',
                    'cancelled' => 'İptal', 'cancel_rate' => 'İptal Oranı (%)',
                    'requests_handled' => 'Karşılanan Talep',
                ],
            ],
        ];
    }

    public static function exists(string $key): bool
    {
        return array_key_exists($key, self::all());
    }

    /** @return array{service: class-string, method: string, title: string, rows: string, columns: array<string, string>} */
    public static function get(string $key): array
    {
        return self::all()[$key];
    }

    /** Servisi çağırıp ham rapor verisini döndürür. */
    public static function run(string $key, ReportFilters $filters): array
    {
        $def = self::get($key);

        return app($def['service'])->{$def['method']}($filters);
    }
}
