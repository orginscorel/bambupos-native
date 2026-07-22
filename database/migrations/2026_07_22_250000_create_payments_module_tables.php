<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Payments modülü (Faz-5, ADR-010): kasa + ödeme + POS adapter.
 *
 * - `payments` TEK DOĞRULUK KAYNAĞIDIR; `orders.paid_minor` /
 *   `orders.refunded_minor` bu tablodan türetilir (asla elle set edilmez).
 * - Para alanları kuruş-integer (ADR-007). `rounding_minor` İMZALIDIR
 *   (yuvarlama aşağı/yukarı olabilir); geri kalan tutarlar unsigned.
 * - UNIQUE(provider, provider_txn_id): aynı sağlayıcı işlemi İKİ KEZ
 *   kaydedilemez (callback replay koruması katmanlarından biri).
 * - `cash_movements` DEĞİŞMEZDİR (model guard'ı) — düzeltme yalnız ters
 *   kayıtla yapılır; sessiz geriye dönük değişiklik imkânsızdır.
 */
return new class extends Migration
{
    public function up(): void
    {
        // ---- Orders'a Faz-5 alanları (servis bedeli / yuvarlama / iade) ----
        Schema::table('orders', function (Blueprint $table) {
            $table->unsignedBigInteger('service_charge_minor')->default(0)->after('vat_total_minor');
            $table->decimal('service_charge_percent', 5, 2)->nullable()->after('service_charge_minor');
            $table->string('service_charge_reason')->nullable()->after('service_charge_percent');
            $table->bigInteger('rounding_minor')->default(0)->after('service_charge_reason'); // İMZALI: ±99 kuruş
            $table->unsignedBigInteger('refunded_minor')->default(0)->after('paid_minor');
        });

        // ---- Kasa tanımı (şube başına birden fazla kasa) ----
        Schema::create('cash_registers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->string('name', 80);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['tenant_id', 'branch_id', 'name']);
        });

        // ---- Kasa oturumu (açılış → sayım → kapanış / Z) ----
        Schema::create('cash_sessions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->foreignId('cash_register_id')->constrained('cash_registers')->cascadeOnDelete();
            $table->unsignedInteger('z_number');                 // kasa başına artan Z sıra no
            $table->string('status', 10)->default('open');       // open | closed
            $table->unsignedBigInteger('opening_float_minor')->default(0); // açılış kasası (devir)
            $table->foreignId('opened_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('opened_at')->nullable();
            $table->foreignId('closed_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('closed_at')->nullable();
            $table->unsignedBigInteger('expected_cash_minor')->nullable(); // beklenen nakit (kapanışta hesaplanır)
            $table->unsignedBigInteger('counted_cash_minor')->nullable();  // sayılan nakit
            $table->bigInteger('difference_minor')->nullable();            // İMZALI fark (sayılan - beklenen)
            $table->string('closing_note', 500)->nullable();
            $table->json('summary')->nullable();                 // Z raporu anlık görüntüsü (kapanışta dondurulur)
            $table->timestamps();

            $table->unique(['cash_register_id', 'z_number']);
            $table->index(['tenant_id', 'branch_id', 'status']);
            $table->index(['tenant_id', 'cash_register_id', 'status']);
        });

        // ---- Ödemeler: TEK DOĞRULUK KAYNAĞI (ADR-010) ----
        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained(); // para kaydı: şube silinirken engellenir
            $table->foreignId('order_id')->constrained();  // para kaydı: sipariş silinirken engellenir
            $table->char('reference', 26)->unique();       // opak public referans (callback eşleme)

            $table->string('kind', 10)->default('payment'); // payment | refund
            $table->foreignId('refund_of_id')->nullable()->constrained('payments'); // iade referansı

            $table->string('method', 20);                  // PaymentMethod enum
            $table->string('status', 20)->default('pending'); // PaymentStatus enum

            $table->unsignedBigInteger('amount_minor');            // adisyona işleyen tutar
            $table->unsignedBigInteger('tip_minor')->default(0);   // bahşiş (adisyona İŞLEMEZ)
            $table->unsignedBigInteger('tendered_minor')->nullable(); // nakit: müşterinin verdiği
            $table->unsignedBigInteger('change_minor')->default(0);   // nakit: para üstü
            $table->char('currency', 3)->default('TRY');

            $table->string('provider', 30)->nullable();       // cash | card_present | mock | sandbox
            $table->string('provider_txn_id', 100)->nullable();
            $table->string('terminal_id', 60)->nullable();

            $table->foreignId('cash_session_id')->nullable()->constrained('cash_sessions')->nullOnDelete();
            $table->foreignId('cashier_id')->nullable()->constrained('users')->nullOnDelete();

            $table->string('reason')->nullable();             // void/iade nedeni
            $table->string('note')->nullable();
            $table->boolean('suspect')->default(false);       // tutar uyuşmazlığı vb. alarm
            $table->string('suspect_reason')->nullable();
            $table->json('meta')->nullable();                 // sağlayıcı ham yanıt özeti (maskeli)

            $table->timestamp('paid_at')->nullable();         // başarı anı
            $table->timestamps();

            // Aynı sağlayıcı işlemi iki kez kaydedilemez (replay/çift işleme).
            $table->unique(['provider', 'provider_txn_id']);
            $table->index(['tenant_id', 'order_id']);
            $table->index(['tenant_id', 'branch_id', 'status']);
            $table->index(['tenant_id', 'cash_session_id']);
        });

        // ---- Kasa hareketleri: DEĞİŞMEZ defter (düzeltme = ters kayıt) ----
        Schema::create('cash_movements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->foreignId('cash_session_id')->constrained('cash_sessions')->cascadeOnDelete();

            $table->string('type', 20);      // opening_float | payment | refund | cash_in | cash_out | expense | advance | correction
            $table->string('direction', 3);  // in | out
            $table->unsignedBigInteger('amount_minor');
            $table->string('reason')->nullable();

            $table->foreignId('payment_id')->nullable()->constrained('payments')->nullOnDelete();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();

            // Ters kayıt zinciri: düzeltme açık ve izlenebilir.
            $table->foreignId('reverses_id')->nullable()->constrained('cash_movements');
            $table->foreignId('reversed_by_id')->nullable()->constrained('cash_movements');

            $table->timestamp('created_at')->useCurrent();

            $table->index(['tenant_id', 'cash_session_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cash_movements');
        Schema::dropIfExists('payments');
        Schema::dropIfExists('cash_sessions');
        Schema::dropIfExists('cash_registers');

        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn([
                'service_charge_minor', 'service_charge_percent', 'service_charge_reason',
                'rounding_minor', 'refunded_minor',
            ]);
        });
    }
};
