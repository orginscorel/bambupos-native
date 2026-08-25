<?php

/*
|--------------------------------------------------------------------------
| Kurumsal / yasal / bilgi sayfaları — slug → içerik (config-tabanlı)
|--------------------------------------------------------------------------
| PageController@corporate + marketing.corporate şablonu ile render edilir.
| blocks tipleri:
|   prose     → title? + body(string|array)
|   features  → title? + lead? + items[[icon,title,desc]]
|   cards     → title? + lead? + items[{icon,title,desc,url?}]   (url varsa linkli)
|   stats     → title? + lead? + items[[num,label]]              (DÜRÜST ürün nitelikleri)
|   steps     → title? + lead? + items[[title,desc]]             (numaralı akış)
|   split     → eyebrow? + icon? + title + body(string|array) + items[]  (metin + checklist)
|   checklist → title? + lead? + items[]                          (2 sütun ✓ liste)
|   callout   → icon? + title? + body
|   faq       → title? + items[[soru,cevap]]
|   contact   → (iletişim kartları)
|   cta       → title? + text?                                    (sayfa ortası koyu bant)
| icon anahtarları: App\Modules\Marketing\Support\Icons::all()
| NOT: stats/rakamlar UYDURMA olamaz — yalnız ürünün gerçek nitelikleri.
*/

