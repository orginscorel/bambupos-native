<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * İşletme Vitrini: şubenin public QR menüsünde gösterilecek WiFi bilgisi,
 * çalışma saatleri, sosyal medya ve konum verisi. Tek nullable JSON kolonu
 * (şema esnek; yeni alanlar migration'sız eklenebilir). Sadece public menüde
 * okunur — hassas sipariş/adisyon verisiyle ilişkisi yok.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('branches', function (Blueprint $table): void {
            $table->json('showcase')->nullable()->after('phone');
        });
    }

    public function down(): void
    {
        Schema::table('branches', function (Blueprint $table): void {
            $table->dropColumn('showcase');
        });
    }
};
