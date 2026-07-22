<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Masadan servis talepleri (garson çağır / hesap iste / su iste) —
 * public QR menüden gelir (kimlik yalnız token, ADR-008), garson
 * panosunda görünür ve kapatılır.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('service_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->foreignId('table_id')->constrained('tables')->cascadeOnDelete();
            $table->string('kind', 10);              // waiter | bill | water
            $table->string('status', 10)->default('open'); // open | done
            $table->foreignId('handled_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('handled_at')->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'branch_id', 'status']);
            $table->index(['tenant_id', 'table_id', 'kind', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('service_requests');
    }
};
