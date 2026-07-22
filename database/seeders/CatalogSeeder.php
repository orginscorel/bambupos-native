<?php

namespace Database\Seeders;

use App\Modules\Catalog\Models\Allergen;
use App\Modules\Catalog\Models\Category;
use App\Modules\Catalog\Models\Menu;
use App\Modules\Catalog\Models\OptionGroup;
use App\Modules\Catalog\Models\Product;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Katalog seed'i (DATA_MIGRATION_PLAN §2 kararı):
 *
 *  1) KÜRESEL alerjen sözlüğü: 14 AB alerjeni + 7 diyet etiketi
 *     (ad + açıklama + ikon; ikon tek başına yeterli değil — §10.3).
 *  2) Demo kiracısına "örnek kafe menüsü" şablonu: eski `oritoriu_menu`
 *     DB'sindeki 12 kategori + 68 ürün + 28 ekstra, TÜRKÇE DİYAKRİTİK
 *     KÜRASYONUYLA (SigaraBoregi→Sigara Böreği vb.) elle düzeltilerek.
 *     Eski DB'ye dokunulmaz; veriler tek seferlik SELECT kopyasından
 *     bu dosyaya kürasyonla aktarılmıştır. Fiyatlar ×100 kuruş (ADR-007).
 *  3) 28 eski "ekstra" → 7 seçenek grubu + 29 seçenek (Çikolata Sosu
 *     iki grupta yer alır) ve kategori-bazlı ürün atamaları (467 bağın
 *     sadeleşmiş karşılığı).
 *  4) Menü planları: Kahvaltı / Öğle / Akşam / Tüm Gün.
 *
 * Idempotent: küresel sözlük ve demo menüsü ancak yoksa yazılır.
 */
class CatalogSeeder extends Seeder
{
    public function run(): void
    {
        app(TenantContext::class)->runWithoutTenancy(function (): void {
            $this->seedGlobalAllergens();
            $this->seedDemoMenu();
        });
    }

    /* ================= 1) Küresel sözlük ================= */

