<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Personel Portalı: mola türü ayrımı (normal mola / tuvalet molası).
 *
 * Yeni tablo GEREKMEZ — mevcut time_entry_breaks satırına 'kind' kolonu
 * eklenir. Varsayılan 'break' (geriye dönük tüm kayıtlar normal mola sayılır).
 * TimeClockService::breakStart türü yazar; süre/hesap makinesi türden bağımsız
 * (finalize yalnız toplam dakikayı kullanır).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('time_entry_breaks', function (Blueprint $table) {
            // break | toilet (ileride genişletilebilir; ENUM değil = migration'sız)
            $table->string('kind', 20)->default('break')->after('time_entry_id');
        });
    }

    public function down(): void
    {
        Schema::table('time_entry_breaks', function (Blueprint $table) {
            $table->dropColumn('kind');
        });
    }
};
