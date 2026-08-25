<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * A2 — Abonelik & Faturalama TEMELİ (SaaS gelir modeli — platform seviyesi).
 *
 * DİKKAT: Bu tablolar `payments` (POS/kasa tahsilatı, işletme içi ciro) ile
 * KARIŞTIRILMAMALI. Buradakiler BamBumPOS'un işletmelerden aldığı SaaS
 * abonelik ücretidir (kiracı-üstü/platform geliri).
 *
 * - `saas_plans`: satılabilir paket kataloğu (config/pricing_saas.php ile
 *   hizalı — bu migration varsayılan satırları da tohumlar).
 * - `saas_subscriptions`: işletme başına abonelik durumu. `plan_key`,
 *   `saas_plans.key`'e FK'lidir (referans bütünlüğü).
 * - `saas_invoices`: SaaS abonelik faturası (gerçek ödeme sağlayıcı
 *   entegrasyonu YOK — yalnız veri modeli; bkz. BillingService).
 *
 * Bu modeller kiracı-scoped DEĞİLDİR (Tenant modeliyle aynı mantık —
 * yönetimi yalnız platform/süper-admin tarafında yapılır, `tenant`
 * middleware'i olan panel rotalarına bağlanmaz).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('saas_plans', function (Blueprint $table) {
            $table->id();
            $table->string('key', 30)->unique();
            $table->string('name', 80);
            $table->unsignedBigInteger('price_minor')->default(0); // kuruş
            $table->string('currency', 3)->default('TRY');
            $table->string('interval', 10)->default('monthly'); // monthly | yearly
            $table->json('features')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('saas_subscriptions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('plan_key', 30);
            $table->string('status', 15)->default('trial'); // trial | active | past_due | cancelled
            $table->date('current_period_end')->nullable();
            $table->boolean('cancel_at_period_end')->default(false);
            $table->timestamps();

            $table->foreign('plan_key')->references('key')->on('saas_plans');
            $table->index(['tenant_id', 'status']);
            $table->index(['status', 'current_period_end']);
        });

        Schema::create('saas_invoices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('subscription_id')->nullable()->constrained('saas_subscriptions')->nullOnDelete();
            $table->string('number', 40)->unique();
            $table->unsignedBigInteger('amount_minor'); // kuruş
            $table->string('currency', 3)->default('TRY');
            $table->string('status', 10)->default('draft'); // draft | unpaid | paid | void
            $table->timestamp('issued_at')->nullable();
            $table->timestamp('due_at')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->json('meta')->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'status']);
            $table->index('due_at');
            $table->index('issued_at');
        });

        // Varsayılan paket kataloğunu tohumla (config/pricing_saas.php ile
        // hizalı). insertOrIgnore → migration tekrar çalışsa da (ör. taze bir
        // ortamda) hata vermez; mevcut satırları EZMEZ.
        $now = now();
        $plans = (array) config('pricing_saas.plans', []);
        $rows = [];
        foreach ($plans as $key => $p) {
            $rows[] = [
                'key' => $key,
                'name' => $p['name'] ?? $key,
                'price_minor' => (int) ($p['price_minor'] ?? 0),
                'currency' => $p['currency'] ?? 'TRY',
                'interval' => $p['interval'] ?? 'monthly',
                'features' => json_encode($p['features'] ?? [], JSON_UNESCAPED_UNICODE),
                'is_active' => (bool) ($p['is_active'] ?? true),
                'created_at' => $now,
                'updated_at' => $now,
            ];
        }
        if ($rows !== []) {
            DB::table('saas_plans')->insertOrIgnore($rows);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('saas_invoices');
        Schema::dropIfExists('saas_subscriptions');
        Schema::dropIfExists('saas_plans');
    }
};
