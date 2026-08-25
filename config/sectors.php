<?php

/*
|--------------------------------------------------------------------------
| Sektör sayfaları içeriği (SEO + satış) — slug bazlı, özgün Türkçe içerik
|--------------------------------------------------------------------------
| PageController@show bu kaydı çözer, marketing.sector şablonuyla render eder.
| Her sektör: gerçek operasyon problemleri + BamBumPOS çözümü (kopya değil).
| icon anahtarları: App\Modules\Marketing\Support\Icons.
*/

return [

    'kafe-pos-sistemi' => [
        'name' => 'Kafe', 'label' => 'Kafe POS Sistemi',
        'title' => 'Kafe POS Sistemi — QR Menü, Barista Ekranı ve Hızlı Satış | BamBumPOS',
        'desc' => 'Kafeniz için hepsi bir arada POS: QR menü, barista hazırlık ekranı, hızlı satış, stok ve raporlar. Yoğun saatte sırayı hızlandırın, fireyi azaltın.',
        'hero' => 'Yoğun saatte bile sıra hızlı, kasa doğru, barista düzenli',
        'lead' => 'Kafenizin en kritik anı yoğun saat. BamBumPOS ile QR self-servis, hızlı kasa ve barista hazırlık ekranı sırayı akıcı tutar; siparişler karışmaz, ürün maliyeti gözünüzün önünde kalır.',
        'hero_screen' => 'adisyon', 'hero_badges' => ['Aynı gün kurulum', 'Çevrimdışı çalışır', 'Barista ekranı'],
        'showcases' => [
            ['eyebrow' => 'QR Self-Servis', 'icon' => 'qr', 'screen' => 'qr', 'title' => 'Müşteri sırada beklemeden QR ile sipariş versin', 'body' => 'Masadaki veya sıradaki QR kodu okutan müşteri menüyü görür, sipariş verir ve öder. Kasadaki yük azalır, sıra hızlanır, personeliniz hazırlığa odaklanır.', 'bullets' => ['Temassız sipariş ve ödeme', 'Menü fotoğraflı, TR/EN/DE dilli', 'Sipariş doğrudan baristaya düşer']],
            ['eyebrow' => 'Barista Ekranı', 'icon' => 'coffee', 'screen' => 'adisyon', 'title' => 'Her sipariş baristaya sırayla ve süreli düşsün', 'body' => 'Gelen her içecek barista hazırlık ekranına anında düşer; bekleme süresi renklenir, gecikme görünür olur. Hangi bardağın kime ait olduğu asla karışmaz.', 'bullets' => ['Sipariş sırası ve süre takibi', '“Hazır” işaretiyle teslim netliği', 'Yoğun saatte bile düzen']],
        ],
        'stats' => [['QR ile', 'temassız self-servis'], ['Barista ekranı', 'sıra ve süre görünür'], ['Çevrimdışı', 'internet kesilse de satış'], ['Anlık', 'saatlik yoğunluk raporu']],
        'problems' => [
            ['Yoğun saatte sıra ve karışan siparişler', 'Kalabalıkta el yazısı fişler ve sözlü siparişler karışır, yanlış ürün hazırlanır, müşteri bekler.'],
            ['Barista ile kasa arasında kopukluk', 'Siparişin baristaya ulaşması gecikir, hangi bardağın kimin olduğu belirsizleşir.'],
            ['Ürün maliyeti ve fire takibi yok', 'Süt, çekirdek ve şurup tüketimi ölçülmez; kâr sızıntısı fark edilmez.'],
        ],
        'features' => [
            ['qr', 'QR self-servis', 'Müşteri masadan veya sırada QR ile sipariş verir; kasadaki yük azalır.'],
            ['coffee', 'Barista hazırlık ekranı', 'Her sipariş baristaya anında düşer, süre takibiyle gecikme görünür.'],
            ['bolt', 'Hızlı satış modu', 'Tek dokunuşla favori ürünler, hızlı ödeme ve hesap kapatma.'],
            ['box', 'Reçete & stok', 'Latte satıldığında süt ve çekirdek otomatik düşer, kritik stok uyarısı gelir.'],
            ['chart', 'Saatlik yoğunluk raporu', 'En yoğun saatleri ve en çok satan içecekleri görüp vardiya planlayın.'],
            ['card', 'Markadan bağımsız ödeme', 'Sanal POS, ÖKC ve nakit; tek akışta hızlı tahsilat.'],
        ],
        'modules' => ['QR Menü', 'Barista Ekranı', 'Hızlı Satış', 'Stok & Reçete', 'Sadakat & Puan', 'Saatlik Raporlar'],
        'scenario' => 'Sabah yoğunluğunda müşteri QR ile latte ve filtre söyler; sipariş baristaya düşer, süt stoktan iner. Barista hazırlayıp "hazır" işaretler, komi teslim eder. Gün sonunda en çok satan içecek ve saatlik yoğunluk raporu otomatik oluşur.',
        'faq' => [
            ['Küçük bir kafe için de uygun mu?', 'Evet. Başlangıç paketi tek terminal ve temel modüllerle küçük kafeler için tasarlandı; büyüdükçe modül eklersiniz.'],
            ['Barista ekranı için ayrı cihaz şart mı?', 'Hayır. Tablet veya mevcut bir ekranı barista ekranı olarak kullanabilirsiniz; eklentiyle açılıp kapanır.'],
            ['Sadakat/puan sistemi var mı?', 'Evet, müşteri ve sadakat modülüyle puan ve kampanya tanımlayabilirsiniz.'],
        ],
        'related' => [['Restoran POS Sistemi', '/restoran-pos-sistemi'], ['QR Menü', '/qr-menu'], ['Barista Ekranı', '/barista-ekrani']],
    ],

    'restoran-pos-sistemi' => [
        'name' => 'Restoran', 'label' => 'Restoran POS Sistemi',
        'title' => 'Restoran POS Sistemi — Masa/Adisyon, Kat Planı ve Mutfak Ekranı | BamBumPOS',
        'desc' => 'Restoranınız için masa ve adisyon yönetimi, kat planı, mutfak istasyonları, hesap bölme ve reçete-maliyet takibi. Servisi hızlandırın, hataları azaltın.',
        'hero' => 'Masadan mutfağa, servisten hesaba tek akış',
        'lead' => 'A la carte serviste hız ve doğruluk her şeydir. BamBumPOS ile kat planı, adisyon, mutfak istasyonları ve hesap bölme kusursuz çalışır; garson koşturmaz, mutfak şaşırmaz.',
        'hero_screen' => 'masalar', 'hero_badges' => ['Kat planı', 'Mutfak ekranı (KDS)', 'Hesap bölme'],
        'showcases' => [
            ['eyebrow' => 'Masa & Adisyon', 'icon' => 'grid', 'screen' => 'adisyon', 'title' => 'Kat planında her masa tek bakışta yönetilsin', 'body' => 'Salonunuzu dijital kat planında görün; dolu, boş ve rezerve masalar renkle ayrışır. Garson masadan sipariş alır, yemekler mutfağa, içecekler baristaya otomatik düşer.', 'bullets' => ['Dolu/boş/rezerve renkli masa', 'Kişiye veya ürüne göre hesap bölme', 'İkram, indirim ve masa birleştirme']],
            ['eyebrow' => 'Yönetim & Rapor', 'icon' => 'chart', 'screen' => 'manager', 'title' => 'Ciro, masa devri ve reçete maliyeti anlık görünsün', 'body' => 'Patron panelinde günün cirosu, en çok satan ürünler, masa devir hızı ve tabak maliyeti anlık gelir. Kararlarınızı tahminle değil veriyle verirsiniz.', 'bullets' => ['Anlık ciro ve ürün analizi', 'Reçete/maliyet ve brüt kâr', 'Masa devir hızı ve yoğunluk']],
        ],
        'stats' => [['Kat planı', 'dolu/boş/rezerve renkli'], ['Mutfak (KDS)', 'istasyonlara otomatik'], ['Hesap bölme', 'kişiye/ürüne göre'], ['Anlık rapor', 'masa devir hızı']],
        'problems' => [
            ['Adisyon karmaşası ve kayıp sipariş', 'El yazısı adisyonlar okunmaz, siparişler unutulur, masa yanlışlıkları çıkar.'],
            ['Mutfak-servis kopukluğu', 'Hangi masanın ne beklediği belirsiz; sıcak-soğuk uyumu bozulur.'],
            ['Hesap bölme ve ikram kaosu', 'Kalabalık masalarda hesabı bölmek ve ikramları takip etmek zorlaşır.'],
        ],
        'features' => [
            ['grid', 'Kat planı & masa yönetimi', 'Salonu dijital planlayın; dolu/boş/rezerve masaları renkle görün.'],
            ['flame', 'Mutfak istasyonları (KDS)', 'Yemek mutfağa, içecek baristaya otomatik düşer; süre takibiyle.'],
            ['receipt', 'Adisyon & hesap bölme', 'Kişiye/ürüne göre hesap bölme, birleştirme ve ikram/indirim.'],
            ['box', 'Reçete & maliyet', 'Her tabağın maliyeti ve brüt kârı; fire ve teorik-gerçek stok farkı.'],
            ['calendar', 'Rezervasyon', 'Masa rezervasyonu takvimle; otomatik masa durumu güncellenir.'],
            ['users', 'Garson & yetki', 'Garson uygulaması, rol bazlı yetki ve prim/performans takibi.'],
        ],
        'modules' => ['Masa & Adisyon', 'Kat Planı', 'Mutfak Ekranı', 'Rezervasyon', 'Stok & Reçete', 'Garson Uygulaması', 'Raporlar'],
        'scenario' => 'Garson masadan sipariş alır; yemekler mutfağa, içecekler baristaya düşer. Kat planında masa "dolu" olur. Servis sonrası hesap kişiye göre bölünür, biri ikram edilir. Reçete maliyeti ve masa devir hızı rapora yansır.',
        'faq' => [
            ['Hesabı kişiye göre bölebilir miyim?', 'Evet. Adisyonu kişiye veya ürüne göre bölebilir, ayrı ödeme alabilirsiniz.'],
            ['Mutfakta birden fazla istasyon olabilir mi?', 'Evet. Mutfak, barista, tatlı gibi istasyonlar tanımlayıp siparişleri otomatik yönlendirebilirsiniz.'],
            ['Rezervasyon masayı otomatik meşgul eder mi?', 'Evet, rezervasyon saatinde masa "rezerve" görünür ve isim/saat aralığı yazılır.'],
        ],
        'related' => [['Kafe POS Sistemi', '/kafe-pos-sistemi'], ['Mutfak Ekranı', '/mutfak-ekran-sistemi'], ['Rezervasyon Yönetimi', '/rezervasyon-yonetimi']],
    ],

    'nargile-salonu-pos-sistemi' => [
        'name' => 'Nargile Salonu', 'label' => 'Nargile Salonu POS Sistemi',
        'title' => 'Nargile Salonu POS Sistemi — Nargile Hazırlık Ekranı ve Masa Süre Takibi | BamBumPOS',
        'desc' => 'Nargile salonları için özel POS: nargile hazırlık kulvarı, masa süre/köz takibi, adisyon ve stok. Köz ve tütün israfını azaltın, servisi hızlandırın.',
        'hero' => 'Nargile hazırlığı ayrı kulvarda, köz ve süre kontrol altında',
        'lead' => 'Nargile servisi kendine has bir akıştır. BamBumPOS nargileyi ayrı bir hazırlık ekranına yönlendirir, köz tazeleme ve masa süresini takip eder; mutfak ve bar akışına karışmaz.',
        'hero_screen' => 'adisyon', 'hero_badges' => ['Nargile kulvarı', 'Süre/köz takibi', 'Eklenti aç-kapa'],
        'showcases' => [
            ['eyebrow' => 'Nargile Hazırlık', 'icon' => 'flame', 'screen' => 'adisyon', 'title' => 'Nargile ayrı kulvarda, köz ve süre kontrol altında', 'body' => 'Nargile siparişleri yemek ve içecekten ayrı bir hazırlık ekranına düşer. Hangi masanın közü ne zaman tazelenecek, kim ne kadar oturdu tek ekranda görünür.', 'bullets' => ['Nargile mutfak akışına karışmaz', 'Masa süre ve köz tazeleme takibi', 'Tütün/köz tüketimi stoktan düşer']],
            ['eyebrow' => 'QR Menü', 'icon' => 'qr', 'screen' => 'qr', 'title' => 'Masadan QR ile nargile ve içecek siparişi', 'body' => 'Müşteri masadaki QR ile aroma ve içecek seçip sipariş verir; talep doğrudan ilgili istasyona düşer. Uzun oturmalarda ek sipariş için garson beklenmez.', 'bullets' => ['Fotoğraflı aroma menüsü', 'Ek sipariş tek dokunuş', 'Açık adisyona otomatik eklenir']],
        ],
        'stats' => [['Ayrı kulvar', 'nargile mutfağa karışmaz'], ['Süre & köz', 'masa bazında takip'], ['Tütün/köz', 'stoktan otomatik düşer'], ['Doluluk', 'ortalama oturma süresi']],
        'problems' => [
            ['Nargile siparişi mutfak akışına karışıyor', 'Nargile, yemek ve içecekle aynı listede kaybolur; hazırlık gecikir.'],
            ['Köz tazeleme ve süre takibi elde', 'Hangi masanın közü ne zaman değişecek, kim ne kadar oturdu belirsiz.'],
            ['Tütün ve köz maliyeti ölçülmüyor', 'Sarf malzeme takibi olmadan kâr ve israf görünmez.'],
        ],
        'features' => [
            ['flame', 'Nargile hazırlık ekranı', 'Nargile siparişleri ayrı kulvara düşer; hazırlık ve köz durumu görünür.'],
            ['clock', 'Masa süre & köz takibi', 'Masanın oturma süresi ve köz tazeleme zamanı takip edilir.'],
            ['receipt', 'Adisyon & masa yönetimi', 'Uzun oturmalar için açık adisyon, ikram ve hesap bölme.'],
            ['box', 'Tütün & köz stoğu', 'Sarf malzeme reçetesiyle tütün/köz tüketimi ve maliyet takibi.'],
            ['card', 'Hızlı ödeme', 'Sanal POS, ÖKC ve nakit ile hızlı tahsilat.'],
            ['chart', 'Doluluk & ciro raporu', 'Masa doluluğu, ortalama oturma süresi ve ciro analizi.'],
        ],
        'modules' => ['Nargile Hazırlık Ekranı', 'Masa & Süre Takibi', 'Adisyon', 'Stok (Tütün/Köz)', 'QR Menü', 'Raporlar'],
        'scenario' => 'Müşteri nargile ve çay söyler; nargile hazırlık ekranına, çay baristaya düşer. Hazırlık ekranı köz tazeleme zamanını hatırlatır. Masa süresi ve tütün tüketimi kaydedilir; gün sonu doluluk ve ciro raporu oluşur.',
        'faq' => [
            ['Nargile ekranını kapatabilir miyim?', 'Evet, nargile hazırlık ekranı eklentidir; Ayarlar › Eklentiler’den açıp kapatırsınız.'],
            ['Köz tazeleme hatırlatması var mı?', 'Masa süre takibiyle köz tazeleme zamanını izleyebilirsiniz.'],
            ['Tütün tüketimini stoktan düşer mi?', 'Evet, sarf malzeme reçetesi tanımlayarak tütün ve köz tüketimini otomatik düşebilirsiniz.'],
        ],
        'related' => [['Nargile Hazırlık Ekranı', '/nargile-hazirlik-ekrani'], ['Bar & Pub POS', '/bar-pub-pos-sistemi'], ['Stok Yönetimi', '/stok-yonetimi']],
    ],

    'bar-pub-pos-sistemi' => [
        'name' => 'Bar & Pub', 'label' => 'Bar & Pub POS Sistemi',
        'title' => 'Bar & Pub POS Sistemi — Hızlı Bar Satışı, Adisyon ve Hesap Bölme | BamBumPOS',
        'desc' => 'Bar ve publar için hızlı satış, açık hesap (tab), hesap bölme, happy hour kampanyaları ve içki stok takibi. Yoğun barda hız ve doğruluk.',
        'hero' => 'Yoğun barda saniyeler önemli — hız, açık hesap, doğru stok',
        'lead' => 'Barda kuyruk uzarsa ciro düşer. BamBumPOS hızlı satış, açık hesap (tab) ve tek dokunuş kampanyalarla barmeni hızlandırır; şişe/kadeh stoğunu doğru tutar.',
        'hero_screen' => 'kasa', 'hero_badges' => ['Açık hesap (tab)', 'Happy hour', 'Hızlı satış'],
        'showcases' => [
            ['eyebrow' => 'Hızlı Satış', 'icon' => 'bolt', 'screen' => 'adisyon', 'title' => 'Barmen menüde kaybolmadan saniyede satsın', 'body' => 'En çok satan içkiler tek dokunuşta; müşteri hesabı açık tutulur (tab), happy hour fiyatı saate göre otomatik uygulanır. Kalabalıkta bile kuyruk büyümez.', 'bullets' => ['Favori içkiler tek dokunuş', 'Açık hesap ve grup hesabı bölme', 'Happy hour otomatik fiyat']],
            ['eyebrow' => 'Ciro & Stok', 'icon' => 'chart', 'screen' => 'manager', 'title' => 'Gece sonu ciro ve içki stoğu tek tabloda', 'body' => 'Her kadeh porsiyon reçetesiyle stoktan düşer; fire ve kaçak görünür olur. Gecenin cirosu, en çok satan içkiler ve barmen primi rapora anında yansır.', 'bullets' => ['Kadeh bazında stok düşümü', 'Fire ve kaçak görünürlüğü', 'Barmen prim ve performansı']],
        ],
        'stats' => [['Açık hesap', 'tek seferde tahsil'], ['Happy hour', 'saate bağlı otomatik'], ['Kadeh stoğu', 'porsiyon bazında düşer'], ['Çevrimdışı', 'yoğun barda kesintisiz']],
        'problems' => [
            ['Yoğunlukta yavaş satış', 'Uzun menüde ürün aramak barmeni yavaşlatır, kuyruk uzar.'],
            ['Açık hesap ve hesap bölme zorluğu', 'Müşteri hesabı açık tutmak ve grup hesabını bölmek karışır.'],
            ['İçki stok ve fire kaçağı', 'Şişe ve kadeh takibi zayıfsa fire ve kayıp fark edilmez.'],
        ],
        'features' => [
            ['bolt', 'Hızlı satış & favoriler', 'En çok satan içkiler tek dokunuş; barmen menüde kaybolmaz.'],
            ['receipt', 'Açık hesap (tab)', 'Müşteri hesabını açık tutun, kapanışta tek seferde tahsil edin.'],
            ['tag', 'Happy hour & kampanya', 'Saate bağlı fiyat ve kampanyalar otomatik uygulanır.'],
            ['box', 'İçki stoğu & porsiyon', 'Şişe/kadeh reçetesiyle tüketim düşer, kritik stok uyarısı gelir.'],
            ['users', 'Barmen yetki & vardiya', 'Rol bazlı yetki, vardiya ve prim takibi.'],
            ['card', 'Hızlı ödeme & bölme', 'Grup hesabını bölme ve markadan bağımsız hızlı tahsilat.'],
        ],
        'modules' => ['Hızlı Satış', 'Açık Hesap', 'Kampanya', 'Stok', 'Vardiya & Prim', 'Raporlar'],
        'scenario' => 'Müşteri barda hesap açar; barmen tek dokunuşla içkileri ekler, happy hour fiyatı otomatik uygulanır. Kadeh stoktan düşer. Gece sonunda hesap bölünüp tahsil edilir; barmen primi hesaplanır.',
        'faq' => [
            ['Açık hesabı masaya bağlayabilir miyim?', 'Evet, hesabı müşteri veya masa bazında açık tutup kapanışta tahsil edebilirsiniz.'],
            ['Happy hour otomatik mi çalışır?', 'Evet, kampanya modülüyle saate bağlı fiyat ve indirimleri otomatik tanımlarsınız.'],
            ['Kadeh bazında stok düşer mi?', 'Evet, porsiyon reçetesiyle şişeden kadeh bazında tüketim düşebilirsiniz.'],
        ],
        'related' => [['Nargile Salonu POS', '/nargile-salonu-pos-sistemi'], ['Kampanya Yönetimi', '/kampanya-yonetimi'], ['Stok Yönetimi', '/stok-yonetimi']],
    ],

    'fast-food-pos-sistemi' => [
        'name' => 'Fast Food', 'label' => 'Fast Food POS Sistemi',
        'title' => 'Fast Food POS Sistemi — Sayaç Satışı, Kiosk ve Paket Sipariş | BamBumPOS',
        'desc' => 'Fast food için hızlı sayaç satışı, self servis kiosk, mutfak ekranı ve paket sipariş entegrasyonu. Sıra numarası ile teslimi hızlandırın.',
        'hero' => 'Sayaçta hız, kioskla self servis, mutfakta düzen',
        'lead' => 'Fast food’da servis hızı doğrudan ciroyu belirler. BamBumPOS sayaç satışını, kioskları ve paket siparişi tek mutfağa bağlar; sıra numarasıyla teslim karışmaz.',
        'hero_screen' => 'kiosk', 'hero_badges' => ['Sayaç & kiosk', 'Sıra numarası', 'Paket sipariş'],
        'showcases' => [
            ['eyebrow' => 'Sayaç & Kiosk', 'icon' => 'store', 'screen' => 'adisyon', 'title' => 'Sayaçta ve kioskta hızlı, hatasız sipariş', 'body' => 'Menü, kombo ve ekstralar tek ekranda; sayaçta saniyeler önemli. Self servis kioskla müşteri kendi siparişini verip öder, kasadaki darboğaz açılır.', 'bullets' => ['Kombo ve ekstralar tek ekranda', 'Self servis kioskla kısa kuyruk', 'Kartla temassız hızlı ödeme']],
            ['eyebrow' => 'Tek Mutfak', 'icon' => 'qr', 'screen' => 'qr', 'title' => 'Salon, kiosk ve paket tek mutfakta buluşsun', 'body' => 'Hangi kanaldan gelirse gelsin tüm siparişler tek mutfağa düşer ve sıra numarasıyla teslim edilir. Paket ile salon siparişi asla birbirine karışmaz.', 'bullets' => ['Tüm kanallar tek mutfakta', 'Sıra numarasıyla teslim', 'Paket ve salon ayrımı nettir']],
        ],
        'stats' => [['Self kiosk', 'kasadaki yük azalır'], ['Sıra no', 'teslim karışmaz'], ['Paket', 'tek akışta toplanır'], ['Hız raporu', 'ortalama hazırlık süresi']],
        'problems' => [
            ['Sayaçta yavaş sipariş', 'Menü kombinasyonları ve ekstralar sayaçta zaman kaybettirir.'],
            ['Paket ve salon karışması', 'Salon, kiosk ve paket siparişleri mutfakta karışır, teslim şaşar.'],
            ['Yoğunlukta personel yetmiyor', 'Pik saatte kasa darboğaz olur; kiosk olmadan sıra uzar.'],
        ],
        'features' => [
            ['store', 'Hızlı sayaç satışı', 'Menü, kombo ve ekstralar tek ekranda; hızlı ödeme.'],
            ['grid', 'Self servis kiosk', 'Müşteri kioskta sipariş verip öder; kasadaki yük azalır.'],
            ['flame', 'Mutfak ekranı & sıra no', 'Tüm kanallar tek mutfağa; sıra numarasıyla teslim.'],
            ['truck', 'Paket sipariş', 'Telefon ve platform siparişleri tek akışta, kurye atamasıyla.'],
            ['card', 'Kartla hızlı ödeme', 'Kioskta ve sayaçta sanal POS/ÖKC ile temassız ödeme.'],
            ['chart', 'Yoğunluk & hız raporu', 'Ortalama hazırlık süresi ve saatlik yoğunlukla vardiya planı.'],
        ],
        'modules' => ['Sayaç Satışı', 'Kiosk', 'Mutfak Ekranı', 'Paket Sipariş', 'Kurye', 'Raporlar'],
        'scenario' => 'Müşteri kioskta menü seçip kartla öder; sipariş sıra numarasıyla mutfağa düşer. Aynı anda paket sipariş de aynı mutfağa gelir. Hazır olunca ekranda numara çağrılır; teslim karışmaz.',
        'faq' => [
            ['Kiosk zorunlu mu?', 'Hayır, kiosk eklentidir. Sayaç satışıyla başlayıp sonra kiosk ekleyebilirsiniz.'],
            ['Paket platformlarıyla çalışır mı?', 'Paket sipariş modülüyle telefon ve online siparişleri tek akışta yönetirsiniz; desteklenen platformlar entegrasyonlar sayfasında.'],
            ['Sıra numarası ekranı var mı?', 'Evet, hazır siparişler sıra numarasıyla teslim ekranında gösterilir.'],
        ],
        'related' => [['Self Servis Kiosk', '/self-servis-kiosk'], ['Paket Sipariş Yönetimi', '/paket-siparis-yonetimi'], ['Mutfak Ekranı', '/mutfak-ekran-sistemi']],
    ],

    'otel-pos-sistemi' => [
        'name' => 'Otel & Sosyal Tesis', 'label' => 'Otel & Sosyal Tesis POS Sistemi',
        'title' => 'Otel & Sosyal Tesis POS Sistemi — Çoklu Nokta ve Oda/Üye Hesabı | BamBumPOS',
        'desc' => 'Otel ve sosyal tesisler için çok noktalı POS: restoran, bar, havuz ve lobi tek sistemde; oda/üye hesabına aktarım ve konsolide tesis raporu.',
        'hero' => 'Restoran, bar, havuz — tüm noktalar tek sistemde',
        'lead' => 'Otel ve tesislerde satış birden çok noktada olur. BamBumPOS restoran, bar, havuz ve lobiyi tek sisteme bağlar; harcamaları oda veya üye hesabına aktarır, tesis genelini raporlar.',
        'hero_screen' => 'subeler', 'hero_badges' => ['Çoklu nokta', 'Oda/üye hesabı', 'Konsolide rapor'],
        'showcases' => [
            ['eyebrow' => 'Çoklu Nokta', 'icon' => 'branch', 'screen' => 'manager', 'title' => 'Restoran, bar ve havuz tek panelde toplansın', 'body' => 'Tüm satış noktaları tek menü altyapısı ve tek panelde yönetilir. Misafirin havuz barındaki harcaması oda hesabına yazılır, çıkışta tek faturada toplanır.', 'bullets' => ['Nokta bazlı menü ve fiyat', 'Harcama oda/üye hesabına aktarılır', 'Çıkışta tek konsolide fatura']],
            ['eyebrow' => 'Personel & Yetki', 'icon' => 'users', 'screen' => 'personel', 'title' => 'Her nokta için ayrı ekip ve yetki tanımlansın', 'body' => 'Nokta yöneticisi, garson ve kasiyer için ayrı yetki seviyeleri tanımlarsınız. Kim hangi noktada ne yapabilir nettir; tüm kritik işlemler kayıt altındadır.', 'bullets' => ['Rol bazlı erişim ve işlem kaydı', 'Nokta bazlı personel ve vardiya', 'Merkezi stok ve transfer']],
        ],
        'stats' => [['Çoklu nokta', 'tek menü altyapısı'], ['Oda/üye', 'harcama hesaba aktarılır'], ['Konsolide', 'nokta bazlı ciro'], ['Merkezi stok', 'noktalar arası transfer']],
        'problems' => [
            ['Noktalar arası dağınık satış', 'Restoran, bar ve havuz ayrı sistemlerde; bütünsel görünüm yok.'],
            ['Oda/üye hesabına aktarım zorluğu', 'Misafirin harcamasını odaya veya üyeye yazmak elle ve hatalı.'],
            ['Konsolide rapor eksikliği', 'Tesis genelinin cirosu ve nokta karşılaştırması görünmez.'],
        ],
        'features' => [
            ['branch', 'Çoklu satış noktası', 'Restoran, bar, havuz, lobi — tek panelde, tek menü altyapısı.'],
            ['bed', 'Oda / üye hesabı', 'Harcamayı oda veya üye hesabına aktarın, çıkışta tek fatura.'],
            ['chart', 'Konsolide tesis raporu', 'Nokta bazlı ve toplam ciro, karşılaştırma ve trend.'],
            ['users', 'Rol & yetki', 'Nokta yöneticisi, garson ve kasiyer için ayrı yetkiler.'],
            ['box', 'Merkezi stok', 'Noktalar arası stok görünürlüğü ve transfer.'],
            ['card', 'Esnek ödeme', 'Nakit, kart, oda/üye hesabı ve kurumsal fatura.'],
        ],
        'modules' => ['Çoklu Nokta', 'Oda/Üye Hesabı', 'Merkezi Stok', 'Yetkilendirme', 'Konsolide Rapor', 'Rezervasyon'],
        'scenario' => 'Misafir havuz barında içecek alır, harcama oda hesabına yazılır. Akşam restoranda yemek yer, aynı hesaba eklenir. Çıkışta tek faturada toplanır; tesis genelinin gün sonu cirosu nokta bazında raporlanır.',
        'faq' => [
            ['Oda hesabına aktarım PMS ile mi çalışır?', 'Harcamaları oda/üye hesabında toplayabilirsiniz; PMS entegrasyonu ihtiyaca göre değerlendirilir.'],
            ['Her nokta ayrı menü kullanabilir mi?', 'Evet, merkezi altyapıda her noktaya özel menü ve fiyat tanımlayabilirsiniz.'],
            ['Üyeli sosyal tesis için uygun mu?', 'Evet, üye hesabı ve üyeye özel fiyat/indirim tanımlanabilir.'],
        ],
        'related' => [['Sosyal Tesis POS', '/sosyal-tesis-pos-sistemi'], ['Çoklu Şube Yönetimi', '/coklu-sube-yonetimi'], ['Satış Raporları', '/satis-raporlari']],
    ],

    'sosyal-tesis-pos-sistemi' => [
        'name' => 'Sosyal Tesis', 'label' => 'Sosyal Tesis POS Sistemi',
        'title' => 'Sosyal Tesis POS Sistemi — Üye Hesabı, Çoklu Nokta ve Raporlama | BamBumPOS',
        'desc' => 'Kurum ve dernek sosyal tesisleri için üyeye özel fiyat, üye hesabı/cari, çok noktalı satış ve şeffaf konsolide raporlama.',
        'hero' => 'Üyeye özel fiyat, şeffaf hesap, denetlenebilir raporlar',
        'lead' => 'Sosyal tesislerde üye memnuniyeti ve şeffaflık esastır. BamBumPOS üyeye özel fiyat, üye cari hesabı ve rol bazlı yetkiyle satışı düzenler; yönetim kuruluna net raporlar sunar.',
        'hero_screen' => 'manager', 'hero_badges' => ['Üye cari', 'Denetim/log', 'Konsolide rapor'],
        'showcases' => [
            ['eyebrow' => 'Üye & Cari', 'icon' => 'users', 'screen' => 'personel', 'title' => 'Üyeye özel fiyat, cari bakiye ve ekstre', 'body' => 'Üye grubuna göre özel fiyat tanımlar, harcamayı üye cari hesabına yazarsınız. Ay sonunda üyeye ekstre çıkar; bakiye ve dönemsel hareket şeffaf görünür.', 'bullets' => ['Üye grubuna özel fiyat', 'Cari bakiye ve dönemsel ekstre', 'Nakit, kart veya cariye yazma']],
            ['eyebrow' => 'Denetim & Rapor', 'icon' => 'shield', 'screen' => 'manager', 'title' => 'Yönetim kuruluna denetlenebilir, şeffaf tablo', 'body' => 'Her iptal, ikram ve indirim kullanıcı ve zaman bilgisiyle loglanır. Yönetime nokta ve dönem bazlı konsolide ciro raporu sunulur; hiçbir işlem gölgede kalmaz.', 'bullets' => ['Tüm kritik işlemler loglanır', 'Nokta ve dönem bazlı rapor', 'Rol bazlı sınırlı yetki']],
        ],
        'stats' => [['Üye cari', 'bakiye ve ekstre'], ['Denetim', 'tüm işlemler loglanır'], ['Çoklu nokta', 'lokal/çay ocağı tek panel'], ['Şeffaf', 'yönetime konsolide rapor']],
        'problems' => [
            ['Üye fiyatı ve cari takibi zor', 'Üyeye özel fiyat ve borç/alacak takibi elle yürür, hata olur.'],
            ['Şeffaflık ve denetim ihtiyacı', 'Yönetim ciroyu ve harcamaları denetlenebilir görmek ister.'],
            ['Çok noktalı dağınık satış', 'Lokal, çay ocağı ve tesis noktaları ayrı ayrı yönetilir.'],
        ],
        'features' => [
            ['users', 'Üye hesabı & cari', 'Üyeye özel fiyat, cari bakiye ve dönemsel ekstre.'],
            ['branch', 'Çoklu nokta', 'Lokal, çay ocağı ve tesis noktaları tek panelde.'],
            ['shield', 'Denetim & işlem kaydı', 'Her işlem loglanır; iptal/ikram/indirim izlenebilir.'],
            ['chart', 'Konsolide rapor', 'Yönetim için nokta ve dönem bazlı şeffaf raporlar.'],
            ['lock', 'Rol bazlı yetki', 'Yönetim, kasiyer ve görevli için ayrı yetki seviyeleri.'],
            ['card', 'Esnek ödeme', 'Nakit, kart ve üye cari hesabına yazma.'],
        ],
        'modules' => ['Üye Hesabı & Cari', 'Çoklu Nokta', 'Yetki & Denetim', 'Kampanya', 'Konsolide Rapor', 'Stok'],
        'scenario' => 'Üye lokalde çay içer, harcama üye cari hesabına yazılır. Ay sonunda üyeye ekstre çıkar. Tüm iptal ve ikramlar loglanır; yönetim kuruluna dönemsel şeffaf ciro raporu sunulur.',
        'faq' => [
            ['Üyeye özel fiyat tanımlanabilir mi?', 'Evet, üye grubuna göre özel fiyat ve indirim tanımlayabilirsiniz.'],
            ['Üye borç/alacak takibi var mı?', 'Evet, üye cari hesabıyla bakiye takibi ve dönemsel ekstre alınır.'],
            ['İşlemler denetlenebilir mi?', 'Evet, tüm kritik işlemler kullanıcı ve zaman bilgisiyle loglanır.'],
        ],
        'related' => [['Otel & Sosyal Tesis POS', '/otel-pos-sistemi'], ['Müşteri & Sadakat', '/musteri-sadakat'], ['Satış Raporları', '/satis-raporlari']],
    ],

    'paket-servis-pos-sistemi' => [
        'name' => 'Paket Servis', 'label' => 'Paket Servis POS Sistemi',
        'title' => 'Paket Servis POS Sistemi — Telefon/Online Sipariş, Kurye ve Bölge | BamBumPOS',
        'desc' => 'Paket servis için telefon ve online sipariş, arayan kimliği, kayıtlı adres, kurye atama, teslimat bölgesi ve sipariş durumu takibi.',
        'hero' => 'Telefondan kuryeye kadar tek akışta paket servis',
        'lead' => 'Paket serviste hız ve doğru adres kârı belirler. BamBumPOS telefon ve online siparişi, müşteri geçmişini, kurye atamasını ve bölge yönetimini tek akışta toplar.',
        'hero_screen' => 'adisyon', 'hero_badges' => ['Arayan kimliği', 'Kurye atama', 'Bölge yönetimi'],
        'showcases' => [
            ['eyebrow' => 'Telefon & Adres', 'icon' => 'phone', 'screen' => 'adisyon', 'title' => 'Arayanı tanı, kayıtlı adresle saniyede sipariş aç', 'body' => 'Telefon çaldığında arayan kimliği müşteriyi ve kayıtlı adresini getirir; geçmiş siparişiyle giriş saniyeler sürer. Yanlış adres ve gecikme ortadan kalkar.', 'bullets' => ['Arayan numarası müşteri kartını açar', 'Kayıtlı adres ve geçmiş sipariş', 'Bölgeye göre ücret ve min. sepet']],
            ['eyebrow' => 'Durum & Rapor', 'icon' => 'chart', 'screen' => 'manager', 'title' => 'Sipariş “yolda”, bölge performansı tabloda', 'body' => 'Sipariş alındı → hazırlanıyor → yolda → teslim adımlarıyla takip edilir; kurye atanır. Bölge, saat ve kurye bazında performans raporlanır, darboğazlar görünür olur.', 'bullets' => ['Şeffaf sipariş durumu takibi', 'Kurye atama ve teslim durumu', 'Bölge ve saat bazında ciro analizi']],
        ],
        'stats' => [['Arayan kimliği', 'müşteri ve adres otomatik'], ['Kurye', 'atama ve durum takibi'], ['Bölge', 'ücret ve min. sepet'], ['Durum', 'alındı → yolda → teslim']],
        'problems' => [
            ['Telefon siparişinde adres ve hata', 'Adres ve sipariş elle yazılır, yanlış teslim ve gecikme olur.'],
            ['Kurye atama ve takip zorluğu', 'Hangi kurye nerede, hangi sipariş nerede belirsiz.'],
            ['Bölge ve minimum sepet karmaşası', 'Teslimat ücreti ve minimum sepet elle hesaplanır.'],
        ],
        'features' => [
            ['phone', 'Telefon siparişi & arayan kimliği', 'Arayanı tanı, geçmiş sipariş ve kayıtlı adresle hızlı giriş.'],
            ['truck', 'Kurye atama & takip', 'Siparişe kurye ata, durumu ve teslimatı takip et.'],
            ['globe', 'Teslimat bölgesi', 'Bölgeye göre ücret, minimum sepet ve teslimat süresi.'],
            ['receipt', 'Sipariş durumu', 'Alındı → hazırlanıyor → yolda → teslim; müşteriye şeffaflık.'],
            ['store', 'Online sipariş sayfası', 'Kendi online sipariş kanalınız, tek mutfağa bağlı.'],
            ['chart', 'Bölge & ciro raporu', 'Bölge, saat ve kurye bazında performans analizi.'],
        ],
        'modules' => ['Telefon Siparişi', 'Online Sipariş', 'Kurye Yönetimi', 'Teslimat Bölgesi', 'Müşteri Geçmişi', 'Raporlar'],
        'scenario' => 'Telefon çalar, arayan kimliği müşteriyi ve kayıtlı adresini getirir. Sipariş bölgeye göre teslimat ücretiyle oluşur, mutfağa düşer. Hazır olunca kurye atanır; müşteri "yolda" durumunu görür.',
        'faq' => [
            ['Arayan kimliği için ne gerekir?', 'Uygun santral/telefon entegrasyonuyla arayan numarası müşteri kartını açar; detay entegrasyonlar sayfasında.'],
            ['Kurye konumu takip edilir mi?', 'Kurye atama ve teslim durumu takip edilir; canlı konum ihtiyaca göre değerlendirilir.'],
            ['Bölgeye göre ücret tanımlanır mı?', 'Evet, teslimat bölgesi, ücreti ve minimum sepeti tanımlayabilirsiniz.'],
        ],
        'related' => [['Kurye Yönetimi', '/kurye-yonetimi'], ['Online Sipariş', '/online-siparis'], ['Fast Food POS', '/fast-food-pos-sistemi']],
    ],

    'cok-subeli-restoran-yonetimi' => [
        'name' => 'Çok Şubeli', 'label' => 'Çok Şubeli Restoran Yönetimi',
        'title' => 'Çok Şubeli Restoran Yönetimi — Merkezi Menü, Şube Karşılaştırma, Stok Transferi | BamBumPOS',
        'desc' => 'Zincir ve çok şubeli işletmeler için merkezi menü, şubeye özel fiyat, şubeler arası stok transferi, konsolide rapor ve franchise yönetimi.',
        'hero' => 'Tüm şubeleri tek merkezden yönetin, tek tabloda görün',
        'lead' => 'Şube sayısı arttıkça kontrol zorlaşır. BamBumPOS merkezi menü, şubeye özel fiyat, stok transferi ve konsolide raporla tüm zinciri tek panelden yönetmenizi sağlar.',
        'hero_screen' => 'raporlar', 'hero_badges' => ['Merkezi menü', 'Şube karşılaştırma', 'Stok transferi'],
        'showcases' => [
            ['eyebrow' => 'Merkezi Yönetim', 'icon' => 'layers', 'screen' => 'manager', 'title' => 'Menü ve fiyatı merkezden, tüm şubelere anında', 'body' => 'Yeni bir ürünü veya fiyatı merkezden tanımlarsınız; tüm şubelere anında yansır. Bir şube için özel fiyat veya istisna tanımlamak tek tıktır. Standart hiç bozulmaz.', 'bullets' => ['Merkezi menü ve reçete', 'Şubeye özel fiyat ve istisna', 'Değişiklik anında yansır']],
            ['eyebrow' => 'Şube Karşılaştırma', 'icon' => 'branch', 'screen' => 'personel', 'title' => 'Hangi şube nasıl gidiyor, tek tabloda görün', 'body' => 'Şube bazlı ciro, sağlık durumu ve karşılaştırmalı tablo tek panelde. Bir şubenin stoğu azalınca diğerinden transfer açılır; bölge müdürü sınırlı yetkiyle yönetir.', 'bullets' => ['Şube bazlı ciro ve karşılaştırma', 'Şubeler arası stok transferi', 'Bölge/franchise için rol bazlı yetki']],
        ],
        'stats' => [['Merkezi menü', 'şubeye anında yansır'], ['Karşılaştırma', 'şube bazlı ciro'], ['Stok transfer', 'şubeler arası'], ['Rol/bölge', 'franchise yetkisi']],
        'problems' => [
            ['Şubeler arası tutarsızlık', 'Menü, fiyat ve reçeteler şubeden şubeye kayar; standart bozulur.'],
            ['Merkez görünürlüğü yok', 'Hangi şube nasıl gidiyor, gerçek zamanlı görmek zor.'],
            ['Stok transferi ve franchise kontrolü', 'Şubeler arası stok ve franchise yetkileri elle yönetilir.'],
        ],
        'features' => [
            ['layers', 'Merkezi menü & fiyat', 'Menüyü merkezden yönetin, şubeye özel fiyat/istisna tanımlayın.'],
            ['branch', 'Şube karşılaştırma', 'Şube bazlı ciro, sağlık durumu ve karşılaştırmalı tablo.'],
            ['box', 'Şubeler arası stok transferi', 'Stok görünürlüğü ve şubeler arası transfer akışı.'],
            ['lock', 'Rol & bölge yetkileri', 'Şube yöneticisi, bölge müdürü ve franchise için ayrı yetkiler.'],
            ['chart', 'Konsolide rapor', 'Tüm zincirin toplam ve şube kırılımlı raporları.'],
            ['shield', 'Denetim & standart', 'İşlem kayıtları ve merkezi kontrolle standardı koruyun.'],
        ],
        'modules' => ['Merkezi Menü', 'Şubeye Özel Fiyat', 'Stok Transferi', 'Bölge/Franchise Yetkisi', 'Konsolide Rapor', 'Kampanya'],
        'scenario' => 'Merkez yeni bir menü ürününü tanımlar; tüm şubelere anında yansır, bir şube için özel fiyat verilir. Bir şubenin stoğu azalınca diğerinden transfer açılır. Bölge müdürü konsolide raporda şubeleri karşılaştırır.',
        'faq' => [
            ['Şubeye özel fiyat verebilir miyim?', 'Evet, menü merkezden yönetilir; şube bazında fiyat ve istisna tanımlanır.'],
            ['Franchise şubeleri sınırlı yetkiyle yönetebilir miyim?', 'Evet, bölge müdürü ve franchise için rol bazlı sınırlı yetkiler tanımlanır.'],
            ['Şubeler arası stok transferi var mı?', 'Evet, stok görünürlüğü ve şubeler arası transfer akışı desteklenir.'],
        ],
        'related' => [['Satış Raporları', '/satis-raporlari'], ['Çoklu Şube Yönetimi', '/coklu-sube-yonetimi'], ['Stok Yönetimi', '/stok-yonetimi']],
    ],

];
