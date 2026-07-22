# Eski Sistem Denetimi — QR Menü / Restoran Yönetim Platformu

**Denetim tarihi:** 2026-07-22
**Denetlenen sistem:** `/home/oritoriu/public_html` (docroot), DB `oritoriu_menu`
**Erişim modu:** SALT-OKUNUR. Hiçbir dosya değiştirilmedi/silinmedi/oluşturulmadı; DB'ye yalnızca `SELECT`/`SHOW`/`information_schema` sorguları yapıldı.
**Ürün adı/sürüm:** "PROMENU" / "Cafe Menu System" — `VERSION` = `2.5.0`, `settings.app_version` = `v3`
**Çalışma ortamı:** ea-php82 (`.htaccess` AddHandler), MariaDB 10.11.18, LiteSpeed/Apache, cPanel hesabı `oritoriu`
**Hedef sistem (bu denetimin girdisi olduğu proje):** ayrı cPanel hesabı `qrmenu`, `qrmenu.bogahostdeveloper.com.tr`, PHP 8.3, Laravel 13, **çok kiracılı SaaS**

> **Kapsam uyarısı:** Aynı docroot altında bu projeye ait OLMAYAN 4 ayrı proje var: `basakmotor.bogahostdeveloper.com.tr/`, `keycrypt.bogahostdeveloper.com.tr/`, `park.bogahostdeveloper.com.tr/`, `perpa.bogahostdeveloper.com.tr/`. Bunlar denetime dahil edilmedi.

---

## 1. Dosya Yapısı ve Mimari

Procedural PHP. Framework yok, `composer.json` yok, otomatik yükleme (autoload) yok, şablon motoru yok. Her sayfa kendi HTML'ini içinde barındıran tek bir `.php` dosyası.

### 1.1 Klasörler

| Klasör | Ne yapıyor | Dosya sayısı / boyut |
|---|---|---|
| `admin/` | Yönetim paneli — 36 PHP sayfası + `api/` (13 JSON uç noktası) + `includes/` (header/footer) | ~470 KB kod + 875 KB `error_log` |
| `admin/api/` | Panelin AJAX uç noktaları (JSON) | 13 dosya |
| `admin/includes/` | `header.php` (54.6 KB!) = auth + oto-migrasyon + menü + CSS; `footer.php` (433 B) | 2 dosya |
| `menu/` | Müşteriye açık QR menü (public) | `index.php` 115 KB (1625 satır) + 5 uç nokta |
| `menu/api/` | `tables.php` — masa listesi (public GET) | 1 dosya |
| `menu/includes/` | `menu-helpers.php` | 1 dosya |
| `kiosk/` | Personel kiosk/adisyon ekranı (1154 satır tek dosya) | 1 dosya |
| `api/v1/` | REST API + SSE — **ÇALIŞMIYOR**, bkz. §7.3 | 4 dosya, 593 satır |
| `includes/` | Ortak çekirdek: `config.php`, `db.php`, `functions.php`, `permissions.php`, `license-check.php` | 5 dosya, ~1470 satır |
| `database/` | `schema.sql` (21.6 KB) — kurulum şeması | `.htaccess` ile 403 |
| `install/` | `install.php` — kurulum sihirbazı, **hâlâ diskte** | 1 dosya |
| `cache/` | Dosya tabanlı önbellek: `queries/`, `objects/`, `pages/`, `views/`, `api/` | 3 `.cache` dosyası |
| `logs/` | `access/`, `errors/`, `orders/` — **hepsi boş, hiç kullanılmıyor** | 0 dosya |
| `uploads/` | `products/`, `categories/`, `branches/`, `logo/`, `qr/`, `temp/` — **hepsi boş, 0 dosya** | 0 dosya |
| `tools/` | `encode.php` + `encode_cafe.py` — AES-256-CBC kaynak-kod şifreleyici | 3 dosya |
| `tests/` | `run-tests.php`, `test-helpers.php` | 2 dosya |
| `__MACOSX/` | macOS ZIP çöpü (12 alt klasör) | çöp |

### 1.2 Giriş noktaları ve yönlendirme

Yönlendirme yok — doğrudan dosya erişimi. `.htaccess` yalnız `RewriteEngine On` + `RewriteBase /` içeriyor, hiçbir front-controller kuralı yok.

| URL | Dosya | Auth |
|---|---|---|
| `/` | `index.php` (4 satır) → `menu/`'ya 302 | yok |
| `/menu/` | `menu/index.php` | **yok (public)** — `?table=<id>` ile masa bağlanır |
| `/menu/order.php` | POST JSON — sipariş oluşturma | **yok (public)** |
| `/menu/waiter-call.php` | POST JSON — garson çağır | **yok (public)**, 60 sn/masa limit |
| `/menu/rate.php` | POST JSON — ürün puanla | **yok (public)** |
| `/menu/reservation-api.php` | POST JSON — rezervasyon | **yok (public)** |
| `/menu/print.php` | Adisyon yazdırma | **yok** |
| `/menu/api/tables.php` | GET masa listesi + doluluk + **ödenmemiş tutar** | **yok (public)** |
| `/admin/` | `admin/index.php` — giriş formu | — |
| `/admin/*.php` | 35 panel sayfası | `includes/header.php:9` → `$_SESSION['admin_logged_in']` |
| `/admin/api/*.php` | 13 JSON uç noktası | yalnız `admin_logged_in` (rol kontrolü **YOK**) |
| `/kiosk/` | `kiosk/index.php` | `admin_logged_in` + opsiyonel kiosk PIN |
| `/api/v1/*` | REST/SSE | kırık (bkz. §7.3) |
| `/install/` | kurulum | `.htaccess` rewrite ile 301 (config varsa) |

### 1.3 Ortak `includes` dosyaları

| Dosya | Satır | İçerik | Not |
|---|---|---|---|
| `includes/config.php` | 23 | DB kimlik bilgileri, `SECRET_KEY`, `JWT_SECRET`, timezone `Europe/Istanbul`, oturum ini ayarları | Otomatik üretilmiş; başlıkta "DO NOT EDIT" |
| `includes/db.php` | 277 | `Database` singleton — PDO, `ATTR_EMULATE_PREPARES=false`, dosya-tabanlı sorgu önbelleği, transaction sarmalayıcıları | `query/queryOne/execute` tek erişim yolu |
| `includes/functions.php` | 796 | `sanitize`, `generateSlug`, `uploadImage`, `createThumbnail`, `convertToWebP`, `csrfToken/Field/Validate`, `logActivity`, `formatLogSummaryTr` (~175 satır TR log metni), `cacheGet/Set`, `checkRateLimit`, `validateInput` | Tek büyük yardımcı çöplüğü |
| `includes/permissions.php` | 326 | Rol matrisi, `hasPermission`, `requirePermission`, `isFeatureEnabled`, rol renkleri/ikonları | Renk/CSS mantığı yetki dosyasında |
| `includes/license-check.php` | 49 | `license.txt` var mı + `CAFE-`/`HSDL1-` öneki kontrolü | Etkisiz koruma, bkz. §7.5 |

