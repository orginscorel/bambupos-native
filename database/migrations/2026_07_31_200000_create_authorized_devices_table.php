<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * İzinli Cihazlar (A3 — cihaz kilidi temeli).
 *
 * Amaç: KDS/kiosk/masaüstü/terminal ekranlarının açıldığı bir "link"i
 * (route/kaynak tanımı) İLK açan tarayıcıya kilitlemek. Kayıt iki şekilde
 * doğar:
 *  - Otomatik: link ilk kez açıldığında (henüz kayıt yoksa) DeviceBindingService
 *    kendisi bir satır oluşturup device_token üretir ve tarayıcıya çerez olarak
 *    yazar.
 *  - Ön-yetkili: yönetici panelden "yeni ekle" ile bound_link BOŞ bir satır
 *    oluşturur, device_token'ı (URL parametresi olarak) hedef cihaza verir;
 *    o token'la yapılan ilk ziyaret bound_link'i doldurur ve cihaza kilitler.
 *
 * device_token TARAYICIDA saklanan sırdır (çerez/localStorage); bound_link
 * ise bu sırrın hangi ekrana/kaynağa ait olduğunu tutar. Aynı bound_link'e
 * FARKLI bir device_token ile gelen istek reddedilir ("başka cihaza kilitli").
 *
 * NOT: (tenant_id, bound_link) çifti üzerinde mantıksal olarak tekil olmalı;
 * bound_link NULL olabildiği için (ön-yetkili, henüz bağlanmamış satırlar)
 * portable bir kısmi-unique kısıt yerine DeviceBindingService eşzamanlılığı
 * transaction + lockForUpdate ile yönetir (bkz. app/Modules/Devices/Services/
 * DeviceBindingService.php).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('authorized_devices', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('tenant_id');

            $table->uuid('device_token')->unique();
            $table->string('kind', 20); // kds | kiosk | desktop | terminal
            $table->string('name', 100)->nullable();
            // Bağlandığı link/kaynak tanımı (ör. route adı veya route token'ı).
            $table->string('bound_link', 255)->nullable();
            $table->string('status', 20)->default('active'); // active | revoked

            $table->timestamp('last_seen_at')->nullable();
            $table->timestamp('first_bound_at')->nullable();
            $table->json('meta')->nullable();

            $table->timestamps();

            $table->index(['tenant_id', 'kind']);
            $table->index(['tenant_id', 'bound_link']);
            $table->index(['tenant_id', 'status']);
        });

        if (Schema::getConnection()->getDriverName() === 'mysql') {
            Schema::table('authorized_devices', function (Blueprint $table): void {
                $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('authorized_devices');
    }
};
