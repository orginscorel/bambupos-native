<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Personel Portalı — GÖREV (staff_tasks) tablosu.
 *
 * Yönetici bir personele görev atar (tasks.assign); personel kendi
 * "Görevlerim" ekranından durumunu ilerletir (open → in_progress → done).
 * Çok kiracılı (tenant_id) + şube kapsamlı (branch_id, nullable = şubesiz).
 * Görev atanınca ilgili personele TaskAssigned bildirimi gider.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff_tasks', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()
                ->constrained()->nullOnDelete();

            // Görevi ÜSTLENEN personel
            $table->foreignId('assigned_to_id')->constrained('users')->cascadeOnDelete();

            $table->string('title', 160);
            $table->text('description')->nullable();

            $table->string('priority', 10)->default('normal'); // low|normal|high
            $table->string('status', 12)->default('open');     // open|in_progress|done

            $table->dateTime('due_at')->nullable();

            // Görevi ATAYAN yönetici (silinirse iz kalır → nullOnDelete)
            $table->foreignId('created_by_id')->nullable()
                ->constrained('users')->nullOnDelete();

            $table->timestamp('completed_at')->nullable();

            $table->timestamps();

            $table->index(['tenant_id', 'assigned_to_id', 'status']);
            $table->index(['tenant_id', 'branch_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_tasks');
    }
};
