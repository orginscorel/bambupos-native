<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Modules\Catalog\Models\Category;
use App\Modules\Catalog\Models\Product;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Demo ürünlere TAHMİNİ gramaj (porsiyon g/ml) + kalori (kcal) doldurur.
 *
 * Kurallar:
 * - Kiracı-üstü çalışır: TenantScope bilinçle kaldırılır (Product::withoutTenancy)
 *   → tüm demo işletmelerin ürünleri kapsanır.
 * - Yalnız BOŞ alanlar doldurulur; elle girilmiş/var olan değerler EZİLMEZ.
 * - Değerler tahmini ve tutarlıdır (yaklaşık porsiyon ağırlığı ve enerji).
 *   İçecekler ml, yemekler g olarak alınır; nargile beslenme taşımaz (atlanır).
 *
 * Eşleme sırası: (1) ürün adına birebir tablo, (2) ad anahtar kelimesi,
 * (3) kategori adına göre makul varsayılan. Hiçbiri tutmazsa ürün atlanır.
 */
class ProductNutritionSeeder extends Seeder
{
    public function run(): void
    {
        // (1) Ürün adı => [gramaj (g|ml), kalori (kcal)] — kürasyonlu demo katalog.
        $byName = [
            // Kahvaltılar
            'serpme kahvaltı (2 kişilik)' => [1200, 1400],
            'hızlı kahvaltı tabağı' => [450, 620],
            'menemen' => [350, 420],
            'sucuklu yumurta' => [300, 520],
            'pancake kulesi' => [350, 720],
            // Başlangıçlar
            'sigara böreği (4 adet)' => [180, 480],
            'humus tabağı' => [220, 380],
            'çıtır tavuk (8 adet)' => [280, 620],
            'patates kızartması' => [200, 450],
            'soğan halkası' => [180, 420],
            'mozzarella stick (6 adet)' => [200, 540],
            // Ana Yemekler
            'izgara köfte' => [350, 620],
            'bonfile lokum' => [400, 680],
            'tavuk şiş' => [380, 560],
            'piliç pirzola' => [420, 640],
            'karışık ızgara' => [550, 1150],
            // Burgerler
            'classic cheeseburger' => [320, 780],
            'mushroom burger' => [330, 760],
            'bbq bacon burger' => [360, 920],
            'chicken burger' => [300, 680],
            'double smash burger' => [400, 1050],
            'vegan burger' => [320, 620],
            // Pizzalar (bütün pizza)
            'margherita' => [550, 1100],
            'karışık pizza' => [650, 1500],
            'pepperoni' => [600, 1400],
            'sucuklu pizza' => [620, 1450],
            // Makarnalar
            'fettuccine alfredo' => [400, 780],
            'spaghetti bolonez' => [420, 720],
            'penne arrabbiata' => [400, 560],
            'mantarlı makarna' => [400, 680],
            // Salatalar
            'sezar salata' => [300, 420],
            'akdeniz salata' => [280, 220],
            'ton balıklı salata' => [300, 340],
            'avokadolu tavuk salata' => [320, 480],
            // Tostlar & Sandviçler
            'kaşarlı tost' => [180, 420],
            'karışık tost' => [220, 520],
            'club sandwich' => [350, 720],
            'tavuklu wrap' => [300, 560],
            'kasap köfte sandviç' => [380, 780],
            // Tatlılar
            'san sebastian cheesecake' => [150, 480],
            'çikolatalı sufle' => [160, 520],
            'waffle' => [250, 620],
            'künefe' => [200, 560],
            'tiramisu' => [150, 420],
            'magnolia' => [180, 380],
            // Sıcak İçecekler (ml)
            'türk kahvesi' => [60, 10],
            'espresso' => [30, 5],
            'americano' => [180, 10],
            'latte' => [240, 150],
            'cappuccino' => [180, 120],
            'mocha' => [250, 290],
            'sıcak çikolata' => [250, 320],
            'chai latte' => [240, 200],
            'filtre kahve' => [240, 5],
            'çay (bardak)' => [120, 2],
            // Soğuk İçecekler (ml)
            'ev yapımı limonata' => [300, 160],
            'ice americano' => [300, 15],
            'iced latte' => [300, 180],
            'milkshake (çikolata)' => [400, 560],
            'mango smoothie' => [350, 280],
            'taze portakal suyu' => [300, 140],
            'meyveli soda' => [330, 120],
            'mojito (alkolsüz)' => [350, 180],
        ];

        // (3) Kategori adına göre makul varsayılan (birebir/anahtar tutmazsa).
        // Nargile kasıtla YOK → beslenme değeri taşımaz, atlanır.
        $byCategory = [
            'kahvaltılar' => [400, 550],
            'başlangıçlar' => [200, 420],
            'ana yemekler' => [400, 650],
            'burgerler' => [330, 780],
            'pizzalar' => [600, 1350],
            'makarnalar' => [400, 700],
            'salatalar' => [300, 360],
            'tostlar & sandviçler' => [280, 560],
            'tatlılar' => [170, 460],
            'sıcak içecekler' => [220, 120],
            'soğuk içecekler' => [320, 180],
        ];

        // Kiracı-üstü kategori haritası (id => normalize edilmiş ad).
        $categoryNames = Category::withoutTenancy()
            ->pluck('name', 'id')
            ->map(fn (string $name): string => $this->norm($name))
            ->all();

        $touched = 0;

        Product::withoutTenancy()
            ->select(['id', 'name', 'category_id', 'weight_grams', 'calories'])
            ->orderBy('id')
            ->chunkById(200, function ($products) use ($byName, $byCategory, $categoryNames, &$touched): void {
                foreach ($products as $product) {
                    $estimate = $this->estimate($product, $byName, $byCategory, $categoryNames);
                    if ($estimate === null) {
                        continue; // ör. Nargile → beslenme uygulanmaz
                    }

                    [$weight, $calories] = $estimate;

                    // Yalnız boş alanları doldur; mevcut değerleri koru.
                    $dirty = false;
                    if ($product->weight_grams === null) {
                        $product->weight_grams = $weight;
                        $dirty = true;
                    }
                    if ($product->calories === null) {
                        $product->calories = $calories;
                        $dirty = true;
                    }

                    if ($dirty) {
                        $product->saveQuietly(); // denetim/olay gürültüsü olmadan
                        $touched++;
                    }
                }
            });

        $this->command?->info("Beslenme tahmini uygulandı: {$touched} ürün güncellendi.");
    }

