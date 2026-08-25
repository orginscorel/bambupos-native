<?php

/**
 * Site (panel) sürüm notları — Sürüm-Changelog ajanı.
 *
 * KURAL: Buraya YALNIZ gerçekten yapılmış ve `git log`'da karşılığı olan
 * işler girer. Planlanan ama henüz yazılmamış bir özelliği buraya "yapıldı"
 * diye eklemeyin — sürüm notları güven belgesidir, uydurma girdi YASAK.
 * Yeni bir modül tamamlandığında listeye YENİ bir sürüm girdisi eklenir
 * (var olanlar değiştirilmez); `current_version` güncellenir.
 *
 * Semantic Versioning: 1.0.0'a kadar (platform hâlâ fazlar hâlinde
 * kuruluyor) MINOR = yeni modül/özellik seti, PATCH = iyileştirme/düzeltme
 * demeti. type: 'new' | 'improved' | 'fixed'.
 */
return [

    'current_version' => '0.24.0',
    'released_at' => '2026-07-30',

    'entries' => [
        [
            'version' => '0.24.0',
            'date' => '2026-07-30',
            'title' => 'BamBumPOS kimliği, POS/ÖKC entegratörü, Nargile & Şarjmatik eklentileri, tema yönetimi, işletme adı düzenleme',
            'changes' => [
                ['type' => 'new', 'text' => 'Sistem "BamBumPOS" markasıyla yeniden yapılandırıldı (panel, giriş ekranları ve müşteri menüsü); altyapı bogahost.com tarafından sağlanır ("powered by bogahost.com").'],
                ['type' => 'new', 'text' => 'POS / yazarkasa / ÖKC entegratörü: markadan bağımsız, tüm sağlayıcılara uyum için REST ve XML/SOAP adaptörleri + hazır banka/ÖKC ön ayarları (her markanın doküman bağlantısıyla). Kasa, terminal ve kioskta ödeme bu altyapıdan geçer.'],
                ['type' => 'new', 'text' => 'Nargile eklentisi (Ayarlar › Eklentiler): açıldığında nargileye ayrı hazırlık ekranı (kendi KDS kulvarı) + nargileci terminali; Nargile istasyonuna atanan ürünler Mutfak yerine Nargile ekranına düşer, kapalıyken Mutfak kulvarında kalır.'],
                ['type' => 'new', 'text' => 'Şarjmatik eklentisi: açıkken müşteri QR menüden "Şarjmatik İste" der, personele bildirim düşer; kapalıyken buton hiç görünmez.'],
                ['type' => 'new', 'text' => 'Kapsamlı tema yönetimi (Ayarlar › Tema): marka rengi, vurgu rengi, yazı tipi ve açık/koyu mod seçimi; canlı önizleme ile.'],
                ['type' => 'new', 'text' => 'İşletme adı artık Ayarlar › İşletme / Marka ekranından düzenlenebiliyor (QR menü başlığında görünen isim); adres, çalışma saatleri ve WiFi için Şubeler ekranına hızlı yönlendirme.'],
                ['type' => 'improved', 'text' => 'Fişler yeniden tasarlandı: birime özel (mutfak/barista/nargile) hazırlık fişleri ve kasa ödeme fişi daha profesyonel ve detaylı (istasyon başlığı, KDV dökümü, mali not).'],
                ['type' => 'improved', 'text' => 'Adisyona ürün eklerken "mutfağa iletilsin mi?" onayı: kazara eklenen kalem mutfağa gitmeden düzeltilebilir, unutulmaz.'],
                ['type' => 'improved', 'text' => 'Operasyon ekranlarında istasyon filtresi sadeleşti: her ekran kendine atananların tümünü görür, hiçbir kalem gözden kaçmaz.'],
                ['type' => 'fixed', 'text' => 'Ödenmiş adisyonun masayı meşgul göstermesi düzeltildi (masa doğru şekilde boşalır).'],
                ['type' => 'fixed', 'text' => 'QR kart tasarımı önizlemesi artık ayarları anında yansıtıyor (renk/çerçeve/başlık değişince önizleme güncellenir).'],
            ],
        ],
        [
            'version' => '0.23.0',
            'date' => '2026-07-29',
            'title' => 'Ürün görselleri + zoom, sipariş birleştirme, ödeme akışı, hızlı bildirim, tıklanabilir KPI, renkli mesai',
            'changes' => [
                ['type' => 'new', 'text' => 'Operasyon ekranlarında (mutfak/barista/komi/garson) sipariş kalemlerinde ürün görseli; dokununca tam-ekran büyüteç (parmakla yakınlaştır/uzaklaştır, tüm cihazlarda).'],
                ['type' => 'improved', 'text' => 'Aynı ürünü tekrar eklerken (aynı seçenek/not) yeni satır açılmaz, adet artar (ör. "çay ×2") — mutfak henüz bitirmediyse; adisyon daha derli toplu.'],
                ['type' => 'improved', 'text' => 'Ödeme akışı netleşti: "Borca taşı" yalnız kasada; "Açık hesap" ödeme yöntemi kaldırıldı — cari işi artık tek net yolla "Borca yaz".'],
                ['type' => 'improved', 'text' => 'Bildirimler (toast + web push) artık isteği bekletmeden, yanıt sonrası tek seferde ve eksiksiz gönderiliyor (belirgin hız artışı).'],
                ['type' => 'new', 'text' => 'Düşük stok bildirimi + periyodik hatırlatıcı (kritik eşik altı kalemler; tekrar tekrar rahatsız etmeden).'],
                ['type' => 'improved', 'text' => 'Panel KPI kartları tıklanabilir → ilgili içeriğe gider; vardiya saatleri döneme göre renkli (sabah/gündüz/akşam/gece).'],
            ],
        ],
        [
            'version' => '0.22.0',
            'date' => '2026-07-29',
            'title' => 'Patron paneli yeni grafikler: kategori, haftanın günleri, saatlik + günlük',
            'changes' => [
                ['type' => 'new', 'text' => 'Patron Paneli özetine yeni grafikler: kategori bazlı satış çubukları, haftanın günü performansı ve saatlik ciro dağılımı (artık günlük seyirle birlikte aynı ekranda).'],
                ['type' => 'new', 'text' => 'Patron Paneli: sipariş kanalı dağılımı (QR/Kiosk/Masa/Paket), masa bazlı ciro sıralaması ve dönem indirim + ikram toplamları.'],
                ['type' => 'improved', 'text' => 'QR müşteri menüsü tema renkleri panelle tam uyumlu hale getirildi (turuncu/sıcak tonlar → mavi + serin nötr; açık ve koyu modda).'],
            ],
        ],
        [
            'version' => '0.21.0',
            'date' => '2026-07-29',
            'title' => 'Patron paneli operasyon metrikleri + menü çoklu dil + native liste hareketi',
            'changes' => [
                ['type' => 'new', 'text' => 'Patron Paneli özetine "Operasyon metrikleri": misafir sayısı + kişi başı ciro, ortalama servis süresi, masa devir hızı, QR self-servis payı, iptal oranı, en yoğun saat ve en iyi gün.'],
                ['type' => 'new', 'text' => 'QR müşteri menüsü İngilizce ve Almanca dil altyapısı (tüm menü metinleri + İşletme Vitrini çevrildi).'],
                ['type' => 'improved', 'text' => 'Patron Paneli menüsü yeniden konumlandı: üstte premium segmented sekme kontrolü (ikonlu, aktif sekme belirgin).'],
                ['type' => 'improved', 'text' => 'Liste ekranlarında native "kademeli beliriş" animasyonu + satıra dokununca hafif geri bildirim (hareket-azaltma tercihine saygılı).'],
            ],
        ],
        [
            'version' => '0.20.0',
            'date' => '2026-07-28',
            'title' => 'İşletme Vitrini + koyu mod, Patron Paneli vardiya & görev yönetimi',
            'changes' => [
                ['type' => 'new', 'text' => 'QR müşteri menüsüne "İşletme Vitrini": WiFi (tek dokunuşla şifre kopyala), haftalık çalışma saatleri + "şu an açık/kapalı" rozeti, konum/yol tarifi ve sosyal medya bağlantıları. Şubeler > İşletme Vitrini bölümünden doldurulur; boş alanlar gösterilmez.'],
                ['type' => 'new', 'text' => 'QR müşteri menüsünde koyu mod: sağ üstte tema düğmesi (cihaz tercihini izler, seçim hatırlanır).'],
                ['type' => 'new', 'text' => 'Patron Paneli genişledi: üstte sekmeler (Özet · Vardiya · Görevler). Vardiya sekmesinde haftalık plan üzerinden personele vardiya ekleme/düzenleme/silme; Görevler sekmesinde personele görev atama ve durum takibi.'],
                ['type' => 'improved', 'text' => 'Sürüm güncellendiğinde tüm açık oturumlara "yeni sürüm — sayfayı yenile" bildirimi düşer.'],
            ],
        ],
        [
            'version' => '0.19.0',
            'date' => '2026-07-28',
            'title' => 'Native-mobil arayüz, Patron Paneli, ödeme rol akışı, bildirim baloncukları',
            'changes' => [
                ['type' => 'improved', 'text' => 'Panel baştan sona native-mobil hissi: alt sekme çubuğu + orta QR hızlı-işlem düğmesi (FAB), gruplu listeler (Personel/Mesai), mobil filtre çekmecesi, tutarlı dokunma alanları. Masaüstü düzeni korundu.'],
                ['type' => 'new', 'text' => 'Patron Paneli: "Yönetim Kokpiti" operasyon menüsünden çıkarıldı; patron için AYRI, executive tasarımlı bir panel oldu (kullanıcı menüsünden erişilir). Ciro/kıyas hero kartı + KPI + grafikler.'],
                ['type' => 'improved', 'text' => 'Ödeme rol akışı: garson artık ödeme ALMAZ → "Ödemeye gönder" ile adisyonu kasaya iletir ("ödeme bekliyor"); kasa "Tekrar siparişe gönder / Ödeme al / Borca yaz" yapabilir.'],
                ['type' => 'improved', 'text' => 'Mutfak (KDS) ekranı yeniden tasarlandı: aciliyet-renkli başlık, tek satır alerjen uyarısı, reçete modalı, dengeli kart ızgarası, yeni-sipariş bildirim şeridi, oto-fiş göstergesi.'],
                ['type' => 'improved', 'text' => 'Bildirimler artık ekranda GÖRÜNÜR baloncuk (toast) olarak da düşer (tıklayınca ilgili sayfaya gider); "Garson/Su/Hesap çağır" ilgili garson VE kasaya ulaşır; garson panosunda sesli+görsel uyarı.'],
                ['type' => 'new', 'text' => 'Ürün eklerken onay adımı: yanlış/kazara eklemeyi önlemek için adet seçimi + "Ekle/Vazgeç" (basit ürün de artık doğrudan mutfağa düşmez).'],
                ['type' => 'fixed', 'text' => 'Ödeme tamamlanınca masa otomatik boşalır (eskiden "temizleniyor"da takılıp dolu görünüyordu).'],
                ['type' => 'fixed', 'text' => 'Kasada para girişinde binlik ayıracı ("1.234") artık doğru okunuyor (eksik tahsilat riski giderildi).'],
                ['type' => 'fixed', 'text' => 'Görev atama/istasyon/prim ekranlarında personel isimleri boş görünmesi düzeltildi; Komi ekranına personel giriş kapısı eklendi.'],
            ],
        ],
        [
            'version' => '0.18.0',
            'date' => '2026-07-26',
            'title' => 'Yönetim Kokpiti (BOSS), Entegrasyon çerçevesi, Terminal erişimi',
            'changes' => [
                ['type' => 'new', 'text' => 'Yönetim Kokpiti (BOSS): ciro + önceki döneme kıyas, saatlik/günlük grafik, ödeme & servis-tipi dağılımı, en çok satanlar, personel performans + prim, açık adisyon/borç, düşük stok ve teslimat özeti — tek ekranda. Şube müdürleri kendi şubesini görür.'],
                ['type' => 'new', 'text' => 'Entegrasyon çerçevesi: ödeme/teslimat platformu/e-fatura/muhasebe entegrasyonları tek yerden açılıp yapılandırılır; aktifse sistem uyum sağlar, kapalıysa hiçbir yeri etkilemez.'],
                ['type' => 'new', 'text' => 'Menü ürünlerine tahmini gramaj ve kalori (menüde "≈ 320 g · 780 kcal").'],
                ['type' => 'improved', 'text' => 'Terminaller artık tek ekrana kilitli değil: yönetim/hassas ekranlar kapalı kalırken izinli operasyon ekranlarına (menü/masalar vb.) geçebilir.'],
                ['type' => 'improved', 'text' => 'Yeni "Depo Sorumlusu" rolü; Eklentiler sayfası detaylandırıldı.'],
                ['type' => 'fixed', 'text' => 'Sipariş açarken gereksiz "şube seçilmeli" uyarısı kaldırıldı (şube cihaz/kullanıcıdan otomatik).'],
            ],
        ],
        [
            'version' => '0.17.0',
            'date' => '2026-07-26',
            'title' => 'Teslimat + Prim modülleri, Entegrasyonlar, sidebar düzeni',
            'changes' => [
                ['type' => 'new', 'text' => 'Teslimat / Paket-Kurye: paket siparişlerde adres + kurye atama + teslim durumu (Bekliyor→Atandı→Yolda→Teslim) panosu; kuryeye bildirim; personel portalında "Teslimatlarım" ekranı. (Ayarlar › Eklentiler’den açılır.)'],
                ['type' => 'new', 'text' => 'Prim / Komisyon: satış-bazlı prim şeması (yüzde / sipariş başı / hedef primi), pozisyon hedefi ve prim raporu; personel portalında "Kazancım" özeti. (Ayarlar › Eklentiler’den açılır.)'],
                ['type' => 'new', 'text' => 'Entegrasyonlar merkezi: teslimat platformları, ödeme, e-Fatura ve muhasebe entegrasyonlarının durumu/yol haritası tek ekranda.'],
                ['type' => 'improved', 'text' => 'Sol menü bölümlere ayrıldı (Operasyon · Menü & Rezervasyon · Stok & Finans · Personel & Yönetim · Cihazlar & Entegrasyonlar · Sistem) — başlıklı, düzenli.'],
                ['type' => 'fixed', 'text' => 'QR menüde "Garson çağır / Su iste / Hesap iste" artık çalışıyor (servis ucu bağlandı).'],
                ['type' => 'improved', 'text' => 'Opsiyonel modüller kapatıldığında API dâhil tüm ekranları gizleyen özellik kapısı (feature-flag) altyapısı güçlendirildi.'],
            ],
        ],
        [
            'version' => '0.16.0',
            'date' => '2026-07-26',
            'title' => 'Güvenlik sıkılaştırma + bildirim sesi/izni (denetim sonrası)',
            'changes' => [
                ['type' => 'fixed', 'text' => 'GÜVENLİK: rol atama üzerinden yetki yükseltme kapatıldı — bir yönetici artık kendi sahip olmadığı yetkileri içeren (ör. "Sahip") bir rolü kimseye, kendine de atayamaz.'],
                ['type' => 'new', 'text' => 'Bildirim sesi: yeni sipariş, servis çağrısı, hazır ürün, teslim gecikmesi, görev/izin gibi kritik olaylarda panel ve personel portalında sesli uyarı (cihaz bazında aç/kapa).'],
                ['type' => 'new', 'text' => 'Bildirimleri aç istemi: panel ve portalda tek-tık "Bildirimleri açın" kartı — web push aboneliği artık kolayca açılıyor. Kritik push bildirimleri titreşimli ve ekranda kalıcı.'],
                ['type' => 'new', 'text' => 'İzin sonucu bildirimi: talep onaylanınca/reddedilince personele anında bildirim.'],
                ['type' => 'improved', 'text' => 'Görev durumu yalnızca ileri alınabilir (tamamlanan görev yeniden açılamaz); görev işlemleri denetim kaydına yazılıyor.'],
                ['type' => 'improved', 'text' => 'Sekme arka plandayken başlıkta okunmamış bildirim sayacı; performans için sipariş listelerinde sorgu iyileştirmesi.'],
                ['type' => 'fixed', 'text' => '"Şubeler" menüsü doğru yetkiyle gösteriliyor.'],
            ],
        ],
        [
            'version' => '0.15.0',
            'date' => '2026-07-26',
            'title' => 'Personel Portalı: canlı saat, mesai hatırlatma, performans detayı',
            'changes' => [
                ['type' => 'new', 'text' => 'Vardiya hatırlatması: mesai başlangıcına 10 dakika kala ilgili personele bildirim + web push gönderilir (dakikalık cron).'],
                ['type' => 'new', 'text' => 'Takvim: sıradaki/devam eden vardiya için canlı geri sayım ("başlamasına X saat Y dakika kaldı").'],
                ['type' => 'new', 'text' => 'Panelim ve Mesaim: çalışırken vardiya bitişine kalan süre + planlı süre; hero’da canlı saat.'],
                ['type' => 'new', 'text' => 'Raporlarım: fiili çalışma (mola düşülmüş) vs planlı süre, aynı gün kaç kez mesai başlat/bitir yapıldığı ve anomali uyarısı; ortalama alma/teslim süresi ve gecikme sayısı.'],
                ['type' => 'improved', 'text' => 'Raporlarda operasyon istatistikleri (hazırlanan/teslim/servis) veri 0 olsa da her zaman görünür.'],
                ['type' => 'improved', 'text' => 'Portal hero’suna dekoratif grafikler eklendi (daha premium mobil görünüm).'],
                ['type' => 'improved', 'text' => 'Profil: ad/soyad artık personel tarafından değiştirilemez (yönetici belirler); bildirim izni verilemiyorsa nedeni (HTTPS/iOS) açıkça belirtilir.'],
            ],
        ],
        [
            'version' => '0.14.0',
            'date' => '2026-07-26',
            'title' => 'Personel Portalı: izin talebi, bildirim zili, mesai geçmişi',
            'changes' => [
                ['type' => 'new', 'text' => 'İzin talebi: personel takvimden gün/tarih aralığı ve tür seçip mazeretini yazarak izin/rapor talebi gönderir; yönetici Vardiya > İzinler ekranından onaylar/ret eder. Talep gelince yöneticilere bildirim düşer.'],
                ['type' => 'new', 'text' => 'Portal bildirim zili: personel portalında okunmamış rozetli bildirim listesi (görev atama, izin kararı vb.) + tümünü okundu işaretle.'],
                ['type' => 'new', 'text' => 'Mesaim: mesai geçmişi listesi (giriş-çıkış, çalışma/mola/tuvalet süreleri) ve molaların daha ayrıntılı (süre + tür) gösterimi.'],
                ['type' => 'improved', 'text' => 'Panelim ve Raporlarım artık varsayılan "Bugün" ile açılıyor; grafikler ve kart yerleşimi büyütülüp okunurluk artırıldı.'],
                ['type' => 'fixed', 'text' => 'Görev-atama bildiriminin sessizce düşmesine yol açan bir sorun giderildi.'],
            ],
        ],
        [
            'version' => '0.13.0',
            'date' => '2026-07-26',
            'title' => 'Personel Portalı (ayrı adres, mobil PWA)',
            'changes' => [
                ['type' => 'new', 'text' => 'Personel Portalı ayrı bir adreste (personel alt alan adı) açıldı: kendine özgü, modern, mobil-öncelikli tasarım. QR yönetim paneli burada ASLA görünmez — personel yalnız kendi ekranlarını görür.'],
                ['type' => 'new', 'text' => 'Panelim (özet ekran): selamlama, mesai durumu + hızlı başlat/bitir, açık görev özeti, bu haftaki performans ve hızlı erişim tek bakışta.'],
                ['type' => 'new', 'text' => 'Mesaim: PIN gerekmeden mesai başlat/bitir, mola ve tuvalet molası; canlı süreler. Mola olayları yöneticiye ve o an mesaidekilere bildirilir.'],
                ['type' => 'new', 'text' => 'Görevler: yönetici personele görev atar (öncelik + son tarih); personel görevini görüp Başladım/Tamamladım ile ilerletir; atanınca bildirim gider.'],
                ['type' => 'new', 'text' => 'Takvim: personel kendi yaklaşan vardiyalarını gün gün görür.'],
                ['type' => 'new', 'text' => 'Raporlarım: kişiye özel performans panosu — grafiklerle günlük/haftalık/aylık çalışma süresi, hazırlanan/teslim/servis sayıları, ortalama teslim ve gecikme süreleri.'],
                ['type' => 'new', 'text' => 'Profilim: kimlik özeti, bilgi/telefon, PIN, parola değiştirme, oturum/cihaz yönetimi.'],
                ['type' => 'improved', 'text' => 'Yönetici panelinde yeni "Görevler" ekranı ve "Görev ata" yetkisi eklendi.'],
            ],
        ],
        [
            'version' => '0.12.0',
            'date' => '2026-07-25',
            'title' => 'Büyük özellik dalgası',
            'changes' => [
                ['type' => 'new', 'text' => 'Kiosk self-servis sipariş: müşteriler cihazdaki dokunmatik ekrandan, ürün görselleriyle kendileri sipariş verip ödeyebiliyor (şimdilik deneme/mock ödeme).'],
                ['type' => 'new', 'text' => 'Rezervasyon sistemi tamamlandı: takvim üzerinden rezervasyon, dolu olduğunda bekleme listesi ve gelmeyen (no-show) takibi.'],
                ['type' => 'new', 'text' => 'Depo / Stok: reçeteye göre otomatik stok düşümü, sebepli iade, gün/ay bazlı rapor ve sade bir "Genel Bakış" arayüzü.'],
                ['type' => 'new', 'text' => 'Vardiya yönetimi: vardiya planı, PIN\'li cihaz üzerinden mesai başlat/bitir (clock-in) ve devam/mesai raporu.'],
                ['type' => 'new', 'text' => 'Mutfak ve Barista istasyonları ayrıldı: kahve/içecekler Barista\'ya, yemekler Mutfak\'a düşer; komi tüm hazır kalemleri görür.'],
                ['type' => 'improved', 'text' => 'Kiosk siparişleri artık Siparişler panosuna ve mutfağa da düşüyor; ödeme durumu (ödendi / kalan) kartın üzerinde görünür.'],
                ['type' => 'improved', 'text' => 'Sipariş durum akışı sadeleşti: Hazırlanıyor → Garson & Komi bekliyor → Servis edildi. Durum yalnızca ilgili istasyonda ilerler.'],
                ['type' => 'improved', 'text' => 'Kasa ekranı kapsamlı hale geldi: kalemleri gözden geçirme, düzeltme/ikram, hesabı bölme (split) ve para üstü.'],
                ['type' => 'improved', 'text' => 'Masalar ekranı sadeleşti ve profesyonelleşti — dolu/boş masa artık ilk bakışta net.'],
                ['type' => 'improved', 'text' => 'Müşteri menüsünde ürün ve alerjen tasarımı yenilendi.'],
                ['type' => 'improved', 'text' => 'Personel için "Test için giriş yap" (kişinin yerine görüntüleme) eklendi; menü ve açılır liste düzeltmeleri yapıldı.'],
                ['type' => 'improved', 'text' => 'Rezervasyon, Raporlar, Vardiya ve Depo ekranları "Genel Bakış" + gruplu sekmeler ve açıklamalarla yeniden düzenlendi.'],
            ],
        ],
        [
            'version' => '0.11.0',
            'date' => '2026-07-23',
            'title' => 'Menüde logo ve öne çıkan kategoriler',
            'changes' => [
                ['type' => 'new', 'text' => 'Müşteri menüsünün üst kısmında artık işletmenin logosu gösteriliyor.'],
                ['type' => 'new', 'text' => 'Öne çıkan kategoriler, büyük görsellerle "hikaye" tarzında vurgulanabiliyor.'],
            ],
        ],
        [
            'version' => '0.10.0',
            'date' => '2026-07-23',
            'title' => 'Rezervasyon ve bekleme listesi',
            'changes' => [
                ['type' => 'new', 'text' => 'Müşteriler QR menü üzerinden masa rezervasyonu talep edebiliyor.'],
                ['type' => 'new', 'text' => 'Şube dolu olduğunda bekleme listesi tutulabiliyor; personel listeyi panelden yönetiyor.'],
                ['type' => 'new', 'text' => 'Rezervasyon onay ve iptal bağlantısı müşteriye e-posta ile gönderiliyor.'],
            ],
        ],
        [
            'version' => '0.9.1',
            'date' => '2026-07-23',
            'title' => 'İyileştirmeler ve düzeltmeler',
            'changes' => [
                ['type' => 'new', 'text' => 'Ürün kartındaki görsele dokununca fotoğraf tam ekran büyüyor.'],
                ['type' => 'new', 'text' => 'Menü ürünlerine örnek görseller eklendi.'],
                ['type' => 'improved', 'text' => 'Mutfak ve komi ekranları, panelin tasarım sistemiyle uyumlu, daha ferah bir görünüme kavuştu.'],
                ['type' => 'fixed', 'text' => 'Bir masadaki tüm siparişler tamamlanıp masa boşaldığında, masa artık "dolu" görünümünde takılı kalmıyor.'],
            ],
        ],
        [
            'version' => '0.9.0',
            'date' => '2026-07-22',
            'title' => 'Personel ve yetki yönetimi',
            'changes' => [
                ['type' => 'new', 'text' => 'Personel ekleme, rol atama ve yetki yönetimi ekranları eklendi.'],
                ['type' => 'new', 'text' => 'Yetkiler tek tek açılıp kapatılabiliyor; kişiye özel istisnalar tanımlanabiliyor.'],
                ['type' => 'new', 'text' => 'Her role, giriş sonrası açılacak varsayılan ekran atanabiliyor.'],
            ],
        ],
        [
            'version' => '0.8.0',
            'date' => '2026-07-22',
            'title' => 'Kasa ve ödeme',
            'changes' => [
                ['type' => 'new', 'text' => 'Adisyon kapatma, kasa açma/kapama ve ödeme alma ekranları eklendi.'],
                ['type' => 'new', 'text' => 'Nakit ve kart gibi farklı ödeme yöntemleri, POS cihazlarıyla bağlantı için hazır hâle geldi.'],
            ],
        ],
        [
            'version' => '0.7.0',
            'date' => '2026-07-22',
            'title' => 'Mutfak ekranı (KDS)',
            'changes' => [
                ['type' => 'new', 'text' => 'Mutfak, bar ve komi (servis) için ayrı ekranlar eklendi; siparişler ilgili istasyona otomatik düşüyor.'],
                ['type' => 'new', 'text' => 'Ekranlar kendiliğinden güncelleniyor — sayfayı yenilemeye gerek kalmıyor.'],
            ],
        ],
        [
            'version' => '0.6.0',
            'date' => '2026-07-22',
            'title' => 'Sipariş ve adisyon',
            'changes' => [
                ['type' => 'new', 'text' => 'QR menüden gelen siparişler artık masanın adisyonuna düşüyor ve garson ekranından takip edilebiliyor.'],
            ],
        ],
        [
            'version' => '0.5.0',
            'date' => '2026-07-22',
            'title' => 'Menü ve ürün kataloğu',
            'changes' => [
                ['type' => 'new', 'text' => 'Panelden ürün ve kategori ekleme/düzenleme, güvenli görsel yükleme ile eklendi.'],
                ['type' => 'new', 'text' => 'Müşteri tarafında tam menü sayfası: ürün detayı, arama, filtre, sepet ve sipariş akışı eklendi.'],
            ],
        ],
        [
            'version' => '0.4.0',
            'date' => '2026-07-22',
            'title' => 'Şube, masa ve QR',
            'changes' => [
                ['type' => 'new', 'text' => 'Şube / kat / alan / masa hiyerarşisi ve her masa için güvenli, benzersiz QR kod üretimi eklendi.'],
            ],
        ],
        [
            'version' => '0.3.0',
            'date' => '2026-07-22',
            'title' => 'Giriş ve panel arayüzü',
            'changes' => [
                ['type' => 'new', 'text' => 'Giriş ve panel ana ekranları hayata geçirildi.'],
                ['type' => 'improved', 'text' => 'Panele özel yazı tipi ve şubenin saat dilimine göre çalışan canlı saat eklendi.'],
                ['type' => 'new', 'text' => 'Panelden yönetilen e-posta (SMTP) ayarları eklendi.'],
            ],
        ],
        [
            'version' => '0.2.0',
            'date' => '2026-07-22',
            'title' => 'Çok işletmeli altyapı ve kimlik doğrulama',
            'changes' => [
                ['type' => 'new', 'text' => 'Birden çok işletmenin aynı sistemde, verileri birbirine karışmadan güvenle çalışmasını sağlayan temel altyapı kuruldu.'],
                ['type' => 'new', 'text' => 'Kullanıcı girişi, rol/izin sistemi ve işlem kayıtları (denetim izi) eklendi.'],
            ],
        ],
        [
            'version' => '0.1.0',
            'date' => '2026-07-22',
            'title' => 'Temel altyapı',
            'changes' => [
                ['type' => 'new', 'text' => 'Projenin teknik temeli atıldı.'],
                ['type' => 'new', 'text' => 'Ortak tasarım sistemi (bileşenler, renk ve tipografi kuralları) oluşturuldu; panel ve müşteri menüsü kabukları hazırlandı.'],
            ],
        ],
    ],

];
