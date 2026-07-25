<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Reports modülü: gün sonu (ops-eod) ve mutabakat (finance-reconciliation)
 * raporları orders.placed_at / orders.closed_at üzerinden ARALIK taraması
 * yapar (açılan/kapanan adisyon sayımı). Var olan tek indeks
 * (tenant_id, created_at) bu kolonları kapsamaz — filtre `Using where` ile
 * TÜM tenant satırlarını tarardı (EXPLAIN doğrulandı). YALNIZ EK indeks;
 * Orders şeması/davranışı değişmez (payments.paid_at ile aynı desen,
 * bkz. 2026_07_23_120000_create_report_exports_table.php).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->index(['tenant_id', 'placed_at'], 'orders_tenant_placed_at_idx');
            $table->index(['tenant_id', 'closed_at'], 'orders_tenant_closed_at_idx');
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropIndex('orders_tenant_placed_at_idx');
            $table->dropIndex('orders_tenant_closed_at_idx');
        });
    }
};
