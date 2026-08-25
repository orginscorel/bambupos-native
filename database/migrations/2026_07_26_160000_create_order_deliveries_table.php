<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Teslimat (Paket/Kurye) — order_deliveries tablosu.
 *
 * Her PAKET siparişe (Order service_type=package) bir teslimat kaydı eşlik
 * eder (order_id UNIQUE). Yönetici bir kuryeye atar (delivery.manage), kurye
 * kendi portalından durumunu ilerletir (assigned → on_the_way → delivered).
 * Çok kiracılı (tenant_id) + şube kapsamlı (branch_id, nullable = şubesiz).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('order_deliveries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();

            // Sipariş — sipariş başına TEK teslimat kaydı (unique).
            $table->foreignId('order_id')->unique()
                ->constrained('orders')->cascadeOnDelete();

            $table->foreignId('branch_id')->nullable()
                ->constrained()->nullOnDelete();

            $table->string('address', 400);
            $table->string('note', 255)->nullable();

            // Atanan kurye (personel). Silinirse teslimat sahipsiz kalır → nullOnDelete.
            $table->foreignId('courier_id')->nullable()
                ->constrained('users')->nullOnDelete();

            // pending|assigned|on_the_way|delivered|failed
            $table->string('status', 16)->default('pending');

            $table->unsignedBigInteger('fee_minor')->default(0);

            $table->dateTime('assigned_at')->nullable();
            $table->dateTime('delivered_at')->nullable();

            $table->timestamps();

            $table->index(['tenant_id', 'status']);
            $table->index(['tenant_id', 'courier_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('order_deliveries');
    }
};
