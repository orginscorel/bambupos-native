# BamBumPOS

Restoran, kafe ve nargile işletmeleri için **çok kiracılı (multi-tenant) adisyon,
kasa ve işletme yönetimi** platformu. Tek bir Laravel uygulaması dört ayrı
kullanıcı sistemini besler; her biri kendi arayüzü, yetki modeli ve cihaz
profiliyle çalışır.

> Üretim: <https://bambumpos.com> · Depo: özel (private)

---

## İçindekiler

- [Sistemler](#sistemler)
- [Öne çıkan yetenekler](#öne-çıkan-yetenekler)
- [Mimari](#mimari)
- [Modül haritası](#modül-haritası)
- [Kurulum](#kurulum)
- [Geliştirme](#geliştirme)
- [Test](#test)
- [Dağıtım](#dağıtım)
- [Güvenlik notları](#güvenlik-notları)

---

## Sistemler

| Sistem | Kim kullanır | Nereden girilir |
| --- | --- | --- |
| **Panel** | İşletme sahibi, müdür, muhasebe | `/panel` |
| **Adisyon & Kasa** | Garson, kasiyer, mutfak, barista, komi | `/panel/siparisler`, `/panel/kasa`, `/panel/mutfak` |
| **Personel Portalı** | Tüm personel (mesai, mola, izin, profil) | `personel.*` alt alanı, `/mesaim` |
| **Patron** | Çok şubeli işletme sahibi (kiracı-üstü bakış) | `/patron` |

Dördü de aynı kod tabanında yaşar; ayrım **host + yetki + arayüz kabuğu**
düzeyindedir. Süper-admin (`/yonetim`) kiracıları yönetir.

---

## Öne çıkan yetenekler

### Adisyon (sipariş) ekranı
- Tam ekran POS düzeni: solda ürün ızgarası (görsel öne çıkan kartlar, iki
  seviyeli kategori, arama), sağda sepet/geçmiş sekmeli adisyon paneli.
- Varyant + seçenek grupları (`free_limit` ile "ilk N ücretsiz" kuralı),
  kalem notu, ikram, kalem taşıma, adisyon bölme/birleştirme.
- **Birleşik masalar:** kalabalık grup birden çok masaya oturduğunda masalar
  tek adisyona bağlanır; pano birleşik gösterir, kasa tek hesapta toplar.
- Kişi sayısı ve adisyon notu sonradan düzenlenebilir.
- Hesap fişi yazdırma (termal 58/80mm, A4 veya PDF).

### Kasa
- Üç kolon POS: adisyon listesi · numpad + ödeme yöntemleri · adisyon paneli.
- Kalem seçerek kısmi tahsilat, `1/n` serbest bölme, fiziksel klavye girişi.
- Nakit para üstü, bahşiş, kısmi ödeme, void ve iade.
- **Kasa oturumu otomatik açılır** — tahsilat asla Z raporunun dışında kalmaz.
- **Masasız borç tahsilatı:** cari borçlar kasa ekranından tahsil edilir.
- Hazır indirim tanımları (şehit/gazi yakını, kamu personeli…), tek-indirim
  kuralı ve ay bazlı kullanım istatistiği.

### Mutfak / Barista / Komi (KDS)
- Kulvar bazlı kuyruk, SLA sayacı ve gecikme uyarısı, alerjen ve diyet
  vurgusu, reçete görüntüleme, istasyonlar arası kalem aktarma.
- Sessiz termal fiş yazdırma (kiosk-printing) ve sesli yeni sipariş uyarısı.

### Masa panosu
- Kat/alan gruplu kartlar; dolu/boş/rezerve renk kodu, açılış saati, masa
  süresi, son sipariş (30 dk+ ise uyarı rengi), garson adı.
- Sekmeler (tüm masalar / açık masalar / paket & kanal), sıralama, süzgeçler.
- Paket, gel-al ve kiosk siparişleri; QR servis çağrıları (garson/su/hesap).

### Diğer modüller
Menü ve katalog · Stok ve reçete · Rezervasyon ve bekleme listesi · Cari
borçlar · Prim/komisyon · Raporlar · Personel, vardiya ve izin · Kiosk ·
Terminal cihazları · İzinli cihazlar · Entegrasyonlar (POS, e-posta, push).

---

## Mimari

- **Laravel 12** + **Inertia 2** + **Vue 3** (`<script setup>`, TypeScript)
- **Tailwind 4** — tüm renkler `--ui-*` token'larından; açık/koyu tema tek
  kaynaktan türer, sabit renk (hex) kullanılmaz.
- **Çok kiracılılık:** `BelongsToTenant` + `TenantContext`; şube kapsamı
  `BranchContext` üzerinden — istekten `branch_id` **asla** güvenilmez.
- **Yetki:** `config/authz.php` tek katalog; policy'ler izin + kiracı + şube
  kapsamını birlikte doğrular.
- **Para:** her tutar **kuruş (minor)** tamsayı olarak tutulur; float yok.
  KDV fiyata dahildir (`Money::vatPortionOfGross`).
- **Eşzamanlılık:** adisyon mutasyonları satır kilidi + `expected_version`
  (iyimser kilit) ile korunur; çakışmada `409` döner.
- **Idempotency:** kalem ekleme ve tahsilat `Idempotency-Key` ile korunur —
  çift dokunma ikinci kaydı düşürmez.

### Terminal ekranları
Mutfak, komi, kasa, sipariş ve masa panosu **tam ekran terminal kabuğu**
kullanır (`kds-canvas` + `TerminalTopBar`): cihaz kilidi, operatör kapısı,
PIN'li hassas eylemler, boşta-kalma kilidi ve heartbeat bu kabukta yaşar.

---

## Modül haritası

```
app/Modules/
├── Orders/        Adisyon, kalem, masa birleştirme/bölme, servis talepleri
├── Payments/      Tahsilat, kasa oturumu (Z raporu), POS sağlayıcıları
├── Catalog/       Ürün, varyant, seçenek grubu, kategori, alerjen, menü
├── Kds/           Mutfak/barista/komi kuyrukları, istasyonlar, fiş
├── Inventory/     Stok, reçete, sayım, satın alma, tedarikçi
├── Receivables/   Cari hesap, borca taşıma, tahsilat
├── Reservations/  Rezervasyon, bekleme listesi, no-show
├── Identity/      Kullanıcı, rol, izin, PIN, denetim günlüğü
├── Staff/         Personel, görev, vardiya, izin
├── Portal/        Personel portalı (mesai/mola/profil)
├── Boss/          Patron (çok şube üstü bakış)
├── Venue/         Şube, alan/kat, masa, QR
├── Devices/       İzinli cihazlar, cihaz kilidi
├── Terminal/      İstasyon terminalleri, operatör kapısı
├── Kiosk/         Self servis kiosk
├── Notify/        Bildirim yönlendirme + Web Push (VAPID)
├── Reports/       Raporlar ve pano
├── Settings/      Ayarlar, eklenti (feature flag) kataloğu
└── Marketing/     bambumpos.com tanıtım sayfaları
```

---

## Kurulum

```bash
composer install
npm install

cp .env.example .env
php artisan key:generate

# Veritabanı bilgilerini .env içinde doldurun, sonra:
php artisan migrate --seed

npm run build
```

Gereksinimler: **PHP 8.3+**, **MySQL 8**, **Node 20+**.

> Sunucuda PHP çağrıları `ea-php83` ile yapılır:
> `/opt/cpanel/ea-php83/root/usr/bin/php artisan ...`

---

## Geliştirme

```bash
npm run dev          # Vite geliştirme sunucusu
npm run build        # üretim derlemesi
npm run typecheck    # vue-tsc (bellek için: NODE_OPTIONS=--max-old-space-size=4096)
```

### Kurallar
- Para hesabı **daima** kuruş tamsayısı; `float` kullanmayın.
- Renkler `--ui-*` token'larından; şablona sabit hex yazmayın.
- Yeni izin eklerken `config/authz.php` kataloğunu güncelleyin.
- Kullanıcıya görünen tüm metin **Türkçe**.

---

## Test

```bash
php artisan test
# veya
vendor/bin/phpunit --filter Order
```

Test paketi **SQLite bellek-içi** çalışır. Bu yüzden `orders` gibi ham SQL
tetikleyicisi olan tablolara `foreignId()->constrained()` ile sütun
**eklemeyin** — SQLite tabloyu yeniden kurar ve tetikleyiciler sessizce
kaybolur. Sütunu düz ekleyip yabancı anahtarı yalnız MySQL'de tanımlayın
(örnek: `2026_08_25_140000_add_discount_preset_id_to_orders`).

---

## Dağıtım

Kaynak `/home/qrmenu/apps/qrmenu`, üretim hedefi `/home/bambumpos/apps/qrmenu`
ve docroot `/home/bambumpos/public_html`.

```bash
npm run build
rsync -a --exclude '*.bak*' resources/js/ /home/bambumpos/apps/qrmenu/resources/js/
cp -rf public/build/. /home/bambumpos/apps/qrmenu/public/build/
cp -rf public/build/. /home/bambumpos/public_html/build/
chown -R bambumpos:bambumpos /home/bambumpos/apps/qrmenu /home/bambumpos/public_html/build
sudo -u bambumpos /opt/cpanel/ea-php83/root/usr/bin/php artisan migrate --force
sudo -u bambumpos /opt/cpanel/ea-php83/root/usr/bin/php artisan optimize:clear
```

> **Sahiplik tuzağı:** `.env` veya uygulama dosyaları root olarak
> düzenlenirse site 500 verir. Her kopyalamadan sonra `chown` şarttır.

---

## Güvenlik notları

- `.env` ve **yedekleri** (`.env.bak-*`) depoya girmez; `.gitignore` bunu
  yıldızlı kalıpla kapatır. Yedek alırken bu kalıbın dışına çıkmayın.
- Üretimde alınan `*.bak-*` dosyaları depoya dahil değildir.
- Şube/kiracı kapsamı istekten değil bağlamdan türetilir.
- Hassas eylemler (ikram, iptal, iade, indirim, tahsilat) terminal
  oturumunda **PIN** ister ve denetim günlüğüne yazılır.
