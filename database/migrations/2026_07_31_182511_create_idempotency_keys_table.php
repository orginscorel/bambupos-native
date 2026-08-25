<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/*
|--------------------------------------------------------------------------
| idempotency_keys — Offline-first operasyon kuyruğu, sunucu temeli (B)
|--------------------------------------------------------------------------
| App\Support\Idempotency\IdempotentRequest tarafından kullanılır.
|
| `order_idempotency_keys`'ten (Idempotency-Key HEADER, tek ağ isteği
| tekrarını çözer) BİLİNÇLİ olarak AYRI ve modül-bağımsız bir tablo:
| offline istemci `op_id`'yi işlemi KUYRUĞA eklerken üretir (ağ isteğinden
| önce var olur), gün(ler) sonra geç senkron olsa da AYNI kalır. Yalnız
| Orders modülüne özgü değildir — ileride payments/diğer mutasyonlar da
| aynı tabloyu `scope` ile ayrışarak kullanabilir (bkz. docs/offline-sync-
| protocol.md).
|
| (tenant_id, op_id) UNIQUE: aynı kiracıda aynı op_id İKİ KEZ işlenemez.
| request_hash: aynı op_id FARKLI gövdeyle tekrar gelirse (istemci hatası/
| çakışma) sessizce yutulmaz — 409 döner (bkz. IdempotentRequest::replay).
*/
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('idempotency_keys', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('op_id');
            $table->string('scope', 60);
            $table->string('request_hash', 64); // sha256(hex)
            $table->json('response_snapshot')->nullable(); // ilk yanıtın özeti (status+body) — replay için
            $table->string('status', 20)->default('processing'); // processing | completed
            $table->timestamp('created_at')->useCurrent();

            $table->unique(['tenant_id', 'op_id']);
            $table->index(['tenant_id', 'scope']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('idempotency_keys');
    }
};