    private function seedGlobalAllergens(): void
    {
        $rows = [
            // 14 AB alerjeni (prompt §10.3)
            ['allergen', 'gluten', 'Gluten', 'Buğday, arpa, çavdar, yulaf gibi glüten içeren tahıllar ve ürünleri.', 'wheat', '#f59e0b'],
            ['allergen', 'kabuklular', 'Kabuklular', 'Karides, yengeç, ıstakoz gibi kabuklu deniz canlıları.', 'shrimp', '#14b8a6'],
            ['allergen', 'yumurta', 'Yumurta', 'Yumurta ve yumurta içeren ürünler (majonez, bazı hamur işleri).', 'egg', '#eab308'],
            ['allergen', 'balik', 'Balık', 'Balık ve balık içeren ürünler (sos, sardalya, ançüez dahil).', 'fish', '#06b6d4'],
            ['allergen', 'yer-fistigi', 'Yer Fıstığı', 'Yer fıstığı ve yer fıstığı içeren ürünler (fıstık ezmesi, yağı).', 'peanut', '#84cc16'],
            ['allergen', 'soya', 'Soya', 'Soya fasulyesi ve soya ürünleri (soya sosu, tofu, lesitin).', 'bean', '#22c55e'],
            ['allergen', 'sut', 'Süt (Laktoz)', 'Süt ve süt ürünleri; laktoz içerir (peynir, tereyağı, krema).', 'milk', '#3b82f6'],
            ['allergen', 'sert-kabuklu', 'Sert Kabuklu Yemişler', 'Fındık, ceviz, badem, antep fıstığı, kaju gibi yemişler.', 'nut', '#a855f7'],
            ['allergen', 'kereviz', 'Kereviz', 'Kereviz kökü, sapı, yaprağı ve tohumu içeren ürünler.', 'celery', '#65a30d'],
            ['allergen', 'hardal', 'Hardal', 'Hardal ve hardal içeren soslar, marinasyonlar.', 'mustard', '#ca8a04'],
            ['allergen', 'susam', 'Susam', 'Susam tohumu ve ürünleri (tahin, susamlı çıtır, simit).', 'sesame', '#d97706'],
            ['allergen', 'sulfit', 'Kükürt Dioksit / Sülfit', 'Kurutulmuş meyve, şarap ve bazı işlenmiş gıdalardaki koruyucular (>10 mg/kg).', 'flask', '#f43f5e'],
            ['allergen', 'aci-bakla', 'Acı Bakla (Lupin)', 'Lupin unu ve tohumu içeren ürünler (bazı unlu mamuller).', 'seed', '#8b5cf6'],
            ['allergen', 'yumusakcalar', 'Yumuşakçalar', 'Midye, kalamar, ahtapot, salyangoz gibi yumuşakçalar.', 'shell', '#0ea5e9'],

            // Diyet etiketleri
            ['diet', 'vegan', 'Vegan', 'Hiçbir hayvansal ürün içermez.', 'leaf', '#16a34a'],
            ['diet', 'vejetaryen', 'Vejetaryen', 'Et, tavuk ve balık içermez; süt/yumurta içerebilir.', 'sprout', '#22c55e'],
            ['diet', 'glutensiz', 'Glutensiz', 'Glüten içeren tahıl ve türevi içermez.', 'wheat-off', '#f59e0b'],
            ['diet', 'laktozsuz', 'Laktozsuz', 'Laktoz içermez; laktoz intoleransına uygundur.', 'milk-off', '#3b82f6'],
            ['diet', 'helal', 'Helal', 'Helal sertifikalı/uyumlu içerikle hazırlanır.', 'badge-check', '#0d9488'],
            ['diet', 'sekersiz', 'Şekersiz', 'İlave şeker içermez.', 'candy-off', '#ec4899'],
            ['diet', 'keto', 'Keto Dostu', 'Düşük karbonhidratlı, ketojenik beslenmeye uygun.', 'flame', '#f97316'],
        ];

        foreach ($rows as $i => [$kind, $code, $name, $description, $icon, $color]) {
            Allergen::query()
                ->withoutGlobalScopes()
                ->whereNull('tenant_id')
                ->firstOrCreate(
                    ['code' => $code],
                    [
                        'kind' => $kind,
                        'name' => $name,
                        'description' => $description,
                        'icon' => $icon,
                        'color' => $color,
                        'sort_order' => ($i + 1) * 10,
                    ],
                );
        }
    }

    /* ================= 2-4) Demo kiracısının örnek menüsü ================= */

