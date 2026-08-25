<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Kiracı bazlı PANEL TEMASI: marka rengi + font + açık/koyu varsayılan.
 * Güvenli: nullable JSON; boşsa sistem varsayılan teması kullanılır.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table): void {
            $table->json('theme')->nullable()->after('logo_path');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table): void {
            $table->dropColumn('theme');
        });
    }
};
