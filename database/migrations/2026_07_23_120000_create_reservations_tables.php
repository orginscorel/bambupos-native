<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Faz-9 (Reservations): rezervasyon + bekleme listesi.
 *
 * - reservations: müşteri bilgisi, tarih/saat (reserved_at), süre + tampon,
 *   bölüm tercihi, hassas alerji notu, kapora (kuruş-integer), kaynak,
 *   durum makinesi + onay/hatırlatma izleri, public onay/iptal token'ı.
 * - reservation_tables: masa ataması (birleştirme = birden çok satır).
 * - waitlist_entries: bekleme listesi + tahmini süre + sonuç izi.
 *
 * Masa durumuna bağ: onaylı rezervasyon masayı 'reserved' yapar; saat
 * geçince 'reservation_late'. Venue'nun sipariş-türevli durum senkronu
 * (TableStatusSynchronizer) bu iki durumu zaten EZMEZ; tersine bu modül de
 * aktif adisyonlu masaların durumuna dokunmaz (ReservationTableSync).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('reservations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();

            // Müşteri (rezervasyon kendi iletişim bilgisini taşır; CRM'e bağımlı değil)
            $table->string('customer_name', 120);
            $table->string('customer_phone', 30)->nullable();
            $table->string('customer_email', 190)->nullable();

            // Zaman: tek kolon (tarih+saat) + süre + temizlik/hazırlık tamponu
            $table->dateTime('reserved_at');
            $table->unsignedSmallInteger('duration_minutes')->default(120);
            $table->unsignedSmallInteger('buffer_minutes')->default(15);

            $table->unsignedSmallInteger('party_size');

            // Tercihler / notlar
            $table->foreignId('area_id')->nullable()
                ->constrained('venue_areas')->nullOnDelete(); // bölüm tercihi
            $table->string('special_note', 500)->nullable();
            $table->text('allergy_note')->nullable();          // HASSAS: yalnız reservations.view_sensitive
            $table->string('occasion', 30)->nullable();        // birthday/anniversary/business/other
            $table->string('occasion_note', 255)->nullable();

            // Kapora (kuruş-integer, ADR)
            $table->unsignedBigInteger('deposit_minor')->default(0);
            $table->string('deposit_status', 20)->default('none'); // none|pending|paid|refunded|forfeited

            // Kaynak + alan personel
            $table->string('source', 20)->default('panel');    // qr|panel|phone
            $table->foreignId('created_by')->nullable()
                ->constrained('users')->nullOnDelete();

            // Durum makinesi + izler
            $table->string('status', 30)->default('requested');
            $table->string('cancel_reason', 255)->nullable();
            $table->timestamp('confirmed_at')->nullable();
            $table->timestamp('arrived_at')->nullable();
            $table->timestamp('seated_at')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamp('cancelled_at')->nullable();

            // Public onay/iptal bağlantısı (e-postadaki link) — opak token
            $table->char('confirmation_token', 40)->unique();

            // Hatırlatma altyapısı
            $table->string('reminder_status', 20)->default('pending'); // pending|sent|failed|skipped
            $table->timestamp('reminder_sent_at')->nullable();

            $table->timestamps();

            $table->index(['tenant_id', 'branch_id', 'reserved_at']);
            $table->index(['tenant_id', 'status']);
            $table->index(['tenant_id', 'customer_phone']);
        });

        Schema::create('reservation_tables', function (Blueprint $table) {
            $table->id();
            $table->foreignId('reservation_id')->constrained()->cascadeOnDelete();
            $table->foreignId('table_id')->constrained('tables')->cascadeOnDelete();

            $table->unique(['reservation_id', 'table_id']);
            $table->index('table_id');
        });

        Schema::create('waitlist_entries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();

            $table->string('customer_name', 120);
            $table->string('customer_phone', 30)->nullable();
            $table->unsignedSmallInteger('party_size');
            $table->string('note', 255)->nullable();

            $table->string('status', 20)->default('waiting'); // waiting|notified|seated|cancelled|expired
            $table->unsignedSmallInteger('quoted_wait_minutes')->nullable(); // personelin verdiği tahmin
            $table->string('source', 20)->default('panel');

            // Masaya alınırsa hangi rezervasyon kaydına dönüştü (opsiyonel iz)
            $table->foreignId('reservation_id')->nullable()
                ->constrained('reservations')->nullOnDelete();

            $table->timestamp('notified_at')->nullable(); // "müşteri çağrıldı" bildirimi
            $table->timestamp('seated_at')->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'branch_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('waitlist_entries');
        Schema::dropIfExists('reservation_tables');
        Schema::dropIfExists('reservations');
    }
};
