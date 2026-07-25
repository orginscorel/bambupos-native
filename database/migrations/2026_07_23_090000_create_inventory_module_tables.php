<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Inventory modülü (Faz 6 — §17): depo + stok kartı + değişmez hareket
 * defteri + reçete + sayım + satın alma.
 *
 * MİKTAR TEMSİLİ (para ADR-007'nin ikizi): tüm miktarlar ANA BİRİMİN
 * BİNDE BİRİ cinsinden TAMSAYI saklanır (`*_qty_milli`). 0.160 kg = 160.
 * Float sürüklenmesi olmaz; sqlite/mysql aynı davranır. Para kuruş-int.
 *
 * DEFTER KURALI (§17.4): inv_movements SATIRLARI ASLA GÜNCELLENMEZ /
 * SİLİNMEZ (model katmanı fırlatır). Anlık stok inv_stock_levels'ta
 * denormalize tutulur ama TEK doğruluk kaynağı defterdir; seviye her
 * hareketle aynı transaction içinde senkron güncellenir.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('inv_warehouses', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();
            $table->string('name', 120);
            $table->string('code', 40)->nullable();
            // main | branch | kitchen | bar | cold | consumable | custom
            $table->string('type', 20)->default('main');
            $table->boolean('is_default')->default(false);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->unique(['tenant_id', 'name']);
        });

        Schema::create('inv_categories', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 120);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();
            $table->unique(['tenant_id', 'name']);
        });

        Schema::create('inv_suppliers', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 160);
            $table->string('contact_name', 120)->nullable();
            $table->string('phone', 40)->nullable();
            $table->string('email', 160)->nullable();
            $table->string('tax_no', 40)->nullable();
            $table->string('address', 500)->nullable();
            $table->unsignedSmallInteger('payment_term_days')->default(0); // vade (gün)
            $table->string('note', 500)->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->unique(['tenant_id', 'name']);
        });

        Schema::create('inv_items', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('category_id')->nullable()->constrained('inv_categories')->nullOnDelete();
            $table->string('name', 160);
            $table->string('code', 60)->nullable();
            $table->string('barcode', 60)->nullable();
            $table->string('base_unit', 20)->default('adet');        // ana birim (kg, lt, adet…)
            $table->string('sub_unit', 20)->nullable();              // alt birim (g, ml…)
            $table->unsignedInteger('sub_unit_factor')->nullable();  // 1 ana = N alt (1 kg = 1000 g)
            $table->bigInteger('min_qty_milli')->default(0);
            $table->bigInteger('critical_qty_milli')->default(0);
            $table->bigInteger('max_qty_milli')->nullable();
            $table->unsignedBigInteger('avg_cost_minor')->default(0); // kuruş / ana birim (hareketli ortalama)
            $table->unsignedBigInteger('last_cost_minor')->nullable(); // son alış (kuruş / ana birim)
            $table->timestamp('last_purchase_at')->nullable();
            $table->foreignId('default_supplier_id')->nullable()->constrained('inv_suppliers')->nullOnDelete();
            $table->boolean('track_expiry')->default(false); // SKT takibi
            $table->boolean('track_lot')->default(false);    // lot takibi
            $table->string('shelf_location', 80)->nullable(); // depo konumu / raf
            $table->decimal('tax_rate', 5, 2)->default(0);
            $table->boolean('is_semi_finished')->default(false); // yarı mamul (kendi reçetesi olabilir)
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->unique(['tenant_id', 'name']);
            $table->index(['tenant_id', 'barcode']);
        });

        Schema::create('inv_stock_levels', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('warehouse_id')->constrained('inv_warehouses')->cascadeOnDelete();
            $table->foreignId('item_id')->constrained('inv_items')->cascadeOnDelete();
            $table->bigInteger('qty_milli')->default(0);
            $table->timestamps();
            $table->unique(['warehouse_id', 'item_id']);
            $table->index(['tenant_id', 'item_id']);
        });

        // DEĞİŞMEZ HAREKET DEFTERİ. qty_milli İMZALIDIR: + giriş, - çıkış.
        Schema::create('inv_movements', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable();
            $table->foreignId('warehouse_id')->constrained('inv_warehouses');
            $table->foreignId('item_id')->constrained('inv_items');
            // purchase | sale | purchase_return | waste | loss | count_adjust |
            // transfer_out | transfer_in | production | recipe_consumption |
            // manual_adjust | comp_consumption
            $table->string('type', 30);
            $table->bigInteger('qty_milli');                       // imzalı miktar (ana birim ×1000)
            $table->string('unit_label', 20);                      // hareket anındaki ana birim adı
            $table->unsignedBigInteger('unit_cost_minor')->nullable();  // kuruş / ana birim
            $table->unsignedBigInteger('total_cost_minor')->nullable(); // kuruş (|qty| × birim maliyet)
            $table->string('lot_no', 60)->nullable();
            $table->date('expires_at')->nullable();                // SKT
            $table->string('ref_type', 40)->nullable();            // order_item | purchase_order | count | production | movement_request
            $table->unsignedBigInteger('ref_id')->nullable();
            $table->unsignedBigInteger('counterpart_id')->nullable(); // transfer çifti
            $table->string('description', 500)->nullable();
            $table->foreignId('user_id')->nullable();
            $table->foreignId('approved_by_id')->nullable();
            $table->timestamp('approved_at')->nullable();
            $table->timestamp('occurred_at');
            $table->timestamps();
            $table->index(['tenant_id', 'item_id', 'occurred_at']);
            $table->index(['warehouse_id', 'item_id']);
            $table->index(['ref_type', 'ref_id']);
            $table->index(['tenant_id', 'type']);
        });

        // Manuel hareket İSTEK kuyruğu: onaylanınca gerçek deftere yazılır.
        // Defter böylece saf-değişmez kalır (bekleyen kayıt defterde durmaz).
        Schema::create('inv_movement_requests', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('warehouse_id')->constrained('inv_warehouses');
            $table->foreignId('item_id')->constrained('inv_items');
            $table->string('type', 30);
            $table->bigInteger('qty_milli');
            $table->unsignedBigInteger('unit_cost_minor')->nullable();
            $table->string('lot_no', 60)->nullable();
            $table->date('expires_at')->nullable();
            $table->string('description', 500)->nullable();
            $table->string('status', 20)->default('pending'); // pending | approved | rejected
            $table->foreignId('requested_by_id')->nullable();
            $table->foreignId('decided_by_id')->nullable();
            $table->timestamp('decided_at')->nullable();
            $table->unsignedBigInteger('movement_id')->nullable(); // onayla oluşan defter satırı
            $table->timestamps();
            $table->index(['tenant_id', 'status']);
        });

        // Reçete başlığı: ürün(+varyant) YA DA yarı mamul stok kalemi için.
        // Versiyonlama: değişiklik = YENİ satır (version+1), eski is_active=false.
        Schema::create('inv_recipes', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->nullable()->constrained('products')->cascadeOnDelete();
            $table->foreignId('variant_id')->nullable()->constrained('product_variants')->cascadeOnDelete();
            $table->foreignId('item_id')->nullable()->constrained('inv_items')->cascadeOnDelete(); // yarı mamul hedefi
            $table->foreignId('branch_id')->nullable()->constrained()->cascadeOnDelete(); // şube özel reçete
            $table->unsignedInteger('version')->default(1);
            $table->bigInteger('yield_qty_milli')->default(1000); // üretim verimi (yarı mamul; 1 porsiyon=1000)
            $table->decimal('waste_percent', 5, 2)->default(0);   // reçete geneli fire
            $table->boolean('is_active')->default(true);
            $table->string('note', 500)->nullable();
            $table->foreignId('created_by_id')->nullable();
            $table->timestamps();
            $table->index(['tenant_id', 'product_id', 'variant_id', 'branch_id', 'is_active'], 'inv_recipes_lookup');
            $table->index(['tenant_id', 'item_id', 'is_active']);
        });

        Schema::create('inv_recipe_lines', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('recipe_id')->constrained('inv_recipes')->cascadeOnDelete();
            $table->foreignId('item_id')->constrained('inv_items'); // ham madde YA DA yarı mamul
            $table->bigInteger('qty_milli');                        // 1 porsiyon/verim başına, ana birim ×1000
            $table->string('unit_entry', 10)->default('base');      // giriş birimi: base | sub (görüntü)
            $table->decimal('waste_percent', 5, 2)->default(0);     // satır bazlı fire
            $table->foreignId('warehouse_id')->nullable()->constrained('inv_warehouses')->nullOnDelete();
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();
        });

        Schema::create('inv_counts', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable();
            $table->foreignId('warehouse_id')->constrained('inv_warehouses');
            $table->string('status', 20)->default('draft'); // draft | submitted | approved | cancelled
            $table->boolean('is_blind')->default(true);     // kör sayım: beklenen, gönderilene dek gizli
            $table->string('note', 500)->nullable();
            $table->foreignId('created_by_id')->nullable();
            $table->timestamp('submitted_at')->nullable();
            $table->foreignId('approved_by_id')->nullable();
            $table->timestamp('approved_at')->nullable();
            $table->timestamps();
            $table->index(['tenant_id', 'status']);
        });

        Schema::create('inv_count_lines', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('count_id')->constrained('inv_counts')->cascadeOnDelete();
            $table->foreignId('item_id')->constrained('inv_items')->cascadeOnDelete();
            $table->bigInteger('counted_qty_milli')->nullable();
            $table->bigInteger('expected_qty_milli')->nullable(); // gönderim ANINDA snapshot
            $table->bigInteger('diff_qty_milli')->nullable();     // sayılan - beklenen
            $table->timestamps();
            $table->unique(['count_id', 'item_id']);
        });

        Schema::create('inv_purchase_orders', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable();
            $table->foreignId('supplier_id')->constrained('inv_suppliers');
            $table->foreignId('warehouse_id')->nullable()->constrained('inv_warehouses')->nullOnDelete();
            // draft(talep) | quoted(teklif) | ordered(sipariş) | partially_received | received | cancelled
            $table->string('status', 30)->default('draft');
            $table->string('invoice_no', 60)->nullable();
            $table->unsignedBigInteger('invoice_total_minor')->nullable();
            $table->timestamp('invoiced_at')->nullable();
            $table->string('payment_status', 20)->default('unpaid'); // unpaid | partial | paid
            $table->unsignedBigInteger('paid_minor')->default(0);
            $table->date('due_date')->nullable();   // vade
            $table->date('expected_at')->nullable();
            $table->string('note', 500)->nullable();
            $table->foreignId('created_by_id')->nullable();
            $table->timestamp('ordered_at')->nullable();
            $table->timestamps();
            $table->index(['tenant_id', 'status']);
        });

        Schema::create('inv_purchase_lines', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('purchase_order_id')->constrained('inv_purchase_orders')->cascadeOnDelete();
            $table->foreignId('item_id')->constrained('inv_items');
            $table->bigInteger('qty_milli');                    // sipariş edilen
            $table->bigInteger('received_qty_milli')->default(0);
            $table->bigInteger('returned_qty_milli')->default(0);
            $table->unsignedBigInteger('unit_price_minor');     // kuruş / ana birim
            $table->decimal('tax_rate', 5, 2)->default(0);
            $table->timestamps();
        });

        // Tedarikçi fiyat geçmişi (mal kabulünde otomatik yazılır).
        Schema::create('inv_supplier_prices', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('supplier_id')->constrained('inv_suppliers')->cascadeOnDelete();
            $table->foreignId('item_id')->constrained('inv_items')->cascadeOnDelete();
            $table->unsignedBigInteger('unit_price_minor');
            $table->timestamp('recorded_at');
            $table->timestamps();
            $table->index(['tenant_id', 'item_id', 'supplier_id']);
        });
    }

    public function down(): void
    {
        foreach ([
            'inv_supplier_prices', 'inv_purchase_lines', 'inv_purchase_orders',
            'inv_count_lines', 'inv_counts', 'inv_recipe_lines', 'inv_recipes',
            'inv_movement_requests', 'inv_movements', 'inv_stock_levels',
            'inv_items', 'inv_suppliers', 'inv_categories', 'inv_warehouses',
        ] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
