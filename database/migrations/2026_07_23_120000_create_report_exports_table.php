<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Reports modülü: dışa aktarma kuyruğu kayıtları + rapor sorgu indeksleri.
 *
 * - Büyük raporlar web isteğinde ÜRETİLMEZ (prompt §23): kayıt açılır,
 *   queue job dosyayı üretir, panel durumu yoklar ve hazır olunca indirir.
 * - payments(tenant_id, paid_at): finans raporlarının aralık taraması için
 *   YALNIZ EK indekstir; Payments şeması/davranışı değişmez.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('report_exports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();

            $table->string('report_key', 60);
            $table->string('format', 8);              // csv | xlsx | pdf
            $table->json('params');                   // ReportFilters::toArray()
            $table->string('status', 12)->default('queued'); // queued|processing|done|failed
            $table->string('file_path')->nullable();  // export diski göreli yolu
            $table->unsignedInteger('rows_count')->nullable();
            $table->string('error')->nullable();      // kullanıcıya gösterilebilir kısa neden
            $table->timestamp('finished_at')->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'user_id', 'id']);
            $table->index(['tenant_id', 'status']);
        });

        Schema::table('payments', function (Blueprint $table) {
            $table->index(['tenant_id', 'paid_at'], 'payments_tenant_paid_at_idx');
        });
    }

    public function down(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->dropIndex('payments_tenant_paid_at_idx');
        });

        Schema::dropIfExists('report_exports');
    }
};
