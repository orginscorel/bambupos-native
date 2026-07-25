<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * İstasyon Cihaz Modu (§13, Faz A) — gizli terminal kullanıcısı işaretleri.
 *
 * Terminal cihazı (Mutfak/Barista/Komi) = istasyona-atanmış, GİZLİ bir
 * kullanıcı + opak token (kiosk deseni). Bu kullanıcılar mevcut auth/izin/
 * istasyon-süzme altyapısını BİREBİR kullanır; tek fark:
 *  - is_terminal=true → Personel listesinde GÖRÜNMEZ, impersonate edilemez,
 *    normal (e-posta/PIN/WHMCS) giriş yapamaz, panele KİLİTLİ moddan girer.
 *  - terminal_station → cihazın istasyonu (kitchen|barista|komi); kilitli
 *    modda yalnız bu istasyon ekranı açılır (rota koruması + kilit rozeti).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->boolean('is_terminal')->default(false)->after('is_active');
            $table->string('terminal_station', 20)->nullable()->after('is_terminal');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn(['is_terminal', 'terminal_station']);
        });
    }
};
