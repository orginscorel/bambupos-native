<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * SaaS süper-admin alanları:
 *  - users.is_super_admin: kiracı-üstü ürün yöneticisi (BamBumPOS operatörü).
 *  - tenants: plan + deneme/abonelik tarihleri (satış tarafı yönetimi).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->boolean('is_super_admin')->default(false)->after('is_active');
        });

        Schema::table('tenants', function (Blueprint $table): void {
            $table->string('plan', 30)->nullable()->after('status');       // trial | basic | pro | enterprise
            $table->date('trial_ends_at')->nullable()->after('plan');
            $table->date('subscribed_until')->nullable()->after('trial_ends_at');
            $table->string('billing_note', 255)->nullable()->after('subscribed_until');
        });
    }

    public function down(): void
    {
        Schema::table('users', fn (Blueprint $t) => $t->dropColumn('is_super_admin'));
        Schema::table('tenants', fn (Blueprint $t) => $t->dropColumn(['plan', 'trial_ends_at', 'subscribed_until', 'billing_note']));
    }
};
