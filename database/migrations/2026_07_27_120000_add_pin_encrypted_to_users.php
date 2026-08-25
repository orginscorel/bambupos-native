<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Personel PIN'inin YÖNETİCİ tarafından görüntülenebilmesi için tersine-
 * çevrilebilir (Crypt) şifreli kopyası. Doğrulama HÂLÂ bcrypt `pin_hash` ile
 * yapılır (tek yönlü, güvenli); `pin_encrypted` yalnızca yetkili yöneticinin
 * "PIN görüntüle" işlevi içindir (app key olmadan çözülemez, audit'lenir).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->text('pin_encrypted')->nullable()->after('pin_hash');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn('pin_encrypted');
        });
    }
};
