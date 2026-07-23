<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Borçlar / Cari modülü (Adisyon-Cari): "adisyonu borca taşı" hedefi.
 *
 * - `receivables`: cari hesap (ad/telefon/e-posta + kuruş-integer bakiye —
 *   ADR-007). Bakiye HER ZAMAN >= 0 (aşırı tahsilat REDDEDİLİR — para
 *   değişmezi; bkz. ReceivableService::collect).
 * - `receivable_transactions`: DEĞİŞMEZ defter (CashMovement ile aynı
 *   desen). `amount_minor` işaretli: borç transferi/düzeltme (+),
 *   tahsilat (-). Bakiye HER ZAMAN bu defterin toplamından türetilebilir
 *   (para korunumu testi: Σamount_minor = receivables.balance_minor).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('receivables', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();

            $table->string('name', 150);
            $table->string('phone', 32)->nullable();
            $table->string('email', 150)->nullable();
            $table->string('note', 500)->nullable();

            // Kuruş-integer, HER ZAMAN >= 0 (aşırı tahsilat reddedilir).
            $table->unsignedBigInteger('balance_minor')->default(0);

            $table->boolean('is_active')->default(true);
            $table->foreignId('created_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['tenant_id', 'is_active', 'name']);
        });

        Schema::create('receivable_transactions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('receivable_id')->constrained()->cascadeOnDelete();
            $table->foreignId('order_id')->nullable()->constrained('orders')->nullOnDelete();

            $table->string('type', 20); // debt_transfer | payment | adjustment
            $table->bigInteger('amount_minor'); // + borç artışı, - tahsilat/azalış
            $table->string('method', 20)->nullable(); // tahsilat yöntemi (cash/card/other)
            $table->string('note', 500)->nullable();
            $table->unsignedBigInteger('balance_after_minor'); // iz: o andaki bakiye

            $table->foreignId('performed_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['tenant_id', 'receivable_id', 'id']);
            $table->index(['tenant_id', 'order_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('receivable_transactions');
        Schema::dropIfExists('receivables');
    }
};
