# Veri Aktarım Planı — Eski "PROMENU" → QR Menü SaaS

**Ajan:** Mimari-Karar · **Tarih:** 2026-07-22
**Kaynak:** DB `oritoriu_menu` (hesap `oritoriu`) — **SALT-OKUNUR, kaynağa yazma/dokunma KESİNLİKLE YOK**
**Hedef:** DB `qrmenu_app` (hesap `qrmenu`), Laravel 13, çok kiracılı şema (ADR-004)
**Girdi ölçümleri:** `LEGACY_SYSTEM_AUDIT.md` (bu plan oradaki satır sayıları ve şema tespitlerine dayanır)

---

## 1. Niteleme: Bu bir "büyük göç" DEĞİL — **temiz başlangıç + seçmeli tohumlama**

LEGACY_SYSTEM_AUDIT §4 kesin sonucu: **sistemde gerçek işletme verisi yok.** 11 sipariş (5 ayda), 68 demo ürün (adları ASCII'leşmiş, görselleri Unsplash), 1 kullanıcı (geliştiricinin kendisi), 1747 satırlık bildirim çöpü. Korunması gereken müşteri geçmişi, ciro, cari, rezervasyon **yoktur**.

Dolayısıyla:
- Yeni sistem **boş ve temiz** kurulur; migrasyonlar + seeder'lar tek doğruluk kaynağıdır.
- Eski veriden yalnız **kürasyondan geçirilmiş katalog verisi** tohum (seed) olarak alınır (§2).
- Bu belgedeki tam eşleme tablosu (§4), **ileride gerçek veriyle çalışan bir PROMENU kurulumu** devralınırsa kullanılacak şablondur; script kuralları (§6) o güne de aynen geçerlidir.

---

## 2. Ne taşınacak / taşınmayacak — KARAR

| Veri kümesi | Satır | Karar | Gerekçe |
|---|---|---|---|
| `allergens` (8) | 8 | **TAŞINIR — global sözlük seed'i** | Alerjen listesi kiracıdan bağımsız standart sözlük; hazır ve doğru |
| `categories` (12) + `products` (68) + `product_extras` (28) + `product_product_extras` (467) | 575 | **TAŞINIR — "örnek kafe menüsü" şablon seed'i olarak, kürasyonla** | Gerçekçi, dolu bir TR kafe menüsü; demo kiracısı ve yeni kiracı onboarding'inde "hazır şablon menü" olarak değerli. **Kürasyon şartı:** Türkçe diyakritik kaynakta kayıp ("Sigara Boregi" → "Sigara Böreği") — seed dosyasında elle düzeltilir; `name_en/de/ar` doluysa çeviri tablosuna alınır |
| `product_images` (68, hepsi Unsplash URL) | 68 | **KISMEN** — URL'ler seed kürasyonunda **yerel dosyaya indirilir**; hotlink taşınmaz | Prod sistem üçüncü taraf hotlink'e bağlanamaz; `uploads/` diskte 0 dosya (ölçüldü) → kopyalanacak dosya yok |
| `tables` (16) + `table_areas` (5) | 21 | **TAŞINIR — demo kiracısının salon şablonu** | Temiz veri; durumlar sıfırlanır (`free`), yeni QR token üretilir (ADR-008 — eski `?table=id` deseni ölür) |
| `announcements` (12) + `cafe_events` (8) + `broadcasts` (3) | 23 | **TAŞINIR (isteğe bağlı, demo içerik)** — tek `contents` modeline | Demo kiracısını dolu göstermek için; canlı kiracıya gitmez |
| `settings` (35) | 35 | **TAŞINMAZ** (yalnız 3-5 anahtar elle referans alınır: `currency=TRY`, `tax_rate=10`, çalışma saatleri) | Değerler placeholder (`site adı`, `sada\nasdasd`, `dfsad`); yeni ayar modeli kiracı-bazlı ve farklı |
| `settings.floor_plan_layout` (JSON blob) | 1 | **TAŞINMAZ** | Yeni sistemde salon planı kendi tablosunda; eski blob demo değeri taşımıyor |
| `users` (1: `admin`) | 1 | **TAŞINMAZ** | Geliştirici hesabı; yeni sistemde kullanıcılar sıfırdan, parola sıfırlama akışıyla açılır. (Gerçek kurulum devralınırsa: bcrypt `$2y$` hash'leri Laravel ile birebir uyumludur, hash olduğu gibi taşınır — §4.11) |
| `orders` (11) + `order_items` (34) + `order_payments` (2) | 47 | **TAŞINMAZ — arşivlenir** | Demo; 7/11'inde `status=''` (bozuk ENUM). Tek seferlik dump arşivde saklanır (§7), yeni DB'ye girmez |
| `notification_queue` (1747) | 1747 | **TAŞINMAZ** | %79'u `table_alert` spam'i; tamamı çöp |
| `activity_logs` (84), `waiter_calls` (10), `reviews` (3) | 97 | **TAŞINMAZ** | Demo operasyon izi; iş değeri yok |
| Boş 12 tablo (`branches`, `campaigns`, `customers`, `customer_debts`, `debt_payments`, `newsletter_subscribers`, `product_allergens`, `product_variants`, `qr_codes`, `reservations`, `role_permissions`, `shifts`) | 0 | **TAŞINACAK VERİ YOK** | 0 satır; yalnız şema eşlemesi §4'te |

**Net sonuç:** Yeni DB'ye giren tek şey ≈ 700 satırlık, elle gözden geçirilmiş katalog+salon+içerik seed'i; tamamı **tek demo kiracısı** altında.

---

## 3. Hedef yerleşim: her şey tek kiracı altına

Hedef şema çok kiracılı (ADR-004: `tenants` → `branches` → veri). Eski sistem tek işletme olduğundan:

| Hedef kayıt | Değer |
|---|---|
| `tenants` | 1 kayıt: `demo` (örnek/şablon kiracı; "powered by bogahost" dışında hiçbir marka metni yok) |
| `branches` | 1 kayıt: `demo-merkez` (eski veride `branch_id` hepsi NULL ve `branches` 0 satır — LEGACY §2.7 — yani şube ayrımı zaten hiç yok) |
| Tüm seed satırları | `tenant_id = <demo>`, `branch_id = <demo-merkez>` |

Gerçek kurulum devralınırsa aynı kural: kurulum başına 1 tenant; `branches` doluysa şubeler birebir eşlenir, boşsa tek branch açılır.

---

## 4. Tam Eşleme Tablosu (eski → yeni)

> Bu bölüm **gelecekteki gerçek-veri aktarımının şablonudur**; §2'de "taşınmaz" denilen tablolar için de eşleme verilir.
> Ortak kurallar her tabloya uygulanır: `+ tenant_id, branch_id` eklenir; `created_at/updated_at` §5.2'ye göre UTC'ye çevrilir; para alanları §5.3'e göre ×100 kuruş-integer olur; eski `id` doğrudan taşınmaz, `legacy_id_map` üzerinden yeni id atanır (§6).

### 4.1 Tablo düzeyi özet

| Eski tablo | Yeni tablo | Not |
|---|---|---|
| `categories` | `categories` + `category_translations` | dil kolonları çeviri tablosuna |
| `products` | `products` + `product_translations` | " ; denormalize sayaçlar taşınmaz |
| `product_images` | `product_media` | dosya yerel depoya |
| `product_extras` / `product_product_extras` | `modifiers` / `modifier_product` | ekstra = "modifier" genel modeli |
| `product_variants` | `product_variants` (+çeviri) | 0 satır; şema eşlemesi hazır |
| `allergens` / `product_allergens` | `allergens` (global) / `allergen_product` | sözlük global, bağ kiracı verisi |
| `tables` | `tables` | + `qr_token`; `status` ayrıştırılır (§4.7) |
| `table_areas` | `table_areas` | birebir |
| `orders` | `orders` | `table_number` VARCHAR → `table_id` FK (§4.8) |
| `order_items` | `order_items` | `extras` JSON → `order_item_modifiers` satırları |
| `order_payments` (+`orders.payment_status`) | `payments` | **tek doğruluk kaynağı** (ADR-010); iki eski yol birleştirilir |
| `waiter_calls` | `waiter_calls` | birebir + FK'ler tamamlanır |
| `reservations` | `reservations` | 0 satır; kapasite/çakışma yeni |
| `users` | `users` + rol/izin tabloları | rol ENUM → RBAC kayıtları |
| `role_permissions` | `permissions`/`role_has_permissions` | 0 satır; hard-coded matris yeni sistemde seed |
| `customers`, `newsletter_subscribers` | — (v1 kapsam dışı) | 0 satır; ileride `customers` |
| `customer_debts`, `debt_payments` | — (v1 kapsam dışı) | 0 satır |
| `shifts` | — (v1 kapsam dışı) | 0 satır |
| `campaigns`, `campaign_products` | `campaigns`, `campaign_product` | 0 satır; şema yeni kurulur |
| `announcements`, `cafe_events`, `broadcasts` | `contents` (tek model, `type` alanlı) | LEGACY §8 önerisi |
| `reviews` | `reviews` | moderasyonlu; demo veri taşınmaz |
| `settings` | `tenant_settings` (key-value, kiracı bazlı) | seçmeli; §2 |
| `qr_codes` | `qr_scans` (analitik) | eski tablo 0 satır; kavram değişti |
| `activity_logs` | `activity_log` (spatie tarzı) | eski kayıtlar taşınmaz |
| `notification_queue` | `notifications`/outbox (TTL'li) | veri taşınmaz |
| (yok) `user_api_keys` | — | kaynakta tablo zaten yok (kırık API); eşlenecek şey yok |

### 4.2 `categories` → `categories` (+`category_translations`)

| Eski alan | Yeni alan | Dönüşüm |
|---|---|---|
| `id` | — | `legacy_id_map('category', id)` |
| `parent_id` | `parent_id` | map üzerinden; sıra: önce ebeveynler (2 geçiş) |
| `branch_id` (hep NULL) | `branch_id` | demo-merkez |
| `name`, `name_en/de/ar` | `category_translations(locale, name)` | `tr` satırı kürasyonla diyakritik düzeltmeli; boş dil satırı açılmaz |
| `slug` | `slug` | yeniden üretilir (TR karakter düzeltmesi sonrası), `UNIQUE(tenant_id, slug)` |
| `description`, `icon`, `image`, `color` | aynı adlar | `image` varsa medya kopyası (§8) |
| `time_start/time_end` | `available_from/available_until` | TIME, olduğu gibi |
| `sort_order`, `is_active` | aynı | — |
| `is_alcohol` | `is_alcohol` | — |

### 4.3 `products` → `products` (+`product_translations`)

| Eski alan | Yeni alan | Dönüşüm |
|---|---|---|
| `id` | — | map |
| `category_id`, `branch_id` | map / demo-merkez | — |
| `sku` | `sku` | `UNIQUE(tenant_id, sku)` |
| `name`+3 dil, `description`+3 dil | `product_translations` | kürasyon (diyakritik) |
| `slug` | `slug` | yeniden üretilir, tenant-scoped |
| `base_price` DEC(10,2) | `base_price_minor` BIGINT | **×100** (§5.3) |
| `happy_hour_price` | `happy_hour_price_minor` | ×100; NULL korunur |
| `happy_hour_start/end` | aynı | TIME |
| `cost_price` | `cost_price_minor` | ×100 |
| `tax_rate` DEC(5,2) | `tax_rate` | oran, olduğu gibi (kaynakta hepsi 0.00 — KDV yeni sistemde kiracı ayarından gelir, LEGACY §3.7) |
| `calories/protein/carbs/fat`, `preparation_time` | aynı | — |
| `stock_status` ENUM, `stock_quantity`, `daily_stock_*`, `min_stock_alert` | `stock_*` | ENUM değerleri birebir (`in_stock/limited/out_of_stock`) |
| `badge` ENUM, `is_vegetarian/vegan/gluten_free`, `video_url` | aynı | — |
| `sort_order`, `is_active`, `is_featured` | aynı | — |
| `view_count`, `order_count`, `rating_avg`, `rating_count` | **taşınmaz** | türetilmiş/denormalize demo sayaçları; yeni sistemde kendi tablolarından türer |

### 4.4 `product_images` → `product_media`

| Eski | Yeni | Dönüşüm |
|---|---|---|
| `product_id` | map | — |
| `image_path` (68/68 Unsplash URL) | `path` | **URL indirim adımı:** seed kürasyonunda dosya indirilir → `storage/app/public/tenants/<t>/products/…`; indirilemeyen → satır atlanır ve raporlanır. Gerçek kurulumda: yerel yol ise dosya kopyası (§8) |
| `thumbnail_path`, `webp_path` | — | taşınmaz; türevler yeni sistemde üretilir |
| `is_primary`, `sort_order` | aynı | — |

### 4.5 `product_extras` → `modifiers`; `product_product_extras` → `modifier_product`

| Eski | Yeni | Dönüşüm |
|---|---|---|
| `name`+3 dil | `modifier_translations` | kürasyon |
| `price` DEC(10,2) | `price_minor` | ×100 |
| `icon`, `is_active` | aynı | — |
| pivot (`product_id`,`extra_id`) | (`product_id`,`modifier_id`) | map×2; 467 bağ birebir |

### 4.6 `allergens` → `allergens` (global sözlük); `product_allergens` → `allergen_product`

8 satır (`name`+3 dil, `icon`, `color`, `description`) birebir, **tenant_id'siz** (küresel sözlük). Bağ tablosu kaynakta 0 satır; eşleme map×2.

### 4.7 `tables`/`table_areas` → `tables`/`table_areas`

| Eski | Yeni | Dönüşüm |
|---|---|---|
| `tables.name` (global UNIQUE) | `name`, `UNIQUE(branch_id, name)` | — |
| `capacity`, `area_id`, `sort/is_active` | aynı; `area_id` map + **gerçek FK** | kaynakta FK yoktu |
| `status` ENUM + `occupied_since/last_order_at/last_reminder_at` | **taşınmaz** — hepsi `free`/NULL başlar | 15/16 masa demo'dan beri `occupied` kilitli (LEGACY §3.4); operasyonel durum seed'e girmez |
| `game_fee` DEC(10,2) | `game_fee_minor` | ×100 (hepsi 0) |
| (yok) | `qr_token` | **her masaya yeni üretilir** (ADR-008) |
| `table_areas.*` | birebir | — |

### 4.8 `orders` → `orders` (yalnız gerçek-veri senaryosu; demo taşınmaz)

| Eski | Yeni | Dönüşüm |
|---|---|---|
| `order_number` | `order_number` | `UNIQUE(tenant_id, order_number)`; korunur |
| **`table_number` VARCHAR(50)** | **`table_id` FK (nullable)** | Çözümleme: `table_number = tables.name` YA DA `= CAST(tables.id AS CHAR)` (kaynaktaki karışık desen — LEGACY §3.3); eşleşmeyen → `table_id=NULL` + orijinal değer `table_label` kolonunda saklanır + rapora yazılır |
| `status` ENUM(6) + boş string vakaları | `status` | `'' → completed_at doluysa 'completed', değilse payment_status='paid' ise 'completed', aksi halde 'unknown'+rapor` (LEGACY §10 belirsizliği: kural budur, elle onaylanır) |
| `subtotal/discount_amount/tax_amount/total_amount` DEC | `*_minor` | ×100; `subtotal-discount+tax = total` doğrulaması, tutmayan satır raporlanır |
| `payment_status`, `payment_method` | **`payments` tablosuna türetilir** | `order_payments` kaydı varsa o esas; yoksa `payment_status='paid'` olan siparişe tek sentetik `payments` satırı (`source='migrated_orders_flag'`) — iki eski yol tek kaynakta birleşir (ADR-010) |
| `customer_*`, `order_type`, `special_instructions`, `delivery_*`, `estimated_time`, `source` | aynı adlar | `delivery_fee` ×100 |
| `campaign_id`, `staff_id`, `customer_id` | map (FK, SET NULL) | — |
| `created_at/confirmed_at/completed_at` | aynı | TZ dönüşümü (§5.2) |
| `loyalty_points_earned` | taşınmaz (v1 kapsam dışı) | raporda not edilir |

`order_items`: `product_id` map (silinmiş ürün → NULL + `product_name` denormalize kopyası zaten var, korunur); `unit_price/total_price` ×100; `extras` JSON → `order_item_modifiers` satırlarına açılır (ad+fiyat_minor); `variant_id` (kaynakta hep NULL) map; `is_complimentary` birebir.

### 4.9 `order_payments` → `payments`

`order_id` map; `amount` ×100 → `amount_minor`; `payment_method` ENUM birebir; `idempotency_key = 'legacy-op-<eski_id>'` (idempotent tekrar-koşum garantisi).

### 4.10 İçerik: `announcements`/`cafe_events`/`broadcasts` → `contents`

`type = announcement|event|broadcast`; ortak alanlar (`title/body/is_active/tarih`) birebir; tipe özgü alanlar (`event_type`, `team_home/away`, `channel`, `match_time`, `recurring`) `payload` JSON'a.

### 4.11 `users` → `users` (yalnız gerçek-veri senaryosu)

`username/email` → `UNIQUE(tenant_id, email)`; **parola bcrypt hash'i olduğu gibi taşınır** (`$2y$10$` Laravel uyumlu — kullanıcılar parolalarını korur); `role` ENUM(9) → yeni RBAC rol ataması (eşleme: superadmin/owner/admin→`owner|admin`, manager→`manager`, chef/barista/komi→`kitchen`, cashier→`cashier`, staff→`staff`); `hourly_rate` ×100; `last_login/avatar/phone` birebir. 4 haneli superadmin PIN mekanizması **taşınmaz** (LEGACY §5.6).

---

## 5. Dönüşüm Kuralları

### 5.1 Charset / collation
- **Ölçülen gerçek (LEGACY §2):** kaynak DB zaten `utf8mb4` / `utf8mb4_unicode_ci` (tek istisna `role_permissions` = `general_ci`, ki taşınmıyor). **Mojibake yok, charset dönüşümü GEREKMİYOR.** Aktarım bağlantıları yine de açıkça `charset=utf8mb4` kurar (sunucu default'u latin1 — kazara latin1 bağlantı = bozulma).
- Türkçe karakter sorunu **veri kalitesi** sorunudur (kaynakta ASCII girilmiş): `SigaraBoregi→Böreği` düzeltmesi charset işi değil, **seed kürasyonu** işidir (§2). Otomatik "ASCII→TR" dönüştürücü yazılmaz (Kizartma→Kızartma güvenli değil: "sik/şık" tipi belirsizlikler); 12 kategori + 68 ürün elle düzeltilir (~1 saat).
- Hedef DB oluşturma: `CREATE DATABASE qrmenu_app CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;` (SERVER_AUDIT §6/8).

### 5.2 Tarih / saat dilimi
- Kaynak: PHP `Europe/Istanbul` (config.php) + MySQL DATETIME (naif) → tüm eski zaman damgaları **Europe/Istanbul yerel saatidir**.
- Hedef: Laravel `app.timezone=UTC`, DB'de UTC saklanır, görüntüde Istanbul'a çevrilir.
- Dönüşüm: her DATETIME `Europe/Istanbul → UTC` (Carbon; TR'de 2016'dan beri DST yok, sabit +03:00 — yine de kütüphaneyle, elle -3 değil).
- Salt-TIME alanları (`time_start`, `happy_hour_*`, `daily_stock_reset_time`) **yerel saat anlamı taşır**, çevrilmez; yeni sistemde "şube yerel saati" olarak yorumlanır (branch'te `timezone` kolonu, default `Europe/Istanbul`).

### 5.3 Para: DECIMAL(10,2) → kuruş-integer (ADR-007)
- Kaynakta float yok (LEGACY §3.7) → dönüşüm **kayıpsız ve deterministik**: `amount_minor = CAST(ROUND(amount * 100) AS SIGNED)`.
- Doğrulama: her tabloda `SUM(eski)*100 == SUM(yeni_minor)` (§9).
- Kaynaktaki `tax_amount/discount_amount` fiilen hep 0 (KDV hiç işlememiş) — dönüşümde sorun üretmez.

---

## 6. Aktarım Scriptlerinin Kuralları (bağlayıcı)

Scriptler `php artisan legacy:import {entity} [--dry-run]` biçiminde artisan komutlarıdır; repo içinde `app/Console/Commands/LegacyImport/` altında yaşar.

| Kural | Uygulama |
|---|---|
| **Kaynağa asla yazmaz** | Scriptler kaynağa hiç bağlanmaz; yalnız **staging kopyasını** okur (§7). Staging bağlantısı da `qrmenu_legacy` kullanıcısıyla salt SELECT grant'lidir — yanlışlıkla yazma DB katmanında da engelli |
| **Idempotent** | Her satır `legacy_id_map (entity, legacy_id, new_id, imported_at)` UNIQUE(entity, legacy_id) üzerinden upsert; ikinci koşum aynı sonucu verir, mükerrer üretmez |
| **Transaction'lı** | Entity başına chunk'lı (500 satır) transaction; chunk içi hata → o chunk rollback, sonraki chunk devam |
| **Dry-run** | `--dry-run`: hedefe yazmaz, tüm dönüşüm+doğrulamayı koşar, tam rapor üretir. Canlı koşumdan önce dry-run **zorunlu** |
| **Log** | `storage/logs/legacy-import-<tarih>.log`: satır bazında sonuç (ok/atlandı/hata + neden), sonda özet sayım tablosu |
| **Hatalıyı atla + raporla** | Tek bozuk satır koşumu durdurmaz; `import_rejects` tablosuna (entity, legacy_id, sebep, ham veri JSON) yazılır; koşum sonunda insan incelemesi |
| **Sıra bağımlılığı** | tenants → branches → areas → tables → allergens → categories(2 geçiş: parent) → modifiers → products → media → pivotlar → (gerçek-veri: users → orders → items → payments) |
| **Kod tekrar-koşulabilirliği** | Komutlar migration değil komuttur; prod'da bir kez, staging'de istendiği kadar koşulur |

---

## 7. Hesaplar Arası Erişim: tek seferlik dump → staging (kaynağa sıfır temas)

**Karar: canlı kaynak DB'ye bağlanılMAZ; tek seferlik dump ile çalışılır.**

| Adım | Komut / detay | Kim |
|---|---|---|
| 1. Dump | `mysqldump --single-transaction --no-tablespaces --default-character-set=utf8mb4 oritoriu_menu > /home/qrmenu/migration/oritoriu_menu_$(date +%F).sql` | root (tek MariaDB sunucusu; `--single-transaction` kaynağı kilitlemez, salt-okur) |
| 2. Sahiplik | `chown qrmenu:qrmenu` + `chmod 600` — dump DB parolası içermez ama veri içerir; `migration/` docroot dışında | root → hemen devir (find -user root = 0 kuralı) |
| 3. Staging DB | cPanel'den `qrmenu_legacy` (utf8mb4) + kullanıcı `qrmenu_legacy_ro`; import: `mysql qrmenu_legacy < dump.sql`; sonra kullanıcıya yalnız `SELECT` grant | qrmenu |
| 4. Import koşumları | Artisan komutları `qrmenu_legacy`'den okur, `qrmenu_app`'e yazar | qrmenu |
| 5. Arşiv | Dump + import logları + reject raporu `migration/archive/`'a; **demo sipariş verisinin kalıcı arşivi de budur** (§2 "arşivlenir" kararı) | qrmenu |
| 6. Temizlik | Staging DB kurulum onayından sonra silinebilir; arşiv dump'ı kalır | qrmenu |

**Reddedilen alternatif — kaynağa salt-okuma MySQL kullanıcısı:** teknik olarak mümkün (aynı MariaDB) ve `oritoriu_menu` verisine yazmaz; ancak (a) grant işlemi kaynak hesabın DB yönetiminde değişiklik demektir (salt-okunurluk taahhüdünün ruhuna aykırı), (b) canlı sisteme koşum sırasında sorgu yükü bindirir, (c) tekrarlanabilirlik dump kadar iyi değildir (kaynak değişirse koşumlar tutarsızlaşır). Dump anlık görüntüsü hem izole hem kanıtlanabilir.

---

## 8. Medya / Görsel Kopyası (taşıma değil, kopya)

- **Ölçülen:** `/home/oritoriu/public_html/uploads/` altındaki tüm alt klasörler **boş — 0 dosya** (LEGACY §1.1); 68 ürün görselinin tamamı Unsplash URL'i. **Bu kurulumda kopyalanacak dosya yok.**
- Seed görselleri: kürasyon sırasında Unsplash URL'lerinden indirilecek dosyalar doğrudan `qrmenu` hesabında üretilir (§4.4) → sahiplik zaten `qrmenu:qrmenu`. (Not: Unsplash lisansı ticari kullanım için serbesttir; yine de demo kiracısıyla sınırlı tutulur, canlı kiracıya kendi görselleri yüklenir.)
- **Gerçek kurulum devralınırsa prosedür:** `rsync -a` (KOPYA — kaynaktan silme yok, `--remove-source-files` YASAK) `oritoriu` docroot'undaki `uploads/` → `/home/qrmenu/apps/qrmenu/storage/app/public/tenants/<t>/…`; root koşarsa ardından zorunlu `chown -R qrmenu:qrmenu` + `find ... -type d -exec chmod 750` / `-type f -exec chmod 640`; import scripti dosya varlığını doğrular, eksik dosyalı medya satırı reject'e düşer. Kaynak dizinde hiçbir dosya değiştirilmez/silinmez.

---

## 9. Doğrulama SQL'leri ve Geri Alma

### 9.1 Doğrulama (her koşum sonunda otomatik + elle)

```sql
-- Sayım mutabakatı (entity başına; beklenen = kaynak - reject)
SELECT 'categories' e, (SELECT COUNT(*) FROM qrmenu_legacy.categories) src,
       (SELECT COUNT(*) FROM qrmenu_app.categories WHERE tenant_id=@t) dst,
       (SELECT COUNT(*) FROM qrmenu_app.import_rejects WHERE entity='category') rej;
-- (products, modifiers, tables, ... aynı desen)

-- Para mutabakatı (×100 kayıpsızlık kanıtı)
SELECT (SELECT CAST(SUM(base_price*100) AS SIGNED) FROM qrmenu_legacy.products) src_minor,
       (SELECT SUM(base_price_minor) FROM qrmenu_app.products WHERE tenant_id=@t) dst_minor;

-- Pivot bütünlüğü (467 bağ)
SELECT (SELECT COUNT(*) FROM qrmenu_legacy.product_product_extras) src,
       (SELECT COUNT(*) FROM qrmenu_app.modifier_product mp
         JOIN qrmenu_app.products p ON p.id=mp.product_id WHERE p.tenant_id=@t) dst;

-- Yetim kontrolü (FK'ler zaten engeller; map tutarlılığı)
SELECT * FROM qrmenu_app.legacy_id_map m
 LEFT JOIN qrmenu_app.products p ON m.entity='product' AND p.id=m.new_id
 WHERE m.entity='product' AND p.id IS NULL;

-- Charset kanıtı (kürasyon sonrası TR karakter varlığı)
SELECT COUNT(*) FROM qrmenu_app.product_translations
 WHERE locale='tr' AND name REGEXP '[çğıöşüÇĞİÖŞÜ]';  -- 0 ise kürasyon yapılmamış demektir

-- (gerçek-veri senaryosu) sipariş tutar bütünlüğü
SELECT o.id FROM qrmenu_app.orders o
 WHERE o.subtotal_minor - o.discount_minor + o.tax_minor <> o.total_minor;
```

Elle kabul: demo kiracısında menü sayfası açılır, 12 kategori/68 ürün/fiyatlar/ekstralar gözle karşılaştırılır (kaynak ekran görüntüsüyle).

### 9.2 Geri alma

| Senaryo | Yöntem |
|---|---|
| Import bozuk çıktı (canlı kiracı yokken — beklenen durum) | En basit ve tercih edilen: demo tenant'ı sil (`DELETE FROM tenants WHERE id=@t` — FK CASCADE tüm seed'i götürür) + `legacy_id_map`/`import_rejects` truncate → yeniden koş. Kaynak ve arşiv dump'ı el değmemiş durur |
| Canlı kiracılar varken gerçek-veri importu (gelecek senaryo) | Koşumdan hemen önce `mysqldump qrmenu_app` (ADR-012 altyapısı) → sorun halinde restore; import tek tenant'a yazdığı için tenant-sil + yeniden koşum da geçerli |
| Kaynak tarafı | Geri alınacak bir şey **yok** — kaynağa hiçbir aşamada yazılmadı (dump `--single-transaction` salt okuma) |

---

## 10. Açık / Belirsiz Noktalar

| Konu | Durum |
|---|---|
| 68 ürün adının TR diyakritik kürasyonu | İnsan işi (~1 saat), seed PR'ında yapılacak; otomatikleştirilmeyecek (§5.1 gerekçesi) |
| `orders.status=''` 7 kaydın iş anlamı | Demo olduğu için taşınmıyor; gerçek-veri senaryosunda §4.8 kuralı + elle onay (LEGACY §10 belirsizliği aynen geçerli) |
| Unsplash görsellerinin indirilebilirliği | Koşum anında doğrulanır; kırık URL → ürün görselsiz seed'lenir, raporlanır |
| `qrmenu_legacy` staging DB'sinin cPanel'de açılması | qrmenu hesabından yapılabilir (MAXSQL unlimited — SERVER_AUDIT); onay gerekmez, dump adımı (root) gerekir |
