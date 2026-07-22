<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Panelden yönetilen e-posta (SMTP) ayarları.
 *
 * Kapsam modeli:
 *  - tenant_id NULL  → platform düzeyi VARSAYILAN (tek satır; kod garanti eder)
 *  - tenant_id dolu  → işletmenin İSTEĞE BAĞLI override'ı (satır varsa geçerlidir)
 *
 * `password` sütunu HER ZAMAN Laravel Crypt ile şifreli saklanır
 * (modelde `encrypted` cast). Düz metin parola asla yazılmaz.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('mail_settings', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->nullable()->unique()
                ->constrained('tenants')->cascadeOnDelete();

            $table->string('mailer', 20)->default('smtp'); // smtp | sendmail | log
            $table->string('host')->nullable();
            $table->unsignedInteger('port')->nullable();
            $table->string('encryption', 10)->default('tls'); // tls | ssl | none
            $table->string('username')->nullable();
            $table->text('password')->nullable(); // Crypt ile şifreli (encrypted cast)
            $table->string('from_name', 120)->nullable();
            $table->string('from_address')->nullable();
            $table->string('reply_to')->nullable();
            $table->unsignedSmallInteger('timeout')->default(30);

            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('mail_settings');
    }
};