    private function seedDemoMenu(): void
    {
        $tenant = Tenant::query()->where('slug', 'demo')->first();

        if ($tenant === null) {
            return; // demo kiracısı yoksa şablon menü kurulamaz
        }

        if (Category::query()->withoutGlobalScopes()->where('tenant_id', $tenant->id)->exists()) {
            return; // idempotent: menü zaten kurulu
        }

        $t = (int) $tenant->id;

        /* ---- Seçenek grupları (28 eski ekstranın karşılığı) ---- */

        $groupDefs = [
            'soslar' => [
                'name' => 'Soslar', 'selection_type' => 'multiple', 'is_required' => false, 'free_limit' => 2,
                'description' => 'Yanında istediğiniz soslar (2 adede kadar ücretsiz olanlar mevcut).',
                'options' => [
                    ['Ketçap', 0], ['Mayonez', 0], ['Hardal', 0], ['Ranch Sos', 500], ['BBQ Sos', 500], ['Acı Sos', 300],
                ],
            ],
            'ekstra' => [
                'name' => 'Ekstra Malzemeler', 'selection_type' => 'multiple', 'is_required' => false, 'free_limit' => 0,
                'description' => 'Ürününüze ekleyebileceğiniz ilave malzemeler.',
                'options' => [
                    ['Ekstra Peynir', 1500], ['Ekstra Et (Köfte)', 3000], ['Mantar', 1000],
                    ['Jalapeno', 800], ['Avokado', 2000], ['Patates (Yanında)', 2500],
                ],
            ],
            'sut' => [
                'name' => 'Süt Tercihi', 'selection_type' => 'single', 'is_required' => false, 'free_limit' => 0,
                'description' => 'Kahveniz için alternatif süt seçimi.',
                'options' => [
                    ['Badem Sütü', 1200], ['Yulaf Sütü', 1200], ['Hindistan Cevizi Sütü', 1500],
                ],
            ],
            'kahve' => [
                'name' => 'Kahve Ekstraları', 'selection_type' => 'multiple', 'is_required' => false, 'free_limit' => 0,
                'description' => 'Kahvenizi zenginleştirin.',
                'options' => [
                    ['Shot Espresso', 1500], ['Karamel Şurubu', 1000], ['Vanilya Şurubu', 1000],
                    ['Çikolata Sosu', 1000], ['Ekstra Krema', 800],
                ],
            ],
            'koz' => [
                'name' => 'Köz Seçimi', 'selection_type' => 'single', 'is_required' => true, 'free_limit' => 1,
                'description' => 'Nargileniz için köz tercihi (zorunlu).',
                'options' => [
                    ['Hindistan Cevizi Közü', 0], ['Bambu Közü', 0],
                ],
            ],
            'nargile' => [
                'name' => 'Nargile Ekstraları', 'selection_type' => 'multiple', 'is_required' => false, 'free_limit' => 0,
                'description' => 'Nargile deneyiminizi kişiselleştirin.',
                'options' => [
                    ['Buz Aparatı', 1500], ['Çift Aroma', 2000], ['Meyve Başlığı', 3000], ['Süt Dolgusu', 1500],
                ],
            ],
            'tatli' => [
                'name' => 'Tatlı Ekstraları', 'selection_type' => 'multiple', 'is_required' => false, 'free_limit' => 0,
                'description' => 'Tatlınızın yanına ilaveler.',
                'options' => [
                    ['Çikolata Sosu', 1000], ['Ekstra Dondurma', 1200], ['Fındık Parçası', 800],
                ],
            ],
        ];

        $groups = [];
        $g = 0;

        foreach ($groupDefs as $key => $def) {
            $group = new OptionGroup([
                'name' => $def['name'],
                'description' => $def['description'],
                'selection_type' => $def['selection_type'],
                'is_required' => $def['is_required'],
                'min_select' => $def['is_required'] ? 1 : 0,
                'max_select' => $def['selection_type'] === 'single' ? 1 : null,
                'free_limit' => $def['free_limit'],
                'sort_order' => (++$g) * 10,
                'is_active' => true,
            ]);
            $group->tenant_id = $t;
            $group->save();

            foreach ($def['options'] as $i => [$name, $priceMinor]) {
                $option = $group->options()->make([
                    'name' => $name,
                    'price_minor' => $priceMinor,
                    'sort_order' => ($i + 1) * 10,
                    'is_active' => true,
                ]);
                $option->tenant_id = $t;
                $option->save();
            }

            $groups[$key] = $group;
        }

        /* ---- Kategoriler (12, kürasyonlu) + ürünler (68, kürasyonlu) ---- */

        // Kategori => [seçenek grubu anahtarları], ürünler:
        // [ad, açıklama, fiyat(kuruş), rozet(null|new|chef|best), vejetaryen, vegan, glutensiz]
        $catalog = [
            ['Kahvaltılar', 'Güne enerjik başlayın', 'sun-icon', ['soslar', 'ekstra'], ['07:00', '13:00'], [
                ['Serpme Kahvaltı (2 Kişilik)', 'Ezine peyniri, eski kaşar, bal-kaymak, tereyağı, zeytin, domates, salatalık, yumurta ve sıcak ekmek sepeti.', 85000, 'best', false, false, false],
                ['Hızlı Kahvaltı Tabağı', 'Haşlanmış yumurta, beyaz peynir, kaşar, domates, salatalık, zeytin, bal, tereyağı.', 32000, null, false, false, false],
                ['Menemen', 'Geleneksel menemen; taze domates, biber ve yumurta. Yanında ekmek ile.', 18000, null, true, false, false],
                ['Sucuklu Yumurta', 'Kangal sucuk ve çiftlik yumurtası. Yanında taze ekmek.', 20000, 'best', false, false, false],
                ['Pancake Kulesi', '4 katlı pancake; mevsim meyveleri, çikolata ve akçaağaç şurubu ile.', 24000, 'best', true, false, false],
            ]],
            ['Başlangıçlar', 'Hafif ve lezzetli atıştırmalıklar', 'seedling-icon', ['soslar', 'ekstra'], [null, null], [
                ['Sigara Böreği (4 Adet)', 'El açması yufka, beyaz peynir ve maydanoz dolgulu. Ceviz sos ile.', 12000, null, true, false, false],
                ['Humus Tabağı', 'Nohut püresi, tahin, zeytinyağı, sumak ve pita ekmeği.', 10000, null, true, true, false],
                ['Çıtır Tavuk (8 Adet)', 'Mısır gevrekli kaplamayla çıtırlaştırılmış tavuk parçaları. Ranch sos ile.', 16000, 'best', false, false, false],
                ['Patates Kızartması', 'Özel kesim patates, deniz tuzu ve biberiye. Ketçap ile.', 9000, null, true, true, true],
                ['Soğan Halkası', 'Çıtır kaplamayla kızartılmış taze soğan halkaları. BBQ sos ile.', 11000, null, true, false, false],
                ['Mozzarella Stick (6 Adet)', 'Çıtır kaplamayla kızartılmış mozzarella çubuğu. Marinara sos ile.', 14000, 'new', true, false, false],
            ]],
            ['Ana Yemekler', 'Doyurucu ana yemekler', 'plate-icon', ['soslar', 'ekstra'], [null, null], [
                ['Izgara Köfte', 'Kasap köfte; pilav, ızgara domates, biber ve patates kızartması ile.', 38000, 'chef', false, false, false],
                ['Bonfile Lokum', '200 gr dana bonfile; tereyağlı patates püresi ve sote sebzeler ile.', 65000, 'chef', false, false, true],
                ['Tavuk Şiş', 'Marine edilmiş tavuk şiş; bulgur pilavı ve yeşil salata ile.', 32000, null, false, false, false],
                ['Piliç Pirzola', 'Izgara piliç but; fırın patates ve mevsim salata ile.', 35000, 'best', false, false, false],
                ['Karışık Izgara', 'Köfte, tavuk şiş, pirzola, Adana kebap. Pilav ve salata ile.', 75000, 'best', false, false, false],
            ]],
            ['Burgerler', 'El yapımı özel burgerler', 'burger-icon', ['soslar', 'ekstra'], [null, null], [
                ['Classic Cheeseburger', '160 gr dana burger köftesi, cheddar peyniri, karamelize soğan, turşu, özel sos.', 32000, 'best', false, false, false],
                ['Mushroom Burger', '160 gr köfte, sote mantar, İsviçre peyniri, trüf mayonez.', 34000, null, false, false, false],
                ['BBQ Bacon Burger', '160 gr köfte, çıtır bacon, cheddar, BBQ sos, soğan halkası.', 38000, 'best', false, false, false],
                ['Chicken Burger', 'Çıtır tavuk file, marul, domates, ranch sos.', 29000, null, false, false, false],
                ['Double Smash Burger', '2×120 gr smash köfte, double cheddar, karamelize soğan, özel smash sos.', 42000, 'chef', false, false, false],
                ['Vegan Burger', 'Mercimek ve sebze köftesi, vegan peynir, avokado, özel vegan sos.', 35000, null, true, true, false],
            ]],
            ['Pizzalar', 'İtalyan usulü pizzalar', 'pizza-icon', ['soslar', 'ekstra'], [null, null], [
                ['Margherita', 'Domates sos, taze mozzarella, fesleğen, sızma zeytinyağı.', 25000, null, true, false, false],
                ['Karışık Pizza', 'Sucuk, sosis, mantar, mısır, yeşil biber, zeytin, mozzarella.', 32000, 'best', false, false, false],
                ['Pepperoni', 'Bol pepperoni, mozzarella, domates sos.', 30000, 'best', false, false, false],
                ['Sucuklu Pizza', 'Kangal sucuk, kaşar, mozzarella, domates sos.', 28000, null, false, false, false],
            ]],
            ['Makarnalar', 'Taze makarna çeşitleri', 'pasta-icon', ['ekstra'], [null, null], [
                ['Fettuccine Alfredo', 'Krema, mantar, parmesan ve tavuk parçaları ile.', 29000, 'best', false, false, false],
                ['Spaghetti Bolonez', 'Kıyma soslu klasik İtalyan makarna. Parmesan ile servis.', 26000, null, false, false, false],
                ['Penne Arrabbiata', 'Acılı domates sos, sarımsak, fesleğen. Vegan seçeneği.', 24000, null, true, true, false],
                ['Mantarlı Makarna', 'Krema soslu karışık mantar, kekik ve parmesan.', 25000, 'new', true, false, false],
            ]],
            ['Salatalar', 'Taze ve sağlıklı salatalar', 'leaf-icon', ['ekstra'], [null, null], [
                ['Sezar Salata', 'Marul, kruton, parmesan, tavuk ve Sezar sos.', 22000, null, false, false, false],
                ['Akdeniz Salata', 'Roka, domates, salatalık, zeytin, lor peyniri, nar ekşisi.', 18000, null, true, true, true],
                ['Ton Balıklı Salata', 'Ton balığı, mısır, havuç, marul, limon sos.', 26000, 'best', false, false, true],
                ['Avokadolu Tavuk Salata', 'Izgara tavuk, avokado, cherry domates, kinoa, yeşil sos.', 28000, 'chef', false, false, true],
            ]],
            ['Tostlar & Sandviçler', 'Sıcak tostlar ve sandviçler', 'bread-icon', ['soslar', 'ekstra'], [null, null], [
                ['Kaşarlı Tost', 'Bol kaşarlı klasik tost.', 12000, null, true, false, false],
                ['Karışık Tost', 'Kaşar, sucuk, domates, yeşil biber.', 16000, 'best', false, false, false],
                ['Club Sandwich', 'Tavuk, bacon, marul, domates, mayonez. Patates ile.', 22000, null, false, false, false],
                ['Tavuklu Wrap', 'Izgara tavuk, marul, domates, ranch sos, lavaş ekmeği.', 20000, 'new', false, false, false],
                ['Kasap Köfte Sandviç', 'El yapımı köfte, kaşar, domates, turşu, özel sos. Yanında patates.', 26000, 'best', false, false, false],
            ]],
            ['Tatlılar', 'El yapımı tatlılar', 'cake-icon', ['tatli'], [null, null], [
                ['San Sebastian Cheesecake', 'Akışkan iç dokusuyla; yanında Belçika çikolatası sosu ile.', 22000, 'best', true, false, false],
                ['Çikolatalı Sufle', 'Sıcak akışkan çikolata; yanında vanilyalı dondurma ile.', 20000, 'chef', true, false, false],
                ['Waffle', 'Taze waffle; çikolata sos, muz, dondurma ve fındık ile.', 18000, 'best', true, false, false],
                ['Künefe', 'Antep fıstıklı geleneksel künefe. Dondurma ile servis.', 25000, null, true, false, false],
                ['Tiramisu', 'Klasik İtalyan tiramisu; mascarpone ve espresso ile.', 21000, null, true, false, false],
                ['Magnolia', 'Muzlu magnolia; üzüm ve ceviz ile.', 19000, 'new', true, false, false],
            ]],
            ['Sıcak İçecekler', 'Kahve ve sıcak içecekler', 'mug-icon', ['sut', 'kahve'], [null, null], [
                ['Türk Kahvesi', 'Geleneksel lezzet, lokum ile servis.', 8000, null, true, true, true],
                ['Espresso', 'Çift shot espresso; yoğun ve aromatik.', 9000, null, true, true, true],
                ['Americano', 'Espresso ve sıcak su. Hafif ve dengeli.', 10000, null, true, true, true],
                ['Latte', 'Espresso ve buharda ısıtılmış süt. Kremsi doku.', 11000, 'best', true, false, true],
                ['Cappuccino', 'Espresso, süt köpüğü ve kakao tozu ile.', 11000, null, true, false, true],
                ['Mocha', 'Espresso, çikolata ve süt. Krema ile.', 13000, null, true, false, false],
                ['Sıcak Çikolata', 'Belçika çikolatası, süt ve krema.', 12000, null, true, false, false],
                ['Chai Latte', 'Baharatlı chai ve buharda ısıtılmış süt.', 12000, 'new', true, false, true],
                ['Filtre Kahve', 'Günün filtre kahvesi; zengin aroma.', 8000, null, true, true, true],
                ['Çay (Bardak)', 'Rize çayı, demlik servis.', 3000, null, true, true, true],
            ]],
            ['Soğuk İçecekler', 'Serinleten içecekler', 'glass-icon', ['sut', 'kahve'], [null, null], [
                ['Ev Yapımı Limonata', 'Taze limon, nane ve şeker ile.', 10000, 'best', true, true, true],
                ['Ice Americano', 'Soğuk su ve buz üzerinde çift espresso.', 12000, null, true, true, true],
                ['Iced Latte', 'Soğuk süt ve buz üzerinde espresso.', 13000, 'best', true, false, true],
                ['Milkshake (Çikolata)', 'Belçika çikolatası, süt ve dondurma.', 14000, null, true, false, false],
                ['Mango Smoothie', 'Taze mango, muz ve portakal suyu.', 15000, null, true, true, true],
                ['Taze Portakal Suyu', 'Sıkma taze portakal suyu.', 10000, null, true, true, true],
                ['Meyveli Soda', 'Limon, nar veya şeftali aromalı soda.', 9000, null, true, true, true],
                ['Mojito (Alkolsüz)', 'Nane, lime, şeker ve soda.', 11000, 'new', true, true, true],
            ]],
            ['Nargile', 'Premium nargile deneyimi', 'wind-icon', ['koz', 'nargile'], [null, null], [
                ['Klasik Nargile', 'Tek aroma, standart köz servisi. 60+ aroma seçeneği.', 25000, null, false, false, false],
                ['Premium Nargile', 'Özel karışım aroma, hindistan cevizi közü, buz aparatı dahil.', 35000, 'best', false, false, false],
                ['VIP Nargile (Özel Karışım)', 'Şefin özel aroma karışımı, premium köz, meyve başlığı ve buz aparatı.', 45000, 'chef', false, false, false],
                ['Meyve Başlıklı Nargile', 'Ananas, portakal veya karpuz başlığı ile nargile deneyimi.', 40000, 'best', false, false, false],
                ['Buz Nargile', 'Buzlu nargile deneyimi; mentol aroma, buz aparatı.', 38000, 'new', false, false, false],
            ]],
        ];

        // Diyet etiketleri + alerjen sözlüğünden id haritası
        $dict = Allergen::query()->withoutGlobalScopes()->whereNull('tenant_id')->pluck('id', 'code');

        // Anahtar kelime → alerjen kodu eşlemesi (örnek menü için makul atama)
        $keywordAllergens = [
            'gluten' => ['ekmek', 'börek', 'yufka', 'tost', 'sandviç', 'sandwich', 'wrap', 'pizza', 'burger', 'makarna', 'fettuccine', 'spaghetti', 'penne', 'pancake', 'waffle', 'künefe', 'kruton', 'pita', 'cheesecake', 'sufle', 'tiramisu', 'magnolia', 'lavaş', 'soğan halkası', 'çıtır'],
            'sut' => ['peynir', 'kaşar', 'mozzarella', 'cheddar', 'krema', 'süt', 'tereyağ', 'kaymak', 'latte', 'cappuccino', 'mocha', 'milkshake', 'dondurma', 'mascarpone', 'lor', 'parmesan', 'yoğurt', 'çikolata'],
            'yumurta' => ['yumurta', 'menemen', 'pancake', 'mayonez', 'sufle', 'tiramisu', 'waffle', 'cheesecake'],
            'balik' => ['ton balı', 'balık'],
            'sert-kabuklu' => ['fındık', 'ceviz', 'fıstıklı', 'badem'],
            'susam' => ['tahin', 'humus', 'simit'],
            'hardal' => ['hardal'],
        ];

        $sort = 0;

        foreach ($catalog as [$catName, $catDesc, $catIcon, $groupKeys, $hours, $products]) {
            $category = new Category([
                'name' => $catName,
                'slug' => Str::slug($catName),
                'description' => $catDesc,
                'available_from' => $hours[0],
                'available_until' => $hours[1],
                'sort_order' => (++$sort) * 10,
                'is_active' => true,
            ]);
            $category->tenant_id = $t;
            $category->save();

            foreach ($products as $i => [$name, $desc, $priceMinor, $badge, $veg, $vegan, $gf]) {
                $product = new Product([
                    'name' => $name,
                    'description' => $desc,
                    'category_id' => $category->id,
                    'price_minor' => $priceMinor,
                    'currency' => 'TRY',
                    'tax_rate' => 10.00,
                    'prep_minutes' => 15,
                    'unit' => 'porsiyon',
                    'is_new' => $badge === 'new',
                    'is_chef_pick' => $badge === 'chef',
                    'is_bestseller' => $badge === 'best',
                    'is_active' => true,
                    'is_available' => true,
                    'min_order_qty' => 1,
                    'sort_order' => ($i + 1) * 10,
                ]);
                $product->tenant_id = $t;
                $product->save();

                // Seçenek grupları (28 ekstranın kategori-bazlı karşılığı)
                $sync = [];
                foreach ($groupKeys as $gi => $key) {
                    $sync[$groups[$key]->id] = ['sort_order' => ($gi + 1) * 10];
                }
                $product->optionGroups()->sync($sync);

                // Alerjen + diyet etiketleri
                $ids = [];
                $haystack = Str::lower($name.' '.$desc);
                foreach ($keywordAllergens as $code => $keywords) {
                    foreach ($keywords as $keyword) {
                        if (str_contains($haystack, $keyword)) {
                            $ids[] = $dict[$code];
                            break;
                        }
                    }
                }
                if ($veg) {
                    $ids[] = $dict['vejetaryen'];
                }
                if ($vegan) {
                    $ids[] = $dict['vegan'];
                }
                if ($gf) {
                    $ids[] = $dict['glutensiz'];
                }
                $product->allergens()->sync(array_values(array_unique($ids)));
            }
        }

        /* ---- Menü planları ---- */

        $byName = Category::query()->withoutGlobalScopes()
            ->where('tenant_id', $t)->pluck('id', 'name');

        $menus = [
            ['Kahvaltı Menüsü', 'Sabah servisi', [1, 2, 3, 4, 5, 6, 7], '07:00', '13:00',
                ['Kahvaltılar', 'Sıcak İçecekler', 'Soğuk İçecekler']],
            ['Öğle Menüsü', 'Öğle servisi', [1, 2, 3, 4, 5, 6, 7], '12:00', '17:00',
                ['Başlangıçlar', 'Ana Yemekler', 'Burgerler', 'Pizzalar', 'Makarnalar', 'Salatalar', 'Tostlar & Sandviçler', 'Soğuk İçecekler', 'Sıcak İçecekler']],
            ['Akşam Menüsü', 'Akşam servisi', [1, 2, 3, 4, 5, 6, 7], '17:00', '23:30',
                ['Başlangıçlar', 'Ana Yemekler', 'Burgerler', 'Pizzalar', 'Makarnalar', 'Salatalar', 'Tatlılar', 'Nargile', 'Sıcak İçecekler', 'Soğuk İçecekler']],
            ['Hafta Sonu Tatlı & Kahve', 'Hafta sonu ikindi servisi', [6, 7], '14:00', '19:00',
                ['Tatlılar', 'Sıcak İçecekler', 'Soğuk İçecekler']],
        ];

        foreach ($menus as $mi => [$name, $desc, $days, $start, $end, $catNames]) {
            $menu = new Menu([
                'name' => $name,
                'description' => $desc,
                'days' => $days,
                'start_time' => $start,
                'end_time' => $end,
                'channels' => null, // tüm kanallar
                'sort_order' => ($mi + 1) * 10,
                'is_active' => true,
            ]);
            $menu->tenant_id = $t;
            $menu->save();

            $sync = [];
            foreach (array_values($catNames) as $ci => $cn) {
                if ($byName->has($cn)) {
                    $sync[$byName[$cn]] = ['sort_order' => ($ci + 1) * 10];
                }
            }
            $menu->categories()->sync($sync);
        }
    }
}
