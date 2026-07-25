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

    'current_version' => '0.12.0',
    'released_at' => '2026-07-25',

    'entries' => [
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