    /**
     * Bir ürün için [gramaj, kalori] tahmini üretir; uygun değilse null.
     *
     * @param  array<string, array{0: int, 1: int}>  $byName
     * @param  array<string, array{0: int, 1: int}>  $byCategory
     * @param  array<int, string>  $categoryNames
     * @return array{0: int, 1: int}|null
     */
    private function estimate(Product $product, array $byName, array $byCategory, array $categoryNames): ?array
    {
        $name = $this->norm($product->name);

        // (1) Birebir ad
        if (isset($byName[$name])) {
            return $byName[$name];
        }

        $category = $product->category_id !== null ? ($categoryNames[$product->category_id] ?? null) : null;

        // Nargile: gramaj/kalori anlamsız → atla.
        if ($category === 'nargile' || Str::contains($name, 'nargile')) {
            return null;
        }

        // (2) Ad anahtar kelimeleri (kategori bilinmese de makul tahmin)
        $keyword = $this->keywordEstimate($name);
        if ($keyword !== null) {
            return $keyword;
        }

        // (3) Kategori varsayılanı
        if ($category !== null && isset($byCategory[$category])) {
            return $byCategory[$category];
        }

        return null;
    }

    /**
     * Ada gömülü tür ipuçlarından tahmin (kürasyon dışı/eklenmiş ürünler için).
     *
     * @return array{0: int, 1: int}|null
     */
    private function keywordEstimate(string $name): ?array
    {
        // Alt-dize eşleşmesi güvenli olan anahtarlar (yanlış eşleşme riski düşük).
        $substring = [
            'burger' => [330, 780],
            'pizza' => [600, 1350],
            'köfte' => [350, 620],
            'lahmacun' => [150, 300],
            'pide' => [350, 700],
            'döner' => [300, 650],
            'kebap' => [350, 700],
            'makarna' => [400, 700],
            'salata' => [300, 360],
            'çorba' => [300, 220],
            'tost' => [200, 480],
            'sandviç' => [300, 560],
            'wrap' => [300, 560],
            'kahvaltı' => [450, 600],
            'dondurma' => [120, 240],
            'baklava' => [150, 520],
            'kahve' => [200, 60],
            'ayran' => [300, 150],
            'limonata' => [300, 160],
            'smoothie' => [350, 280],
            'milkshake' => [400, 560],
        ];

        foreach ($substring as $keyword => $values) {
            if (Str::contains($name, $keyword)) {
                return $values;
            }
        }

        // Kısa/çok-anlamlı anahtarlar YALNIZ tam kelime olarak (ör. "su",
        // "kola" → "çi-kola-ta"/"su-cuk" yanlış eşleşmesin diye \b sınırı).
        $word = [
            'su' => [500, 0],
            'kola' => [330, 139],
            'soda' => [330, 90],
            'çay' => [120, 5],
            'tatlı' => [170, 460],
        ];

        foreach ($word as $keyword => $values) {
            if (preg_match('/(?<![\p{L}])'.preg_quote($keyword, '/').'(?![\p{L}])/u', $name) === 1) {
                return $values;
            }
        }

        return null;
    }

    /** Türkçe-duyarlı küçük harf + kırpma (eşleme anahtarı normalizasyonu). */
    private function norm(string $value): string
    {
        return trim(mb_strtolower($value, 'UTF-8'));
    }
}