**Kritik mimari kusur:** `admin/includes/header.php` her admin sayfa yüklemesinde ~25 adet `ALTER TABLE`/`CREATE TABLE IF NOT EXISTS` çalıştırıyor (satır 27+). Bu bir "oto-migrasyon" tasarımı; şema zaten güncel olduğu için her istekte 25 hata üretiyor (`admin/error_log`'da her deseninden 224 kayıt).

---

## 2. Veritabanı Şeması (33 tablo)

**Ölçülen değerler:** Charset `utf8mb4`, collation **`utf8mb4_unicode_ci`** (32 tablo) — tek istisna `role_permissions` = `utf8mb4_general_ci` (çalışma anında `permissions.php:59`'da `COLLATE` belirtilmeden `CREATE TABLE IF NOT EXISTS` ile üretildiği için). Motor: **tümü InnoDB**. Toplam ~2.2 MB. `sql_mode` = `NO_ENGINE_SUBSTITUTION` — **STRICT MODE KAPALI** (bkz. §5.4).

### 2.1 Menü / Ürün (7 tablo)

| Tablo | Satır | Ana sütunlar | İndeks / FK |
|---|---|---|---|
| `categories` | **12** | `id`, `parent_id`, `branch_id`, `name`+`name_en/de/ar`, `slug`, `description`, `icon`, `image`, `color`, `time_start/end`, `sort_order`, `is_alcohol`, `is_active`, `created_at`, `updated_at` | PK; `idx_parent`,`idx_branch`,`idx_slug`,`idx_active`,`idx_sort`; FULLTEXT(`name`); FK→`categories.id` CASCADE, FK→`branches.id` CASCADE |
| `products` | **68** | `category_id`, `branch_id`, `sku`, `name`+3 dil, `slug`, `description`+3 dil, `base_price` DEC(10,2), `happy_hour_price/start/end`, `cost_price`, `tax_rate` DEC(5,2), `calories/protein/carbs/fat`, `preparation_time`, `stock_status` ENUM, `stock_quantity`, `daily_stock_quantity`, `daily_stock_reset_time`, `min_stock_alert`, `badge` ENUM, `is_vegetarian/vegan/gluten_free`, `video_url`, `sort_order`, `is_active`, `is_featured`, `view_count`, `order_count`, `rating_avg`, `rating_count` | PK; UNIQUE(`sku`); 8 KEY; FULLTEXT(`name`,`description`); FK→`categories` CASCADE, FK→`branches` SET NULL |
| `product_images` | **68** | `product_id`, `image_path`, `thumbnail_path`, `webp_path`, `is_primary`, `sort_order` | `idx_product`,`idx_primary`; FK→`products` CASCADE |
| `product_extras` | **28** | `name`+3 dil, `price` DEC(10,2), `icon`, `is_active` | `idx_active` |
| `product_product_extras` | **467** | `product_id`+`extra_id` (bileşik PK) | FK×2 CASCADE — ürün başına ort. **6.9 ekstra** |
| `product_variants` | **0** | `product_id`, `name`+3 dil, `type`, `price_modifier`, `is_default`, `sort_order` | FK→`products` CASCADE |
| `allergens` | **8** | `name`+3 dil, `icon`, `color`, `description` | PK yalnız |
| `product_allergens` | **0** | `product_id`+`allergen_id` | FK×2 CASCADE |

### 2.2 Masa / Salon (2 tablo)

| Tablo | Satır | Ana sütunlar | İndeks |
|---|---|---|---|
| `tables` | **16** | `name` (UNIQUE), `capacity`, `area_id`, `status` ENUM(`free`,`occupied`,`reserved`,`cleaning`), `occupied_since`, `last_order_at`, `last_reminder_at`, `game_fee` DEC(10,2), `is_active` | `idx_status`,`idx_active`,`idx_area`. **`area_id` için FK YOK** |
| `table_areas` | **5** | `name`, `icon`, `color`, `sort_order`, `is_active` | PK yalnız |

Salon yerleşimi (floor plan) tabloda değil; `settings.floor_plan_layout` içinde JSON blob olarak duruyor (`admin/api/save-floor-plan.php:16`).

### 2.3 Sipariş (4 tablo)

| Tablo | Satır | Ana sütunlar | İndeks / FK |
|---|---|---|---|
| `orders` | **11** | `order_number` UNIQUE, `branch_id`, `customer_id`, **`table_number` VARCHAR(50)**, `customer_name/phone/email`, `order_type` ENUM(`dine_in`,`takeaway`,`delivery`), `status` ENUM(6), `subtotal`/`discount_amount`/`tax_amount`/`total_amount` DEC(10,2), `campaign_id`, `payment_method` ENUM, `payment_status` ENUM, `delivery_address/fee`, `special_instructions`, `estimated_time`, `loyalty_points_earned`, `staff_id`, `source` VARCHAR(20), `created_at`, `confirmed_at`, `completed_at` | UNIQUE(`order_number`); `idx_status`,`idx_created`,`idx_customer`,`branch_id`,`staff_id`; FK→`branches`/`customers`/`users` SET NULL. **`table_number` için indeks YOK**, `campaign_id` için FK YOK |
| `order_items` | **34** | `order_id`, `product_id`, `product_name` (denormalize), `variant_id`, `variant_name`, `quantity`, `unit_price`, `total_price`, `extras` JSON, `special_instructions`, `is_complimentary` (ikram) | `idx_order`,`idx_product`; FK→`orders` CASCADE, FK→`products` RESTRICT |
| `order_payments` | **2** | `order_id`, `amount`, `payment_method` ENUM | `idx_order`. **FK YOK** |
| `notification_queue` | **1747** | `type` ENUM(`new_order`,`waiter_call`,`reservation`,`table_alert`,`order_paid`,`table_cleared`), `reference_id`, `message`, `is_read` | `idx_unread`,`idx_type`. **FK yok (polimorfik)** |

### 2.4 Rezervasyon / Çağrı (2 tablo)

| Tablo | Satır | Ana sütunlar |
|---|---|---|
| `reservations` | **0** | `customer_name/phone/email`, `table_id`, `reservation_date`, `reservation_time`, `party_size`, `duration_minutes`, `status` ENUM(5), `notes`; FK→`tables` SET NULL |
| `waiter_calls` | **10** | `table_id`, `message`, `status` ENUM(`pending`,`acknowledged`,`completed`), `staff_id`, `acknowledged_at`, `completed_at`; FK→`tables` CASCADE. **`staff_id` için FK YOK** |

### 2.5 Kullanıcı / Müşteri / Yetki (6 tablo)

| Tablo | Satır | Ana sütunlar | Not |
|---|---|---|---|
| `users` | **1** | `username` UNIQUE, `email` UNIQUE, `password`, `full_name`, `role` ENUM(9: superadmin/owner/admin/manager/chef/barista/cashier/komi/staff), `phone`, `avatar`, `is_active`, `last_login`, `hourly_rate` | Tek kayıt: `admin` / `seolizmsy@gmail.com` / rol `owner` / **bcrypt `$2y$10$`** ✅ |
| `role_permissions` | **0** | `role`+`permission_page` UNIQUE, `is_allowed` | Boş → hard-coded varsayılanlara düşüyor (`permissions.php:70`) |
| `customers` | **0** | `phone` UNIQUE, `email` UNIQUE, `full_name`, `password`, `loyalty_points`, `total_orders`, `total_spent`, `favorite_products`/`dietary_preferences`/`allergies` JSON, `language`, `push_token`, `is_newsletter_subscribed`, `is_vip`, `notes` | Hiç kullanılmamış |
| `customer_debts` | **0** | `customer_name/surname`, `table_number`, `order_id`, `amount`, `status` ENUM(`open`,`partial`,`paid`), `staff_id` | Cari/veresiye. FK **yok** |
| `debt_payments` | **0** | `debt_id`, `amount`, `payment_method` ENUM | FK **yok** |
| `shifts` | **0** | `user_id`, `shift_date`, `start_time`, `end_time`, `status` ENUM(4), `shift_type` ENUM(`regular`,`leave`,`sick`,`holiday`) | FK **yok** |
| `newsletter_subscribers` | **0** | `email` UNIQUE, `full_name`, `is_active`, `subscribed_at`, `unsubscribed_at` | Admin sayfası bile yok |

### 2.6 İçerik / Pazarlama (6 tablo)

| Tablo | Satır | Not |
|---|---|---|
| `announcements` | **12** | `title`, `body`, `is_active` — superadmin panelinden yönetiliyor |
| `broadcasts` | **3** | Maç yayını: `team_home`, `team_away`, `channel`, `match_time`, `image_url` |
| `cafe_events` | **8** | `event_type` ENUM(`ramadan`,`live_music`,`special_menu`,`announcement`,`promotion`), `event_date`, `start/end_time`, `recurring` |
| `reviews` | **3** | `product_id`, `customer_id`, `order_id`, `rating` TINYINT, `comment`, `images` JSON, `is_approved`, `admin_response`, `helpful_count` |
| `campaigns` | **0** | `code` UNIQUE, `discount_type` ENUM(`percentage`,`fixed`,`bogo`), `discount_value`, `min_order_amount`, `max_discount_amount`, `usage_limit/per_customer/count`, tarih aralığı |
| `campaign_products` | **0** | `campaign_id`+`product_id`, FK×2 CASCADE |

### 2.7 Altyapı / Ayar (3 tablo)

| Tablo | Satır | Not |
|---|---|---|
| `settings` | **35** | `setting_key` UNIQUE, `setting_value` TEXT, `setting_type` ENUM(`string`,`number`,`boolean`,`json`). **AUTO_INCREMENT = 16881** → ~16.850 ID `ON DUPLICATE KEY UPDATE` yüzünden yakılmış |
| `activity_logs` | **84** | `user_id`, `action`, `entity_type`, `entity_id`, `old_values`/`new_values` JSON (CHECK json_valid), `ip_address`, `user_agent`; FK→`users` SET NULL |
| `branches` | **0** | Çok-şubelilik tablosu: `slug` UNIQUE, adres, `latitude`/`longitude` DEC, `opening_hours` JSON, `logo`, `cover_image`, `sort_order`; FULLTEXT(`name`,`address`) |

**Kritik:** `branches` tablosu ve `categories.branch_id` / `products.branch_id` / `orders.branch_id` FK'leri **var**, ama admin panelinde şube yönetim sayfası **yok** ve tabloda **0 satır**. Yani çok-şubelilik şemada tasarlanmış, uygulamada hiç bitirilmemiş. Tüm mevcut kayıtlarda `branch_id IS NULL`.

### 2.8 Şemada olmayıp kodun beklediği tablo

`user_api_keys` — `api/v1/base.php:75-80` bu tabloya `INNER JOIN` yapıyor. **Tablo veritabanında YOK** (doğrulandı: `information_schema` sorgusu 0 döndürdü). REST API'nin kimlik doğrulaması kalıcı olarak kırık.

---

## 3. İş Kuralları

### 3.1 QR / Masa bağlama
- QR bir masaya değil, `menu/?table=<tables.id>` URL'ine bağlanır (`menu/index.php:25`). Token/imza yok — sıradaki tam sayıyı deneyerek başka masaya sipariş açılabilir.
- `qr_codes` tablosu (kod, tip, tarama sayacı, dosya yolu) **hiç kullanılmıyor** (0 satır); `admin/qr-codes.php` sayfası QR'ı anlık üretiyor.
- Masa doğrulaması: `menu/index.php:29` → `SELECT name FROM tables WHERE id=? AND is_active=1`.

### 3.2 Sipariş akışı (`menu/order.php`)
1. Ayar kontrolü: `ordering_enabled` = `0` ise reddedilir — **ama `source='kiosk'` gönderilirse bu kontrol atlanır** (satır 21-28). Kimlik doğrulaması olmadığı için herhangi biri `{"source":"kiosk"}` göndererek kapalı sipariş sistemini açabilir.
2. Ürünler toplu çekilir (`WHERE id IN (...) AND is_active=1`) — **fiyat sunucuda hesaplanır, istemciden gelen fiyat kullanılmaz** ✅.
3. Stok: `out_of_stock` → kalem atlanır; `limited` ve `stock_quantity < adet` → kalem atlanır.
4. Ekstralar tek tek sorgulanır (N+1) ve fiyata eklenir; `order_items.extras` JSON'a yazılır.
5. Sipariş no: `ORD-yymmdd-XXXXX` (`strtoupper(substr(md5(uniqid()),0,5))`) — çakışma riski düşük ama kriptografik değil.
6. Transaction içinde `orders` + `order_items` yazılır, `products.order_count` artırılır, `limited` stok düşülür, 0'a inince `out_of_stock` yapılır.
7. Masa `occupied` yapılır: `WHERE id = ? OR name = ?` — `table_number` VARCHAR olduğu için kimlik belirsizliği (bkz. §3.3).
8. `notification_queue`'ya `new_order` kaydı düşülür.
9. Commit sonrası ikram (`is_complimentary`) kalemleri sıfırlanarak toplam yeniden hesaplanır.

**Sipariş durumları:** `pending → confirmed → preparing → ready → delivered` (+ `cancelled`). Panel ayrıca `completed` gösteriyor (`admin/orders.php:50`, `order-detail.php:37`) **ama bu değer ENUM'da YOK** → strict mode kapalı olduğu için `status` boş string olarak yazılıyor. **Ölçüldü: 11 siparişin 7'sinde `status = ''`.**

### 3.3 Masa ↔ sipariş bağı (mimari zayıflık)
`orders.table_number` **VARCHAR(50)**; `tables.id` (int) ya da `tables.name` (metin) tutabiliyor. Mevcut veride her ikisi de karışık: `"Okey 1"`, `"Masa 4"`, `"10"`, `"16"`, `"VIP 1"`. Bu yüzden her sorgu şu deseni kullanmak zorunda:
```
o.table_number = t.name OR o.table_number = CAST(t.id AS CHAR)
```
(`menu/api/tables.php:26-27`, `admin/api/table-payment.php:26-28`, `admin/orders.php:69-72`). **`orders.table_number` üzerinde indeks yok** (doğrulandı) → bu sorgular sargable değil, tam tarama yapıyor.

### 3.4 Masa durumları
`free → occupied` (sipariş girilince otomatik), `→ free` (ödeme tamamlanınca `admin/api/table-payment.php:77`), ayrıca `reserved`, `cleaning` (elle). `occupied_since` / `last_order_at` / `last_reminder_at` zaman damgaları var. **Ölçüldü:** 16 masanın 15'i `occupied`, 1'i `cleaning` — hiçbiri `free` değil; demo siparişlerden beri kilitli kalmışlar.

### 3.5 Garson çağırma (`menu/waiter-call.php`)
Public POST. Masa başına 60 sn hız limiti (satır 35-42, DB sorgusuyla). `waiter_call_enabled` ayarı ile kapatılabilir. `waiter_calls` + `notification_queue` kaydı. Durumlar: `pending → acknowledged → completed`. Ölçülen: 9 `completed`, 1 `pending`.

### 3.6 Kiosk akışı (`kiosk/index.php`)
Personel içi adisyon ekranı. `admin_logged_in` gerektirir + opsiyonel `settings.kiosk_pin` (bcrypt, `password_verify`). Masa seç → ürün ekle → ikram işaretle → ödeme al. Sipariş oluşturmayı `menu/order.php`'ye `source=kiosk` ile gönderiyor. **Rol/yetki kontrolü yok** — `kiosk` yetkisi olmayan bir rol de doğrudan `/kiosk/` ile girebilir (`kiosk/index.php:9` yalnız oturum bakıyor).

### 3.7 Fiyat / KDV
- **Tüm para alanları `DECIMAL(10,2)`** ✅ — float yok. Yeni sisteme geçişte kayıp riski yok.
- `settings.tax_rate` = `10` (number). Ama `products.tax_rate` **68 üründe de 0.00**, `orders.tax_amount` toplamı **0.00**, `orders.discount_amount` toplamı **0.00**.
  → **KDV hiç hesaplanmamış; fiyatlar KDV dahil kabul edilmiş.** Kampanya/indirim mekanizması da hiç çalıştırılmamış.
- Happy hour (`happy_hour_price/start/end`) ve `game_fee` (oyun masası ücreti) alanları var ama üretimde kullanılmamış (tüm `game_fee` = 0.00).
- `formatPrice()` (`functions.php:41`) TR biçimi + `₺`; para birimi `settings.currency` = `TRY`.

### 3.8 Roller ve yetkiler
9 rol: `superadmin`, `owner`, `admin` → tam yetki (`*`); `manager`, `chef`, `barista`, `cashier`, `komi`, `staff` → sayfa listesi (`permissions.php:17-48`).
- Yetki **sayfa adı** bazlı (`hasPermission('orders')`), kaynak/eylem bazlı değil.
- `role_permissions` tablosu boş → hard-coded varsayılanlar geçerli; `admin/role-permissions.php` sayfası pratikte hiç kullanılmamış.
- Ayrıca "özellik anahtarı" katmanı var: `settings.feature_<sayfa>` = 0/1 (`isFeatureEnabled`, `permissions.php:290`), superadmin panelinden yönetiliyor. Kayıt yoksa **varsayılan AÇIK** (satır 304).
- **Kritik boşluk:** `requirePermission()` yalnız `admin/*.php` sayfalarında çağrılıyor; `admin/api/*.php` (13 uç nokta) yalnız `admin_logged_in` bakıyor, **rol kontrolü sıfır** (bkz. §5.2).

### 3.9 Bildirimler
`notification_queue` tablosu + panelde polling (`admin/api/notifications.php`). SSE denemesi (`api/v1/sse.php`) kırık. Web push yok, e-posta yok. `table_alert` tipi "masa hâlâ dolu" hatırlatıcısı üretiyor — bkz. §4.2.

---

## 4. Veri İçeriği: Gerçek mi Test mi?

### 4.1 Sonuç: **Sistemde gerçek işletme verisi YOK. Tamamı demo/test verisi.**

Kanıtlar:

| Kanıt | Değer |
|---|---|
| `settings.cafe_name` | `site adı` (placeholder) |
| `settings.cafe_address` / `contact_address` | `sada\nasdasd` (klavye gürültüsü) |
| `settings.google_place_id` | `dfsad` |
| `license.txt` | `CAFE-DEMO-REPLACE-WITH-REAL-KEY` |
| `users` (1 kayıt) | `admin` / `Administrator` / `seolizmsy@gmail.com` — geliştiricinin kendi e-postası |
| `product_images` 68/68 satır | **hepsi `https://images.unsplash.com/...` stok fotoğrafı** — `uploads/` klasörü tamamen boş (0 dosya) |
| Sipariş müşteri adları | 8 sipariş `Administrator`, 3 sipariş `Misafir`; `customer_phone` hepsi boş |
| Ürün/kategori adları | Genel demo menü ("Serpme Kahvalti", "Patates Kizartmasi", "Mozzarella Stick") |
| Sipariş tarih aralığı | 2026-02-19 → 2026-07-09, 5 ayda **11 sipariş** — gerçek bir kafenin hacmi değil |

### 4.2 Tablo bazında doluluk

| Durum | Tablolar |
|---|---|
| **Veri var (demo)** — 12 | `products` 68, `product_images` 68, `product_product_extras` 467, `product_extras` 28, `categories` 12, `announcements` 12, `tables` 16, `table_areas` 5, `allergens` 8, `cafe_events` 8, `broadcasts` 3, `reviews` 3, `orders` 11, `order_items` 34, `order_payments` 2, `settings` 35, `activity_logs` 84, `waiter_calls` 10, `users` 1 |
| **Şişkin çöp** — 1 | `notification_queue` **1747** satır; bunun **1724'ü** `table_alert` tipinde otomatik üretilmiş spam. Örnek: `"Tavla 1 hala dolu - 196743 dk. Bosaltilsin mi?"` (~136 gün). Yalnız 15 farklı masa referansı. Masalar demo siparişlerden beri `occupied` kaldığı için sistem aylarca kendine hatırlatıcı üretmiş. Tablo satırlarının **%79'u** bu. |
| **Tamamen boş — modül hiç kullanılmamış** — 12 | `branches`, `campaigns`, `campaign_products`, `customers`, `customer_debts`, `debt_payments`, `newsletter_subscribers`, `product_allergens`, `product_variants`, `qr_codes`, `reservations`, `role_permissions`, `shifts` |

### 4.3 Veri kalitesi bulguları (ölçüldü)

| Bulgu | Ölçüm |
|---|---|
| Türkçe karakter kaybı | `products` 68/68 kayıtta **hiç** Türkçe diyakritik yok ("Kahvaltilar", "Sigara Boregi", "Citir Tavuk"). `categories`'de yalnız **1** kayıtta var ("Baslangiçlar") → tohum veri ASCII'ye dönüştürülerek girilmiş. **Mojibake değil** — DB gerçekten `utf8mb4`, sorun kaynak veride. |
| HTML entity kirliliği | `products.name/description` içinde `&amp;`/`&quot;` **0 kayıt** — `sanitize()` yıkıcı olsa da bu veri setinde hasar oluşmamış |
| Geçersiz ENUM | `orders.status = ''` → **7/11 satır** (ENUM'da olmayan `completed` yazılması + strict mode kapalı) |
| Yetim/eksik | `order_items.variant_id` dolu olan: **0**. Görselsiz ürün: **0**. `branch_id` dolu kayıt: **0** |
| Ödeme tutarsızlığı | 11 siparişten 7'si `paid`, ama `order_payments` tablosunda yalnız **2** kayıt → ödemelerin çoğu `orders.payment_status`'a doğrudan yazılmış, ödeme tablosuna değil. **İki farklı ödeme yolu var ve senkron değil.** |
| Ödeme/durum uyuşmazlığı | ID 1: `status=ready`, `payment_status=pending`; ID 4: `ready`/`pending`; ID 10, 11: `pending`/`pending` — masalar hâlâ `occupied` |
| `settings` ID israfı | AUTO_INCREMENT 16881 / 35 satır |

---

## 5. Güvenlik Problemleri

> Aşağıdakiler yalnızca **tespit**tir. Hiçbiri düzeltilmedi.

### 5.1 KRİTİK — Kaynak kod + DB parolası web'den indirilebiliyor

Docroot'ta 4 arşiv var ve `.htaccess` yalnız `config.php`/`.env`/`composer.*` isimlerini engelliyor (`.htaccess:4-6`) — `.zip` engellenmiyor:

| Dosya | Boyut | İçerik |
|---|---|---|
| `cafe-menu-system.zip` | 381 KB | **`includes/config.php` (1019 B) dahil** tüm kaynak + `database/schema.sql` |
| `admin.zip` | 343 KB | 129 dosya: tüm admin paneli + `includes/config.php` + `database/schema.sql` |
| `EN GÜNCEL VERSİYON KALICI.zip` | 298 KB | eski sürüm |
| `__MACOSX.zip` | 468 KB | içinde `yedek/includes/` klasörü |

`includes/config.php` içeriği (satır 3-11): DB host/ad/kullanıcı/**parola**, `SECRET_KEY`, `JWT_SECRET`.
**Etki:** Arşivi indiren herkes DB kimlik bilgilerini ve tüm uygulama sırlarını ele geçirir. Sunucuda phpMyAdmin/uzak MySQL erişimi varsa doğrudan veri sızıntısı. **En yüksek öncelikli bulgu.**

### 5.2 KRİTİK — Admin JSON API'lerinde rol kontrolü yok

13 uç noktanın **13'ü de** yalnız `$_SESSION['admin_logged_in']` bakıyor; `hasPermission()` çağrısı **hiçbirinde yok** (ölçüldü). Örnek:

```
admin/api/toggle-user.php:2-12
  session_start();
  if (!isset($_SESSION['admin_logged_in'])) { http_response_code(403); exit; }
  ...
  $db->execute("UPDATE users SET is_active = ? WHERE id = ?", [$active, $id]);
```

**Etki:** En düşük yetkili `staff` rolündeki bir personel `owner` hesabını devre dışı bırakabilir, `table-payment.php` ile ödeme kapatabilir, `transfer-table.php` ile adisyon taşıyabilir, `toggle-product.php`/`toggle-category.php` ile menüyü kapatabilir, `save-floor-plan.php` ile salon planını silebilir. Yatay+dikey yetki yükseltme.

### 5.3 KRİTİK — CSRF koruması pratikte yok

`functions.php:441-475` tam bir CSRF altyapısı içeriyor (`csrfToken`, `csrfField`, `csrfValidate` + token yenileme). Ancak:
- **`csrfValidate()` yalnız `admin/superadmin.php`'de kullanılıyor** — POST işleyen diğer 22 admin sayfasında yok.
- **13 `admin/api/*.php` uç noktasının hiçbirinde CSRF yok** (`grep -l csrf admin/api/*.php` → 0).
- Oturum çerezi 365 gün ömürlü (§5.5) → kurban pratikte hep giriş yapmış durumda.

**Etki:** Personelin tarayıcısında açılan zararlı bir sayfa; ürün silebilir, ödeme kapatabilir, kullanıcı pasifleştirebilir, ayar değiştirebilir.

### 5.4 YÜKSEK — Strict mode kapalı → sessiz veri bozulması

`SELECT @@sql_mode` → `NO_ENGINE_SUBSTITUTION`. `STRICT_TRANS_TABLES` yok.
Kanıt: `admin/order-detail.php:37` `completed` durumunu geçerli sayıyor, ama `orders.status` ENUM'unda `completed` yok → MariaDB uyarı verip **boş string** yazıyor. **11 siparişin 7'si bu durumda.** Aynı risk taşma, tarih, uzunluk hatalarında da geçerli.

### 5.5 YÜKSEK — Oturum yönetimi

| Bulgu | Kanıt |
|---|---|
| Oturum ömrü **365 gün** | `admin/index.php:2-4`, `admin/includes/header.php:4-6`, `kiosk/index.php:4-6` — `86400*365` |
| `session.cookie_secure = 0` | `includes/config.php:21` → çerez düz HTTP üzerinden de gidiyor |
| **Giriş sonrası `session_regenerate_id()` YOK** | `admin/index.php:44-49` (superadmin) ve `62-67` (normal) — oturum sabitleme (session fixation) açık |
| Aynı ini ayarları oturum aktifken tekrar set ediliyor | `admin/error_log`'da 483 + 379 + 242 = **1104 PHP Warning** |

### 5.6 YÜKSEK — Superadmin 4 haneli PIN ile giriş

`admin/index.php:32-54`: kullanıcı adı `superadmin` + parola olarak **4 haneli rakam PIN** (`strlen($password)===4 && ctype_digit(...)`) `settings.superadmin_pin` (bcrypt) ile doğrulanıyor.
- Arama uzayı **10.000** kombinasyon.
- **Deneme hızı sınırı yok, hesap kilitleme yok, CAPTCHA yok** — `checkRateLimit()` fonksiyonu var ama giriş formunda çağrılmıyor.
- Başarılı olan `admin_role = 'superadmin'` alır → tüm yetki + `superadmin.php` paneli.
- PIN'i **`isOwnerOrAdmin()` seviyesindeki herkes değiştirebiliyor** (`admin/settings.php:49`) → owner/admin kendine superadmin arka kapısı açabilir.

### 5.7 ORTA — Public uç noktalarda kimlik/limit eksikleri

| Uç nokta | Sorun |
|---|---|
| `menu/order.php:21-28` | `source='kiosk'` göndererek `ordering_enabled=0` kontrolü atlanıyor. Hız limiti yok → sipariş spam'i mümkün |
| `menu/api/tables.php:26-27` | Kimlik doğrulaması **yok**, `Access-Control-Allow-Origin: *`, ve **her masanın ödenmemiş toplam tutarını** (`unpaid_total`) herkese açık döndürüyor → işletme cirosu sızıntısı |
| `menu/rate.php` | Kimlik yok, hız limiti yok → ürün puanı manipüle edilebilir (`products.rating_avg`) |
| `menu/reservation-api.php` | Kimlik yok, hız limiti yok → rezervasyon spam'i |
| `menu/index.php:25` | `?table=<int>` — imza/token yok, masa numarası tahmin edilebilir |
| `api/v1/base.php:8` | `Access-Control-Allow-Origin: *` + `Allow-Headers: Authorization` |

### 5.8 ORTA — IP adresi güvenilmez kaynaktan alınıyor

`includes/functions.php:281-292` — `getClientIP()` sırasıyla `HTTP_CLIENT_IP`, `HTTP_X_FORWARDED_FOR`, `HTTP_FORWARDED_FOR`, `HTTP_FORWARDED` başlıklarını **doğrulamadan** kabul ediyor, `REMOTE_ADDR` en sonda.
**Etki:** `activity_logs.ip_address` sahte olabilir (denetim izi güvenilmez); `checkRateLimit()` IP anahtarıyla kullanılırsa başlık değiştirerek sınırsız atlanır.

### 5.9 DÜŞÜK-ORTA — SQL enjeksiyonu

Genel durum **iyi**: `db.php` `PDO::ATTR_EMULATE_PREPARES=false` ile gerçek prepared statement kullanıyor ve tüm kullanıcı girdileri `?` parametresiyle geçiyor. Yine de string birleştirme ile SQL kuran yerler var:

| Konum | Değerlendirme |
|---|---|
| `admin/reports.php:21,28,29,35` | `"DATE(o.created_at) BETWEEN '$df' AND '$dt'"` — `$df`/`$dt` `date('Y-m-d', strtotime($_GET[...]))` çıktısı olduğu için biçim garantili. **Şu an sömürülebilir değil**, ama desen tehlikeli ve `strtotime` davranışına bağımlı |
| `admin/reports.php:35` | `INTERVAL $days DAY` — `$days` beyaz listeden (`$periodDays`) geliyor. Güvenli |
| `admin/activity-logs.php:21`, `admin/orders.php:79` | `LIMIT $limit OFFSET $offset` — `$limit` sabit, `$offset` `(int)` cast'lı. Güvenli |
| `admin/customers.php:78`, `reviews.php:43`, `events.php:88`, `variants.php:49`, `export.php:17,47` | `$where` değişkeni birleştiriliyor **ama içindeki değerler `?` ile parametreleniyor**. Güvenli |

**Sonuç: Doğrulanmış, sömürülebilir SQL enjeksiyonu bulunamadı.** Ancak `$dateCondition` deseni yeni sistemde tekrarlanmamalı.

### 5.10 DÜŞÜK-ORTA — XSS ve yıkıcı sanitizasyon

- `sanitize()` (`functions.php:10-16`) girdiye `strip_tags` + `htmlspecialchars` uyguluyor ve **böyle veritabanına yazıyor** — bu "input-time escaping" anti-deseni: `Çay & Kahve` → DB'de `Çay &amp; Kahve`. Çıktıda ikinci kez kaçış yapılırsa `&amp;amp;` olur. (Bu veri setinde henüz hasar yok, ölçüldü: 0 kayıt.)
- `admin/index.php:201` `<?= $error ?>` — kaçışsız, ancak `$error` yalnız sabit sunucu metinleri alıyor → sömürülebilir değil.
- `menu/index.php` çıktılarında 33 `htmlspecialchars` çağrısı var; genel olarak kaçış yapılıyor.
- `formatLogSummaryTr()` (`functions.php:509+`) log JSON'undan gelen `product`/`name` alanlarını kaçışsız döndürüyor; çağıran sayfada kaçış yapılıyorsa sorun yok — **denetlenmedi, belirsiz**.

### 5.11 DÜŞÜK — Dosya yükleme

`functions.php:57-104` `uploadImage()`: `is_uploaded_file` ✅, boyut ✅ (5 MB), **`finfo` ile gerçek MIME kontrolü ✅**, `move_uploaded_file` ✅.
**Zayıflık:** dosya adı `uniqid()._time().'.'.pathinfo($file['name'], PATHINFO_EXTENSION)` — uzantı **kullanıcıdan** alınıyor, MIME'dan türetilmiyor. `.php` uzantılı ama JPEG başlıklı bir dosya `uploads/` altına `xxx.php` olarak yazılır. `uploads/` için `.htaccess` PHP yürütme engeli **yok**. Şu an `uploads/` boş (0 dosya) olduğu için sömürülmemiş, ama yol açık.

### 5.12 DÜŞÜK — Docroot hijyeni

| Öğe | Durum |
|---|---|
| `install/install.php` | Diskte duruyor. Yalnız `.htaccess` rewrite ile (config varlığına bağlı 301) korunuyor — `mod_rewrite` devre dışı kalırsa/kural bozulursa kurulum sihirbazı açılır. `install.php:20-25` girdiden gelen DB kimlik bilgileriyle PDO kuruyor, `install.php:31` `CREATE DATABASE` yapıyor |
| `database/schema.sql` | Diskte; `.htaccess` `RewriteRule ^(cache|logs|database)/ - [F,L]` ile 403 ✅ — **ama `admin.zip` ve `cafe-menu-system.zip` içinde de var** (§5.1) |
| `admin/error_log` | **875 KB**, web'den erişilebilir dizinde, engelleyen kural yok → dosya yolları, SQL parçaları, tablo/sütun adları sızıyor |
| `api/v1/error_log`, `menu/error_log`, `admin/api/error_log` | Aynı sorun |
| `tools/encode.php`, `tools/encode_cafe.py`, `tools/KULLANIM.md` | Şifreleme aracı ve dokümantasyonu web'de |
| `tests/run-tests.php` | Web'den çağrılabilir |
| `__MACOSX/` | 12 alt klasör macOS çöpü |

### 5.13 Şifre saklama — İYİ ✅

`users.password` = **bcrypt `$2y$10$`** (`admin/index.php:61` `password_verify`, `install.php:49` `password_hash(..., PASSWORD_BCRYPT)`). Kiosk PIN ve superadmin PIN de bcrypt (`admin/settings.php:33,52`). **Düz metin veya MD5 yok.** Tek zayıflık PIN'in 4 hane olması (§5.6).

---

## 6. Performans Problemleri

### 6.1 Her admin sayfa yüklemesinde 25+ DDL — **en büyük sorun**
`admin/includes/header.php:26-100+` her istekte `ALTER TABLE ... ADD COLUMN` / `CREATE TABLE IF NOT EXISTS` çalıştırıyor. Şema zaten güncel olduğu için hepsi hata veriyor ve loglanıyor.
**Ölçülen kanıt:** `admin/error_log` içinde her ALTER deseninden **224 kayıt** (`Duplicate column name 'status'`, `'source'`, `'occupied_since'`, `'game_fee'`, `'is_complimentary'`, `'hourly_rate'`, ...). Her admin sayfası açılışı = ~25 gereksiz DDL + istisna + `error_log` yazımı.

### 6.2 İndeks eksikleri
| Eksik | Etki |
|---|---|
| `orders.table_number` — indeks yok | Masa-sipariş sorguları (`menu/api/tables.php`, `admin/api/table-payment.php`, `admin/orders.php`, `kiosk`) tam tarama |
| `orders.payment_status` — indeks yok | Tüm rapor sorguları `WHERE payment_status='paid'` filtreliyor (`admin/reports.php:50-95`, 15+ sorgu) |
| `tables.area_id` FK yok | Referans bütünlüğü yok (indeks var) |
| `order_payments.order_id` FK yok | " |
| `customer_debts`, `debt_payments`, `shifts`, `waiter_calls.staff_id` FK yok | " |

### 6.3 Sargable olmayan sorgular
- `WHERE (o.table_number = t.name OR o.table_number = CAST(t.id AS CHAR))` — hem `OR` hem `CAST`, indeks kullanılamaz (`menu/api/tables.php:26`).
- `WHERE DATE(o.created_at) BETWEEN ... ` — `created_at` üzerindeki indeks kullanılamaz (`admin/reports.php:21,28`).
- `menu/api/tables.php`: her masa satırı için **2 korelasyonlu alt sorgu** → 16 masa × 2 = 32 alt sorgu, her biri `orders` tam taraması.

### 6.4 N+1 sorguları
- `menu/order.php:85` — sipariş kalemindeki **her ekstra için ayrı sorgu**.
- `menu/order.php:141` — kalemler toplu çekilmesine rağmen (satır 58-64) stok güncellemesi için **her kalemde tekrar `SELECT`**.
- `admin/reports.php` — 15+ ayrı `queryOne`/`query`, her biri `orders` üzerinde tam tarama.

### 6.5 Önbellek tasarımı bozuk
`includes/db.php`:
- `clearRelatedCache()` (satır 209-216) tablo adını regex'le çıkarıyor **ama** `deleteCacheFiles()` (satır 221-233) parametreyi **yok sayıp `glob('*.cache')` ile TÜM önbelleği siliyor** → herhangi bir `INSERT/UPDATE/DELETE` tüm önbelleği uçuruyor (cache stampede).
- Sipariş sistemi doğası gereği sürekli yazma yaptığı için `CACHE_ENABLED=true` pratikte **etkisiz** — sadece disk I/O maliyeti ekliyor. Ölçülen: `cache/queries/` içinde yalnız **3** dosya.
- `db.php:81` `$cacheKey` değişkeni satır 68'deki `if` bloğu içinde tanımlanıyor; `$useCache && $cacheEnabled` false ise satır 80'deki koşul da false olduğu için pratikte patlamıyor — ama kırılgan.
- `checkRateLimit()` (`functions.php:774`) dosya tabanlı, kilit yarışına (race condition) açık.

### 6.6 Sınırsız büyüyen tablolar
- `notification_queue`: **1747 satır (160 KB)**, %79'u `table_alert` çöpü. Temizleme/arşivleme mekanizması yok.
- `activity_logs`: 84 satır — henüz sorun değil ama rotasyon yok, `old_values`/`new_values` LONGTEXT.
- `settings` AUTO_INCREMENT 16881 — `ON DUPLICATE KEY UPDATE` her çağrıda ID yakıyor (INT unsigned sınırı uzak ama gösterge).

### 6.7 Sayfa boyutları (kod şişkinliği)
| Dosya | Boyut / satır |
|---|---|
| `menu/index.php` | **115 KB / 1625 satır** — tek dosyada PHP + HTML + CSS + JS |
| `admin/includes/header.php` | **54.6 KB** — auth + migrasyon + navigasyon + tüm panel CSS'i, **her admin sayfasına dahil** |
| `admin/floor-plan.php` | 47.9 KB |
| `admin/order-detail.php` | 45.7 KB |
| `admin/orders.php` | 39.3 KB |
| `admin/reports.php` | 29.9 KB |
| `admin/settings.php` | 28.2 KB |

Dış bağımlılıklar CDN'den yükleniyor (Bootstrap 5.3, Font Awesome 6.4, Google Fonts Poppins — `admin/index.php:95-97`) → üçüncü taraf bağımlılığı + gizlilik + çevrimdışı çalışmama.

---

## 7. Kod Kalitesi

### 7.1 Tekrar eden kod
- Oturum başlatma + `admin_logged_in` kontrolü + `require_once` üçlüsü **50+ dosyada** kopyalanmış (`admin/*.php` header üzerinden, `admin/api/*.php` 13 kez elle, `kiosk/index.php`, `menu/*.php`).
- Aynı ENUM etiket haritaları (durum, ödeme yöntemi, ödeme durumu) hem PHP'de hem JavaScript'te ayrı ayrı yazılmış: `admin/orders.php:50-63` (PHP) + `:467,491,548,552,573` (JS) + `admin/order-detail.php:30-31` + `functions.php:556,570,596,620`. **En az 6 kopya.**
- `table_number = name OR table_number = CAST(id AS CHAR)` deseni en az 4 dosyada.

### 7.2 Ölü kod / yarım modüller
| Modül | Durum |
|---|---|
| `branches` (çok şubelilik) | Şema + FK + FULLTEXT var, **admin sayfası yok**, 0 satır. Yarım bırakılmış |
| `campaigns` + `campaign_products` | `admin/campaigns.php` var, `orders.campaign_id` var, **sipariş akışında indirim hiç uygulanmıyor**, 0 satır |
| `customers` + `newsletter_subscribers` | `admin/customers.php` var, sipariş `customer_id`'yi hiç doldurmuyor, 0 satır. Newsletter'ın sayfası bile yok |
| `customer_debts` + `debt_payments` | `admin/debts.php` (13 KB) yazılmış, 0 satır |
| `shifts` | `admin/shifts.php` (24 KB) yazılmış, `users.hourly_rate` var, 0 satır |
| `product_variants` | `admin/variants.php` + `order_items.variant_id/variant_name` var, 0 satır |
| `product_allergens` | `allergens` 8 satır ama hiçbir ürüne bağlanmamış, 0 satır |
| `qr_codes` | Tablo + tarama sayacı var, `admin/qr-codes.php` QR'ı anlık üretiyor, 0 satır |
| `reservations` | Tablo + public API + admin sayfası var, 0 satır |
| `role_permissions` | Tablo + `admin/role-permissions.php` var, boş → hard-coded'a düşüyor |

### 7.3 Kırık kod
- **`api/v1/` tamamen çalışmıyor.** `base.php:75-80` var olmayan `user_api_keys` tablosuna `INNER JOIN` yapıyor (doğrulandı: tablo yok) → API anahtarıyla kimlik doğrulaması imkânsız.
- **`api/v1/sse.php` çalışmıyor.** `orders.updated_at` sütununu sorguluyor, sütun yok. Kanıt — `api/v1/error_log`:
  `[06-Mar-2026 22:41:32] Query error: SQLSTATE[42S22]: Column not found: 1054 Unknown column 'updated_at' ... FROM orders WHERE (id > ? OR updated_at >= ...)`
  Ayrıca `sse.php:48` `while(true)` + `set_time_limit(0)` → paylaşımlı hostingde PHP işçisi tüketen sonsuz döngü.
- `admin/orders.php` ve `order-detail.php` ENUM'da olmayan `completed` durumunu yazıyor (§5.4).

### 7.4 Çöp dosyalar
`__MACOSX/` (12 alt klasör) · `__MACOSX.zip` (468 KB) · `cafe-menu-system.zip` (381 KB) · `admin.zip` (343 KB) · `EN GÜNCEL VERSİYON KALICI.zip` (298 KB) · `admin/error_log` (875 KB) · `menu/error_log` · `api/v1/error_log` · `admin/api/error_log` · boş `logs/{access,errors,orders}/` · boş `uploads/*`.
**Toplam ~2.4 MB gereksiz/tehlikeli dosya docroot'ta.**

### 7.5 Etkisiz lisans koruması
`includes/license-check.php` yalnız `license.txt` dosyasının varlığını + `CAFE-` / `HSDL1-` önekini kontrol ediyor. Mevcut değer `CAFE-DEMO-REPLACE-WITH-REAL-KEY`. Sunucu doğrulaması, imza, süre kontrolü yok → herhangi bir metinle atlanır. `tools/encode.php` (AES-256-CBC obfuscator) ile birlikte bu, "kaynak kodu satılabilir ürün" niyetinin kalıntısı; yeni sistemde anlamsız.

### 7.6 Testler
`tests/run-tests.php` + `tests/test-helpers.php` mevcut. CI yok, çalıştırılma kanıtı yok. **İçerik denetlenmedi — belirsiz.**

---

## 8. Özellik Sınıflandırması

| Özellik | Sınıf | Gerekçe |
|---|---|---|
| **QR menü (public)** — kategori/ürün listeleme, çoklu dil (`tr/en/de/ar`) | **Yeniden tasarlanacak** | Ürünün özü. 115 KB tek dosya + `name_en/de/ar` sütun-başına-dil yaklaşımı sürdürülemez → ayrı çeviri tablosu |
| **Ürün kataloğu** (68 ürün, 12 kategori, hiyerarşik `parent_id`) | **Korunacak** + **Veri olarak taşınacak** | Şema mantıklı; ürün/kategori verisi taşınabilir (demo olsa da referans menü değeri var) |
| **Ürün ekstraları** (28 ekstra, 467 bağ) | **Korunacak** + **Veri olarak taşınacak** | Çalışıyor ve dolu |
| **Ürün görselleri** (68 kayıt, hepsi Unsplash URL) | **Veri olarak taşınacak** (URL) + **Yeniden tasarlanacak** (depolama) | Dosya yok, hepsi harici URL. Yeni sistemde yerel/CDN depolama + `uploads` güvenliği gerekli |
| **Ürün varyantları** | **Yeniden tasarlanacak** | Şema var, 0 satır. Yeni sistemde doğru kurulmalı (fiyat farkı, zorunlu/opsiyonel seçim grubu) |
| **Alerjen/besin değeri** (8 alerjen, 0 bağ) | **Korunacak** (sözlük olarak) | Alerjen listesi taşınır, ürün bağları yok |
| **Masa & salon alanı** (16 masa, 5 alan) | **Korunacak** + **Veri olarak taşınacak** | Temiz veri |
| **Salon planı (floor plan)** — 48 KB sayfa, JSON blob ayarda | **Yeniden tasarlanacak** | `settings` içinde JSON blob olarak tutulması yanlış; kendi tablosunu hak ediyor |
| **Sipariş akışı** (public + kiosk) | **Yeniden tasarlanacak** | Sunucu-taraflı fiyatlama iyi; ama `table_number` VARCHAR bağı, ENUM/`completed` uyumsuzluğu, `source=kiosk` bypass'ı, çift ödeme yolu düzeltilmeli |
| **Sipariş geçmişi** (11 sipariş, 34 kalem, 2 ödeme) | **Arşivlenecek** | Demo veri; yeni sisteme taşımanın iş değeri yok. Referans için tek seferlik dışa aktarılıp saklanır |
| **Ödeme kaydı** — `orders.payment_status` + `order_payments` (senkron değil) | **Yeniden tasarlanacak** | Tek doğruluk kaynağı olmalı: her ödeme `payments` tablosuna, sipariş durumu türetilmeli |
| **KDV / vergi** | **Yeniden tasarlanacak** | Şu an hiç çalışmıyor (tüm `tax_rate` 0). Yeni sistemde ürün/kategori bazlı KDV + fiş dökümü |
| **Kampanya / indirim** | **Yeniden tasarlanacak** | Şema var, kod yok, 0 satır. Sıfırdan |
| **Garson çağırma** (10 kayıt, 60 sn limit) | **Korunacak** | Basit ve çalışıyor; yeni sistemde gerçek zamanlı bildirime bağlanmalı |
| **Kiosk / adisyon** (1154 satır) | **Yeniden tasarlanacak** | İşlevsel olarak gerekli; yetki kontrolü ve kod yapısı baştan |
| **Rezervasyon** (0 satır) | **Yeniden tasarlanacak** | Şema iyi, veri yok. Yeni sistemde kapasite/çakışma kontrolüyle |
| **Müşteri / sadakat / newsletter** (0 satır) | **Kullanılmayacak** (v1'de) | Hiç kullanılmamış, KVKK yükü getirir. İhtiyaç doğarsa sonraki fazda |
| **Cari / veresiye (`debts`)** (0 satır) | **Kullanılmayacak** (v1'de) | 13 KB kod yazılmış, hiç kullanılmamış. Muhasebe kapsamı ayrı karar |
| **Vardiya (`shifts`)** (0 satır) | **Kullanılmayacak** (v1'de) | Hiç kullanılmamış |
| **Yorum/puanlama** (3 yorum, `menu/rate.php`) | **Yeniden tasarlanacak** | Kimlik/hız limiti yok → puan manipülasyonu. Moderasyon zorunlu |
| **Duyuru / etkinlik / maç yayını** (12+8+3) | **Korunacak** + **Veri olarak taşınacak** | Basit CMS; üçü tek "içerik" modeline birleştirilebilir |
| **Ayarlar** (35 anahtar) | **Veri olarak taşınacak** (seçerek) | Placeholder değerler (`site adı`, `sada\nasdasd`, `dfsad`) taşınmaz; `floor_plan_layout` ayrı ele alınır |
| **Özellik anahtarları** (`feature_*`) | **Korunacak** (kavram) | Modül aç/kapa fikri iyi; varsayılan "açık" yerine "kapalı" olmalı |
| **Rol/yetki sistemi** (9 rol, sayfa bazlı) | **Yeniden tasarlanacak** | Sayfa-adı bazlı yetki yetersiz; kaynak+eylem (`orders.refund`) modeli + API'lerde zorunlu kontrol |
| **Aktivite logu** (84 kayıt, TR özet üretici) | **Korunacak** (kavram) | Fikir iyi; `formatLogSummaryTr` 175 satırlık if-zinciri yeniden yazılmalı. IP kaynağı güvenilir olmalı |
| **Bildirim kuyruğu** (1747 satır, %79 çöp) | **Yeniden tasarlanacak** | Kuyruk mantığı gerekli ama TTL/temizlik/dedup + gerçek zamanlı kanal şart. Mevcut 1724 `table_alert` satırı **taşınmayacak** |
| **Çok şubelilik (`branches`)** | **Yeniden tasarlanacak** | Yarım bırakılmış. Yeni sistem çok-kiracılı olacağı için bu katman temelden kurulmalı |
| **Tek-işletme varsayımları** — global `settings` (tek `cafe_name`/`site_logo`/`tax_rate`/`floor_plan_layout`), `tables.name` global UNIQUE, `products.sku` global UNIQUE, `categories.slug`/`products.slug` global, `users.username`+`email` global UNIQUE, tek düzey rol ENUM'u, `license.txt` tek kurulum | **Yeniden tasarlanacak** | Yeni sistem **çok kiracılı SaaS** (birden çok işletmeye satılacak). Bu tekilliklerin **hepsi** kiracı kapsamına alınmalı (`UNIQUE(tenant_id, ...)`). Hiçbir yerde müşteriye/kuruma özel marka veya metin bulunmayacak — yalnız "powered by bogahost" |
| **QR kod tablosu** (0 satır) | **Yeniden tasarlanacak** | Tahmin edilemez token + tarama analitiği ile |
| **REST API `api/v1/`** | **Güvenlik nedeniyle kaldırılacak** | Kırık (`user_api_keys` yok), `CORS: *`, kimlik doğrulaması çalışmıyor |
| **SSE (`api/v1/sse.php`)** | **Güvenlik nedeniyle kaldırılacak** | Kırık sütun + `while(true)` sonsuz döngü, kaynak tüketimi |
| **Superadmin 4 haneli PIN girişi** | **Güvenlik nedeniyle kaldırılacak** | 10.000 kombinasyon, limit yok, arka kapı deseni |
| **Oto-migrasyon (`header.php` ALTER'ları)** | **Güvenlik nedeniyle kaldırılacak** | Her istekte DDL; uygulama kullanıcısının ALTER yetkisi olmamalı |
| **Lisans kontrolü + `tools/encode.php`** | **Kullanılmayacak** | Etkisiz koruma; kendi sistemimizde anlamsız |
| **`install/` sihirbazı** | **Güvenlik nedeniyle kaldırılacak** | Web'den erişilebilir DB oluşturucu |
| **Docroot'taki 4 ZIP + `error_log`'lar** | **Güvenlik nedeniyle kaldırılacak** | Kaynak kod + DB parolası sızıntısı (§5.1) |
| **`__MACOSX/`, `tests/`, `tools/`, boş `logs/`** | **Kullanılmayacak** | Çöp |
| **`sanitize()` girdi-anında kaçış** | **Kullanılmayacak** | Anti-desen; çıktı-anında kaçış (şablon motoru) kullanılacak |

---

## 9. Öncelikli Eylem Listesi (yeni sistem kararlarından bağımsız)

> Bunlar **öneri**dir; kullanıcı onayı olmadan uygulanmadı.

| # | Aciliyet | Eylem |
|---|---|---|
| 1 | **Hemen** | Docroot'taki 4 ZIP dosyasını web erişiminden kaldır — `includes/config.php` (DB parolası + `SECRET_KEY` + `JWT_SECRET`) indirilebilir durumda |
| 2 | **Hemen** | DB parolasını, `SECRET_KEY`'i ve `JWT_SECRET`'i döndür (rotate) — sızmış kabul edilmeli |
| 3 | Yüksek | Superadmin 4 haneli PIN girişini kapat veya hız sınırı + kilit ekle |
| 4 | Yüksek | `admin/api/*.php` uç noktalarına rol kontrolü + CSRF ekle |
| 5 | Yüksek | `error_log` dosyalarını docroot dışına taşı / erişimi engelle |
| 6 | Orta | `install/` klasörünü kaldır |
| 7 | Orta | Oturum ömrünü makul seviyeye çek, `cookie_secure=1`, girişte `session_regenerate_id()` |
| 8 | Orta | `uploads/` altında PHP yürütmeyi engelle |
| 9 | Düşük | `notification_queue`'daki 1724 `table_alert` satırını arşivle/temizle; masaları `free`'ye çek |

---

## 10. Belirsiz Kalan Noktalar

- `tests/run-tests.php` ve `tests/test-helpers.php` içeriği okunmadı → test kapsamı bilinmiyor.
- `admin/floor-plan.php` (48 KB) ve `menu/index.php` (115 KB) satır satır okunmadı; bulgular yapısal ölçüm ve hedefli grep'e dayanıyor.
- `formatLogSummaryTr()` çıktısının çağrı yerlerinde HTML kaçışı yapılıp yapılmadığı doğrulanmadı (potansiyel saklı XSS).
- `EN GÜNCEL VERSİYON KALICI.zip` içeriği listelenemedi (arşiv okuma hatası) — içinde `config.php` olup olmadığı **doğrulanamadı**; ihtiyatlı davranıp "sızmış" varsayılmalı.
- Web sunucusunun bu ZIP'lere gerçekten HTTP 200 döndürdüğü görev brief'inde bildirildi; bu denetimde ağ isteğiyle **yeniden doğrulanmadı** (yalnız `.htaccess` kuralları incelendi ve `.zip`'i engelleyen kural bulunmadı — bulgu tutarlı).
- `orders.status = ''` olan 7 kaydın iş anlamı ("tamamlandı" mı, "iptal" mi) veriden kesin çıkarılamıyor; `completed_at` ve `payment_status` ile çapraz kontrol gerekir.
