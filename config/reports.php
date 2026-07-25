<?php

/**
 * Raporlar modülü ayarları.
 */
return [

    // Bir sipariş mutfak aşamasında bu süreden uzun kalırsa "geciken" sayılır.
    'delayed_threshold_minutes' => (int) env('REPORTS_DELAYED_THRESHOLD_MINUTES', 20),

    // Dışa aktarma dosyalarının yazıldığı disk ve kök klasör.
    'export_disk' => env('REPORTS_EXPORT_DISK', 'local'),
    'export_dir' => 'reports',

    // PDF dışa aktarmada tablo satır tavanı (dompdf bellek koruması);
    // aşan kısım CSV/XLSX ile alınır — PDF dosyasında açıkça belirtilir.
    'pdf_row_limit' => 2000,

    // Tek dışa aktarma işinin işleyeceği en çok satır (güvenlik tavanı).
    'export_row_limit' => 100000,
];
