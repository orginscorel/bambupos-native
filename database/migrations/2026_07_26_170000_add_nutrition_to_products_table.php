<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ürünlere tahmini gramaj (porsiyon g/ml) alanı ekler.
 *
 * `calories` kolonu Katalog tablolarında (2026_07_22) zaten var; burada yalnız
 * eksik olan(lar) eklenir. Idempotent olması için `hasColumn` ile korunur —
 * eski/yeni kurulumların ikisinde de güvenle çalışır.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('products', function (Blueprint $table): void {
            // Porsiyon başına tahmini net ağırlık/hacim (gram ya da ml).
            if (! Schema::hasColumn('products', 'weight_grams')) {
                $table->unsignedInteger('weight_grams')->nullable()->after('prep_minutes');
            }

            // Kalori (kcal) — normalde Katalog göçünde vardır; yoksa tamamla.
            if (! Schema::hasColumn('products', 'calories')) {
                $table->unsignedInteger('calories')->nullable()->after('weight_grams');
            }
        });
    }

    public function down(): void
    {
        Schema::table('products', function (Blueprint $table): void {
            if (Schema::hasColumn('products', 'weight_grams')) {
                $table->dropColumn('weight_grams');
            }
        });
    }
};
