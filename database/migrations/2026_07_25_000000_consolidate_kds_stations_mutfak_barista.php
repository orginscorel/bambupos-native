<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * §12 İSTASYON YÖNLENDİRME — mevcut veriyi Mutfak/Barista ayrımına oturtur.
 *
 * Önceden ürünler ayrıntılı istasyonlara dağılmıştı (grill/oven/cold_kitchen/
 * dessert = mutfak tarafı; coffee/bar = içecek tarafı). Kullanıcı NET bir
 * "Mutfak vs Barista" istiyor: TÜM yemekler tek Mutfak ekranında, TÜM
 * içecekler tek Barista ekranında görünsün. Ayrıntılı istasyonlar builtin
 * olarak DURUYOR (genişletilebilirlik) ama demo verisi bu iki ana istasyona
 * (+ Nargile) toplanır.
 *
 * Idempotent: fresh kurulumda tablolar boş → no-op (CatalogSeeder zaten doğru
 * atar). Var olan canlı veride ise yönlendirmeyi düzeltir. `station` bir key
 * string'idir; para/kritik alan değildir.
 */
return new class extends Migration
{
    /** Eski ayrıntılı key → iki ana istasyon. */
    private array $toKitchen = ['grill', 'oven', 'cold_kitchen', 'dessert'];

    private array $toBarista = ['coffee', 'bar'];

    public function up(): void
    {
        foreach (['products', 'order_items'] as $table) {
            if (! Schema::hasTable($table) || ! Schema::hasColumn($table, 'station')) {
                continue;
            }

            DB::table($table)->whereIn('station', $this->toKitchen)->update(['station' => 'kitchen']);
            DB::table($table)->whereIn('station', $this->toBarista)->update(['station' => 'barista']);
        }
    }

    public function down(): void
    {
        // Geri alınamaz veri birleştirmesi (hangi ürün eskiden hangi ayrıntılı
        // istasyondaydı bilinmiyor). Bilinçli no-op — kayıp yok, yalnız
        // etiket birleşmesi; istenirse panelden yeniden atanır.
    }
};
