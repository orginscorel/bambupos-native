<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Katalog domaini (Faz 2): kategori, ürün alanları, varyant, seçenek grubu,
 * alerjen sözlüğü, ürün görselleri, menü planlama.
 *
 * Kurallar:
 *  - Kiracı verisi tablolarında tenant_id NOT NULL + bileşik indeksler (ADR-004).
 *  - Para alanları kuruş-integer `*_minor` (ADR-007); KDV oranı DECIMAL(5,2) (oran, para değil).
 *  - `allergens` KÜRESEL sözlük + kiracı-özel satır (tenant_id NULL = küresel) — DATA_MIGRATION_PLAN §4.6.
 *  - Faz-1'in kurduğu products kiracılık kolonlarına DOKUNULMAZ, yalnız alan eklenir.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('categories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('parent_id')->nullable()->constrained('categories')->nullOnDelete();
            $table->string('name', 150);
            $table->string('slug', 180);
            $table->string('description', 500)->nullable();
            $table->string('icon', 60)->nullable();
            $table->string('color', 20)->nullable();
            $table->string('image_path')->nullable();
            $table->time('available_from')->nullable(); // şube yerel saati
            $table->time('available_until')->nullable();
            $table->unsignedInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['tenant_id', 'slug']);
            $table->index(['tenant_id', 'parent_id', 'sort_order']);
            $table->index(['tenant_id', 'is_active']);
        });

        Schema::table('products', function (Blueprint $table) {
            $table->foreignId('category_id')->nullable()->after('branch_id')
                ->constrained('categories')->nullOnDelete();
            $table->string('barcode', 64)->nullable()->after('sku');
            $table->text('description')->nullable()->after('name');

            // KDV oranı (%): para değil oran — DECIMAL kalır (ADR-007 istisnası)
            $table->decimal('tax_rate', 5, 2)->default(10.00)->after('currency');

            // Fiyat seti (kuruş; NULL = satış fiyatı geçerli) — price_minor = satış
            $table->unsignedBigInteger('cost_minor')->nullable()->after('price_minor');
            $table->unsignedBigInteger('package_price_minor')->nullable()->after('cost_minor');
            $table->unsignedBigInteger('kiosk_price_minor')->nullable()->after('package_price_minor');
            $table->unsignedBigInteger('qr_price_minor')->nullable()->after('kiosk_price_minor');
            $table->unsignedBigInteger('discounted_price_minor')->nullable()->after('qr_price_minor');

            $table->string('portion', 100)->nullable();      // "250 gr", "2 kişilik"
            $table->string('unit', 30)->nullable();          // adet / porsiyon / gram / ml
            $table->unsignedSmallInteger('prep_minutes')->nullable();

            // Besin değerleri (100 gr ya da porsiyon başına; serbest bildirim)
            $table->unsignedSmallInteger('calories')->nullable();
            $table->decimal('protein', 6, 2)->nullable();
            $table->decimal('carbs', 6, 2)->nullable();
            $table->decimal('fat', 6, 2)->nullable();

            $table->unsignedTinyInteger('spiciness')->default(0); // 0-3 acılık
            $table->boolean('is_new')->default(false);
            $table->boolean('is_chef_pick')->default(false);
            $table->boolean('is_bestseller')->default(false);

            $table->boolean('is_available')->default(true);  // "mevcut değil" = false (tükendi)
            $table->json('channels')->nullable();            // ["qr","kiosk","package","pos"]; NULL = tümü
            $table->time('available_from')->nullable();      // servis saatleri (şube yerel saati)
            $table->time('available_until')->nullable();
            $table->string('station', 40)->nullable();       // hazırlama istasyonu: kitchen/bar/dessert…

            // Stok bağlantısı (alan olarak; stok modülü sonraki faz)
            $table->boolean('track_stock')->default(false);
            $table->integer('stock_quantity')->nullable();

            $table->unsignedSmallInteger('min_order_qty')->default(1);
            $table->unsignedSmallInteger('max_order_qty')->nullable();
            $table->unsignedInteger('sort_order')->default(0);
        });

        Schema::table('products', function (Blueprint $table) {
            $table->index(['tenant_id', 'category_id', 'sort_order']);
        });

        Schema::create('product_variants', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->constrained()->cascadeOnDelete();
            $table->string('name', 100);                     // Küçük / Orta / Büyük, porsiyon adı
            $table->unsignedBigInteger('price_minor')->default(0);
            $table->boolean('is_default')->default(false);
            $table->unsignedInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['tenant_id', 'product_id', 'sort_order']);
        });

        Schema::create('option_groups', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 150);
            $table->string('description', 500)->nullable();
            $table->string('selection_type', 10)->default('multiple'); // single | multiple
            $table->boolean('is_required')->default(false);
            $table->unsignedSmallInteger('min_select')->default(0);
            $table->unsignedSmallInteger('max_select')->nullable();
            $table->unsignedSmallInteger('free_limit')->default(0);    // ücretsiz adet
            $table->unsignedInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['tenant_id', 'sort_order']);
        });

        Schema::create('options', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('option_group_id')->constrained()->cascadeOnDelete();
            $table->string('name', 150);
            $table->unsignedBigInteger('price_minor')->default(0); // ek ücret (0 = ücretsiz)
            $table->boolean('is_default')->default(false);
            $table->unsignedInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['tenant_id', 'option_group_id', 'sort_order']);
        });

        Schema::create('option_group_product', function (Blueprint $table) {
            $table->foreignId('product_id')->constrained()->cascadeOnDelete();
            $table->foreignId('option_group_id')->constrained()->cascadeOnDelete();
            $table->unsignedInteger('sort_order')->default(0);

            $table->primary(['product_id', 'option_group_id']);
        });

        Schema::create('allergens', function (Blueprint $table) {
            $table->id();
            // NULL = küresel sözlük satırı (14 AB alerjeni + diyet etiketleri);
            // dolu = kiracının kendi eklediği satır.
            $table->foreignId('tenant_id')->nullable()->constrained()->cascadeOnDelete();
            $table->string('kind', 10)->default('allergen'); // allergen | diet
            $table->string('code', 40);
            $table->string('name', 100);
            $table->string('description', 500)->nullable();  // ikon tek başına yeterli değil: ad + açıklama zorunlu
            $table->string('icon', 60)->nullable();
            $table->string('color', 20)->nullable();
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index(['tenant_id', 'kind', 'sort_order']);
            $table->index('code');
        });

        Schema::create('allergen_product', function (Blueprint $table) {
            $table->foreignId('allergen_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->constrained()->cascadeOnDelete();

            $table->primary(['allergen_id', 'product_id']);
        });

        Schema::create('product_images', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('product_id')->constrained()->cascadeOnDelete();
            $table->string('path');                          // tenants/{t}/products/{p}/{rastgele}.{ext}
            $table->string('original_name', 150)->nullable();
            $table->string('mime', 100);
            $table->unsignedInteger('size');                 // bayt
            $table->boolean('is_primary')->default(false);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index(['tenant_id', 'product_id', 'sort_order']);
        });

        Schema::create('menus', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();
            $table->string('name', 150);                     // Kahvaltı / Öğle / Akşam…
            $table->string('description', 500)->nullable();
            $table->json('days')->nullable();                // [1..7] ISO gün; NULL = her gün
            $table->time('start_time')->nullable();          // şube yerel saati
            $table->time('end_time')->nullable();
            $table->json('channels')->nullable();            // NULL = tüm kanallar
            $table->unsignedInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['tenant_id', 'sort_order']);
        });

        Schema::create('category_menu', function (Blueprint $table) {
            $table->foreignId('menu_id')->constrained()->cascadeOnDelete();
            $table->foreignId('category_id')->constrained()->cascadeOnDelete();
            $table->unsignedInteger('sort_order')->default(0);

            $table->primary(['menu_id', 'category_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('category_menu');
        Schema::dropIfExists('menus');
        Schema::dropIfExists('product_images');
        Schema::dropIfExists('allergen_product');
        Schema::dropIfExists('allergens');
        Schema::dropIfExists('option_group_product');
        Schema::dropIfExists('options');
        Schema::dropIfExists('option_groups');
        Schema::dropIfExists('product_variants');

        Schema::table('products', function (Blueprint $table) {
            $table->dropIndex(['tenant_id', 'category_id', 'sort_order']);
            $table->dropConstrainedForeignId('category_id');
            $table->dropColumn([
                'barcode', 'description', 'tax_rate',
                'cost_minor', 'package_price_minor', 'kiosk_price_minor', 'qr_price_minor', 'discounted_price_minor',
                'portion', 'unit', 'prep_minutes',
                'calories', 'protein', 'carbs', 'fat',
                'spiciness', 'is_new', 'is_chef_pick', 'is_bestseller',
                'is_available', 'channels', 'available_from', 'available_until', 'station',
                'track_stock', 'stock_quantity', 'min_order_qty', 'max_order_qty', 'sort_order',
            ]);
        });

        Schema::dropIfExists('categories');
    }
};
