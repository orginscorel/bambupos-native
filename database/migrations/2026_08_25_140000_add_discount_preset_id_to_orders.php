<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Adisyona uygulanan indirimin HANGİ TANIMDAN geldiği.
 *
 * Şimdiye kadar yalnız `discount_reason` (serbest metin) tutuluyordu; hazır
 * tanımlarda bu metin tanımın adıydı. Kullanım istatistiğini ada göre saymak
 * kırılgan: tanım yeniden adlandırılınca geçmiş kayıtlar kopuyor, benzer
 * adlar birbirine karışıyor. Referans sütunu bunu kesinleştirir.
 *
 * DİKKAT — SQLite tuzağı: `foreignId()->constrained()` SQLite'ta tabloyu
 * YENİDEN KURAR ve `orders` üzerindeki ham SQL ile yazılmış TETİKLEYİCİLER
 * (orders_open_slot_bi/bu) ile `orders_tenant_table_open_slot_unique`
 * indeksi kaybolur — "masada tek açık adisyon" güvencesi sessizce düşer.
 * (Test paketi SQLite bellek-içi çalışır ve bunu yakaladı.)
 * Bu yüzden sütun DÜZ eklenir; yabancı anahtar YALNIZ MySQL'de tanımlanır.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table): void {
            $table->unsignedBigInteger('discount_preset_id')->nullable()->after('discount_reason');
            $table->index(['tenant_id', 'discount_preset_id'], 'orders_tenant_discount_preset_index');
        });

        if (DB::getDriverName() === 'mysql') {
            Schema::table('orders', function (Blueprint $table): void {
                $table->foreign('discount_preset_id', 'orders_discount_preset_id_foreign')
                    ->references('id')->on('discount_presets')->nullOnDelete();
            });
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'mysql') {
            Schema::table('orders', function (Blueprint $table): void {
                $table->dropForeign('orders_discount_preset_id_foreign');
            });
        }

        Schema::table('orders', function (Blueprint $table): void {
            $table->dropIndex('orders_tenant_discount_preset_index');
            $table->dropColumn('discount_preset_id');
        });
    }
};
