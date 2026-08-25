<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Terminal LİSANS limiti (§13 Faz 3 — panelden lisanslı terminal kurulumu).
 *
 * Nullable int: NULL = sınırsız (bilinçli, tek tek tenant için açılan bir
 * istisna). Sütun DB-seviyesinde config('terminal.license.default_limit')
 * ile aynı "makul varsayılan" değere sahiptir (bkz. config/terminal.php) —
 * hem yeni hem MEVCUT kiracılar bu satırdan sonra o varsayılanla başlar,
 * hiç kimse aniden "sınırsız" olmaz. Plana bağlı türetme BİLİNÇLİ OLARAK
 * burada YOK (bambumpos SaaS tarafı ileride bu sütunu plana göre günceller);
 * bu geçiş yalnız tenant-setting/config iskeletini kurar.
 */
return new class extends Migration
{
    public function up(): void
    {
        $default = (int) config('terminal.license.default_limit', 5);

        Schema::table('tenants', function (Blueprint $table) use ($default): void {
            $table->unsignedInteger('terminal_license_limit')->nullable()->default($default)->after('theme');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table): void {
            $table->dropColumn('terminal_license_limit');
        });
    }
};
