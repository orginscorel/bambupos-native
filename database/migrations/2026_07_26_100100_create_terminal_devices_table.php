<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * İstasyon terminal cihazı (§13, Faz A) — kiosk_devices deseninin birebir
 * uyarlaması (ADR-008):
 *  - token: 26 karakter base32, tahmin edilemez, URL'de tek kimlik.
 *  - previous_token: rotasyon izi → eski adres 410 "kayıt yenilendi" alır.
 *  - station: kitchen | barista | komi (cihazın kilitli olduğu ekran).
 *  - user_id: bu cihazın açtığı GİZLİ, istasyona-atanmış terminal kullanıcısı
 *    (users.is_terminal=true). Cihaz silinince kullanıcı da düşer (cascade).
 *  - status: active | inactive (uzaktan kilit; panelden anında).
 *
 * Kiracı/şube/istasyon YALNIZ token'dan türer; istekten asla alınmaz.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('terminal_devices', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('tenant_id');
            $table->unsignedBigInteger('branch_id');
            $table->unsignedBigInteger('user_id')->nullable();

            $table->string('station', 20);              // kitchen | barista | komi
            $table->string('name', 100);
            $table->char('token', 26)->unique();
            $table->char('previous_token', 26)->nullable();
            $table->string('status', 20)->default('active'); // active | inactive
            $table->timestamp('token_rotated_at')->nullable();
            $table->timestamp('locked_at')->nullable();
            $table->timestamp('last_seen_at')->nullable();
            $table->string('last_ip', 45)->nullable();

            $table->timestamps();

            $table->index(['tenant_id', 'branch_id']);
            $table->index('previous_token');
        });

        if (Schema::getConnection()->getDriverName() === 'mysql') {
            Schema::table('terminal_devices', function (Blueprint $table): void {
                $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
                $table->foreign('branch_id')->references('id')->on('branches')->cascadeOnDelete();
                // Cihaz silinince gizli terminal kullanıcısı da temizlenir.
                $table->foreign('user_id')->references('id')->on('users')->nullOnDelete();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('terminal_devices');
    }
};