return [

    'hakkimizda' => [
        'crumb' => 'Kurumsal', 'eyebrow' => 'Hakkımızda', 'icon' => 'store',
        'title' => 'Restoran teknolojisini herkes için erişilebilir kılıyoruz',
        'lead' => 'BamBumPOS; kafe, restoran ve tesislerin siparişten mutfağa, kasadan stoğa, personelden raporlamaya kadar tüm operasyonunu tek platformda toplayan bulut tabanlı bir işletme yönetim sistemidir.',
        'hero_badges' => ['Kurulum ücreti yok', 'Taahhüt yok', 'Çevrimdışı çalışır', 'Gerçek destek'],
        'blocks' => [
            ['type' => 'prose', 'title' => 'Neden yola çıktık?', 'body' => [
                'İşletmeler; ayrı adisyon programı, ayrı stok yazılımı, ayrı personel takibi ve birbiriyle konuşmayan cihazlarla boğuşuyordu. Her araç ayrı bir ekran, ayrı bir fatura ve ayrı bir baş ağrısıydı.',
                'Biz tek bir çatı altında, birbirine bağlı ve sade bir sistem kurduk: kurulumu dakikalar süren, internet kesilse de çalışmaya devam eden, gerçek uzman desteği olan bir platform. Amacımız net — işletmecinin işini kolaylaştırmak, teknolojiyi görünmez kılmak.',
            ]],
            ['type' => 'stats', 'title' => 'Tek platform, uçtan uca operasyon', 'lead' => 'Ayrı programlarla değil, birbirine bağlı tek bir sistemle çalışırsınız.', 'items' => [
                ['Tek platform', 'POS · QR menü · mutfak · stok · personel · rapor'],
                ['Bulut + çevrimdışı', 'İnternet kesilse de satış sürer, gelince senkronlanır'],
                ['3 dil', 'Müşteri menüsü TR · EN · DE'],
                ['7/24', 'Kurulum, menü aktarımı ve kullanım desteği'],
            ]],
            ['type' => 'features', 'title' => 'Bizi farklı kılan', 'lead' => 'Rakamlarla değil, işletmenizin gününü kolaylaştıran gerçek farklarla anlatalım.', 'items' => [
                ['layers', 'Tek platform', 'POS, QR menü, mutfak ekranı, stok, personel ve raporlar tek yerde — modüller birbirine bağlı çalışır.'],
                ['shield', 'Kesintisiz operasyon', 'İnternet gitse bile satış durmaz; bağlantı gelince veriler otomatik senkronlanır.'],
                ['headset', 'Gerçek destek', 'Menü aktarımından günlük kullanıma kadar gerçek uzman ekibiyle yanınızdayız.'],
                ['zap', 'Dakikalar içinde kurulum', 'Sektörünüze göre hazır yapılandırmayla aynı gün satışa başlarsınız.'],
                ['users', 'Ekip dostu', 'Rol bazlı yetki, PIN ile hızlı personel girişi ve sade arayüz her seviyeye uygun.'],
                ['trend', 'Sürekli gelişen', 'Sürüm notlarıyla şeffaf, düzenli güncellenen ve işletme geri bildirimiyle büyüyen bir ürün.'],
            ]],
            ['type' => 'split', 'eyebrow' => 'Değerlerimiz', 'icon' => 'target', 'title' => 'Yazılımı işletmecinin diliyle konuşturuyoruz',
                'body' => ['Karmaşık kurumsal yazılımların aksine BamBumPOS, ilk gününde bile öğrenmesi kolaydır. Garsonundan patronuna kadar herkesin rahatça kullanabileceği bir arayüz tasarladık.'],
                'items' => [
                    'Sadelik: her ekran tek bir işi net yapar',
                    'Şeffaflık: gizli ücret yok, sürüm notları açık',
                    'Süreklilik: veriniz şifreli, yedekli ve sizin',
                    'Yakınlık: gerçek insanlarla gerçek destek',
                ]],
            ['type' => 'cta', 'title' => 'BamBumPOS’u kendi işletmenizde görün', 'text' => 'Sektörünüze özel ücretsiz bir demo ile sistemin işletmenizde nasıl çalışacağını birlikte inceleyelim.'],
            ['type' => 'faq', 'title' => 'Merak edilenler', 'items' => [
                ['BamBumPOS kimler için uygun?', 'Kafe, restoran, nargile salonu, bar, fast food, otel ve sosyal tesis, paket servis ve çok şubeli zincirler için hazır yapılandırmalar sunar.'],
                ['Mevcut menümü taşıyabilir miyim?', 'Evet. Ekibimiz menü aktarımında yardımcı olur; ürün, kategori ve fiyatlarınızı hızlıca sisteme alırız.'],
                ['Donanım almak zorunda mıyım?', 'Hayır. Elinizdeki tablet, telefon veya bilgisayarla başlayabilirsiniz; uyumlu yazıcı ve ÖKC cihazlarını da destekleriz.'],
            ]],
        ],
    ],

    'neden-bambumpos' => [
        'crumb' => 'Kurumsal', 'eyebrow' => 'Neden BamBumPOS', 'icon' => 'target',
        'title' => 'Karmaşık kurumsal yazılım değil, işletmenizi büyüten bir sistem',
        'lead' => 'Onlarca ayrı araç yerine, birbirine bağlı tek bir ekosistem. İşte BamBumPOS’u tercih eden işletmelerin en çok önemsediği farklar.',
        'hero_badges' => ['Gizli ücret yok', 'İnternetsiz çalışır', 'Dakikalar içinde kurulum'],
        'blocks' => [
            ['type' => 'features', 'title' => null, 'items' => [
                ['tag', 'Gizli ücret yok', 'Ne kullanıyorsanız onu ödersiniz. Kurulum ücreti yok; taahhüt zorunluluğu yok.'],
                ['shield', 'İnternetsiz de çalışır', 'Yerel çalışma modu sayesinde bağlantı kesilse bile satışlarınız devam eder.'],
                ['zap', 'Dakikalar içinde kurulum', 'Sektörünüze göre hazır yapılandırma ve menü aktarım desteğiyle hızla başlarsınız.'],
                ['users', 'Ekip dostu', 'Rol bazlı yetki, PIN ile hızlı personel girişi ve sade arayüzle her seviyeden kullanıcıya uygun.'],
                ['chart', 'Kanıta dayalı yönetim', 'Ciro, ürün, personel ve şube raporları anlık; kararlarınızı veriye dayandırın.'],
                ['branch', 'Şubelerle büyür', 'Tek şubeden çok şubeli zincire kadar merkezi menü, fiyat ve stok yönetimi.'],
            ]],
            ['type' => 'split', 'eyebrow' => 'Dağınıklığa son', 'icon' => 'layers', 'title' => 'Beş ayrı program yerine tek panel',
                'body' => ['Ayrı adisyon, ayrı stok, ayrı personel, ayrı rapor programı… Her biri ayrı ekran, ayrı abonelik, ayrı sorun. BamBumPOS hepsini birbiriyle konuşan tek bir sistemde toplar.'],
                'items' => [
                    'POS + QR menü + mutfak ekranı tek akışta',
                    'Stok, satıştan otomatik düşer',
                    'Personel mesaisi ve primi tek yerde',
                    'Tüm raporlar tek panelde, anlık',
                ]],
            ['type' => 'checklist', 'title' => 'BamBumPOS ile neler kazanırsınız?', 'lead' => 'İlk günden itibaren hissedeceğiniz somut faydalar.', 'items' => [
                'Sipariş karışıklığının bitmesi',
                'Masalar arası hızlı adisyon ve hesap bölme',
                'Mutfak/barista istasyonlarına otomatik yönlendirme',
                'Gerçek zamanlı ciro ve ürün takibi',
                'Stok tükenmeden uyarı',
                'Personel performans ve prim takibi',
                'Çok şubede merkezi menü ve fiyat',
                'QR menüyle temassız sipariş',
            ]],
            ['type' => 'stats', 'title' => null, 'items' => [
                ['Tek abonelik', 'Beş ayrı program yerine tek sistem'],
                ['Çevrimdışı', 'Bağlantı kesilse de satış devam eder'],
                ['Anlık rapor', 'Ciro ve ürün verisi gecikmesiz'],
                ['Modüler', 'İstemediğiniz modülü kapatın'],
            ]],
            ['type' => 'cta'],
        ],
    ],

    'guvenlik-altyapi' => [
        'crumb' => 'Kurumsal', 'eyebrow' => 'Güvenlik & Altyapı', 'icon' => 'shield',
        'title' => 'Verileriniz güvende, sisteminiz her zaman ayakta',
        'lead' => 'BamBumPOS bulut tabanlı, yedekli ve izlenen bir altyapıda çalışır. İşletmenizin verisi şifreli olarak saklanır ve düzenli olarak yedeklenir.',
        'hero_badges' => ['Şifreli veri', 'Otomatik yedek', 'İzlenen sunucu', 'Rol bazlı erişim'],
        'blocks' => [
            ['type' => 'features', 'title' => 'Altyapı güvencesi', 'items' => [
                ['shield', 'Şifreli & yedekli', 'Veriler aktarımda ve saklamada şifrelenir; düzenli otomatik yedekleme yapılır.'],
                ['card', 'Güvenli ödeme', 'Ödeme entegrasyonları sağlayıcıların güvenli altyapısı üzerinden yürütülür; kart verisi sizde tutulmaz.'],
                ['users', 'Yetki kontrolü', 'Rol bazlı erişim ve işlem kaydı ile kimin ne yaptığı izlenebilir.'],
                ['trend', 'Yüksek erişilebilirlik', 'İzlenen sunucular ve yerel çalışma modu ile kesintisiz operasyon.'],
                ['lock', 'Hesap güvenliği', 'Güçlü oturum yönetimi ve isteğe bağlı iki adımlı doğrulama seçenekleri.'],
                ['clock', 'Sürekli izleme', 'Sunucu sağlığı 7/24 izlenir; olası bir sorunda proaktif müdahale edilir.'],
            ]],
            ['type' => 'checklist', 'title' => 'Aldığımız güvenlik önlemleri', 'items' => [
                'Aktarımda TLS ile şifreli iletişim',
                'Saklamada şifreli veritabanı',
                'Düzenli otomatik yedekleme',
                'Rol bazlı erişim ve işlem günlüğü',
                'Kart verisinin işletmede tutulmaması',
                'Yerel çalışma moduyla kesintisizlik',
                'İzlenen ve yedekli sunucu altyapısı',
                'Sürüm notlarıyla şeffaf güncelleme',
            ]],
            ['type' => 'callout', 'icon' => 'shield', 'title' => 'Veriniz size aittir', 'body' => 'BamBumPOS verilerinizi pazarlama amacıyla üçüncü taraflara satmaz. Verileriniz yalnızca hizmetin sunulması ve sizin talebiniz doğrultusunda işlenir.'],
            ['type' => 'prose', 'title' => 'Altyapı ortağımız', 'body' => 'BamBumPOS, yılların deneyimine sahip bogahost.com barındırma ve ağ altyapısı güvencesiyle sunulur. Sunucu sağlığı sürekli izlenir; olası bir sorunda operasyonunuz etkilenmeden müdahale edilir.'],
            ['type' => 'cta', 'title' => 'Güvenli altyapıyı yakından görün'],
        ],
    ],

    'referanslar' => [
        'crumb' => 'Kurumsal', 'eyebrow' => 'Referanslar', 'icon' => 'tag',
        'title' => 'Kafeden zincir restorana, her ölçekte işletme',
        'lead' => 'BamBumPOS; tek şubeli kafelerden çok şubeli zincirlere, nargile salonlarından paket servis işletmelerine kadar farklı sektörlerde kullanılıyor. İşletme türünüze özel hazır yapılandırmayla başlayın.',
        'blocks' => [
            ['type' => 'cards', 'title' => 'Hangi işletmeler kullanıyor?', 'lead' => 'Sektörünüze özel akış ve hazır yapılandırmayı inceleyin.', 'items' => [
                ['icon' => 'coffee', 'title' => 'Kafe & Kahveci', 'desc' => 'Hızlı servis, QR self-servis ve barista akışı.', 'url' => '/kafe-pos-sistemi'],
                ['icon' => 'utensils', 'title' => 'Restoran', 'desc' => 'Masa/adisyon, kat planı ve mutfak istasyonları.', 'url' => '/restoran-pos-sistemi'],
                ['icon' => 'flame', 'title' => 'Nargile Salonu', 'desc' => 'Nargile hazırlık kulvarı ve masa süre takibi.', 'url' => '/nargile-salonu-pos-sistemi'],
                ['icon' => 'glass', 'title' => 'Bar & Pub', 'desc' => 'Hızlı bar satışı, adisyon ve hesap bölme.', 'url' => '/bar-pub-pos-sistemi'],
                ['icon' => 'burger', 'title' => 'Fast Food', 'desc' => 'Sayaç satışı, kiosk ve paket sipariş.', 'url' => '/fast-food-pos-sistemi'],
                ['icon' => 'bed', 'title' => 'Otel & Sosyal Tesis', 'desc' => 'Çoklu nokta, oda/üye hesabı ve tesis raporu.', 'url' => '/otel-pos-sistemi'],
                ['icon' => 'truck', 'title' => 'Paket Servis', 'desc' => 'Telefon/online sipariş, kurye ve bölge yönetimi.', 'url' => '/paket-servis-pos-sistemi'],
                ['icon' => 'branch', 'title' => 'Çok Şubeli Zincir', 'desc' => 'Merkezi menü, şube karşılaştırma, stok transferi.', 'url' => '/cok-subeli-restoran-yonetimi'],
            ]],
            ['type' => 'split', 'eyebrow' => 'Size özel demo', 'icon' => 'target', 'title' => 'İşletmenizde nasıl çalışacağını birlikte görelim',
                'body' => ['Her işletmenin akışı farklıdır. Ücretsiz demo talebi bırakın; ekibimiz sektörünüze özel bir kurulum planı ve menü aktarımıyla dönüş yapsın.'],
                'items' => [
                    'Sektörünüze göre hazır yapılandırma',
                    'Menünüzün sisteme aktarılması',
                    'Ekibinize kısa kullanım eğitimi',
                    'Taahhütsüz başlangıç',
                ]],
            ['type' => 'callout', 'icon' => 'store', 'title' => 'Siz de referansımız olun', 'body' => 'BamBumPOS’u kullanıyor ve deneyiminizi paylaşmak istiyorsanız bize yazın; işletmenizi referanslarımız arasında memnuniyetle ağırlarız.'],
            ['type' => 'cta', 'title' => 'Sektörünüze özel demo alın'],
        ],
    ],

    'is-ortakligi' => [
        'crumb' => 'Kurumsal', 'eyebrow' => 'İş Ortaklığı', 'icon' => 'branch',
        'title' => 'Birlikte büyüyelim: bayilik ve çözüm ortaklığı',
        'lead' => 'Bölgenizde BamBumPOS’u temsil etmek, kurulum ve destek sağlamak veya entegrasyon geliştirmek isteyen iş ortaklarını arıyoruz.',
        'hero_badges' => ['Cazip komisyon', 'Eğitim & materyal', 'Teknik destek'],
        'blocks' => [
            ['type' => 'features', 'title' => 'Ortaklık modelleri', 'items' => [
                ['store', 'Bölge bayiliği', 'Kendi bölgenizde satış, kurulum ve ilk kademe desteği sağlayın; tekrarlayan gelir elde edin.'],
                ['plug', 'Çözüm ortaklığı', 'Kendi entegrasyon veya donanım çözümünüzü BamBumPOS’a bağlayın, ortak müşterilere ulaşın.'],
                ['users', 'Danışman ağı', 'İşletmelere dijitalleşme danışmanlığı verirken BamBumPOS’u önerin, yönlendirme kazancı elde edin.'],
            ]],
            ['type' => 'steps', 'title' => 'Nasıl iş ortağı olunur?', 'items' => [
                ['Başvurun', 'İletişim formundan ortaklık talebinizi ve bölgenizi iletin.'],
                ['Tanışalım', 'Ekibimiz sizinle görüşüp uygun ortaklık modelini belirlesin.'],
                ['Eğitim alın', 'Ürün, satış ve kurulum eğitimini birlikte tamamlayalım.'],
                ['Satışa başlayın', 'Materyal ve teknik desteğimizle bölgenizde büyümeye başlayın.'],
            ]],
            ['type' => 'checklist', 'title' => 'İş ortaklarımıza sunduklarımız', 'items' => [
                'Rekabetçi komisyon ve tekrarlayan gelir',
                'Ürün ve satış eğitimi',
                'Pazarlama ve tanıtım materyalleri',
                'Öncelikli teknik destek hattı',
                'Demo ve deneme hesabı',
                'Ortak müşteri yönlendirmesi',
            ]],
            ['type' => 'cta', 'title' => 'İş ortağımız olun', 'text' => 'Ortaklık ekibimizle tanışmak için başvurunuzu bırakın; en kısa sürede size dönelim.'],
        ],
    ],

    'kariyer' => [
        'crumb' => 'Kurumsal', 'eyebrow' => 'Kariyer', 'icon' => 'users',
        'title' => 'Restoran teknolojisini birlikte inşa edelim',
        'lead' => 'Ürün, yazılım, destek ve satış alanlarında ekibimizi büyütüyoruz. İşletmelerin hayatını kolaylaştıran bir ürünün parçası olun.',
        'blocks' => [
            ['type' => 'features', 'title' => 'Aradığımız alanlar', 'items' => [
                ['layers', 'Ürün & Yazılım', 'Web, mobil ve altyapı tarafında ürünü birlikte geliştirecek geliştiriciler.'],
                ['headset', 'Müşteri Destek', 'İşletmelere kurulum ve günlük kullanımda yol gösterecek destek uzmanları.'],
                ['megaphone', 'Satış & Pazarlama', 'BamBumPOS’u doğru işletmelerle buluşturacak satış ve pazarlama ekibi.'],
            ]],
            ['type' => 'checklist', 'title' => 'Neden bizimle çalışmalısınız?', 'items' => [
                'Gerçek işletmelerin sorununu çözen bir ürün',
                'Hızlı karar alan, sade bir ekip',
                'Öğrenmeyi ve inisiyatifi destekleyen kültür',
                'Uçtan uca sahiplenme ve etki alanı',
                'Uzaktan/esnek çalışma imkânları',
                'Sürekli gelişim ve mentorluk',
            ]],
            ['type' => 'steps', 'title' => 'Başvuru süreci', 'items' => [
                ['Başvurun', 'İletişim formundan özgeçmişinizi ve ilgilendiğiniz alanı iletin.'],
                ['Tanışalım', 'Uygun bir aday olduğunuzda kısa bir ön görüşme yapalım.'],
                ['Değerlendirme', 'Alanınıza göre pratik bir görüşme veya vaka çalışması.'],
                ['Aramıza katılın', 'Karşılıklı uyum sağlarsak ekibe hoş geldiniz deriz.'],
            ]],
            ['type' => 'callout', 'icon' => 'users', 'title' => 'Açık pozisyon göremiyor musunuz?', 'body' => 'Yine de bize yazın. Yeteneğinizi tanıyalım; uygun bir pozisyon açıldığında ilk sizinle iletişime geçelim.'],
            ['type' => 'cta', 'title' => 'Ekibimize katılın', 'text' => 'Özgeçmişinizi ve ilgilendiğiniz alanı iletişim kanallarımızdan iletin.'],
        ],
    ],

    'iletisim' => [
        'crumb' => 'Kurumsal', 'eyebrow' => 'İletişim', 'icon' => 'headset',
        'title' => 'Bize ulaşın',
        'lead' => 'Sorularınız, demo talebiniz veya iş birliği önerileriniz için buradayız. Size en kısa sürede dönüş yaparız.',
        'blocks' => [
            ['type' => 'contact'],
            ['type' => 'cards', 'title' => 'Nasıl yardımcı olabiliriz?', 'items' => [
                ['icon' => 'zap', 'title' => 'Ücretsiz demo', 'desc' => 'Sektörünüze özel bir demo ile ürünü yakından görün.', 'url' => '/#demo'],
                ['icon' => 'card', 'title' => 'Fiyatlandırma', 'desc' => 'Paketleri inceleyin, işletmenize uygun planı seçin.', 'url' => '/fiyatlandirma'],
                ['icon' => 'headset', 'title' => 'Destek merkezi', 'desc' => 'Kurulum ve kullanım için destek kanallarımıza ulaşın.', 'url' => '/destek'],
            ]],
            ['type' => 'callout', 'icon' => 'clock', 'title' => 'Çalışma saatleri', 'body' => 'Hafta içi 09:00–18:00 arası buradayız. WhatsApp hattımızdan gönderdiğiniz mesajlara en kısa sürede dönüş yaparız.'],
        ],
    ],

    'destek' => [
        'crumb' => 'Kurumsal', 'eyebrow' => 'Destek Merkezi', 'icon' => 'headset',
        'title' => 'Yardıma mı ihtiyacınız var?',
        'lead' => 'Kurulumdan günlük kullanıma kadar her adımda yanınızdayız. Aşağıdaki kanallardan bize ulaşın veya sık sorulanları inceleyin.',
        'blocks' => [
            ['type' => 'contact'],
            ['type' => 'steps', 'title' => 'Kuruluma başlamak çok kolay', 'items' => [
                ['Demo talebi bırakın', 'Sektörünüzü ve işletme büyüklüğünüzü paylaşın.'],
                ['Menünüzü aktaralım', 'Ürün, kategori ve fiyatlarınızı sisteme alalım.'],
                ['Ekibinizi tanıştıralım', 'Kısa bir kullanım turuyla ekibinizi hazırlayalım.'],
                ['Satışa başlayın', 'QR kodları yazdırın, ilk siparişinizi alın.'],
            ]],
            ['type' => 'faq', 'title' => 'Sık sorulanlar', 'items' => [
                ['Kuruluma nasıl başlarım?', 'Ücretsiz demo talebi bırakın; ekibimiz sektörünüze göre hazır bir kurulum ve menü aktarımıyla dönüş yapar.'],
                ['İnternet kesilirse ne olur?', 'BamBumPOS yerel çalışma modu sayesinde bağlantı olmadan da satışa devam eder; bağlantı gelince veriler senkronlanır.'],
                ['Hangi cihazlarda çalışır?', 'Tablet, telefon ve bilgisayarda; iOS, Android, Windows ve macOS tarayıcılarında çalışır. Uyumlu yazıcı, çekmece ve ÖKC cihazlarını destekler.'],
                ['Menümü sonradan değiştirebilir miyim?', 'Evet. Ürün, kategori, fiyat ve görselleri istediğiniz zaman panelden düzenlersiniz; değişiklik QR menüye anında yansır.'],
                ['Birden fazla şubem var, yönetebilir miyim?', 'Evet. Çok şubeli yönetimle merkezi menü/fiyat tanımlar, şubeleri tek panelden karşılaştırırsınız.'],
            ]],
        ],
    ],

    'blog' => [
        'crumb' => 'Kurumsal', 'eyebrow' => 'Blog', 'icon' => 'receipt',
        'title' => 'İşletmenizi büyütecek içerikler yolda',
        'lead' => 'Restoran ve kafe işletmeciliği, dijitalleşme ve BamBumPOS ipuçlarını paylaşacağımız blogumuz çok yakında burada olacak.',
        'blocks' => [
            ['type' => 'cards', 'title' => 'Yakında ele alacağımız konular', 'items' => [
                ['icon' => 'chart', 'title' => 'Kârlılık & maliyet', 'desc' => 'Menü mühendisliği, porsiyon maliyeti ve fire yönetimiyle kârınızı artırın.'],
                ['icon' => 'qr', 'title' => 'QR menü ipuçları', 'desc' => 'Temassız sipariş, dijital menü ve müşteri deneyimi üzerine pratik öneriler.'],
                ['icon' => 'users', 'title' => 'Personel yönetimi', 'desc' => 'Vardiya planlama, prim sistemi ve ekip verimliliği için yöntemler.'],
                ['icon' => 'box', 'title' => 'Stok & tedarik', 'desc' => 'Stok takibi, reçete/maliyet ve tedarikçi yönetiminde iyi uygulamalar.'],
                ['icon' => 'megaphone', 'title' => 'Pazarlama & sadakat', 'desc' => 'Kampanya, sadakat ve tekrar eden müşteri kazanma stratejileri.'],
                ['icon' => 'branch', 'title' => 'Şubeleşme', 'desc' => 'Tek şubeden çok şubeye geçerken dikkat edilecek operasyonel konular.'],
            ]],
            ['type' => 'prose', 'title' => null, 'body' => 'Bu arada ürünü yakından görmek isterseniz ücretsiz demo talebi bırakabilir veya çözümleri inceleyebilirsiniz.'],
            ['type' => 'cta', 'title' => 'İçerikleri kaçırmayın'],
        ],
    ],

    'entegrasyonlar' => [
        'crumb' => 'Entegrasyonlar', 'eyebrow' => 'Entegrasyonlar', 'icon' => 'plug',
        'title' => 'Kullandığınız cihaz ve servislerle konuşur',
        'lead' => 'BamBumPOS; ödeme, yazarkasa, donanım, paket sipariş platformları, muhasebe ve geliştirici araçlarıyla entegre çalışır. İhtiyacınıza göre açar, tek panelden yönetirsiniz.',
        'hero_badges' => ['Tek panel', 'İhtiyaca göre aç/kapa', 'API & Webhook'],
        'blocks' => [
            ['type' => 'features', 'title' => null, 'items' => [
                ['card', 'Ödeme', 'Sanal POS ve ödeme sağlayıcılarıyla hızlı, güvenli tahsilat.'],
                ['receipt', 'Yazarkasa & ÖKC', 'YN-POS / ÖKC cihazlarıyla yasal fiş ve entegre satış.'],
                ['box', 'Donanım', 'Fiş yazıcısı, mutfak yazıcısı, para çekmecesi, el terminali, barkod ve terazi.'],
                ['truck', 'Paket sipariş platformları', 'Online sipariş kanallarından gelen siparişleri tek adisyona toplayın.'],
                ['chart', 'Muhasebe & e-Fatura', 'Satış ve gelir verilerini ön muhasebe ve e-belge süreçlerinize aktarın.'],
                ['plug', 'API & Webhook', 'Geliştirici erişimiyle kendi sistemlerinizi BamBumPOS’a bağlayın.'],
            ]],
            ['type' => 'checklist', 'title' => 'Entegrasyonlarla ne kazanırsınız?', 'items' => [
                'Ödeme, fiş ve satışın tek akışta buluşması',
                'Paket sipariş platformlarının tek adisyonda toplanması',
                'Donanımlarınızın tak-çalıştır uyumu',
                'Satış verisinin muhasebeye otomatik akması',
                'Kendi sistemlerinizle API üzerinden bağ',
                'İhtiyacınız olmayan entegrasyonu kapatma esnekliği',
            ]],
            ['type' => 'callout', 'icon' => 'plug', 'title' => 'İhtiyacınız listede yok mu?', 'body' => 'Kullandığınız bir cihaz veya servisi entegre etmek istiyorsanız bize yazın; entegrasyon ekibimiz uygunluğu değerlendirip yol haritasını paylaşsın.'],
            ['type' => 'cta', 'title' => 'Entegrasyonları sizin için yapılandıralım'],
        ],
    ],

    // ── Yasal sayfalar (genel bilgilendirme; işletmenizin hukuk ekibi özelleştirebilir) ──
    'gizlilik-politikasi' => [
        'crumb' => 'Yasal', 'eyebrow' => 'Gizlilik Politikası', 'icon' => 'shield',
        'title' => 'Gizlilik Politikası',
        'lead' => 'Kişisel verilerinizin gizliliği bizim için önemlidir. Bu politika, BamBumPOS’u kullanırken hangi verileri işlediğimizi ve nasıl koruduğumuzu açıklar.',
        'blocks' => [
            ['type' => 'callout', 'icon' => 'shield', 'body' => 'Bu metin genel bilgilendirme amaçlıdır. Nihai kapsam, işletmenizle imzalanan sözleşme ve yürürlükteki mevzuatla belirlenir.'],
            ['type' => 'prose', 'title' => 'Hangi verileri işleriz?', 'body' => 'Hizmeti sunabilmek için hesap bilgileri (ad, e-posta, telefon), işletme ve kullanım verileri ile işlem kayıtlarını işleriz. Ödeme bilgileri, ilgili ödeme sağlayıcılarının güvenli altyapısı üzerinden yürütülür ve kart verisi tarafımızca saklanmaz.'],
            ['type' => 'prose', 'title' => 'Verilerinizi nasıl kullanırız?', 'body' => 'Verileriniz yalnızca hizmetin sağlanması, güvenliğin korunması, yasal yükümlülüklerin yerine getirilmesi ve talep etmeniz halinde destek verilmesi amacıyla kullanılır. Verileriniz üçüncü taraflara pazarlama amacıyla satılmaz.'],
            ['type' => 'prose', 'title' => 'Veri güvenliği ve saklama', 'body' => 'Verileriniz aktarımda ve saklamada şifrelenir, düzenli olarak yedeklenir ve erişim rol bazlı olarak sınırlandırılır. Veriler, işleme amacının gerektirdiği süre boyunca ve yasal saklama yükümlülükleri çerçevesinde tutulur.'],
            ['type' => 'prose', 'title' => 'Haklarınız', 'body' => 'Kişisel verilerinize erişme, düzeltme, silme ve işlemeyi kısıtlama haklarına sahipsiniz. Talepleriniz için iletişim kanallarımızdan bize ulaşabilirsiniz.'],
        ],
    ],
    'kvkk' => [
        'crumb' => 'Yasal', 'eyebrow' => 'KVKK Aydınlatma', 'icon' => 'shield',
        'title' => 'KVKK Aydınlatma Metni',
        'lead' => '6698 sayılı Kişisel Verilerin Korunması Kanunu kapsamında, kişisel verilerinizin işlenmesine ilişkin aydınlatma metni.',
        'blocks' => [
            ['type' => 'callout', 'icon' => 'shield', 'body' => 'Bu metin genel bilgilendirme amaçlıdır ve işletmenizin veri sorumlusu sıfatına göre özelleştirilebilir.'],
            ['type' => 'prose', 'title' => 'Veri sorumlusu', 'body' => 'Kişisel verileriniz, BamBumPOS hizmetini sunan veri sorumlusu tarafından, KVKK ve ilgili mevzuata uygun olarak işlenir.'],
            ['type' => 'prose', 'title' => 'İşleme amacı ve hukuki sebep', 'body' => 'Verileriniz; sözleşmenin kurulması ve ifası, hizmetin sunulması, yasal yükümlülüklerin yerine getirilmesi ve meşru menfaat kapsamında işlenir. Verileriniz amaçla sınırlı ve ölçülü olarak işlenir.'],
            ['type' => 'prose', 'title' => 'Verilerin aktarımı', 'body' => 'Verileriniz; hizmetin sunulması için gerekli olduğu ölçüde, gizlilik yükümlülüğü altındaki hizmet sağlayıcıları (barındırma, ödeme, e-belge vb.) ve yasal olarak yetkili kurumlarla, mevzuata uygun biçimde paylaşılabilir.'],
            ['type' => 'prose', 'title' => 'İlgili kişinin hakları', 'body' => 'KVKK md. 11 uyarınca; verilerinizin işlenip işlenmediğini öğrenme, düzeltme, silinmesini isteme ve işlemeye itiraz etme haklarına sahipsiniz. Taleplerinizi iletişim kanallarımızdan iletebilirsiniz.'],
        ],
    ],
    'cerez-politikasi' => [
        'crumb' => 'Yasal', 'eyebrow' => 'Çerez Politikası', 'icon' => 'grid',
        'title' => 'Çerez Politikası',
        'lead' => 'Web sitemiz ve uygulamamız, deneyiminizi iyileştirmek için çerezler kullanır. Bu politika hangi çerezleri neden kullandığımızı açıklar.',
        'blocks' => [
            ['type' => 'prose', 'title' => 'Çerez nedir?', 'body' => 'Çerezler, siteyi ziyaret ettiğinizde cihazınıza kaydedilen küçük metin dosyalarıdır. Oturumunuzun sürdürülmesi ve tercihlerinizin hatırlanması gibi işlevler için kullanılır.'],
            ['type' => 'prose', 'title' => 'Kullandığımız çerezler', 'body' => 'Zorunlu çerezler (oturum ve güvenlik) hizmetin çalışması için gereklidir. Analitik/performans çerezleri, siteyi nasıl kullandığınızı anlamamıza yardımcı olur ve tarayıcı ayarlarınızdan yönetilebilir.'],
            ['type' => 'prose', 'title' => 'Çerezleri nasıl yönetirsiniz?', 'body' => 'Tarayıcı ayarlarınızdan çerezleri silebilir veya engelleyebilirsiniz. Zorunlu çerezlerin engellenmesi, sitenin bazı bölümlerinin düzgün çalışmamasına neden olabilir.'],
        ],
    ],
    'kullanim-kosullari' => [
        'crumb' => 'Yasal', 'eyebrow' => 'Kullanım Koşulları', 'icon' => 'receipt',
        'title' => 'Kullanım Koşulları',
        'lead' => 'BamBumPOS hizmetini kullanarak aşağıdaki koşulları kabul etmiş olursunuz. Bu koşullar hizmetin kullanımına ilişkin genel çerçeveyi belirler.',
        'blocks' => [
            ['type' => 'callout', 'icon' => 'receipt', 'body' => 'Bu metin genel bilgilendirme amaçlıdır; taraflar arasındaki nihai sözleşme hükümleri geçerlidir.'],
            ['type' => 'prose', 'title' => 'Hizmetin kullanımı', 'body' => 'Hizmet, yürürlükteki mevzuata ve bu koşullara uygun şekilde kullanılmalıdır. Hesabınızın güvenliğinden ve hesabınız üzerinden yapılan işlemlerden siz sorumlusunuz.'],
            ['type' => 'prose', 'title' => 'Fikri mülkiyet', 'body' => 'BamBumPOS yazılımı, arayüzü ve markası ilgili hak sahiplerine aittir. Hizmeti kullanmanız, size yazılım üzerinde kullanım hakkı dışında bir hak vermez.'],
            ['type' => 'prose', 'title' => 'Sorumluluk ve değişiklikler', 'body' => 'Hizmet kesintisiz ve hatasız olacak şekilde sunulmaya çalışılır; ancak mücbir sebep ve bakım durumları saklıdır. Bu koşullar zaman zaman güncellenebilir; güncel sürüm bu sayfada yayımlanır.'],
        ],
    ],
];
