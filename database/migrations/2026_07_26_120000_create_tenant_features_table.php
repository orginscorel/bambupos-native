<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Kiracı bazlı özellik (feature-flag) deposu — MODULE_MAP §9 "Eklentiler".
 *
 * Yalnız OPSİYONEL modüller/davranışlar burada tutulur (kiosk, rezervasyon,
 * qr'dan sipariş, garson-çağır, stok, vardiya, borçlar, terminaller).
 * Çekirdek (siparişler/masalar/kasa/menü/personel/raporlar) KAPATILAMAZ →
 * bu tabloya hiç yazılmaz.
 *
 * Satır YOKSA → koddaki makul VARSAYILAN geçerlidir (FeatureCatalog::default).
 * Satır varsa → `enabled` sütunu esastır. (ADR: kapalı = özellik hiç render
 * edilmez, veri sızmaz.)
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tenant_features', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained('tenants')->cascadeOnDelete();
            $table->string('feature', 40); // FeatureCatalog anahtarı (kiosk, reservations, ...)
            $table->boolean('enabled')->default(true);
            $table->timestamps();

            // Kiracı başına anahtar TEKİL: aynı özellik iki kez yazılamaz.
            $table->unique(['tenant_id', 'feature']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tenant_features');
    }
};
