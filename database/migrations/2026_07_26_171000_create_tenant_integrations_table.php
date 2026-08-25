<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Takılabilir entegrasyon çerçevesi deposu — ödeme / teslimat platformu /
 * e-fatura / muhasebe bağlantıları TEK yerden aç/kapa + yapılandırma.
 *
 * Her satır bir kiracının bir entegrasyonuna karşılık gelir:
 *   - is_enabled: AKTİF ise sistem entegrasyona uyum sağlar; PASİF (veya satır
 *     yok) ise sistem entegrasyonsuz sorunsuz çalışır (graceful no-op).
 *   - config: sağlayıcıya özel API anahtarları / gizli değerler (JSON). Gizli
 *     alanlar panele MASKELİ döner; boş bırakılırsa mevcut değer korunur.
 *
 * Satır YOKSA → entegrasyon kapalı sayılır (IntegrationCatalog varsayılanı
 * kapalı). Kiracı süzgeci TenantIntegration modelinde (BelongsToTenant) ve
 * Integrations cephesinde AÇIKÇA uygulanır. ADR: kapalı = çerçeve sessiz.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tenant_integrations', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained('tenants')->cascadeOnDelete();
            $table->string('key', 40); // IntegrationCatalog anahtarı (iyzico, yemeksepeti, efatura, ...)
            $table->boolean('is_enabled')->default(false);
            $table->json('config')->nullable(); // sağlayıcı API anahtarları vb. (gizli alanlar dahil)
            $table->timestamps();

            // Kiracı başına entegrasyon anahtarı TEKİL: aynı sağlayıcı iki kez yazılamaz.
            $table->unique(['tenant_id', 'key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tenant_integrations');
    }
};
