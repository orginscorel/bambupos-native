<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Kiosk cihaz kaydı (Faz 8).
 *
 * Her kiosk cihazı BİR kiracı + BİR şubeye bağlıdır ve yalnız kendi opak
 * token'ıyla tanınır (masa QR token deseninin aynısı — ADR-008):
 *  - token: 26 karakter base32, tahmin edilemez, URL'de tek kimlik.
 *  - previous_token: rotasyon izi → eski adres 410 "kayıt yenilendi" alır.
 *  - status: active | locked (uzaktan kilit; panelden anında).
 *  - payment_mode: kiosk_pos (mock POS ile cihazda tahsilat) | counter
 *    (sipariş kioskta, ödeme kasada).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('kiosk_devices', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('tenant_id');
            $table->unsignedBigInteger('branch_id');

            $table->string('name', 100);
            $table->char('token', 26)->unique();
            $table->char('previous_token', 26)->nullable();
            $table->string('status', 20)->default('active');
            $table->string('payment_mode', 20)->default('kiosk_pos');

            $table->timestamp('locked_at')->nullable();
            $table->timestamp('token_rotated_at')->nullable();
            $table->timestamp('last_seen_at')->nullable();
            $table->string('last_ip', 45)->nullable();
            $table->json('meta')->nullable();

            $table->timestamps();

            $table->index(['tenant_id', 'branch_id']);
            $table->index('previous_token');
        });

        if (Schema::getConnection()->getDriverName() === 'mysql') {
            Schema::table('kiosk_devices', function (Blueprint $table): void {
                $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
                $table->foreign('branch_id')->references('id')->on('branches')->cascadeOnDelete();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('kiosk_devices');
    }
};
