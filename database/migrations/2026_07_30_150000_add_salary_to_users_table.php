<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Maaş/Bordro (§Vardiya): personele maaş tanımı.
 *  - salary_type: 'monthly' (aylık sabit) | 'hourly' (saatlik ücret) | null (tanımsız)
 *  - salary_amount_minor: aylıkta AYLIK brüt tutar; saatlikte SAAT BAŞI ücret (kuruş)
 * Saatlik kazanç time_entries.worked_min üzerinden hesaplanır (kayıt tutulmaz;
 * ekranda anlık türetilir). Aylık sabitte tutar dönemden bağımsız sabittir.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->string('salary_type', 16)->nullable()->after('position');
            $table->unsignedBigInteger('salary_amount_minor')->nullable()->after('salary_type');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn(['salary_type', 'salary_amount_minor']);
        });
    }
};
