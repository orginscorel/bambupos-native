<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Personel-Yetki ajanı: kişi bazlı izin istisnaları + varsayılan açılış ekranı.
 *
 * permission_user.mode:
 *  - grant  → rol setinin ÜZERİNE eklenen izin,
 *  - revoke → rolden gelse bile kullanıcıdan DÜŞÜLEN izin.
 * Etkili izin = (rollerin birleşimi + grant'lar) − revoke'lar.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('permission_user', function (Blueprint $table) {
            $table->id();
            $table->foreignId('permission_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('mode', 10)->default('grant'); // grant | revoke
            $table->timestamps();

            $table->unique(['permission_id', 'user_id']);
            $table->index(['user_id', 'mode']);
        });

        Schema::table('users', function (Blueprint $table) {
            // null = otomatik (izinlere göre en uygun ekran seçilir)
            $table->string('default_screen', 30)->nullable()->after('theme');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('default_screen');
        });

        Schema::dropIfExists('permission_user');
    }
};
