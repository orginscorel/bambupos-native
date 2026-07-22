<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // Kiracılık
            $table->unsignedBigInteger('tenant_id')->nullable()->after('id');
            $table->unsignedBigInteger('branch_id')->nullable()->after('tenant_id');

            // Kimlik / özlük
            $table->string('first_name', 100)->nullable()->after('name');
            $table->string('last_name', 100)->nullable()->after('first_name');
            $table->string('phone', 32)->nullable()->after('email');
            $table->string('staff_code', 32)->nullable()->after('phone');
            $table->string('department', 100)->nullable()->after('staff_code');
            $table->string('position', 100)->nullable()->after('department');
            $table->date('hired_at')->nullable()->after('position');
            $table->boolean('is_active')->default(true)->after('hired_at');

            // Tercihler
            $table->string('locale', 10)->default('tr')->after('is_active');
            $table->string('theme', 20)->default('system')->after('locale');

            // Oturum izleri
            $table->timestamp('last_login_at')->nullable()->after('theme');
            $table->string('last_login_ip', 45)->nullable()->after('last_login_at');

            // Hızlı PIN girişi (bcrypt; en az 6 hane — 4 hane YASAK)
            $table->string('pin_hash')->nullable()->after('password');
            $table->unsignedTinyInteger('failed_pin_attempts')->default(0)->after('pin_hash');
            $table->timestamp('pin_locked_until')->nullable()->after('failed_pin_attempts');

            // İki faktörlü doğrulama (hazır yapı — v1'de zorunlu değil)
            $table->text('two_factor_secret')->nullable()->after('pin_locked_until');
            $table->text('two_factor_recovery_codes')->nullable()->after('two_factor_secret');
            $table->timestamp('two_factor_confirmed_at')->nullable()->after('two_factor_recovery_codes');
        });

        Schema::table('users', function (Blueprint $table) {
            // Tek-işletme varsayımı kırılır: e-posta kiracı içinde benzersiz (ADR-004)
            $table->dropUnique('users_email_unique');
            $table->unique(['tenant_id', 'email']);
            $table->unique(['tenant_id', 'staff_code']);
            $table->index(['tenant_id', 'branch_id']);
            $table->index(['tenant_id', 'is_active']);
            $table->index('email'); // login sorgusu (kiracı-öncesi) için
        });

        if (Schema::getConnection()->getDriverName() === 'mysql') {
            Schema::table('users', function (Blueprint $table) {
                $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
                $table->foreign('branch_id')->references('id')->on('branches')->nullOnDelete();
            });
        }
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (Schema::getConnection()->getDriverName() === 'mysql') {
                $table->dropForeign(['tenant_id']);
                $table->dropForeign(['branch_id']);
            }

            $table->dropUnique(['tenant_id', 'email']);
            $table->dropUnique(['tenant_id', 'staff_code']);
            $table->dropIndex(['tenant_id', 'branch_id']);
            $table->dropIndex(['tenant_id', 'is_active']);
            $table->dropIndex(['email']);
            $table->unique('email');

            $table->dropColumn([
                'tenant_id', 'branch_id', 'first_name', 'last_name', 'phone', 'staff_code',
                'department', 'position', 'hired_at', 'is_active', 'locale', 'theme',
                'last_login_at', 'last_login_ip', 'pin_hash', 'failed_pin_attempts',
                'pin_locked_until', 'two_factor_secret', 'two_factor_recovery_codes',
                'two_factor_confirmed_at',
            ]);
        });
    }
};
