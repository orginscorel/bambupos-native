<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Shifts modülü (Faz-7): vardiya planlama + mesai takibi.
 *
 * - Tüm tablolar kiracılı (tenant_id, ADR-004; BelongsToTenant).
 * - Süreler DAKİKA-integer tutulur (para alanlarındaki kuruş-integer
 *   yaklaşımının zaman karşılığı; kayan nokta yok).
 * - KVKK (prompt §7): konum kolonları VARSAYILAN BOŞtur; yalnız işletme
 *   ayarı AÇIK + personelin AÇIK RIZASI (shift_location_consents) varsa
 *   yazılır. Konum takibi hiçbir akışta zorunlu değildir.
 * - NFC/QR uyumu: giriş yöntemi serbest metin enum'dur (pin|device|manual|
 *   qr|nfc) — v1'de pin/device/manual kullanılır, kolon genişletme gerekmez.
 */
return new class extends Migration
{
    public function up(): void
    {
        // İşletme başına mesai ayarları (tek satır / kiracı).
        Schema::create('shift_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->unique()->constrained()->cascadeOnDelete();

            $table->unsignedSmallInteger('standard_daily_min')->default(540);   // vardiyasız günde fazla mesai eşiği (9 saat)
            $table->unsignedSmallInteger('late_tolerance_min')->default(5);     // geç kalma toleransı
            $table->unsignedSmallInteger('early_leave_tolerance_min')->default(5);
            $table->unsignedSmallInteger('default_break_min')->default(30);     // yeni vardiyada önerilen mola

            // KVKK: konum takibi VARSAYILAN KAPALI; açılırsa politika metni zorunlu.
            $table->boolean('location_tracking_enabled')->default(false);
            $table->text('location_policy')->nullable();

            $table->timestamps();
        });

        // Yetkili giriş/çıkış cihazları (tablet/kiosk). Token SHA-256 hash'iyle
        // saklanır; düz metin yalnız oluşturma anında bir kez gösterilir.
        Schema::create('clock_devices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();
            $table->string('name', 100);
            $table->char('token_hash', 64)->unique();
            $table->boolean('is_active')->default(true);
            $table->timestamp('last_seen_at')->nullable();
            $table->foreignId('created_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['tenant_id', 'is_active']);
        });

        // Planlanan vardiyalar. Tekrarlayan vardiyalar tek tek satır olarak
        // üretilir ve repeat_group (uuid) ile bağlanır — cron/kural motoru yok.
        Schema::create('shifts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('position', 80)->nullable();        // pozisyon bazlı planlama (garson, mutfak…)
            $table->dateTime('starts_at');
            $table->dateTime('ends_at');
            $table->unsignedSmallInteger('break_min')->default(0); // planlanan (ücretsiz) mola
            $table->string('note', 255)->nullable();
            $table->char('repeat_group', 36)->nullable()->index(); // tekrarlayan seri kimliği
            $table->foreignId('created_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['tenant_id', 'branch_id', 'starts_at']);
            $table->index(['tenant_id', 'user_id', 'starts_at']);
        });

        // Vardiya değişim talepleri (personel açar, yönetici karar verir).
        Schema::create('shift_swap_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('shift_id')->constrained()->cascadeOnDelete();
            $table->foreignId('requested_by_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('target_user_id')->nullable()->constrained('users')->nullOnDelete(); // devralması istenen kişi
            $table->string('reason', 255)->nullable();
            $table->string('status', 20)->default('pending'); // pending|approved|rejected|cancelled
            $table->foreignId('decided_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('decided_at')->nullable();
            $table->string('decision_note', 255)->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'status']);
        });

        // Mesai kayıtları (giriş/çıkış). Hesaplanan alanlar TimeClockService
        // tarafından TEK yerden yazılır; dakika-integer.
        Schema::create('time_entries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('shift_id')->nullable()->constrained()->nullOnDelete(); // plansız giriş olabilir

            $table->dateTime('clock_in_at');
            $table->dateTime('clock_out_at')->nullable();

            // Kimlik/iz bilgisi: yöntem (pin|device|manual|qr|nfc), cihaz, IP.
            $table->string('method_in', 10)->default('pin');
            $table->string('method_out', 10)->nullable();
            $table->foreignId('device_id')->nullable()->constrained('clock_devices')->nullOnDelete();
            $table->string('ip_in', 45)->nullable();
            $table->string('ip_out', 45)->nullable();

            // KVKK: yalnız işletme ayarı AÇIK + personel rızası varsa dolar.
            $table->decimal('lat_in', 10, 7)->nullable();
            $table->decimal('lng_in', 10, 7)->nullable();
            $table->decimal('lat_out', 10, 7)->nullable();
            $table->decimal('lng_out', 10, 7)->nullable();

            // Hesap sonuçları (dakika)
            $table->unsignedInteger('break_total_min')->default(0);
            $table->unsignedInteger('worked_min')->nullable();     // çıkışta hesaplanır
            $table->unsignedInteger('planned_min')->nullable();    // vardiyadan (mola düşülmüş)
            $table->unsignedInteger('overtime_min')->default(0);
            $table->unsignedInteger('missing_min')->default(0);    // eksik çalışma
            $table->unsignedInteger('late_min')->default(0);
            $table->unsignedInteger('early_leave_min')->default(0);

            $table->string('status', 20)->default('open');         // open|closed

            // Onay + manuel düzeltme izi (düzeltme ayrıca audit_logs'a düşer)
            $table->timestamp('approved_at')->nullable();
            $table->foreignId('approved_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('edited_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('edited_at')->nullable();
            $table->string('edit_reason', 255)->nullable();

            $table->timestamps();

            $table->index(['tenant_id', 'user_id', 'clock_in_at']);
            $table->index(['tenant_id', 'status']);
        });

        // Mola başlangıç/bitiş çiftleri.
        Schema::create('time_entry_breaks', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('time_entry_id')->constrained()->cascadeOnDelete();
            $table->dateTime('started_at');
            $table->dateTime('ended_at')->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'time_entry_id']);
        });

        // İzin / rapor / tatil / devamsızlık kayıtları.
        // Devamsızlık ('absence') yönetici tarafından kayıt olarak açılır.
        Schema::create('leave_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('type', 20); // annual|sick|unpaid|holiday|absence|other
            $table->date('starts_on');
            $table->date('ends_on');
            $table->string('reason', 255)->nullable();
            $table->string('status', 20)->default('pending'); // pending|approved|rejected|cancelled
            $table->foreignId('decided_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('decided_at')->nullable();
            $table->string('decision_note', 255)->nullable();
            $table->foreignId('created_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['tenant_id', 'user_id', 'starts_on']);
            $table->index(['tenant_id', 'status']);
        });

        // Minimum personel kuralları (şube + haftanın günü + pozisyon).
        Schema::create('shift_staffing_rules', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->unsignedTinyInteger('weekday')->nullable(); // 0=Pzt … 6=Paz; null=her gün
            $table->string('position', 80)->nullable();         // null = toplam personel
            $table->unsignedSmallInteger('min_count');
            $table->timestamps();

            $table->index(['tenant_id', 'branch_id']);
        });

        // KVKK açık rıza kaydı (konum). Rıza personelin KENDİ işlemidir;
        // geri çekilebilir (revoked_at).
        Schema::create('shift_location_consents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->timestamp('consented_at');
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('shift_location_consents');
        Schema::dropIfExists('shift_staffing_rules');
        Schema::dropIfExists('leave_requests');
        Schema::dropIfExists('time_entry_breaks');
        Schema::dropIfExists('time_entries');
        Schema::dropIfExists('shift_swap_requests');
        Schema::dropIfExists('shifts');
        Schema::dropIfExists('clock_devices');
        Schema::dropIfExists('shift_settings');
    }
};
