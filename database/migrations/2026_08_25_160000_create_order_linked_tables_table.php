<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * BİRLEŞİK MASALAR (kalabalık grup birden çok masaya oturur).
 *
 * Adisyon birleştirme şimdiye kadar kaynak adisyonu İPTAL ediyordu; kaynak
 * masa panoda BOŞ görünüyordu. Oysa grup hâlâ o masada oturuyor: garson boş
 * sanıp yeni müsteri oturtabiliyor, kasa da hesabın hangi masaları kapsadığını
 * bilmiyordu.
 *
 * Bu tablo "şu masa şu adisyona bağlı" bağını tutar. Adisyonun KENDİ masası
 * (orders.table_id) burada YER ALMAZ — yalnız sonradan eklenen masalar.
 * Bir masa aynı anda tek adisyona bağlanabilir (unique).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('order_linked_tables', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('order_id')->constrained('orders')->cascadeOnDelete();
            $table->foreignId('table_id')->constrained('tables')->cascadeOnDelete();
            $table->timestamp('created_at')->nullable();

            // Bir masa aynı anda YALNIZ bir adisyona bağlı olabilir.
            $table->unique('table_id', 'order_linked_tables_table_unique');
            $table->index(['tenant_id', 'order_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('order_linked_tables');
    }
};
