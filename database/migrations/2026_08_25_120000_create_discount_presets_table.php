<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * HAZIR İNDİRİM TANIMLARI.
 *
 * İndirim şimdiye kadar her seferinde elle giriliyordu (tür + değer + gerekçe).
 * "Şehit/gazi yakını", "kamu personeli", "öğrenci" gibi TEKRAR EDEN indirimlerde
 * bu hem yavaş hem hataya açıktı (yanlış oran, tutarsız gerekçe metni, raporda
 * gruplanamayan serbest metin). Tanımlar burada bir kez yapılır; kasa ve sepet
 * tek dokunuşla uygular, gerekçe tanımın adından gelir → rapor gruplanabilir.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('discount_presets', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 80);
            // percent → value_percent (ör. 20.00), amount → value_minor (kuruş)
            $table->string('type', 10)->default('percent');
            $table->decimal('value_percent', 5, 2)->nullable();
            $table->unsignedInteger('value_minor')->nullable();
            $table->string('note', 255)->nullable();
            // Tanım YÖNETİCİ tarafından yapılır → onay zaten verilmiştir; bu yüzden
            // "%10 üzeri indirim PIN ister" eşiği hazır tanımlarda VARSAYILAN OLARAK
            // atlanır. Yine de PIN istenmesi gereken tanımlar için açılabilir.
            $table->boolean('requires_approval')->default(false);
            $table->boolean('is_active')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();

            $table->unique(['tenant_id', 'name']);
            $table->index(['tenant_id', 'is_active', 'sort_order']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('discount_presets');
    }
};
