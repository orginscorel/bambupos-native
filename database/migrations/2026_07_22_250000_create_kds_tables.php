<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * KDS modülü (Faz-4): mutfak/bar/komi ekranları.
 *
 * - `kds_stations`: işletmenin KENDİ istasyon tanımları (yerleşikler
 *   config/kds.php'de; StationRegistry ikisini birleştirir).
 * - `kds_user_stations`: personel-istasyon ataması. Ataması olan kullanıcı
 *   KDS'de YALNIZ kendi istasyon(lar)ını görür/işaretler (sunucu tarafında
 *   zorlanır); ataması olmayan kds.view'lı kullanıcı tüm istasyonları görür.
 * - `kds_item_pickups`: komi "teslim aldım" işareti. Orders modülünün kalem
 *   durum makinesine (ready→served) ara durum EKLEMEDEN komi akışını taşır;
 *   "masaya götürdüm" = OrderService::setItemStatus(served).
 * - order_events (tenant_id, branch_id, id) indeksi: KDS polling cursor'ı
 *   "şubede son olay id'si"ni tek indeks okumasıyla bulur (ADR-006, en ucuz
 *   sorgu). Yalnız EK indekstir; Orders şema/davranışı değişmez.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('kds_stations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('key', 40);        // ürün kartındaki station değeri
            $table->string('name', 80);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['tenant_id', 'key']);
        });

        Schema::create('kds_user_stations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('station_key', 40);
            $table->timestamps();

            $table->unique(['tenant_id', 'user_id', 'station_key']);
        });

        Schema::create('kds_item_pickups', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('order_item_id')->constrained('order_items')->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->timestamp('created_at')->useCurrent();

            $table->unique(['order_item_id']);
        });

        Schema::table('order_events', function (Blueprint $table) {
            $table->index(['tenant_id', 'branch_id', 'id'], 'order_events_kds_cursor_idx');
        });
    }

    public function down(): void
    {
        Schema::table('order_events', function (Blueprint $table) {
            $table->dropIndex('order_events_kds_cursor_idx');
        });

        Schema::dropIfExists('kds_item_pickups');
        Schema::dropIfExists('kds_user_stations');
        Schema::dropIfExists('kds_stations');
    }
};
