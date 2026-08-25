<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * BamBumPOS pazarlama sitesi "Demo İste" talepleri (SaaS lead).
 * Süper-admin panelinden görüntülenir/işlenir. Tenant'sız (satış öncesi).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('demo_requests', function (Blueprint $table): void {
            $table->id();
            $table->string('name', 120);
            $table->string('business', 160)->nullable();
            $table->string('phone', 40);
            $table->string('email', 160)->nullable();
            $table->string('sector', 60)->nullable();     // kafe/restoran/nargile/bar...
            $table->text('message')->nullable();
            $table->string('status', 20)->default('new'); // new | contacted | won | lost
            $table->string('source', 40)->default('landing');
            $table->string('ip', 45)->nullable();
            $table->string('user_agent', 255)->nullable();
            $table->timestamp('handled_at')->nullable();
            $table->timestamps();
            $table->index('status');
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('demo_requests');
    }
};
