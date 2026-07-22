<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Faz-2 (Venue): masa iskeletini genişletir; Faz-1 kiracılık omurgası
 * (tenant_id/branch_id/qr_token kolonları ve indeksleri) DEĞİŞMEZ.
 *
 * - tables: masa no (şube içinde tekil), alan, kapasite, şekil, durum,
 *   birleştirilebilirlik + QR rotasyon izi (önceki token → 410, ADR-008).
 * - branches: alansız "genel menü" QR'ı için şube token'ı (aynı ADR-008
 *   kuralları: opak, tekil, rotasyonla anında geçersiz).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tables', function (Blueprint $table) {
            $table->unsignedInteger('number')->nullable()->after('name');
            $table->foreignId('area_id')->nullable()->after('branch_id')
                ->constrained('venue_areas')->nullOnDelete();
            $table->unsignedTinyInteger('capacity')->default(4)->after('number');
            $table->string('shape', 20)->default('square')->after('capacity');
            $table->string('status', 30)->default('available')->after('shape');
            $table->boolean('is_joinable')->default(true)->after('status');
            $table->string('notes', 255)->nullable()->after('is_joinable');
            $table->char('previous_qr_token', 26)->nullable()->after('qr_token');
            $table->timestamp('qr_rotated_at')->nullable()->after('previous_qr_token');

            $table->unique(['tenant_id', 'branch_id', 'number']);
            $table->index(['tenant_id', 'branch_id', 'status']);
            $table->index('previous_qr_token');
        });

        Schema::table('branches', function (Blueprint $table) {
            $table->char('qr_token', 26)->nullable()->unique()->after('timezone');
            $table->char('previous_qr_token', 26)->nullable()->after('qr_token');

            $table->index('previous_qr_token');
        });
    }

    public function down(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->dropIndex(['previous_qr_token']);
            $table->dropUnique(['qr_token']);
            $table->dropColumn(['qr_token', 'previous_qr_token']);
        });

        Schema::table('tables', function (Blueprint $table) {
            $table->dropIndex(['previous_qr_token']);
            $table->dropIndex(['tenant_id', 'branch_id', 'status']);
            $table->dropUnique(['tenant_id', 'branch_id', 'number']);
            $table->dropConstrainedForeignId('area_id');
            $table->dropColumn([
                'number', 'capacity', 'shape', 'status',
                'is_joinable', 'notes', 'previous_qr_token', 'qr_rotated_at',
            ]);
        });
    }
};
