<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Orders modülü (Faz-3): sipariş/adisyon çekirdeği.
 *
 * - Faz-1 `orders` iskeleti GENİŞLETİLİR (kiracılık kolonlarına dokunulmaz).
 * - Para alanları kuruş-integer `*_minor` (ADR-007); tax_rate oran (DECIMAL).
 * - SATIŞ ANINDA SNAPSHOT (prompt §25): kalem, ürün adını / birim fiyatı /
 *   KDV oranını / seçenek fiyatlarını KOPYALAR — ürün sonradan değişse de
 *   eski adisyon değişmez. product_id/option_id yalnız referanstır (nullable,
 *   ürün silinse bile adisyon satırı yaşar).
 * - `orders.version`: optimistic locking; `order_idempotency_keys`: aynı
 *   isteğin iki kez gelmesi sipariş/kalem çoğaltmaz (prompt §12.4).
 * - `order_events`: durum geçiş + işlem günlüğü (ikram/indirim/iptal denetimi
 *   ayrıca audit_logs'a da düşer; §12.3).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->string('channel', 10)->default('table')->after('customer_id');
            $table->char('public_token', 26)->nullable()->unique()->after('channel'); // QR müşteri takibi

            // Eşzamanlılık (prompt §12.4)
            $table->unsignedInteger('version')->default(0)->after('status');

            // Tutar dökümü (kuruş — ADR-007). total_minor Faz-1'den.
            $table->unsignedBigInteger('items_total_minor')->default(0)->after('total_minor'); // kalem toplamı (indirim öncesi)
            $table->unsignedBigInteger('discount_minor')->default(0)->after('items_total_minor'); // adisyon indirimi
            $table->decimal('discount_percent', 5, 2)->nullable()->after('discount_minor');
            $table->string('discount_reason')->nullable()->after('discount_percent');
            $table->foreignId('discount_by_id')->nullable()->after('discount_reason')->constrained('users')->nullOnDelete();
            $table->foreignId('discount_approved_by_id')->nullable()->after('discount_by_id')->constrained('users')->nullOnDelete();
            $table->unsignedBigInteger('comp_total_minor')->default(0)->after('discount_approved_by_id'); // ikram edilen değer (bilgi)
            $table->unsignedBigInteger('vat_total_minor')->default(0)->after('comp_total_minor');
            $table->unsignedBigInteger('paid_minor')->default(0)->after('vat_total_minor');

            $table->unsignedSmallInteger('guest_count')->nullable()->after('paid_minor');
            $table->string('note', 500)->nullable()->after('guest_count');
            $table->string('customer_name', 120)->nullable()->after('note');   // paket/gel-al
            $table->string('customer_phone', 32)->nullable()->after('customer_name');

            $table->foreignId('opened_by_id')->nullable()->after('customer_phone')->constrained('users')->nullOnDelete();
            $table->timestamp('placed_at')->nullable()->after('opened_by_id');
            $table->timestamp('closed_at')->nullable()->after('placed_at');
            $table->timestamp('cancelled_at')->nullable()->after('closed_at');
            $table->string('cancel_reason')->nullable()->after('cancelled_at');
            $table->foreignId('cancelled_by_id')->nullable()->after('cancel_reason')->constrained('users')->nullOnDelete();

            $table->index(['tenant_id', 'table_id', 'status']);
            $table->index(['tenant_id', 'channel', 'status']);
        });

        // Faz-1 iskelet durumu 'open' → yeni makinedeki karşılığı 'placed'.
        DB::table('orders')->where('status', 'open')->update(['status' => 'placed']);

        Schema::create('order_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();

            // Referanslar (nullable — snapshot esastır, ürün silinse de satır yaşar)
            $table->foreignId('product_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('variant_id')->nullable()->constrained('product_variants')->nullOnDelete();

            $table->string('status', 20)->default('placed'); // OrderItemStatus
            $table->unsignedSmallInteger('qty');

            // ---- SATIŞ ANI SNAPSHOT'I (prompt §25) ----
            $table->string('name', 200);                       // ürün adı
            $table->string('variant_name', 100)->nullable();
            $table->unsignedBigInteger('unit_price_minor');    // birim fiyat (kanal fiyatı)
            $table->unsignedBigInteger('options_price_minor')->default(0); // birim başına seçenek toplamı
            $table->decimal('tax_rate', 5, 2)->default(0);     // KDV oranı (o anki)
            $table->string('station', 40)->nullable();         // hazırlama istasyonu (o anki)

            // İndirim / ikram (satır düzeyi)
            $table->unsignedBigInteger('discount_minor')->default(0);
            $table->string('discount_reason')->nullable();
            $table->boolean('is_comp')->default(false);
            $table->string('comp_reason')->nullable();
            $table->foreignId('comp_by_id')->nullable()->constrained('users')->nullOnDelete();

            // Türetilmiş satır toplamları (kuruş; tek yerde hesaplanır: OrderService)
            $table->unsignedBigInteger('line_total_minor')->default(0); // qty*(unit+options) - indirim; ikramda 0
            $table->unsignedBigInteger('vat_minor')->default(0);        // satır KDV payı (brütten)

            $table->string('note', 255)->nullable();
            $table->foreignId('added_by_id')->nullable()->constrained('users')->nullOnDelete();

            $table->timestamp('cancelled_at')->nullable();
            $table->string('cancel_reason')->nullable();
            $table->foreignId('cancelled_by_id')->nullable()->constrained('users')->nullOnDelete();

            $table->timestamps();

            $table->index(['tenant_id', 'order_id']);
            $table->index(['tenant_id', 'status']);
        });

        Schema::create('order_item_options', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('order_item_id')->constrained()->cascadeOnDelete();
            $table->foreignId('option_id')->nullable()->constrained()->nullOnDelete(); // referans

            // Snapshot (prompt §25)
            $table->string('group_name', 150);
            $table->string('option_name', 150);
            $table->unsignedBigInteger('price_minor')->default(0); // birim başına ek ücret (o anki)

            $table->timestamps();

            $table->index(['tenant_id', 'order_item_id']);
        });

        Schema::create('order_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('order_item_id')->nullable()->constrained('order_items')->cascadeOnDelete();

            $table->string('type', 40);               // status_changed, item_added, discount_applied, ...
            $table->string('from_status', 20)->nullable();
            $table->string('to_status', 20)->nullable();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->json('payload')->nullable();      // tutar/neden/yetkilendiren vb. (denetim §12.3)
            $table->timestamp('created_at')->useCurrent();

            $table->index(['tenant_id', 'order_id', 'id']);
        });

        // Aynı isteğin iki kez gelmesi sipariş/kalem ÇOĞALTMAZ (prompt §12.4):
        // UNIQUE(tenant_id, key) — ikinci istek ilkinin saklanmış yanıtını alır.
        Schema::create('order_idempotency_keys', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('key', 80);
            $table->string('endpoint', 60);
            $table->foreignId('order_id')->nullable()->constrained()->cascadeOnDelete();
            $table->json('response')->nullable();     // tamamlanan işlemin yanıtı (replay için)
            $table->unsignedSmallInteger('status_code')->nullable();
            $table->timestamps();

            $table->unique(['tenant_id', 'key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('order_idempotency_keys');
        Schema::dropIfExists('order_events');
        Schema::dropIfExists('order_item_options');
        Schema::dropIfExists('order_items');

        Schema::table('orders', function (Blueprint $table) {
            $table->dropIndex(['tenant_id', 'table_id', 'status']);
            $table->dropIndex(['tenant_id', 'channel', 'status']);

            foreach (['discount_by_id', 'discount_approved_by_id', 'opened_by_id', 'cancelled_by_id'] as $fk) {
                $table->dropConstrainedForeignId($fk);
            }

            $table->dropColumn([
                'channel', 'public_token', 'version',
                'items_total_minor', 'discount_minor', 'discount_percent', 'discount_reason',
                'comp_total_minor', 'vat_total_minor', 'paid_minor',
                'guest_count', 'note', 'customer_name', 'customer_phone',
                'placed_at', 'closed_at', 'cancelled_at', 'cancel_reason',
            ]);
        });
    }
};
