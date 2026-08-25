<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * PRİM / KOMİSYON — prim şeması (commission_schemes) tablosu.
 *
 * Yönetici (commission.manage) personel primini tanımlar. Bir şema ya belirli
 * bir pozisyona (position) ya da herkese (position = null) uygulanır. Prim
 * hesabı üç tabandan (basis) biriyle yapılır:
 *   - percent_sales : satışın yüzdesi (rate_bps; yüzde × 100 → %5 = 500)
 *   - per_order     : kapanan sipariş başına sabit tutar (per_order_minor)
 *   - target_bonus  : satış hedefi (target_minor) tutunca sabit ikramiye (bonus_minor)
 *
 * Çok kiracılı (tenant_id, BelongsToTenant). Tüm para alanları *_minor.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('commission_schemes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();

            $table->string('name', 100);

            // Prim tabanı: percent_sales | per_order | target_bonus
            $table->string('basis', 16);

            // percent_sales için oran (baz puan; %5 = 500)
            $table->unsignedInteger('rate_bps')->default(0);

            // per_order için sipariş başına tutar
            $table->unsignedBigInteger('per_order_minor')->default(0);

            // target_bonus için hedef satış ve ikramiye
            $table->unsignedBigInteger('target_minor')->default(0);
            $table->unsignedBigInteger('bonus_minor')->default(0);

            // Yalnız bu pozisyona uygulanır; null = tüm personel
            $table->string('position', 80)->nullable();

            $table->boolean('is_active')->default(true);

            $table->timestamps();

            $table->index(['tenant_id', 'is_active']);
            $table->index(['tenant_id', 'position']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('commission_schemes');
    }
};
