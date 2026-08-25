<?php

/*
|--------------------------------------------------------------------------
| Çözüm sayfaları içeriği (SEO + satış) — slug bazlı, özgün Türkçe içerik
|--------------------------------------------------------------------------
| PageController@solution çözer, marketing.solution şablonuyla render eder.
| Her çözüm: hero, 3 fayda, özellikler, adım-adım, SSS, ilgili çözümler.
| 'shot' (opsiyonel): gerçek ürün ekran görüntüsü dosyası (yoksa dashboard mockup).
| icon anahtarları: App\Modules\Marketing\Support\Icons.
*/

return [

    'mobil-pos' => [
        'label' => 'Mobil POS', 'icon' => 'phone',
        'title' => 'Mobil POS — Elde Satış ve Adisyon | BamBumPOS',
        'desc' => 'Telefon veya tablette elde satış: masadan sipariş alın, ödeme alın, adisyonu anında güncelleyin. Kasaya bağımlılığı azaltın, servisi hızlandırın.',
        'hero' => 'Kasayı masaya taşıyın — elde satış ve anlık adisyon',
        'lead' => 'Garson veya işletmeci telefonu/tableti eline alır; masadan sipariş girer, ürün istasyona düşer, ödeme masada alınır. Kuyruk ve koşuşturma azalır.',
        'benefits' => [
            ['zap', 'Daha hızlı servis', 'Sipariş masada girilir, mutfağa anında düşer; masa devir hızı artar.'],
            ['card', 'Masada ödeme', 'Adisyonu masada kapatın; kasa kuyruğunu azaltın.'],
            ['shield', 'Daha az hata', 'Sözlü sipariş ve el yazısı fiş yerine dijital, doğru kayıt.'],
        ],
        'features' => [
            ['phone', 'Elde sipariş & adisyon', 'Telefon/tablette masa seç, ürün ekle, not ve varyant gir.'],
            ['flame', 'İstasyona otomatik yönlendirme', 'Yemek mutfağa, içecek baristaya anında düşer.'],
            ['card', 'Masada tahsilat', 'Nakit, kart ve QR ile masada hızlı ödeme.'],
            ['users', 'Rol bazlı yetki', 'Garson yalnız kendi yetkisiyle işlem yapar; hassas eylemde PIN.'],
        ],
        'steps' => [
            ['Masayı seç', 'Cihazdan masayı seçip adisyonu açarsınız.'],
            ['Siparişi gir', 'Ürünleri, varyant ve notları ekler, istasyona gönderirsiniz.'],
            ['Ödemeyi al', 'Servis sonrası masada tahsil edip adisyonu kapatırsınız.'],
        ],
        'faq' => [
            ['Hangi cihazlarda çalışır?', 'Modern Android/iOS telefon ve tabletlerde tarayıcı üzerinden çalışır; ayrı uygulama kurulumu gerekmez.'],
            ['İnternet kesilirse ne olur?', 'Bağlantı gelince kaldığınız yerden devam edersiniz; veriler bulutta güvenli tutulur.'],
        ],
        'related' => [['Garson Uygulaması', '/garson-uygulamasi'], ['QR Menü', '/qr-menu'], ['Satış Raporları', '/satis-raporlari']],
    ],

    'qr-menu' => [
        'label' => 'QR Menü & Sipariş', 'icon' => 'qr', 'shot' => 'phone-menu',
        'title' => 'QR Menü ve Sipariş — Masadan Self Servis | BamBumPOS',
        'desc' => 'Karekodlu dijital menü: müşteri masadan kendi diliyle sipariş verir, garson çağırır, hesap ister. Alerjen ve varyant bilgisiyle, markanıza özel görünümde.',
        'hero' => 'Müşteriniz masadan, kendi dilinde sipariş versin',
        'lead' => 'Karekodu okutan misafir menüyü görür, varyant ve ekstra seçer, sepete ekler; sipariş doğrudan istasyona düşer. Garson yükü azalır, satış artar.',
        'benefits' => [
            ['zap', 'Daha hızlı sipariş', 'Müşteri beklemeden sipariş verir; garson yükü azalır.'],
            ['globe', 'Çoklu dil', 'TR / EN / DE menü; turist yoğun mekânlar için ideal.'],
            ['trend', 'Daha yüksek sepet', 'Görsel menü ve önerilerle ortalama sepet artar.'],
        ],
        'features' => [
            ['qr', 'Dijital menü & kategori', 'Kategori, ürün, varyant, ekstra ve alerjen bilgisi.'],
            ['bell', 'Garson çağır & hesap iste', 'Masadan tek dokunuşla garson çağırma ve hesap isteme.'],
            ['clock', 'Sipariş durumu', 'Alındı → hazırlanıyor → hazır; müşteriye şeffaflık.'],
            ['store', 'Markanıza özel görünüm', 'Logo, renk ve vitrin bilgileriyle size ait bir menü.'],
        ],
        'steps' => [
            ['Karekodu okut', 'Müşteri masadaki karekodu telefonuyla okutur.'],
            ['Menüden seç', 'Kategori, varyant ve ekstraları seçip sepete ekler.'],
            ['Gönder & takip et', 'Sipariş istasyona düşer; müşteri durumu takip eder.'],
        ],
        'faq' => [
            ['Müşteri uygulama indirir mi?', 'Hayır. Karekodu okutunca menü tarayıcıda açılır; kurulum gerekmez.'],
            ['Menü İngilizce/Almanca görünür mü?', 'Evet, dil seçiciyle arayüz seçilen dilde görünür; ürün adları sizin girdiğiniz gibidir.'],
            ['QR menü ödeme alır mı?', 'Sipariş akışı esastır; ödeme yapılandırmanıza göre masada veya online tahsil edilir.'],
        ],
        'related' => [['Online Sipariş', '/online-siparis'], ['Mobil POS', '/mobil-pos'], ['Kafe POS Sistemi', '/kafe-pos-sistemi']],
    ],

    'online-siparis' => [
        'label' => 'Online Sipariş', 'icon' => 'globe',
        'title' => 'Online Sipariş — Kendi Sipariş Kanalınız | BamBumPOS',
        'desc' => 'Kendi online sipariş sayfanız: web üzerinden gelen siparişler tek mutfağa bağlanır, komisyonsuz kendi kanalınızdan satış yaparsınız.',
        'hero' => 'Komisyonsuz kendi online sipariş kanalınız',
        'lead' => 'Kendi markanıza ait online sipariş sayfasıyla müşteri doğrudan sizden sipariş verir; siparişler tek akışta mutfağa ve pakete düşer.',
        'benefits' => [
            ['tag', 'Komisyonsuz satış', 'Platform komisyonu olmadan kendi kanalınızdan satış.'],
            ['layers', 'Tek mutfak akışı', 'Online, salon ve paket siparişler aynı ekranda birleşir.'],
            ['store', 'Marka sizin', 'Kendi adınıza, kendi menünüzle satış yaparsınız.'],
        ],
        'features' => [
            ['globe', 'Web sipariş sayfası', 'Menü, sepet ve teslimat/gel-al seçenekleriyle.'],
            ['truck', 'Teslimat & gel-al', 'Bölgeye göre ücret ve minimum sepet tanımı.'],
            ['card', 'Online ödeme', 'Sanal POS ile güvenli online tahsilat.'],
            ['chart', 'Kanal raporu', 'Online satışın toplam ciroya katkısını görün.'],
        ],
        'steps' => [
            ['Menünü yayınla', 'Menü ve teslimat bölgelerini tanımlayıp sayfanı yayınlarsın.'],
            ['Sipariş gelsin', 'Müşteri sayfadan sipariş verir; mutfağa düşer.'],
            ['Hazırla & teslim et', 'Sipariş hazırlanır, kuryeye atanır veya gel-al ile teslim edilir.'],
        ],
        'faq' => [
            ['Paket platformlarından farkı ne?', 'Kendi kanalınız komisyonsuzdur ve müşteri verisi sizde kalır; platformlar ayrıca entegre edilebilir.'],
            ['Online ödeme zorunlu mu?', 'Hayır, kapıda ödeme veya online ödemeyi birlikte sunabilirsiniz.'],
        ],
        'related' => [['QR Menü', '/qr-menu'], ['Paket Sipariş Yönetimi', '/paket-siparis-yonetimi'], ['Kurye Yönetimi', '/kurye-yonetimi']],
    ],

    'self-servis-kiosk' => [
        'label' => 'Self Servis Kiosk', 'icon' => 'kiosk',
        'title' => 'Self Servis Kiosk — Dokunmatik Sipariş | BamBumPOS',
        'desc' => 'Dokunmatik self servis kiosk: müşteri kendi siparişini verip öder, kasadaki yük azalır, ürün önerileriyle sepet büyür.',
        'hero' => 'Sırayı kısaltın — self servis kiosk ile',
        'lead' => 'Müşteri kioskta menüyü gezip siparişini oluşturur ve kartla öder; sipariş sıra numarasıyla mutfağa düşer. Yoğun saatte kasa darboğazı biter.',
        'benefits' => [
            ['zap', 'Kısa kuyruk', 'Kasadaki yük dağılır; pik saatte hız artar.'],
            ['trend', 'Sepet büyütme', 'Ürün önerileri ve menü kombinleriyle daha yüksek sepet.'],
            ['globe', 'Çoklu dil', 'Turist ve karma müşteri kitlesi için çok dilli arayüz.'],
        ],
        'features' => [
            ['kiosk', 'Dokunmatik menü', 'Kategori, kombo ve ekstralarla akıcı sipariş.'],
            ['card', 'Kartla ödeme', 'Temassız kart ve sanal POS ile self ödeme.'],
            ['bell', 'Sıra numarası', 'Hazır sipariş numarayla teslim ekranında çağrılır.'],
            ['megaphone', 'Öneri & kampanya', 'Uygun ürün önerileri ve kampanyalarla satış artışı.'],
        ],
        'steps' => [
            ['Menüden seç', 'Müşteri kioskta ürünleri ve ekstraları seçer.'],
            ['Kartla öde', 'Temassız kartla ödeme yapar.'],
            ['Numarayla al', 'Sipariş hazır olunca numarayla teslim alınır.'],
        ],
        'faq' => [
            ['Kiosk donanımı gerekli mi?', 'Dokunmatik ekran ve ödeme cihazıyla çalışır; mevcut donanımlarınıza uyum sağlanır.'],
            ['Kiosk zorunlu mu?', 'Hayır, eklentidir. Sayaç satışıyla başlayıp sonradan ekleyebilirsiniz.'],
        ],
        'related' => [['Fast Food POS', '/fast-food-pos-sistemi'], ['Mutfak Ekranı', '/mutfak-ekran-sistemi'], ['Kampanya Yönetimi', '/kampanya-yonetimi']],
    ],

    'garson-uygulamasi' => [
        'label' => 'Garson Uygulaması', 'icon' => 'users',
        'title' => 'Garson Uygulaması — El Terminali Sipariş | BamBumPOS',
        'desc' => 'Garson el terminali: masadan sipariş alın, istasyona anında gönderin, hesap bölün. Koşuşturmayı azaltın, servis hatasını bitirin.',
        'hero' => 'Garson koşuşturmasın — sipariş masada, mutfakta anında',
        'lead' => 'Garson siparişi masada telefon/tabletten girer; ürün doğru istasyona düşer, gecikme takibi yapılır. Kağıt adisyon ve kayıp sipariş sorunu biter.',
        'benefits' => [
            ['zap', 'Hızlı servis', 'Masadan mutfağa sıfır adım; sipariş anında düşer.'],
            ['shield', 'Sıfır kayıp sipariş', 'Dijital adisyonla unutulan/karışan sipariş biter.'],
            ['receipt', 'Kolay hesap bölme', 'Kişiye/ürüne göre hesap bölme ve ikram.'],
        ],
        'features' => [
            ['users', 'Masa & adisyon', 'Masa seç, ürün ekle, not ve varyant gir.'],
            ['flame', 'İstasyon yönlendirme', 'Yemek/içecek/nargile doğru kulvara düşer.'],
            ['receipt', 'Hesap böl & ikram', 'Kişi bazlı bölme, ikram ve indirim.'],
            ['bell', 'Servis çağrıları', 'Masa çağrıları garsona anında bildirilir.'],
        ],
        'steps' => [
            ['Masayı aç', 'Garson masayı seçip adisyonu açar.'],
            ['Siparişi gönder', 'Ürünleri girip istasyona gönderir.'],
            ['Servis & hesap', 'Hazır ürünü servis eder, hesabı böler/kapatır.'],
        ],
        'faq' => [
            ['Garson yetkisi sınırlanabilir mi?', 'Evet, rol bazlı yetkiyle garson yalnız izinli işlemleri yapar; hassas eylemlerde PIN sorulur.'],
            ['Kaç garson aynı anda çalışır?', 'Paketinize göre birden çok cihaz eşzamanlı çalışır.'],
        ],
        'related' => [['Mobil POS', '/mobil-pos'], ['Mutfak Ekranı', '/mutfak-ekran-sistemi'], ['Restoran POS Sistemi', '/restoran-pos-sistemi']],
    ],

    'mutfak-ekran-sistemi' => [
        'label' => 'Mutfak Ekranı (KDS)', 'icon' => 'chef', 'shot' => 'app-mutfak',
        'title' => 'Mutfak Ekran Sistemi (KDS) — Sipariş İstasyonları | BamBumPOS',
        'desc' => 'Mutfak ekranı (KDS): siparişler istasyonlara otomatik düşer, süre ve renkle gecikme takip edilir, hazır ürün komiye iletilir. Kağıt fiş biter.',
        'hero' => 'Mutfakta düzen — hiçbir sipariş kaybolmaz',
        'lead' => 'Her sipariş tanımına göre doğru istasyona düşer; süre takibiyle gecikmeler renklenir. Hazır ürünler komi ekranına iletilir, kağıt fiş karmaşası biter.',
        'benefits' => [
            ['clock', 'Süre takibi', 'Gecikmeler renk ve süreyle görünür; müşteri beklemez.'],
            ['layers', 'İstasyon ayrımı', 'Mutfak, ızgara, tatlı ve fırın ayrı kulvarlarda.'],
            ['shield', 'Kağıtsız & doğru', 'Kağıt fiş yerine dijital, kaybolmayan sipariş akışı.'],
        ],
        'features' => [
            ['chef', 'İstasyon filtreleri', 'Her istasyon yalnız kendi siparişlerini görür.'],
            ['clock', 'Gecikme uyarısı', 'Süre aşımı renkle vurgulanır; öncelik netleşir.'],
            ['shield', 'Alerjen & reçete', 'Sipariş üzerinde alerjen ve reçete bilgisi.'],
            ['bell', 'Komiye iletim', 'Hazır ürün komi ekranına düşer, servis işaretlenir.'],
        ],
        'steps' => [
            ['Sipariş düşer', 'Garson/QR/kiosk siparişi ilgili istasyona iner.'],
            ['Kabul & hazırla', 'İstasyon siparişi kabul eder, hazırlar.'],
            ['Hazır işaretle', 'Hazır ürün komiye iletilir ve servis edilir.'],
        ],
        'faq' => [
            ['Kaç istasyon tanımlanır?', 'Mutfak, ızgara, tatlı, fırın gibi ihtiyacınız kadar istasyon tanımlayabilirsiniz.'],
            ['Ayrı ekran şart mı?', 'Tablet veya mevcut bir ekran KDS olarak kullanılabilir.'],
        ],
        'related' => [['Barista Ekranı', '/barista-ekrani'], ['Nargile Hazırlık Ekranı', '/nargile-hazirlik-ekrani'], ['Restoran POS Sistemi', '/restoran-pos-sistemi']],
    ],

    'barista-ekrani' => [
        'label' => 'Barista Ekranı', 'icon' => 'coffee',
        'title' => 'Barista Ekranı — İçecek Hazırlık Kulvarı | BamBumPOS',
        'desc' => 'İçecekler için ayrı barista ekranı: kahve ve içecek siparişleri kendi kulvarında hazırlanır, süt/çekirdek stoğu düşer, hız artar.',
        'hero' => 'İçecekler baristada, mutfaktan bağımsız',
        'lead' => 'İçecek siparişleri baristaya ayrı bir kulvarda düşer; barista mutfak akışına karışmadan hazırlar, süre takibiyle gecikme görünür.',
        'benefits' => [
            ['zap', 'Hızlı içecek servisi', 'Barista sadece içeceklere odaklanır; hız artar.'],
            ['box', 'Otomatik stok', 'Süt, çekirdek ve şurup tüketimi reçeteyle düşer.'],
            ['clock', 'Gecikme takibi', 'Süreyle gecikme görünür, sıcak-soğuk uyumu korunur.'],
        ],
        'features' => [
            ['coffee', 'İçecek kulvarı', 'Kahve ve içecek siparişleri ayrı ekranda.'],
            ['clock', 'Süre & öncelik', 'Hazırlık süresi ve öncelik takibi.'],
            ['box', 'Reçete & stok', 'Latte satıldığında süt ve çekirdek otomatik düşer.'],
            ['bell', 'Hazır bildirimi', 'Hazır içecek komiye/garsona iletilir.'],
        ],
        'steps' => [
            ['İçecek düşer', 'İçecek siparişi baristaya iner.'],
            ['Hazırla', 'Barista hazırlar, stok otomatik düşer.'],
            ['Servis et', 'Hazır içecek servis için işaretlenir.'],
        ],
        'faq' => [
            ['Barista ekranı kapatılabilir mi?', 'Evet, eklentidir; ihtiyacınıza göre açıp kapatabilirsiniz.'],
            ['Süt/çekirdek stoğu nasıl düşer?', 'Ürün reçetesi tanımlayarak tüketimi otomatik stoktan düşebilirsiniz.'],
        ],
        'related' => [['Kafe POS Sistemi', '/kafe-pos-sistemi'], ['Mutfak Ekranı', '/mutfak-ekran-sistemi'], ['Stok Yönetimi', '/stok-yonetimi']],
    ],

    'nargile-hazirlik-ekrani' => [
        'label' => 'Nargile Hazırlık Ekranı', 'icon' => 'flame',
        'title' => 'Nargile Hazırlık Ekranı — Köz ve Süre Takibi | BamBumPOS',
        'desc' => 'Nargile için ayrı hazırlık ekranı: nargile siparişleri kendi kulvarında hazırlanır, köz tazeleme ve masa süresi takip edilir, tütün stoğu düşer.',
        'hero' => 'Nargile kendi kulvarında — köz ve süre kontrol altında',
        'lead' => 'Nargile siparişleri mutfak ve bar akışına karışmadan ayrı bir ekrana düşer; köz tazeleme zamanı ve masa süresi takip edilir.',
        'benefits' => [
            ['layers', 'Ayrı kulvar', 'Nargile, yemek ve içecekten bağımsız hazırlanır.'],
            ['clock', 'Köz & süre takibi', 'Köz tazeleme zamanı ve oturma süresi izlenir.'],
            ['box', 'Sarf takibi', 'Tütün ve köz tüketimi reçeteyle stoktan düşer.'],
        ],
        'features' => [
            ['flame', 'Nargile kulvarı', 'Nargile siparişleri ayrı ekranda görünür.'],
            ['clock', 'Köz tazeleme', 'Köz değişim zamanını hatırlatır.'],
            ['box', 'Tütün/köz stoğu', 'Sarf malzeme reçetesiyle tüketim düşer.'],
            ['bell', 'Hazır bildirimi', 'Hazır nargile servis için işaretlenir.'],
        ],
        'steps' => [
            ['Nargile düşer', 'Sipariş nargile hazırlık ekranına iner.'],
            ['Hazırla & köz', 'Hazırlanır; köz tazeleme takip edilir.'],
            ['Servis et', 'Hazır nargile servis için işaretlenir.'],
        ],
        'faq' => [
            ['Bu ekran zorunlu mu?', 'Hayır, nargile eklentisiyle açılır; nargile satmayan işletmelerde kapalıdır.'],
            ['Masada süre takibi var mı?', 'Evet, masanın oturma süresi ve köz zamanı izlenebilir.'],
        ],
        'related' => [['Nargile Salonu POS', '/nargile-salonu-pos-sistemi'], ['Mutfak Ekranı', '/mutfak-ekran-sistemi'], ['Stok Yönetimi', '/stok-yonetimi']],
    ],

    'paket-siparis-yonetimi' => [
        'label' => 'Paket Sipariş Yönetimi', 'icon' => 'box',
        'title' => 'Paket Sipariş Yönetimi — Telefon ve Online Sipariş | BamBumPOS',
        'desc' => 'Paket sipariş akışı: telefon ve online siparişleri tek ekranda toplayın, müşteri geçmişi ve adresle hızlı girin, kuryeye atayın.',
        'hero' => 'Tüm paket siparişler tek akışta',
        'lead' => 'Telefon, online ve platform siparişleri tek ekranda toplanır; arayan kimliği ve kayıtlı adresle hızlı giriş, kuryeye atama ve durum takibi yapılır.',
        'benefits' => [
            ['zap', 'Hızlı sipariş girişi', 'Arayan kimliği ve kayıtlı adresle saniyeler içinde.'],
            ['layers', 'Tek ekran', 'Telefon, online ve platform siparişleri birleşir.'],
            ['truck', 'Kolay teslimat', 'Kuryeye atama ve durum takibiyle şeffaflık.'],
        ],
        'features' => [
            ['phone', 'Telefon & arayan kimliği', 'Arayanı tanı, geçmiş sipariş ve adresle hızlı giriş.'],
            ['box', 'Sipariş durumu', 'Alındı → hazırlanıyor → yolda → teslim.'],
            ['truck', 'Kurye atama', 'Siparişe kurye ata, teslimatı takip et.'],
            ['globe', 'Teslimat bölgesi', 'Bölgeye göre ücret ve minimum sepet.'],
        ],
        'steps' => [
            ['Sipariş al', 'Telefon/online sipariş tek ekranda oluşur.'],
            ['Hazırla', 'Sipariş mutfağa düşer, hazırlanır.'],
            ['Kuryeye ver', 'Kurye atanır; müşteri "yolda" durumunu görür.'],
        ],
        'faq' => [
            ['Platform siparişleri entegre olur mu?', 'Paket sipariş platformları entegrasyonlar sayfasındaki desteğe göre bağlanabilir.'],
            ['Arayan kimliği için ne gerekir?', 'Uygun santral/telefon entegrasyonuyla arayan numarası müşteri kartını açar.'],
        ],
        'related' => [['Kurye Yönetimi', '/kurye-yonetimi'], ['Online Sipariş', '/online-siparis'], ['Paket Servis POS', '/paket-servis-pos-sistemi']],
    ],

    'kurye-yonetimi' => [
        'label' => 'Kurye Yönetimi', 'icon' => 'truck',
        'title' => 'Kurye Yönetimi — Atama ve Teslimat Takibi | BamBumPOS',
        'desc' => 'Kurye yönetimi: siparişe kurye atayın, teslimat durumunu ve bölgesini takip edin, performansı raporlayın. Teslimatı hızlandırın.',
        'hero' => 'Doğru kurye, doğru bölge, takipli teslimat',
        'lead' => 'Paket siparişlere kurye atar, teslimat durumunu ve bölgesini izlersiniz; kurye performansı ve bölge yoğunluğu raporlanır.',
        'benefits' => [
            ['truck', 'Hızlı atama', 'Siparişi uygun kuryeye hızla atarsınız.'],
            ['globe', 'Bölge yönetimi', 'Teslimat bölgesi, ücreti ve süresi netdir.'],
            ['chart', 'Performans', 'Kurye ve bölge bazında teslim performansı.'],
        ],
        'features' => [
            ['truck', 'Kurye atama', 'Siparişe kurye ata, durumu güncelle.'],
            ['globe', 'Teslimat bölgesi', 'Bölgeye göre ücret ve minimum sepet.'],
            ['clock', 'Teslim durumu', 'Yolda ve teslim edildi durum takibi.'],
            ['chart', 'Kurye raporu', 'Teslim sayısı ve süresi bazında analiz.'],
        ],
        'steps' => [
            ['Sipariş hazır', 'Paket sipariş hazırlanır.'],
            ['Kurye ata', 'Uygun kurye atanır.'],
            ['Teslim & kapat', 'Teslimat işaretlenir; rapora yansır.'],
        ],
        'faq' => [
            ['Kurye konumu takip edilir mi?', 'Atama ve teslim durumu takip edilir; canlı konum ihtiyaca göre değerlendirilir.'],
            ['Bölgeye göre ücret olur mu?', 'Evet, teslimat bölgesi ve ücretini tanımlayabilirsiniz.'],
        ],
        'related' => [['Paket Sipariş Yönetimi', '/paket-siparis-yonetimi'], ['Online Sipariş', '/online-siparis'], ['Paket Servis POS', '/paket-servis-pos-sistemi']],
    ],

    'rezervasyon-yonetimi' => [
        'label' => 'Rezervasyon Yönetimi', 'icon' => 'calendar',
        'title' => 'Rezervasyon Yönetimi — Masa ve Takvim | BamBumPOS',
        'desc' => 'Masa rezervasyonu: takvimle rezervasyon alın, masa otomatik "rezerve" olsun, isim ve saat aralığı görünsün. Boş masa karışıklığı bitsin.',
        'hero' => 'Masalarınızı takvimle yönetin, karışıklığı bitirin',
        'lead' => 'Rezervasyon takvimle alınır; rezervasyon saatinde masa otomatik "rezerve" görünür, isim ve saat aralığı yazılır. Çift rezervasyon ve boş masa karmaşası biter.',
        'benefits' => [
            ['calendar', 'Takvimli rezervasyon', 'Gün ve saat bazında net rezervasyon.'],
            ['grid', 'Otomatik masa durumu', 'Rezervasyon saatinde masa "rezerve" olur.'],
            ['users', 'İsim & kişi sayısı', 'Rezervasyonda isim, saat aralığı ve kişi sayısı.'],
        ],
        'features' => [
            ['calendar', 'Rezervasyon takvimi', 'Günlük/haftalık rezervasyon görünümü.'],
            ['grid', 'Masa entegrasyonu', 'Rezervasyon masa panosuna renkle yansır.'],
            ['bell', 'Hatırlatma', 'Yaklaşan rezervasyonlar öne çıkar.'],
            ['chart', 'Doluluk analizi', 'Rezervasyon ve doluluk trendleri.'],
        ],
        'steps' => [
            ['Rezervasyonu al', 'İsim, saat ve kişi sayısıyla rezervasyon oluştur.'],
            ['Masa rezerve olsun', 'İlgili masa otomatik "rezerve" görünür.'],
            ['Misafiri karşıla', 'Rezervasyon saatinde masa hazırdır.'],
        ],
        'faq' => [
            ['Rezervasyon masayı otomatik meşgul eder mi?', 'Evet, rezervasyon saatinde masa "rezerve" görünür ve isim/saat yazılır.'],
            ['Çift rezervasyon engellenir mi?', 'Aynı masa/saat için çakışma görünür kılınır.'],
        ],
        'related' => [['Restoran POS Sistemi', '/restoran-pos-sistemi'], ['Müşteri & Sadakat', '/musteri-sadakat'], ['Satış Raporları', '/satis-raporlari']],
    ],

    'personel-yonetimi' => [
        'label' => 'Personel Yönetimi', 'icon' => 'users',
        'title' => 'Personel & Vardiya Yönetimi — Prim, Maaş ve İzin | BamBumPOS',
        'desc' => 'Personel yönetimi: vardiya planı, giriş-çıkış, mola, izin, görev, hedef, prim/komisyon ve maaş/bordro. Ekip verimini artırın.',
        'hero' => 'Ekibinizi vardiyadan prime kadar tek yerden yönetin',
        'lead' => 'Vardiya planı, giriş-çıkış, mola ve izin takibiyle ekibinizi düzenler; görev, hedef, prim/komisyon ve maaş/bordro ile motivasyon ve maliyeti yönetirsiniz.',
        'benefits' => [
            ['calendar', 'Vardiya & mola', 'Haftalık vardiya, mola ve izin tek takvimde.'],
            ['target', 'Hedef & prim', 'Görev, hedef ve prim/komisyonla motivasyon.'],
            ['receipt', 'Maaş & bordro', 'Aylık sabit veya saatlik hak ediş otomatik hesaplanır.'],
        ],
        'features' => [
            ['clock', 'Giriş-çıkış & mola', 'Mesai başlat/bitir, mola ve geç kalma takibi.'],
            ['calendar', 'Vardiya planı', 'Haftalık vardiya, izin ve tatil yönetimi.'],
            ['target', 'Görev & prim', 'Görev atama, hedef ve prim/komisyon.'],
            ['receipt', 'Maaş/bordro', 'Saatlik/aylık hak ediş, avans ve bordro.'],
        ],
        'steps' => [
            ['Vardiyayı planla', 'Haftalık vardiya ve izinleri tanımlarsın.'],
            ['Mesaiyi takip et', 'Giriş-çıkış ve molalar kaydedilir.'],
            ['Hak edişi hesapla', 'Prim ve maaş mesaiye göre otomatik hesaplanır.'],
        ],
        'faq' => [
            ['Maaş saatlik mi aylık mı?', 'İkisi de desteklenir; saatlik hak ediş mesaiye göre otomatik hesaplanır.'],
            ['Prim/komisyon tanımlanır mı?', 'Evet, hedefe veya satışa bağlı prim ve komisyon tanımlanabilir.'],
        ],
        'related' => [['Satış Raporları', '/satis-raporlari'], ['Çoklu Şube Yönetimi', '/coklu-sube-yonetimi'], ['Restoran POS Sistemi', '/restoran-pos-sistemi']],
    ],

    'stok-yonetimi' => [
        'label' => 'Depo & Stok', 'icon' => 'box',
        'title' => 'Depo ve Stok Yönetimi — Kritik Stok ve Fire | BamBumPOS',
        'desc' => 'Depo ve stok yönetimi: reçeteye göre otomatik stok düşümü, kritik stok uyarısı, fire ve teorik-gerçek stok farkı. Kâr sızıntısını görün.',
        'hero' => 'Stok her satışta otomatik düşsün, fire görünsün',
        'lead' => 'Ürün satıldığında malzemeler reçeteye göre otomatik düşer; kritik stok uyarısı üretilir, fire ve teorik-gerçek stok farkı raporlanır.',
        'benefits' => [
            ['box', 'Otomatik düşüm', 'Satışta malzemeler reçeteye göre stoktan düşer.'],
            ['bell', 'Kritik stok uyarısı', 'Azalan malzeme için otomatik hatırlatma.'],
            ['trend', 'Fire kontrolü', 'Teorik-gerçek stok farkıyla kâr sızıntısı görünür.'],
        ],
        'features' => [
            ['box', 'Reçete & stok', 'Ürün reçetesiyle malzeme tüketimi.'],
            ['bell', 'Kritik stok', 'Eşik altına düşen malzeme uyarısı.'],
            ['receipt', 'Sayım & fire', 'Stok sayımı ve fire kaydı.'],
            ['chart', 'Maliyet analizi', 'Ürün maliyeti ve brüt kâr takibi.'],
        ],
        'steps' => [
            ['Reçeteyi tanımla', 'Ürünlerin malzeme reçetelerini girersin.'],
            ['Satış stoğu düşürsün', 'Her satışta malzeme otomatik düşer.'],
            ['Uyarı & sayım', 'Kritik stok uyarısı gelir; sayımla fire görülür.'],
        ],
        'faq' => [
            ['Reçete zorunlu mu?', 'Reçete tanımlarsanız otomatik düşüm ve maliyet analizinden yararlanırsınız.'],
            ['Fire nasıl takip edilir?', 'Sayım ile teorik ve gerçek stok karşılaştırılarak fire görülür.'],
        ],
        'related' => [['Üretim & Reçete', '/uretim-recete'], ['Tedarikçi Yönetimi', '/tedarikci-yonetimi'], ['Satış Raporları', '/satis-raporlari']],
    ],

    'on-muhasebe' => [
        'label' => 'Ön Muhasebe', 'icon' => 'receipt',
        'title' => 'Ön Muhasebe — Gelir-Gider ve Cari Takibi | BamBumPOS',
        'desc' => 'Ön muhasebe: gelir-gider, kasa, cari (tedarikçi/müşteri) ve borç-alacak takibi. İşletmenizin nakit akışını net görün.',
        'hero' => 'Gelir, gider ve cariyi tek yerde görün',
        'lead' => 'Satış geliri, giderler, kasa hareketleri ve cari (tedarikçi/müşteri) borç-alacak takibiyle işletmenizin nakit akışını net görürsünüz.',
        'benefits' => [
            ['receipt', 'Gelir-gider', 'Günlük gelir ve gider tek ekranda.'],
            ['users', 'Cari takibi', 'Tedarikçi ve müşteri borç-alacak bakiyesi.'],
            ['chart', 'Nakit akışı', 'Kasa ve nakit akışı görünürlüğü.'],
        ],
        'features' => [
            ['receipt', 'Gelir & gider', 'Kategorili gelir-gider kaydı.'],
            ['users', 'Cari hesap', 'Tedarikçi/müşteri cari ve ekstre.'],
            ['card', 'Kasa hareketleri', 'Nakit giriş-çıkış ve tahsilat.'],
            ['chart', 'Özet rapor', 'Dönemsel gelir-gider ve kâr özeti.'],
        ],
        'steps' => [
            ['Hareketleri kaydet', 'Gelir, gider ve kasa hareketleri işlenir.'],
            ['Cariyi takip et', 'Tedarikçi/müşteri bakiyesi güncellenir.'],
            ['Özeti gör', 'Dönemsel gelir-gider ve nakit akışı raporlanır.'],
        ],
        'faq' => [
            ['Resmi muhasebe yerine geçer mi?', 'Ön muhasebe işletme içi takip içindir; resmi beyan için mali müşavirinizle çalışırsınız.'],
            ['Cari ekstre alınır mı?', 'Evet, tedarikçi ve müşteri için dönemsel ekstre alınabilir.'],
        ],
        'related' => [['Tedarikçi Yönetimi', '/tedarikci-yonetimi'], ['Satış Raporları', '/satis-raporlari'], ['Stok Yönetimi', '/stok-yonetimi']],
    ],

    'coklu-sube-yonetimi' => [
        'label' => 'Çoklu Şube Yönetimi', 'icon' => 'branch',
        'title' => 'Çoklu Şube Yönetimi — Merkezi Kontrol ve Konsolide Rapor | BamBumPOS',
        'desc' => 'Çok şubeli yönetim: merkezi menü, şubeye özel fiyat, şubeler arası stok transferi, konsolide rapor ve rol/bölge yetkileri.',
        'hero' => 'Tüm şubeleri tek merkezden yönetin',
        'lead' => 'Menüyü merkezden yönetir, şubeye özel fiyat verir, şubeler arası stok transferi yapar ve tüm zinciri konsolide raporla izlersiniz.',
        'benefits' => [
            ['layers', 'Merkezi menü', 'Menü ve fiyat merkezden, şubeye özel istisnalarla.'],
            ['branch', 'Şube karşılaştırma', 'Şube bazlı ciro ve sağlık durumu.'],
            ['box', 'Stok transferi', 'Şubeler arası stok görünürlüğü ve transfer.'],
        ],
        'features' => [
            ['layers', 'Merkezi menü & fiyat', 'Şubeye özel fiyat ve istisna tanımı.'],
            ['chart', 'Konsolide rapor', 'Toplam ve şube kırılımlı raporlar.'],
            ['box', 'Stok transferi', 'Şubeler arası transfer akışı.'],
            ['lock', 'Rol & bölge yetkisi', 'Şube yöneticisi ve bölge müdürü yetkileri.'],
        ],
        'steps' => [
            ['Menüyü merkezden yönet', 'Menü ve fiyatı merkezden tanımlarsın.'],
            ['Şubeleri izle', 'Konsolide raporla şubeleri karşılaştırırsın.'],
            ['Stok transferi yap', 'İhtiyaç halinde şubeler arası transfer açılır.'],
        ],
        'faq' => [
            ['Şubeye özel fiyat verilir mi?', 'Evet, merkezden yönetilen menüde şube bazında fiyat ve istisna tanımlanır.'],
            ['Franchise yönetilebilir mi?', 'Evet, bölge müdürü ve franchise için sınırlı rol bazlı yetkiler tanımlanır.'],
        ],
        'related' => [['Çok Şubeli Restoran Yönetimi', '/cok-subeli-restoran-yonetimi'], ['Satış Raporları', '/satis-raporlari'], ['Stok Yönetimi', '/stok-yonetimi']],
    ],

    'satis-raporlari' => [
        'label' => 'Satış Raporları', 'icon' => 'chart', 'shot' => 'app-dashboard',
        'title' => 'Satış Raporları — Canlı Dashboard ve Analiz | BamBumPOS',
        'desc' => 'Akıllı raporlar: ciro, ortalama fiş, en çok satanlar, saatlik yoğunluk, ödeme dağılımı, iptal/ikram/indirim, fire ve personel performansı — canlı bir panoda.',
        'hero' => 'İşletmenizi tahminle değil, veriyle yönetin',
        'lead' => 'Ciro, ortalama fiş, en çok satanlar, saatlik yoğunluk, ödeme dağılımı, iptal/ikram/indirim, fire ve personel performansı canlı bir panoda toplanır.',
        'benefits' => [
            ['chart', 'Canlı dashboard', 'Bugün/hafta/ay ciro ve karşılaştırma.'],
            ['trend', 'Ürün & saat analizi', 'En çok satanlar ve saatlik yoğunluk.'],
            ['branch', 'Şube karşılaştırma', 'Çok şubede konsolide ve kırılımlı rapor.'],
        ],
        'features' => [
            ['chart', 'Ciro & fiş', 'Ciro, ortalama fiş ve sipariş sayısı.'],
            ['trend', 'Ürün & saat', 'En çok satan ürünler ve saatlik dağılım.'],
            ['card', 'Ödeme dağılımı', 'Nakit/kart/QR ve ödeme kırılımı.'],
            ['receipt', 'İptal/ikram/indirim', 'Kayıp kalemler ve fire analizi.'],
        ],
        'steps' => [
            ['Sat', 'Satışlar gün boyu kaydedilir.'],
            ['Analiz et', 'Pano ciro, ürün ve saat kırılımını gösterir.'],
            ['Karar ver', 'Verilere göre menü, fiyat ve vardiyayı optimize edersin.'],
        ],
        'faq' => [
            ['Raporlar canlı mı?', 'Evet, satışlar işlendikçe pano anlık güncellenir.'],
            ['Şube karşılaştırması var mı?', 'Evet, çok şubede toplam ve şube bazlı raporlar alınır.'],
        ],
        'related' => [['Çoklu Şube Yönetimi', '/coklu-sube-yonetimi'], ['Personel Yönetimi', '/personel-yonetimi'], ['Stok Yönetimi', '/stok-yonetimi']],
    ],

    'musteri-sadakat' => [
        'label' => 'Müşteri & Sadakat', 'icon' => 'tag',
        'title' => 'Müşteri ve Sadakat — Puan, CRM ve Kampanya | BamBumPOS',
        'desc' => 'Müşteri ve sadakat: müşteri kartı, puan biriktirme, kampanya ve geri dönüş. Müşterinizi tanıyın, tekrar kazanın.',
        'hero' => 'Müşterinizi tanıyın, sadakati ödüllendirin',
        'lead' => 'Müşteri kartı, puan biriktirme ve kampanyalarla müşterinizi tanır, tekrar kazanırsınız; geçmiş sipariş ve tercihlerle kişisel hizmet sunarsınız.',
        'benefits' => [
            ['tag', 'Puan & ödül', 'Harcamaya göre puan ve sadakat ödülü.'],
            ['users', 'Müşteri kartı', 'Geçmiş sipariş, adres ve tercih.'],
            ['megaphone', 'Kampanya', 'Hedefli kampanya ve geri dönüş.'],
        ],
        'features' => [
            ['tag', 'Sadakat puanı', 'Puan biriktirme ve harcama.'],
            ['users', 'Müşteri profili', 'İletişim, adres ve sipariş geçmişi.'],
            ['megaphone', 'Kampanya & indirim', 'Segmentli kampanya tanımı.'],
            ['chart', 'Sadakat analizi', 'Tekrar eden müşteri ve puan kullanımı.'],
        ],
        'steps' => [
            ['Müşteriyi tanı', 'Müşteri kartı ve sipariş geçmişi oluşur.'],
            ['Puan biriktir', 'Harcamaya göre puan verilir.'],
            ['Geri kazan', 'Kampanya ve ödülle tekrar sipariş sağlanır.'],
        ],
        'faq' => [
            ['Puan nasıl biriktirilir?', 'Harcama tutarına göre kurallı puan tanımlayabilirsiniz.'],
            ['KVKK uyumlu mu?', 'Müşteri verisi izinli ve aydınlatma metniyle işlenmelidir; altyapı buna uygundur.'],
        ],
        'related' => [['Kampanya Yönetimi', '/kampanya-yonetimi'], ['QR Menü', '/qr-menu'], ['Satış Raporları', '/satis-raporlari']],
    ],

    'kampanya-yonetimi' => [
        'label' => 'Kampanya Yönetimi', 'icon' => 'megaphone',
        'title' => 'Kampanya Yönetimi — İndirim ve Fırsat Kuralları | BamBumPOS',
        'desc' => 'Kampanya yönetimi: saatli happy hour, ürün/kategori indirimi, kombo ve koşullu fırsatlar. Yoğunluğu yönetin, sepeti büyütün.',
        'hero' => 'Doğru saatte doğru fırsatla satışı büyütün',
        'lead' => 'Saate bağlı happy hour, ürün/kategori indirimi ve kombo kampanyalarla yoğunluğu yönetir, ortalama sepeti büyütürsünüz.',
        'benefits' => [
            ['clock', 'Saatli kampanya', 'Happy hour ve zaman bazlı fiyat.'],
            ['trend', 'Sepet büyütme', 'Kombo ve koşullu fırsatlarla sepet artışı.'],
            ['tag', 'Kolay kural', 'Ürün/kategori bazında hızlı indirim tanımı.'],
        ],
        'features' => [
            ['megaphone', 'Kampanya kuralları', 'Ürün, kategori ve koşullu indirim.'],
            ['clock', 'Zaman bazlı', 'Happy hour ve gün/saat kısıtı.'],
            ['tag', 'Kombo & fırsat', 'Menü kombinleri ve paket fırsatlar.'],
            ['chart', 'Kampanya raporu', 'Kampanyanın satışa etkisi.'],
        ],
        'steps' => [
            ['Kampanyayı tanımla', 'Ürün/saat/koşulla kampanya kuralı girersin.'],
            ['Otomatik uygulansın', 'Satışta kampanya otomatik işlenir.'],
            ['Etkiyi ölç', 'Kampanya raporuyla katkısını görürsün.'],
        ],
        'faq' => [
            ['Happy hour otomatik mi çalışır?', 'Evet, tanımlı saatlerde fiyat/indirim otomatik uygulanır.'],
            ['Kampanyalar çakışır mı?', 'Öncelik kurallarıyla çakışma yönetilebilir.'],
        ],
        'related' => [['Müşteri & Sadakat', '/musteri-sadakat'], ['Bar & Pub POS', '/bar-pub-pos-sistemi'], ['Satış Raporları', '/satis-raporlari']],
    ],

    'uretim-recete' => [
        'label' => 'Üretim & Reçete', 'icon' => 'layers',
        'title' => 'Üretim ve Reçete — Maliyet ve Yarı Mamul | BamBumPOS',
        'desc' => 'Üretim ve reçete: ürün maliyeti, yarı mamul üretimi ve reçeteye göre stok düşümü. Kârınızı malzeme seviyesinde görün.',
        'hero' => 'Her tabağın maliyetini ve kârını bilin',
        'lead' => 'Ürün ve yarı mamul reçeteleriyle malzeme maliyetini, brüt kârı ve üretim tüketimini hesaplar; kârınızı malzeme seviyesinde görürsünüz.',
        'benefits' => [
            ['layers', 'Reçete & yarı mamul', 'Ürün ve yarı mamul reçeteleri.'],
            ['receipt', 'Maliyet & kâr', 'Ürün maliyeti ve brüt kâr hesabı.'],
            ['box', 'Otomatik tüketim', 'Üretim ve satışta malzeme düşümü.'],
        ],
        'features' => [
            ['layers', 'Çok kademeli reçete', 'Yarı mamul içeren reçeteler.'],
            ['receipt', 'Maliyet analizi', 'Malzeme maliyeti ve satış kârı.'],
            ['box', 'Üretim kaydı', 'Yarı mamul üretimi ve stok.'],
            ['chart', 'Kârlılık', 'Ürün bazında kârlılık sıralaması.'],
        ],
        'steps' => [
            ['Reçeteyi kur', 'Ürün ve yarı mamul reçetelerini tanımlarsın.'],
            ['Üret & sat', 'Üretim ve satışta malzeme düşer.'],
            ['Kârı gör', 'Ürün maliyeti ve brüt kâr raporlanır.'],
        ],
        'faq' => [
            ['Yarı mamul desteklenir mi?', 'Evet, çok kademeli reçetelerle yarı mamul üretimi tanımlanır.'],
            ['Maliyet nasıl güncellenir?', 'Malzeme alım fiyatları değiştikçe maliyet ve kâr güncellenir.'],
        ],
        'related' => [['Stok Yönetimi', '/stok-yonetimi'], ['Tedarikçi Yönetimi', '/tedarikci-yonetimi'], ['Satış Raporları', '/satis-raporlari']],
    ],

    'tedarikci-yonetimi' => [
        'label' => 'Tedarikçi Yönetimi', 'icon' => 'truck',
        'title' => 'Tedarikçi Yönetimi — Alım ve Cari Takibi | BamBumPOS',
        'desc' => 'Tedarikçi yönetimi: alım siparişi, mal kabul, tedarikçi cari ve borç takibi. Alım maliyetini ve bakiyeyi kontrol altında tutun.',
        'hero' => 'Alımdan bakiyeye tedarikçi süreçleri düzenli',
        'lead' => 'Alım siparişi, mal kabul ve tedarikçi cari takibiyle alım maliyetini ve borç bakiyesini kontrol altında tutar, stokla entegre çalışırsınız.',
        'benefits' => [
            ['truck', 'Alım süreci', 'Alım siparişi ve mal kabul akışı.'],
            ['users', 'Tedarikçi cari', 'Borç-alacak bakiyesi ve ekstre.'],
            ['box', 'Stokla entegre', 'Mal kabul stoğu otomatik günceller.'],
        ],
        'features' => [
            ['truck', 'Alım siparişi', 'Tedarikçiye sipariş ve mal kabul.'],
            ['users', 'Cari & bakiye', 'Tedarikçi borç-alacak takibi.'],
            ['box', 'Stok güncelleme', 'Mal kabul ile stok girişi.'],
            ['chart', 'Alım analizi', 'Tedarikçi ve maliyet bazında analiz.'],
        ],
        'steps' => [
            ['Alım siparişi ver', 'Tedarikçiye sipariş oluşturursun.'],
            ['Mal kabul et', 'Gelen mal stoğa girer, cari güncellenir.'],
            ['Bakiyeyi takip et', 'Tedarikçi borç bakiyesini izlersin.'],
        ],
        'faq' => [
            ['Mal kabul stoğa yansır mı?', 'Evet, mal kabul stok girişini otomatik yapar.'],
            ['Tedarikçi ekstresi alınır mı?', 'Evet, dönemsel cari ekstre alınabilir.'],
        ],
        'related' => [['Stok Yönetimi', '/stok-yonetimi'], ['Ön Muhasebe', '/on-muhasebe'], ['Üretim & Reçete', '/uretim-recete']],
    ],

];
