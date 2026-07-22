<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Faz-2 (Venue): alan hiyerarşisi — şube → kat → salon/alan → masa.
 * Masa kolonları ayrı migration'da `tables`'a eklenir (omurga bozulmaz).
 * ADR-004: tüm tablolar tenant_id + branch_id ile başlar, bileşik indeksli.
 */
return new class extends Migration
{
    public function up(): void
    {
        // Kat (zemin, 1. kat, çatı terası...). İsteğe bağlı seviye:
        // alan bir kata bağlanmak zorunda değildir (tek katlı işletme).
        Schema::create('venue_floors', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->string('name', 100);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();

            $table->unique(['tenant_id', 'branch_id', 'name']);
            $table->index(['tenant_id', 'branch_id', 'sort_order']);
        });

        // Salon/alan: iç salon, teras, bahçe, bar, VIP, paket servis, kiosk...
        Schema::create('venue_areas', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->foreignId('floor_id')->nullable()->constrained('venue_floors')->nullOnDelete();
            $table->string('name', 100);
            $table->string('type', 30)->default('indoor');
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['tenant_id', 'branch_id', 'name']);
            $table->index(['tenant_id', 'branch_id', 'is_active', 'sort_order']);
        });

        // QR tarama günlüğü (ADR-008): token, zaman, UA; IP hash'lenir,
        // kişisel veri tutulmaz. Şüpheli kullanım tespitinin veri kaynağı.
        Schema::create('qr_scans', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->nullable()->constrained()->cascadeOnDelete();
            $table->unsignedBigInteger('table_id')->nullable(); // FK yok: masa silinse de günlük kalır
            $table->char('token', 26);
            $table->string('result', 20); // ok | invalid | revoked | inactive | throttled
            $table->char('ip_hash', 64);
            $table->string('user_agent', 255)->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index('token');
            $table->index(['ip_hash', 'result', 'created_at']); // şüpheli kullanım penceresi
            $table->index(['tenant_id', 'created_at']);
        });

        // QR çıktı şablonu (kiracı başına tek satır): renk/çerçeve/logo/metinler.
        Schema::create('venue_qr_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('header_text', 100)->nullable();  // boşsa işletme adı
            $table->string('description', 160)->nullable();  // ör. "Menü için okutun"
            $table->char('color', 7)->default('#111111');    // QR deseni + metin
            $table->char('bg_color', 7)->default('#FFFFFF');
            $table->string('frame', 20)->default('simple');  // none | simple | rounded
            $table->string('logo_path')->nullable();         // storage/app altı, sunucuda işlenir
            $table->boolean('show_table_no')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('venue_qr_settings');
        Schema::dropIfExists('qr_scans');
        Schema::dropIfExists('venue_areas');
        Schema::dropIfExists('venue_floors');
    }
};
