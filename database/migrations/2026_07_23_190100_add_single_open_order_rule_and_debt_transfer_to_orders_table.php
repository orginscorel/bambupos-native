<?php

use App\Modules\Identity\Models\User;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Adisyon-Cari: MASADA TEK AÇIK ADİSYON kuralı (kullanıcı kararı, 2026-07-23)
 * + "adisyonu borca taşı" alanları.
 *
 * DB-DÜZEYİNDE GARANTİ — neden GENERATED COLUMN değil:
 * MariaDB/MySQL, `table_id` gibi ON DELETE SET NULL ile kısıtlı bir
 * sütuna bağımlı STORED GENERATED COLUMN'A İZİN VERMEZ (hata 1901 —
 * denendi, doğrulandı). Bunun yerine `table_open_slot` SIRADAN (generated
 * olmayan) nullable sütun + BEFORE INSERT/UPDATE TETİKLEYİCİLERİ ile
 * senkron tutulur — tetikleyiciler FK CASCADE/SET NULL ile tetiklenen
 * güncellemelerde de ateşlenir (dokümante edilmiş davranış), yani masa
 * silinip table_id NULL'landığında da slot doğru şekilde boşalır.
 *
 * `table_open_slot` = masaya bağlı + split-parçası OLMAYAN + KAPALI
 * OLMAYAN adisyonlarda table_id, aksi halde NULL. UNIQUE(tenant_id,
 * table_open_slot): NULL değerler unique index'te birbiriyle ÇAKIŞMAZ
 * (standart SQL) → masasız/kapalı/split satırları sınırsız, ama bir
 * masanın AÇIK ANA adisyonundan aynı anda yalnız BİR tane olabilir.
 *
 * Uygulama katmanında AYRICA satır kilidi + kontrol var (bkz.
 * OrderService::open/createPublicOrder/openOrderForTable) — bu tetikleyici
 * + UNIQUE index SON HAT güvencesidir (yarış durumunda ikinci
 * INSERT/UPDATE veritabanı hatasıyla reddedilir).
 *
 * VERİ TEMİZLİĞİ: kural ÖNCESİ oluşmuş, aynı masada birden çok açık
 * adisyon varsa (canlıda 2 grup tespit edildi: masa #1 → 3, masa #3 → 2)
 * UNIQUE index eklenmeden ÖNCE bunlar OrderService::merge() ile TEK
 * adisyona konsolide edilir (kuruş kaybı yok — merge() zaten test edilmiş
 * "toplamları kuruşu kuruşuna korur" mantığını kullanır); en çok içeriği
 * olan (items_total_minor DESC, eşitlikte en düşük id) adisyon birincil
 * kalır, diğerleri onunla birleştirilip 'cancelled' + iz bırakılır.
 */
return new class extends Migration
{
    private const CLOSED = ['paid', 'cancelled', 'refunded', 'debt_transferred'];

    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->boolean('is_split_child')->default(false)->after('version');
            $table->unsignedBigInteger('table_open_slot')->nullable()->after('is_split_child');

            $table->foreignId('debt_receivable_id')->nullable()->after('cancelled_by_id')
                ->constrained('receivables')->nullOnDelete();
            $table->unsignedBigInteger('debt_amount_minor')->nullable()->after('debt_receivable_id');
            $table->timestamp('debt_transferred_at')->nullable()->after('debt_amount_minor');
            $table->foreignId('debt_transferred_by_id')->nullable()->after('debt_transferred_at')
                ->constrained('users')->nullOnDelete();
        });

        $this->consolidateDuplicateOpenOrders();
        $this->backfillTableOpenSlot();
        $this->createTriggers();

        Schema::table('orders', function (Blueprint $table) {
            $table->unique(['tenant_id', 'table_open_slot'], 'orders_tenant_table_open_slot_unique');
        });
    }

    public function down(): void
    {
        DB::unprepared('DROP TRIGGER IF EXISTS orders_open_slot_bi');
        DB::unprepared('DROP TRIGGER IF EXISTS orders_open_slot_bu');
        DB::unprepared('DROP TRIGGER IF EXISTS orders_open_slot_ai');
        DB::unprepared('DROP TRIGGER IF EXISTS orders_open_slot_au');

        Schema::table('orders', function (Blueprint $table) {
            $table->dropUnique('orders_tenant_table_open_slot_unique');
            $table->dropColumn('table_open_slot');
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->dropConstrainedForeignId('debt_receivable_id');
            $table->dropConstrainedForeignId('debt_transferred_by_id');
            $table->dropColumn(['debt_amount_minor', 'debt_transferred_at', 'is_split_child']);
        });
    }

    /** table_open_slot ifadesi (CASE), sütun önekiyle parametreli. */
    private function caseExpr(string $prefix = ''): string
    {
        $closed = implode(',', array_map(fn (string $s): string => "'{$s}'", self::CLOSED));

        return "CASE WHEN {$prefix}table_id IS NOT NULL AND {$prefix}is_split_child = 0 "
            ."AND {$prefix}status NOT IN ({$closed}) THEN {$prefix}table_id ELSE NULL END";
    }

    private function backfillTableOpenSlot(): void
    {
        DB::statement('UPDATE orders SET table_open_slot = '.$this->caseExpr());
    }

    private function createTriggers(): void
    {
        $driver = DB::connection()->getDriverName();

        if ($driver === 'sqlite') {
            // BEFORE trigger'da NEW salt-okunurdur (SQLite) — AFTER trigger
            // + hedefli UPDATE + WHEN koruması (gereksiz/özyinelemeli tetiklemeyi
            // önler) kullanılır. Bir masanın ana adisyonuna eklenen İKİNCİ satır
            // bu UPDATE'in UNIQUE ihlaliyle reddedilmesiyle engellenir.
            DB::unprepared('
                CREATE TRIGGER orders_open_slot_ai AFTER INSERT ON orders
                WHEN ('.$this->caseExpr('NEW.').') IS NOT NEW.table_open_slot
                BEGIN
                    UPDATE orders SET table_open_slot = '.$this->caseExpr().' WHERE id = NEW.id;
                END
            ');
            DB::unprepared('
                CREATE TRIGGER orders_open_slot_au AFTER UPDATE ON orders
                WHEN ('.$this->caseExpr('NEW.').') IS NOT NEW.table_open_slot
                BEGIN
                    UPDATE orders SET table_open_slot = '.$this->caseExpr().' WHERE id = NEW.id;
                END
            ');

            return;
        }

        // MySQL/MariaDB: BEFORE INSERT/UPDATE'te NEW.* doğrudan yazılabilir —
        // FK CASCADE/SET NULL ile tetiklenen güncellemelerde de ateşlenir.
        DB::unprepared('
            CREATE TRIGGER orders_open_slot_bi BEFORE INSERT ON orders
            FOR EACH ROW SET NEW.table_open_slot = '.$this->caseExpr('NEW.').'
        ');
        DB::unprepared('
            CREATE TRIGGER orders_open_slot_bu BEFORE UPDATE ON orders
            FOR EACH ROW SET NEW.table_open_slot = '.$this->caseExpr('NEW.').'
        ');
    }

    /**
     * Kural öncesi bozuk veri: aynı (tenant, table) için birden çok açık
     * adisyon varsa TEK adisyona konsolide eder (para kaybı yok).
     */
    private function consolidateDuplicateOpenOrders(): void
    {
        $groups = DB::table('orders')
            ->select('tenant_id', 'table_id')
            ->whereNotNull('table_id')
            ->whereNotIn('status', self::CLOSED)
            ->groupBy('tenant_id', 'table_id')
            ->havingRaw('count(*) > 1')
            ->get();

        if ($groups->isEmpty()) {
            return;
        }

        /** @var OrderService $orderService */
        $orderService = app(OrderService::class);
        /** @var TenantContext $context */
        $context = app(TenantContext::class);

        foreach ($groups as $group) {
            $context->setTenant((int) $group->tenant_id);

            try {
                $openOrders = Order::withoutTenancy()
                    ->where('tenant_id', $group->tenant_id)
                    ->where('table_id', $group->table_id)
                    ->whereNotIn('status', self::CLOSED)
                    ->orderByDesc('items_total_minor')
                    ->orderBy('id')
                    ->get();

                $primary = $openOrders->first();

                $actor = User::query()->where('tenant_id', $group->tenant_id)->orderBy('id')->first();

                if ($primary === null || $actor === null) {
                    continue;
                }

                foreach ($openOrders as $order) {
                    if ((int) $order->id === (int) $primary->id) {
                        continue;
                    }

                    $orderService->merge($primary, $order, $actor);
                }
            } finally {
                $context->forget();
            }
        }
    }
};
