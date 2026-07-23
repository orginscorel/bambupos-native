<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * İşletme (kiracı) logosu: public QR menüsünün başında gösterilir.
 * Dosyanın kendisi public diskte kiracı-izolasyonlu yoldadır
 * (tenants/{id}/branding/…); burada yalnız yol saklanır.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table): void {
            $table->string('logo_path')->nullable()->after('settings');
        });
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table): void {
            $table->dropColumn('logo_path');
        });
    }
};
