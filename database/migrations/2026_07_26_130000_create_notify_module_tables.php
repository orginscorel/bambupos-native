<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * §8 Bildirim & Push (Notify modülü) şeması.
 *
 *  - notifications           : panel-içi zil + kalıcı bildirim kaydı (alıcı = user_id)
 *  - push_subscriptions      : tarayıcı web-push abonelikleri (endpoint tekil)
 *  - notification_preferences: kişi-bazlı olay tipi tercihleri (in_app / push)
 *
 * Kiracı izolasyonu: tüm tablolarda tenant_id (BelongsToTenant). Şube kapsamı:
 * notifications.branch_id (nullable — sisteme/HQ bildirimleri şubesiz olabilir).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('notifications', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->unsignedBigInteger('branch_id')->nullable();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('type', 40);
            $table->string('title');
            $table->string('body', 500)->nullable();
            // İlgili kayda derin bağlantı için serbest veri (order_id, item_id,
            // url, table_name vb.). Zil tıklamasında yönlendirme buradan.
            $table->json('data')->nullable();
            // Kısa pencere dedup + SLA "zaten bildirildi" kontrolü.
            $table->string('dedup_key', 120)->nullable();
            $table->timestamp('read_at')->nullable();
            $table->timestamps();

            // Zil sorgusu: kullanıcının okunmamış + son bildirimleri.
            $table->index(['user_id', 'read_at']);
            $table->index(['user_id', 'created_at']);
            $table->index(['tenant_id', 'branch_id']);
            $table->index(['user_id', 'dedup_key']);
        });

        Schema::create('push_subscriptions', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            // Push servis ucu (FCM/Mozilla/Apple) — cihaz başına tekil kimlik.
            $table->text('endpoint');
            $table->string('endpoint_hash', 64)->unique(); // sha256(endpoint) — tekillik
            $table->string('p256dh');
            $table->string('auth');
            $table->string('ua', 300)->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamps();

            $table->index(['user_id']);
        });

        Schema::create('notification_preferences', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('type', 40);
            $table->boolean('in_app')->default(true);
            $table->boolean('push')->default(true);
            $table->timestamps();

            // Kişi × olay tipi tekil (satır yoksa katalog varsayılanı geçerli).
            $table->unique(['user_id', 'type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notification_preferences');
        Schema::dropIfExists('push_subscriptions');
        Schema::dropIfExists('notifications');
    }
};
