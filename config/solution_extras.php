<?php

/*
|--------------------------------------------------------------------------
| Çözüm sayfaları — EK içerik (hero animasyonlu ekran + kazanç şeridi + showcase)
|--------------------------------------------------------------------------
| PageController, solutions.$slug ile birleştirir (array_merge).
|   hero_screen / screen : GERÇEK panel ekranı (alana özel — tekrar minimum):
|     siparisler masalar mutfak raporlar dashboard personel stok kasa
|     rezervasyon menu vardiya subeler entegrasyonlar kiosk qr(telefon)
|   stats : [[num,label], ...]  (DÜRÜST ürün nitelikleri — uydurma sayı YOK)
*/

return [

    'mobil-pos' => [
        'hero_screen' => 'siparisler',
        'stats' => [['Elde satış', 'masada sipariş + ödeme'], ['Çevrimdışı', 'internet kesilse de çalışır'], ['Tek ekran', 'sipariş, mutfak, ödeme'], ['Hızlı', 'PIN ile personel girişi']],
        'showcases' => [
            ['eyebrow' => 'Elde POS', 'icon' => 'phone', 'screen' => 'kasa', 'title' => 'Kasaya gitmeden, masada sipariş ve ödeme', 'body' => 'Garson tablet veya telefonla masadan sipariş alır, mutfağa gönderir ve ödemeyi masada tahsil eder. Kuyruk ve koşuşturma biter.', 'bullets' => ['Masada sipariş, mutfağa anında', 'Masada kartlı/nakit tahsilat', 'İnternetsiz de kesintisiz satış']],
        ],
    ],

    'qr-menu' => [
        'hero_screen' => 'qr',
        'stats' => [['Temassız', 'QR ile self-servis'], ['3 dil', 'TR · EN · DE menü'], ['Görsel menü', 'fotoğraf + varyant + alerjen'], ['Anlık', 'sipariş istasyona düşer']],
        'showcases' => [
            ['eyebrow' => 'Self-Servis', 'icon' => 'qr', 'screen' => 'menu', 'title' => 'Müşteri masadan kendi diliyle sipariş versin', 'body' => 'QR’ı okutan misafir fotoğraflı menüden seçer, varyant/ekstra ekler, garson çağırır ve hesap ister. Sipariş doğrudan mutfağa/baristaya düşer.', 'bullets' => ['Fotoğraflı, çok dilli menü', 'Garson çağır & hesap iste', 'Markanıza özel görünüm']],
        ],
    ],

    'online-siparis' => [
        'hero_screen' => 'qr',
        'stats' => [['Kendi kanalınız', 'komisyonsuz online sipariş'], ['Tek mutfak', 'tüm kanallar birleşir'], ['Durum takibi', 'alındı → yolda → teslim'], ['Bölge', 'ücret ve min. sepet']],
        'showcases' => [
            ['eyebrow' => 'Online Sipariş', 'icon' => 'store', 'screen' => 'siparisler', 'title' => 'Kendi online sipariş kanalınız, tek mutfağa bağlı', 'body' => 'Müşteri sitenizden sipariş verir; talep aynı mutfağa düşer, komisyon ödemezsiniz. Teslimat bölgesi, ücreti ve minimum sepet sizin kontrolünüzde.', 'bullets' => ['Komisyonsuz kendi kanalı', 'Salon ve paketle tek akış', 'Şeffaf sipariş durumu']],
        ],
    ],

    'self-servis-kiosk' => [
        'hero_screen' => 'kiosk',
        'stats' => [['Kısa kuyruk', 'müşteri kendi sipariş verir'], ['Yüksek sepet', 'öneri ve upsell'], ['Kartlı ödeme', 'kioskta temassız'], ['Tek mutfak', 'sıra numarasıyla teslim']],
        'showcases' => [
            ['eyebrow' => 'Kiosk', 'icon' => 'grid', 'screen' => 'qr', 'title' => 'Müşteri kioskta seçsin, ödesin, beklemesin', 'body' => 'Self servis kioskla pik saatte kasadaki darboğaz açılır; müşteri menüyü inceler, ekler, kartla öder. Sipariş sıra numarasıyla mutfağa düşer.', 'bullets' => ['Pik saatte kısa kuyruk', 'Öneri ile daha yüksek sepet', 'Sıra numarasıyla teslim']],
        ],
    ],

    'garson-uygulamasi' => [
        'hero_screen' => 'masalar',
        'stats' => [['Elde adisyon', 'masadan mutfağa'], ['Az hata', 'sözlü sipariş yok'], ['Hesap bölme', 'kişiye/ürüne göre'], ['Prim', 'garson performansı']],
        'showcases' => [
            ['eyebrow' => 'Garson', 'icon' => 'users', 'screen' => 'siparisler', 'title' => 'Garson koşturmadan, masadan mutfağa tek dokunuş', 'body' => 'Sipariş masada alınır, yemek mutfağa içecek baristaya otomatik gider. El yazısı adisyon ve sözlü sipariş karışıklığı biter.', 'bullets' => ['Masadan istasyona otomatik', 'Kişiye göre hesap bölme', 'Rol bazlı yetki ve prim']],
        ],
    ],

    'mutfak-ekran-sistemi' => [
        'hero_screen' => 'mutfak',
        'stats' => [['KDS', 'sipariş ekranda, kâğıt yok'], ['Süre takibi', 'gecikme renklenir'], ['İstasyon', 'mutfak/barista/tatlı'], ['Az hata', 'net sipariş akışı']],
        'showcases' => [
            ['eyebrow' => 'Mutfak Ekranı', 'icon' => 'flame', 'screen' => 'siparisler', 'title' => 'Siparişler mutfağa net ve sırayla düşsün', 'body' => 'Her sipariş ilgili istasyona (mutfak, barista, tatlı) otomatik gider; hazırlık süresi renk kodlarıyla takip edilir. Kâğıt fiş ve karışıklık ortadan kalkar.', 'bullets' => ['İstasyonlara otomatik yönlendirme', 'Hazırlık süresi ve gecikme uyarısı', '“Hazır” ile servise net teslim']],
        ],
    ],

    'barista-ekrani' => [
        'hero_screen' => 'menu',
        'stats' => [['Barista kulvarı', 'içecekler ayrı ekranda'], ['Süre', 'bekleme görünür'], ['Sıra', 'hangi bardak kimin'], ['Reçete', 'süt/çekirdek stoktan düşer']],
        'showcases' => [
            ['eyebrow' => 'Barista', 'icon' => 'coffee', 'screen' => 'siparisler', 'title' => 'İçecek siparişleri baristaya sırayla ve süreli', 'body' => 'Her içecek barista hazırlık ekranına anında düşer; bekleme süresi görünür, hangi bardağın kime ait olduğu asla karışmaz.', 'bullets' => ['İçecekler ayrı hazırlık kulvarı', 'Süre takibiyle gecikme uyarısı', 'Reçeteyle otomatik stok düşümü']],
        ],
    ],

    'nargile-hazirlik-ekrani' => [
        'hero_screen' => 'masalar',
        'stats' => [['Ayrı kulvar', 'nargile mutfağa karışmaz'], ['Köz/süre', 'masa bazında takip'], ['Stok', 'tütün/köz düşer'], ['Eklenti', 'aç/kapa']],
        'showcases' => [
            ['eyebrow' => 'Nargile', 'icon' => 'flame', 'screen' => 'siparisler', 'title' => 'Nargile hazırlığı ayrı kulvarda, köz ve süre kontrolde', 'body' => 'Nargile siparişleri yemek/içecekten ayrı bir hazırlık ekranına düşer; köz tazeleme zamanı ve masa süresi izlenir, tütün tüketimi stoktan iner.', 'bullets' => ['Yemek/bar akışına karışmaz', 'Köz tazeleme ve süre takibi', 'Tütün/köz stok düşümü']],
        ],
    ],

    'paket-siparis-yonetimi' => [
        'hero_screen' => 'siparisler',
        'stats' => [['Tek adisyon', 'tüm kanallar toplanır'], ['Arayan kimliği', 'müşteri + adres'], ['Durum', 'alındı → yolda → teslim'], ['Kurye', 'atama ve takip']],
        'showcases' => [
            ['eyebrow' => 'Paket Sipariş', 'icon' => 'truck', 'screen' => 'raporlar', 'title' => 'Telefon ve online paket siparişi tek akışta', 'body' => 'Telefon ve online siparişler tek adisyonda toplanır; arayan kimliğiyle müşteri ve adres saniyede gelir, sipariş mutfağa düşer, kurye atanır.', 'bullets' => ['Arayan kimliği + kayıtlı adres', 'Tüm kanallar tek mutfakta', 'Şeffaf durum ve kurye takibi']],
        ],
    ],

    'kurye-yonetimi' => [
        'hero_screen' => 'raporlar',
        'stats' => [['Kurye atama', 'siparişe kurye'], ['Durum', 'yolda/teslim'], ['Bölge', 'performans analizi'], ['Hız', 'teslim süresi']],
        'showcases' => [
            ['eyebrow' => 'Kurye', 'icon' => 'truck', 'screen' => 'siparisler', 'title' => 'Hangi kurye nerede, hangi sipariş nerede — net', 'body' => 'Siparişe kurye atarsınız, teslim durumunu takip edersiniz; bölge, saat ve kurye bazında performansı raporlarsınız. Darboğazlar görünür olur.', 'bullets' => ['Siparişe kurye atama', 'Teslim durumu takibi', 'Bölge/saat/kurye performansı']],
        ],
    ],

    'rezervasyon-yonetimi' => [
        'hero_screen' => 'rezervasyon',
        'stats' => [['Takvim', 'masa rezervasyonu'], ['Otomatik', 'masa rezerve olur'], ['İsim/saat', 'masada görünür'], ['Doluluk', 'plan ve rapor']],
        'showcases' => [
            ['eyebrow' => 'Rezervasyon', 'icon' => 'calendar', 'screen' => 'masalar', 'title' => 'Rezervasyon masayı otomatik meşgul etsin', 'body' => 'Takvimden alınan rezervasyon, saatinde masayı “rezerve” yapar; isim ve saat aralığı masada görünür. Çift rezervasyon ve boş masa karmaşası biter.', 'bullets' => ['Takvimle masa rezervasyonu', 'Masa durumu otomatik güncellenir', 'İsim ve saat masada görünür']],
        ],
    ],

    'personel-yonetimi' => [
        'hero_screen' => 'personel',
        'stats' => [['Vardiya', 'plan ve mesai'], ['Prim', 'performansa göre'], ['PIN', 'hızlı personel girişi'], ['Yetki', 'rol bazlı erişim']],
        'showcases' => [
            ['eyebrow' => 'Personel', 'icon' => 'users', 'screen' => 'vardiya', 'title' => 'Vardiya, mesai ve primi tek yerden yönetin', 'body' => 'Vardiya planı, mesai takibi ve performansa dayalı prim tek panelde. PIN ile hızlı giriş, rol bazlı yetkiyle kim ne yapabilir nettir.', 'bullets' => ['Vardiya planı ve mesai takibi', 'Performansa dayalı prim', 'PIN girişi + rol bazlı yetki']],
        ],
    ],

    'stok-yonetimi' => [
        'hero_screen' => 'stok',
        'stats' => [['Otomatik düşüm', 'satıştan stoğa'], ['Reçete', 'ürün maliyeti'], ['Kritik uyarı', 'tükenmeden haber'], ['Fire', 'teorik-gerçek fark']],
        'showcases' => [
            ['eyebrow' => 'Stok', 'icon' => 'box', 'screen' => 'menu', 'title' => 'Sattıkça stok kendiliğinden düşsün, fire görünsün', 'body' => 'Reçeteyle her satış hammaddeyi otomatik düşer; kritik seviyede uyarı gelir, teorik ve gerçek stok farkıyla fire ortaya çıkar.', 'bullets' => ['Satıştan otomatik stok düşümü', 'Kritik stok uyarısı', 'Reçete/maliyet ve fire takibi']],
        ],
    ],

    'on-muhasebe' => [
        'hero_screen' => 'kasa',
        'stats' => [['Gelir/gider', 'tek panelde'], ['Cari', 'müşteri/tedarikçi'], ['Kasa', 'gün sonu net'], ['Aktarım', 'e-belge süreçlerine']],
        'showcases' => [
            ['eyebrow' => 'Ön Muhasebe', 'icon' => 'chart', 'screen' => 'raporlar', 'title' => 'Ciro, gider ve cariyi tek panelden görün', 'body' => 'Satış geliri, giderler ve cari hesaplar tek yerde toplanır; gün sonu kasa net çıkar, veriler e-belge/muhasebe süreçlerinize aktarılır.', 'bullets' => ['Gelir-gider ve cari takibi', 'Gün sonu kasa mutabakatı', 'Muhasebe/e-belgeye aktarım']],
        ],
    ],

    'coklu-sube-yonetimi' => [
        'hero_screen' => 'subeler',
        'stats' => [['Merkezi menü', 'şubeye anında'], ['Karşılaştırma', 'şube bazlı ciro'], ['Stok transfer', 'şubeler arası'], ['Yetki', 'bölge/franchise']],
        'showcases' => [
            ['eyebrow' => 'Çoklu Şube', 'icon' => 'branch', 'screen' => 'raporlar', 'title' => 'Tüm şubeleri tek merkezden yönetin, tek tabloda görün', 'body' => 'Menü ve fiyatı merkezden yönetir, şubeye özel istisna tanımlarsınız; şube cirolarını karşılaştırır, şubeler arası stok transferi açarsınız.', 'bullets' => ['Merkezi menü + şubeye özel fiyat', 'Şube karşılaştırma ve konsolide rapor', 'Şubeler arası stok transferi']],
        ],
    ],

    'satis-raporlari' => [
        'hero_screen' => 'raporlar',
        'stats' => [['Anlık', 'ciro ve ürün'], ['Trend', 'saat/gün/ürün'], ['Masa', 'devir ve doluluk'], ['Karar', 'veriye dayalı']],
        'showcases' => [
            ['eyebrow' => 'Raporlar', 'icon' => 'chart', 'screen' => 'dashboard', 'title' => 'Cironuzu, ürünlerinizi ve masayı anlık görün', 'body' => 'Günün cirosu, en çok satanlar, saatlik yoğunluk ve masa devir hızı anlık gelir. Kararlarınızı tahminle değil, veriyle verirsiniz.', 'bullets' => ['Anlık ciro ve ürün analizi', 'Saatlik yoğunluk ve trend', 'Masa devir hızı ve doluluk']],
        ],
    ],

    'musteri-sadakat' => [
        'hero_screen' => 'qr',
        'stats' => [['Puan', 'kazan-harca'], ['Segment', 'sık gelen müşteri'], ['Kampanya', 'kişiye özel'], ['Geri dönüş', 'tekrar ziyaret']],
        'showcases' => [
            ['eyebrow' => 'Sadakat', 'icon' => 'tag', 'screen' => 'menu', 'title' => 'Müşteriyi puan ve kampanyayla geri getirin', 'body' => 'Puan kazan-harca, müşteri segmentleri ve kişiye özel kampanyalarla tekrar eden ziyaret oluşturursunuz; kim ne kadar geliyor görünür olur.', 'bullets' => ['Puan/sadakat programı', 'Müşteri segmentleri', 'Kişiye özel kampanya']],
        ],
    ],

    'kampanya-yonetimi' => [
        'hero_screen' => 'menu',
        'stats' => [['Otomatik', 'saate bağlı fiyat'], ['Happy hour', 'zaman kampanyası'], ['Kombo', 'menü/indirim'], ['Ölçüm', 'kampanya etkisi']],
        'showcases' => [
            ['eyebrow' => 'Kampanya', 'icon' => 'megaphone', 'screen' => 'raporlar', 'title' => 'Kampanya ve happy hour otomatik uygulansın', 'body' => 'Saate bağlı fiyat, kombo ve indirim kampanyalarını tanımlarsınız; kasada otomatik uygulanır. Kampanyanın satışa etkisini raporla ölçersiniz.', 'bullets' => ['Saate bağlı otomatik fiyat', 'Kombo ve indirim kuralları', 'Kampanya etkisi raporu']],
        ],
    ],

    'uretim-recete' => [
        'hero_screen' => 'stok',
        'stats' => [['Reçete', 'ürün maliyeti'], ['Brüt kâr', 'tabak bazında'], ['Yarı mamul', 'üretim takibi'], ['Fire', 'kayıp görünür']],
        'showcases' => [
            ['eyebrow' => 'Reçete & Üretim', 'icon' => 'box', 'screen' => 'menu', 'title' => 'Her ürünün maliyetini ve kârını görün', 'body' => 'Reçeteyle her ürünün hammadde maliyeti ve brüt kârı hesaplanır; yarı mamul üretimi ve fire takibiyle gizli kâr sızıntısı ortaya çıkar.', 'bullets' => ['Reçete ve ürün maliyeti', 'Tabak bazında brüt kâr', 'Yarı mamul ve fire takibi']],
        ],
    ],

    'tedarikci-yonetimi' => [
        'hero_screen' => 'entegrasyonlar',
        'stats' => [['Tedarikçi', 'cari ve sipariş'], ['Alım', 'fiyat geçmişi'], ['Stok', 'girişle güncellenir'], ['Ödeme', 'borç takibi']],
        'showcases' => [
            ['eyebrow' => 'Tedarikçi', 'icon' => 'truck', 'screen' => 'stok', 'title' => 'Tedarikçi siparişi, alım ve borcu tek yerde', 'body' => 'Tedarikçi cari hesabı, alım siparişleri ve fiyat geçmişini yönetirsiniz; mal girişi stoğu günceller, ödeme/borç takibi net tutulur.', 'bullets' => ['Tedarikçi cari ve sipariş', 'Alım fiyatı geçmişi', 'Mal girişi → stok güncelleme']],
        ],
    ],

];
