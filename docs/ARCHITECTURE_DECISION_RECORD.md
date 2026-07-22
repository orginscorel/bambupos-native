# Mimari Karar Kaydı (ADR) — QR Menü / Restoran Yönetim Platformu

**Ajan:** Mimari-Karar · **Tarih:** 2026-07-22 · **Faz:** 0 (kapanış)
**Girdiler:** `SERVER_AUDIT.md`, `LEGACY_SYSTEM_AUDIT.md` (bu belge oradaki ölçümleri tekrarlamaz, referans verir)
**Durum etiketi:** Aksi yazılmadıkça tüm kararlar **KABUL EDİLDİ**.

## Ortam Kısıtları (kararların zemini — SERVER_AUDIT'ten)

| Kısıt | Etkisi |
|---|---|
| ea-php83 (8.3.32) tavan; 8.4/8.5 kurulu değil | Framework sürüm stratejisi (ADR-001) |
| Redis / Supervisor / pm2 / Passenger yok | Queue/cache/lock = database; daemon worker yok (ADR-005) |
| Node hesap içinde yok | Vite build sunucu dışında (ADR-003) |
| LiteSpeed ~50 PHP istek/sn **IP başına**; restoran = tek NAT IP | Public menü tam-sayfa cache **zorunlu** (ADR-011) |
| MariaDB 10.11, sunucu default `latin1` | DB açıkça `utf8mb4_unicode_ci` (ADR-004) |
| Sunucuda hiç otomatik yedek yok | Proje kendi yedeğini kurar (ADR-012) |
| `publichtmlsubsonly=1` | Docroot root-düzeyi userdata düzenlemesiyle `apps/qrmenu/public`'e alınır (SERVER_AUDIT §6, kanıtlı desen) |
| Shell açık, cron açık, Composer var | Kurulum/bakım SSH'dan; cron tabanlı worker mümkün |
| Ürün: **çok kiracılı SaaS** | Kuruma özel marka/metin yok; yalnız "powered by bogahost". İlk müşteri: belediye sosyal tesisleri (çok şube, tek kiracı) |

---

## ADR-001 — Backend framework: Laravel 13 (PHP 8.3)

**Bağlam.** Hedef cPanel/LiteSpeed paylaşımlı hosting; kalıcı process çalıştırma altyapısı (Supervisor/pm2/systemd) yok; PHP tavanı 8.3; ekipteki tüm mevcut sistemler (DCIM, Task, finans, LiveChat) Laravel.

**Karar.** Laravel 13, ea-php83 üzerinde. `composer.json` → `"config": {"platform": {"php": "8.3.32"}}` ile bağımlılık çözümü 8.3'e sabitlenir; `composer.lock` repoda tutulur.

**Gerekçe / Alternatifler:**

| Ölçüt | Laravel (PHP) | Node/NestJS | Go |
|---|---|---|---|
| cPanel/LiteSpeed uyumu | Yerleşik (lsapi), 3 kanıtlı canlı örnek aynı sunucuda | Kalıcı process + reverse proxy gerekir — **sunucuda Passenger/pm2 yok** | Aynı sorun: kalıcı binary + proxy |
| Sürekli process ihtiyacı | Yok (request-per-process) | Zorunlu | Zorunlu |
| Deployment | git + composer, shell'den | Node hesapta bile yok | Binary kopyalama; ama proxy/port yönetimi yok |
| Queue | database driver + cron (ADR-005) | BullMQ → Redis ister (yok) | Kendin yaz |
| Güvenlik varsayılanları | CSRF/auth/policy/ORM hazır — eski sistemin tüm açık sınıflarını (LEGACY §5) framework kapatır | Elle kurulur | Elle kurulur |
| POS/yazıcı/ödeme ekosistemi | iyzico/PayTR PHP SDK'ları, mevcut PayTR deneyimi | Var ama ekip deneyimi yok | Zayıf |
| Geliştirme hızı / bakım | Ekip 5 Laravel uygulaması işletiyor | Sıfır işletme deneyimi bu sunucuda | Sıfır |

Node ve Go bu **sunucuda çalıştırılamadığı** için (kalıcı process + kullanıcı-erişilebilir runtime yok) alternatif değil, teoride kalıyor.

**PHP 8.3 tavanı riski ve azaltma.** SERVER_AUDIT §2 notu: Laravel 13'ün ileri minor'larının (Symfony 8 bağımlılıkları üzerinden) pratikte 8.4 isteyebileceği raporları **teyitsiz**. Plan:
1. `platform.php=8.3.32` + `composer.lock` → çözümleme asla 8.3 üstü paket seçmez; `composer update` kontrollü yapılır.
2. Minor güncellemede lock diff'inde `php` gereksinimi denetlenir; 8.4 dayatan paket gelirse o minor atlanır (güvenlik yamaları backport'la gelir).
3. 8.4 **kaçınılmaz** olursa: WHM » EasyApache 4'ten ea-php84 kurulumu (ayrı onay; sunucudaki diğer siteleri etkilemez — yalnız `qrmenu` hesabının phpversion'ı değiştirilir). Bu yol denenmiş ve düşük riskli; ancak onay gerektirdiği için "son çare" sırasındadır.

**Sonuçlar/ödünler.** Framework güncellemeleri temkinli yapılacak; en-yeni Laravel özellikleri değil kararlılık öncelikli.
**Geri dönüş.** Uygulama standart Laravel olduğundan başka PHP barındırmaya (VPS, başka panel) taşınabilir; framework değişimi öngörülmüyor.

---

## ADR-002 — Modüler monolit (mikroservis değil)

**Bağlam.** Tek sunucu, tek DB, küçük ekip; ama ürün çok modüllü (menü, sipariş, masa, KDS, yazıcı, ödeme) ve SaaS olarak büyüyecek.

**Karar.** Tek Laravel uygulaması, modül sınırları klasörle ve servis arayüzleriyle çizilir:

```
app/Modules/
  Tenancy/    kiracı çözümleme, plan/limit, onboarding
  Identity/   kullanıcı, rol, izin (kaynak+eylem bazlı — LEGACY §3.8 dersinin tersi)
  Catalog/    kategori, ürün, varyant, ekstra, alerjen, çeviri
  Tables/     masa, alan, salon planı, QR token
  Ordering/   sipariş, adisyon, durum makinesi, garson çağrı
  Kds/        mutfak ekranı okuma modelleri + polling uçları
  Payments/   ödeme kayıtları + provider adapter (ADR-010)
  Printing/   print job kuyruğu + adapter (ADR-009)
  Content/    duyuru/etkinlik/yayın (tek içerik modeli)
  Notify/     bildirim üretimi + kanallar
  Reporting/  rapor okuma modelleri
```

Kurallar: modüller birbirinin **modeline değil servisine/eventine** bağlanır; çapraz `use App\Modules\X\Models\...` yalnız aynı modül içinde; modüller arası akış Laravel event'leriyle (`OrderPlaced` → Kds, Notify, Printing dinler).

**Alternatifler.** Mikroservis: bu sunucuda process/queue/gözlem altyapısı yok, ekip boyutu tekil — reddedildi. Düz (modülsüz) monolit: eski sistemin 115 KB tek-dosya kaderi (LEGACY §6.7) — reddedildi.
**Sonuçlar.** Biraz daha fazla iskelet kodu; karşılığında test edilebilir sınırlar.
**Geri dönüş.** Modül sınırları korunursa ileride tek tek servise koparmak (ör. Printing) mümkün; bugün gereksiz.

---

## ADR-003 — Frontend: Vue 3 + TS + Inertia + Vite + Tailwind; public menü Blade

**Bağlam.** Node hesap içinde yok (yalnız `/root/.local/bin`). Public QR menü sayfası tam-sayfa cache'lenmek zorunda (ADR-011) ve düşük donanımlı telefonlarda anında açılmalı.

**Karar — iki katman:**
1. **Yönetim paneli + KDS + kiosk:** Vue 3 + TypeScript + Inertia + Tailwind. Oturumlu, cache'lenmeyen, etkileşimli ekranlar.
2. **Public QR menü (`/m/{token}`):** **Blade + hafif vanilla JS** (sepet/sipariş etkileşimi için küçük, build'siz bir bundle). Gerekçe: tam-sayfa LiteSpeed cache ile mükemmel uyum (HTML çıkışı deterministik), JS framework yükü yok, ilk boyama hızı.

**Build stratejisi (Node yokken):**
- Vite build **sunucuda yapılmaz**. Kaynak repo git'te; build geliştirici makinesinde veya CI'da (`npm ci && npm run build`) çalışır.
- Artefakt = `public/build/` (manifest dahil). Deploy: `rsync -a --delete public/build/ qrmenu@sunucu:/home/qrmenu/apps/qrmenu/public/build/` — **qrmenu kullanıcısıyla**, root'la değil (sahiplik kuralı: `find /home/qrmenu -user root` → 0).
- Sürüm bütünlüğü: build, deploy edilen git commit'iyle aynı commit'ten üretilir; manifest hash'leri cache-bust'ı kendiliğinden çözer.

**Alternatifler.** (a) Kullanıcı home'una nvm kurup sunucuda build — mümkün ama sunucuya Node bakım yükü ve CPU sıçraması ekler (SERVER_AUDIT §11.4); onay gerektirir; **gerekirse B planı**. (b) Root'un Node'uyla sunucuda build — root-sahipli dosya üretir, sahiplik kuralını kırar; reddedildi. (c) Public menüyü de Vue yapmak — cache'lenmiş HTML + hydration karmaşası ve gereksiz JS yükü; reddedildi.
**Sonuçlar.** Deploy adımına "build makinesi" bağımlılığı eklenir; telafi: build çıktısı da git'te tag'lenebilir.
**Geri dönüş.** nvm onayı alınırsa build sunucuya taşınır; kod değişikliği gerekmez.

---

## ADR-004 — Çok kiracılık: tek DB + `tenant_id` (satır düzeyi izolasyon)

**Bağlam.** Çok kiracılı SaaS; ilk müşteri bir belediyenin birden çok tesisi/kafesi. Sunucu paylaşımlı, cPanel DB'leri elle açılıyor, sunucu geneli yedek yok, Redis yok.

**Karar.** Tek veritabanı `qrmenu_app` (`CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci` — sunucu default'u latin1 olduğundan **açıkça**), satır düzeyi kiracılık:

- Hiyerarşi: `tenants` (sözleşme/müşteri) → `branches` (şube/tesis) → operasyonel veriler. Belediye = 1 tenant, N branch. Eski sistemin yarım `branches` niyeti (LEGACY §2.7) burada temelden kurulur.
- Tüm kiracı verisi tablolarında `tenant_id` (+ operasyonelde `branch_id`) NOT NULL; bileşik indeksler `(tenant_id, ...)` ile başlar; eski sistemin global UNIQUE'leri (`tables.name`, `products.sku`, `slug`, `users.email` — LEGACY §8 "tek-işletme varsayımları") `UNIQUE(tenant_id, ...)` olur.
- **Dört savunma katmanı:** (1) `BelongsToTenant` trait → global scope + creating event'inde `tenant_id` otomatik; (2) Policy'ler her modelde tenant eşitliğini ayrıca doğrular; (3) scoped route model binding (`->scopeBindings()`), URL'den gelen her id kiracı süzgecinden geçer; (4) public uçlarda kiracı **yalnız QR token'dan** çözülür (ADR-008), istekten `tenant_id` parametresi asla kabul edilmez.
- Kiracı çözümleme: panelde oturumdaki kullanıcının tenant'ı; public'te token; ileride kiracı-başına subdomain eklenebilir (kolon hazır: `tenants.domain` nullable).

**Alternatifler.** DB-per-tenant: cPanel'de DB açma elle/uzayan onboarding, migrasyonların N DB'de koşulması, `mysqldump` yedeğinin N katı, sunucuda bunu yönetecek otomasyon yok — bu sunucuda **yanlış**; reddedildi. Şema-per-tenant: MariaDB'de ayrı DB demek, aynı sorunlar; reddedildi.
**Sonuçlar.** İzolasyon uygulama katmanında — test zorunlu: her feature testinde ikinci kiracıyla sızıntı denemesi standart olacak. Gürültülü komşu kiracı riski tek DB'de var; `long_query_time=1s` logu izlenir.
**Geri dönüş.** `tenant_id` her tabloda olduğundan, büyük bir kiracı ileride kendi DB'sine `WHERE tenant_id=?` dump'ıyla koparılabilir; model tasarımı bunu engellemez.

---

## ADR-005 — Queue / cache / lock: database sürücüsü + cron-denetimli worker

**Bağlam.** Redis yok; Supervisor/pm2/linger yok → daemon güvenilmez (nohup reboot'ta ölür). Ama shell + cron açık ve MariaDB 10.11 `FOR UPDATE SKIP LOCKED` destekliyor. Sipariş → KDS/yazıcı akışında 60 sn gecikme **kabul edilemez**.

**Karar.**
- `QUEUE_CONNECTION=database`, `CACHE_STORE=database`, `SESSION_DRIVER=database`, atomic lock = cache (database) üzerinden. Laravel'in database queue'su `SKIP LOCKED` kullanır → kilit çekişmesi düşük.
- **Worker modeli: "cron-denetimli kalıcıya-yakın worker"** — SERVER_AUDIT §7'deki `--stop-when-empty` önerisi, sipariş gecikmesi gereksinimiyle **yeniden değerlendirildi ve değiştirildi**:

```cron
* * * * * /usr/bin/flock -n /home/qrmenu/apps/qrmenu/storage/worker.lock \
  /opt/cpanel/ea-php83/root/usr/bin/php /home/qrmenu/apps/qrmenu/artisan \
  queue:work database --sleep=3 --max-time=3600 --memory=256 --tries=3 --backoff=5 >> storage/logs/worker.log 2>&1
* * * * * /opt/cpanel/ea-php83/root/usr/bin/php /home/qrmenu/apps/qrmenu/artisan schedule:run >> /dev/null 2>&1
```

  İşleyiş: worker 1 saat yaşar (`--max-time=3600`, bellek sızıntısı sigortası), kuyruğu 3 sn'de bir yoklar → **iş gecikmesi ≈ 0–3 sn**; öldüğünde/reboot'ta cron+flock en geç 60 sn'de yenisini başlatır; flock ikinci worker'ı engeller. Deploy'da `queue:restart` sinyaliyle güvenli yenilenir.
- Bakım: schedule'da `queue:prune-failed`, `cache:prune-stale-tags` yok (db driver) yerine schedule'lı cache tablosu temizliği, `model:prune`.
- Sınırlar (bilinçli kabul): pub/sub yok, Horizon yok; 3 sn'lik poll paylaşımlı MySQL'e hafif ama sıfır değil (tek indeksli sorgu; slow log'da izlenir).

**Alternatifler.** Saf `--stop-when-empty` dakikalık cron: 60 sn'e varan gecikme KDS/yazıcı için kötü; reddedildi (yalnız fallback). systemd user linger: sunucuda kapalı, root onayı gerekir; alınırsa daha temiz — **açık iyileştirme adayı**. Redis: yok; Faz-2'de hacim gerektirirse kurulum ayrı onay.
**Geri dönüş.** `.env`'de sürücü değişimi (`redis`) kod değişikliği gerektirmez; worker cron satırı silinip Horizon/Supervisor'a geçilebilir.

---

## ADR-006 — Gerçek zamanlılık: kısa-aralık polling; WebSocket yok (v1)

**Bağlam.** Reverb kalıcı process + ayrı port/WS proxy ister — bu sunucuda ikisi de yok (ADR-005 bağlamı). Eski sistemin SSE denemesi `while(true)` ile PHP işçisi tüketiyordu ve kırıktı (LEGACY §7.3). LiteSpeed'de uzun-ömürlü bağlantı = işgal edilen lsphp işçisi; KDS ekranları + panel açık sekmeleri bunu çarpar.

**Karar.** v1'de **HTTP polling**, disiplinli:
- KDS/panel/kiosk: 3–5 sn aralıklı `GET /api/kds/updates?cursor=<son_id>` — cursor (son görülen event id) ile yalnız delta döner; değişiklik yoksa `304` + boş gövde. Tek sorgu, indeksli, cache'li.
- Bildirim üretimi tek tablo (`notify` outbox, TTL'li) — eski `notification_queue`'nun 1747-satır çöp kaderine karşı schedule'lı budama + dedup (aynı `type+reference` açıkken tekrar üretilmez).
- Müşteri tarafı (sipariş durumu sayfası): 10 sn polling, yalnız kendi sipariş token'ı.
- SSE **kullanılmayacak** (v1): lsphp işçisi kilitler, kazanım polling'e göre marjinal.

**Alternatifler.** Reverb/WS: altyapı yok; reddedildi (v1). Pusher/Ably (SaaS WS): dış bağımlılık + maliyet + KVKK; ertelendi. SSE: yukarıda.
**Sonuçlar.** KDS "gerçek zamanlı hissi" 3–5 sn'dir; restoran operasyonu için yeterli. Polling uçları en ucuz sorgu olacak şekilde tasarlanır (tek indeks taraması), IP-throttle bütçesine girer — KDS restoran içi IP'sinden geldiği için istek bütçesi hesaplandı: ekran başına 0,3 istek/sn.
**Geri dönüş.** Frontend'de ulaşım katmanı soyutlanır (`useUpdates()` composable); ileride VPS/Reverb gelirse polling → WS geçişi ekran kodunu değiştirmez.

---

## ADR-007 — Para temsili: **kuruş-integer** (KESİN)

**Bağlam.** Eski sistem DECIMAL(10,2) kullanıyor (float yok — LEGACY §3.7); yeni sistemde KDV, indirim, yüzdeli kampanya, hesap bölüşme gibi ara hesaplar gelecek.

**Karar.** Tüm para alanları **kuruş cinsinden `BIGINT UNSIGNED`** (`*_minor` soneki: `unit_price_minor`, `total_minor`), para birimi kolonu `currency CHAR(3)` (v1'de hep `TRY`). Cast katmanı: uygulamada değer nesnesi (`Money` value object / accessor), Blade/Vue'ya daima biçimlenmiş + minor ikilisi gider. Yüzde hesapları integer üzerinde yapılır, yuvarlama **tek yerde** (Money sınıfı, half-up) — dağınık `round()` yasak. KDV oranı `DECIMAL(5,2)` kalır (para değil, oran).

**Alternatifler.** DECIMAL(10,2): saklamada güvenli ama PHP tarafında float'a düşme kazaları ve yüzde/bölüşme hesaplarında dağınık yuvarlama riski; ayrıca JSON'da string/float ikiliği. Reddedildi. Float: tartışmasız reddedildi.
**Sonuçlar.** Eski veriden aktarım ×100 tam dönüşümdür (kayıpsız — DATA_MIGRATION_PLAN §5). Raporlarda `SUM(total_minor)/100` görüntüleme katmanında.
**Geri dönüş.** Minor→decimal dönüş kayıpsızdır; ters yön (decimal→minor) da bu veri tiplerinde kayıpsız. Kilitlenme yok.

---

## ADR-008 — QR token güvenliği

**Bağlam.** Eski sistem `?table=<artan_int>` — komşu masaya sipariş açılabiliyor (LEGACY §3.1, §5.7).

**Karar.**
- Her masa için **tahmin edilemez opak token**: 26 karakter base32 (ULID değil — sıralanabilirlik istenmez; `random_bytes(16)` → base32), `tables.qr_token` UNIQUE, kiracıdan bağımsız global benzersiz. URL: `https://.../m/{token}`. Token tenant+branch+masayı tek başına çözer; URL'de başka kimlik yok.
- **Rotasyon:** panelden masa başına / şube başına "QR'ı yenile" → eski token anında geçersiz (kolon güncellenir). QR baskısı yenilenene kadar eski token'a `410` + açıklama sayfası.
- **Oturum bağlama:** menü açılışında imzalı, kısa ömürlü (4 saat) bir `guest_session` çerezi verilir; sipariş/garson-çağrı POST'ları token + bu oturum ikilisini ister → token URL'i sızsa da uzaktan toplu spam zorlaşır. Ayrıca uç bazlı rate limit (Laravel `RateLimiter`, database store; anahtar = token+IP, IP tek başına değil — NAT).
- İmzalı-URL (HMAC'li query) **gerekmedi**: token zaten rastgele ve DB'de; imza, iptal edilebilirliği (rotasyonu) zorlaştırırdı.
- `qr_scans` tablosu: token, zaman, UA — analitik; kişisel veri tutulmaz (IP hash'lenir).

**Alternatifler.** Artan id + HMAC imza: rotasyon zor; reddedildi. UUIDv4 URL'de: olur ama base32 daha kısa QR üretir; tercih edildi.
**Geri dönüş.** Token kolon tabanlı olduğundan şema değişmeden farklı üretim stratejisine geçilebilir.

---

## ADR-009 — Yazıcı mimarisi: `print_jobs` kuyruğu + adapter, yerel ajan polling'i

**Bağlam.** Sunucu buluttadır; restoran yazıcıları (ESC/POS termal) NAT arkasındaki yerel ağdadır — sunucudan yazıcıya doğrudan TCP **mümkün değil**. Eski sistem tarayıcıdan `print.php` ile basıyordu.

**Karar.** Katmanlı:
1. **`print_jobs` tablosu** (tenant/branch, hedef `printer_id`, tip: adisyon/mutfak/fiş, payload = yapılandırılmış JSON, durum: `queued→claimed→printed/failed`, deneme sayacı). Sipariş event'leri job üretir; üretim **PrinterAdapter arayüzünün** arkasındadır.
2. **v1 yolu — tarayıcı baskısı:** KDS/kiosk ekranı yeni job'u polling'le görür, yazdırma CSS'li fiş görünümünü `window.print()` ile basar (USB/paylaşımlı yazıcı). Sıfır ek kurulum, belediye tesisleri için yeterli başlangıç.
3. **v1.x yolu — yerel baskı ajanı:** restoran içinde küçük bir istasyon (Windows exe / Raspberry Pi, ayrı mini proje) HTTPS ile `GET /api/print-agent/jobs` (kendi API anahtarı, branch'e kilitli) → job'ı `claim` eder → ESC/POS'a yerel TCP/USB basar → `ack`. Sunucu asla yazıcıya bağlanmaz; ajan **dışarı doğru** bağlanır (NAT problemi yok). Polling 2–3 sn.
4. Desteklenecek adapter'lar: `BrowserPrint` (v1), `EscposAgent` (v1.x), ileride `StarCloudPRNT`-tipi bulut yazıcılar (aynı arayüz).

**Alternatifler.** Sunucudan yazıcıya doğrudan bağlantı: NAT/güvenlik nedeniyle imkânsız; reddedildi. Yalnız tarayıcı baskısı (kuyruksuz): baskı garantisi/tekrar-deneme/izlenebilirlik olmaz; reddedildi — kuyruk v1'de de tarayıcının arkasında durur.
**Sonuçlar.** Ajan ayrı bir teslimat kalemidir (v1'de yok); `print_jobs` şeması ilk günden ajan-uyumlu tasarlanır.
**Geri dönüş.** Adapter arayüzü sayesinde baskı yolu restoran başına seçilebilir; tek yola kilitlenme yok.

---

## ADR-010 — Ödeme: `PaymentProviderInterface` + idempotency + doğrulanmış callback

**Bağlam.** v1'de fiili tahsilat masada (nakit/fiziksel POS) — kayıt amaçlı. Online ödeme (iyzico/PayTR) ileride; ekipte PayTR entegrasyon deneyimi mevcut. Eski sistemde ödeme iki senkronsuz yoldan yazılıyordu (LEGACY §4.3).

**Karar.**
- **Tek doğruluk kaynağı `payments` tablosu**; `orders.payment_status` türetilir (asla elle set edilmez). Eski çift-yol hatası tekrarlanmaz.
- `PaymentProviderInterface`: `initiate(Order): RedirectData`, `verifyCallback(Request): CallbackResult`, `refund(Payment, minor)`. v1 implementasyonları: `CashProvider`, `CardPresentProvider` (kayıt-only). Online provider eklenince kod değil konfig değişir.
- **Idempotency:** `payments.idempotency_key` UNIQUE (provider işlem no ya da bizim ürettiğimiz anahtar); callback ikinci kez gelirse aynı kaydı döner, ikinci satır açılmaz. (PayTR idempotency dersi — bilinen tuzak.)
- **Callback doğrulama:** provider imzası (HMAC) **her** callback'te doğrulanır; tutar callback'ten değil kendi kaydımızdan alınır, callback'teki tutarla **karşılaştırılır**; uyuşmazlık = işlem `suspect` + alarm. Callback uçları CSRF muafiyeti dar tutulur (yalnız o rota) ve yalnız POST.
- Kısmi ödeme / hesap bölüşme: `payments` sipariş başına N satır destekler (`amount_minor` toplamı ≤ sipariş toplamı, aşan tahsilat engellenir).

**Alternatifler.** Provider'a özel kod serpiştirmek: adapter'sız başlanırsa ikinci provider'da yeniden yazım; reddedildi.
**Geri dönüş.** Arayüz dar tutulduğu için provider ekleme/çıkarma lokal değişiklik.

---

## ADR-011 — Önbellekleme: public menüde LiteSpeed tam-sayfa cache (kritik)

**Bağlam.** **En somut altyapı kısıtı:** LiteSpeed IP başına ~50 PHP istek/sn sınırlıyor ve bir restoranın tüm müşterileri tek Wi-Fi NAT IP'sinden gelir. Cache'siz menü sayfası = yoğun saatte throttle → menü açılmaz.

**Karar.** Üç katman:
1. **Tam-sayfa LiteSpeed public cache** — `/m/{token}` yanıtlarına `X-LiteSpeed-Cache-Control: public, max-age=120` + `X-LiteSpeed-Tag: t{tenant}, b{branch}` başlıkları (middleware). Menü değiştiğinde (ürün/fiyat/stok görünürlüğü) event → `X-LiteSpeed-Purge: b{branch}` yanıtı üreten iç istek ile tag purge. Cache'lenen sayfada oturuma/kişiye özel içerik **bulunmaz** (sepet tamamen client-side; `Set-Cookie` cache'lenen yanıtta gönderilmez — guest_session çerezi ilk POST'ta verilir). Sonuç: müşteri trafiğinin ~%95'i PHP'ye hiç inmez → throttle bütçesi yalnız POST'lara (sipariş/çağrı) kalır.
   - **Belirsiz, doğrulanmalı:** vhost'ta `CacheLookup on` / cache modülünün bu sunucu profilinde etkin olup olmadığı ölçülmedi. Faz-1'de ilk iş: `.htaccess` `<IfModule LiteSpeed> CacheLookup on </IfModule>` + `curl -I` ile `x-litespeed-cache: hit` doğrulaması. Etkinleştirilemezse fallback: aynı middleware `Cache-Control: public` + uygulama-içi render cache (aşağıda) ve gerekirse statik JSON snapshot (`storage`→`public` atomik yazım).
2. **Uygulama içi:** menü render verisi (kategori+ürün ağacı, branch başına) database cache'te 5 dk + değişiklikte invalidation; DB'ye inen istekler de tek sorguya yakınlaşır.
3. **Statik varlıklar:** `public/build` immutable (`Cache-Control: max-age=31536000, immutable`, Vite hash'li dosya adları); görseller boyutlandırılmış + uzun TTL.
Panel/KDS **asla** page-cache'lenmez (`X-LiteSpeed-Cache-Control: no-cache`).

**Alternatifler.** Cloudflare önüne almak: DNS şu an CF'siz; ayrıca CF'nin sunucu-sunucu challenge geçmişi (kurumsal hafıza) ve 403-cache tuzakları var; v1'de eklenmedi — ileride yalnız statikler için düşünülebilir. Yalnız uygulama cache'i: PHP'ye inmeye devam eder, throttle çözülmez; tek başına yetersiz.
**Sonuçlar.** "Menü anında güncellensin" beklentisi 0–120 sn gecikebilir; purge event'i bunu pratikte saniyelere indirir. Cache'li sayfada kişiselleştirme yasağı tasarım disiplini ister.
**Geri dönüş.** Middleware başlıkları kapatmak cache'i anında devre dışı bırakır; mimari kilit yok.

---

## ADR-012 — Yedekleme: proje kendi yedeğini kurar

**Bağlam.** Sunucuda **hiçbir otomatik yedek yok** (SERVER_AUDIT §9); sunucu-geneli WHM yedeği ayrı ve root onaylı bir iştir, bu projenin güvencesi olamaz.

**Karar.**
- **Kod:** git (uzak repo) — tek kaynak; sunucudaki kopya her zaman yeniden üretilebilir.
- **DB:** `spatie/laravel-backup` (yalnız DB modu) veya schedule'lı `mysqldump --single-transaction` — gecelik, hedef `apps/qrmenu/storage/backups/` (**docroot dışı**), 7 günlük rotasyon, gzip. Dosya izinleri 600.
- **Offsite:** yerel kopya sunucu kaybında yetersiz → haftalık şifreli arşivin sunucu dışına (SFTP/S3/rclone hedefi) itilmesi **zorunlu kabul**; hedef henüz yok — **belirsiz: offsite hedef (hangi depolama) kullanıcı onayıyla belirlenecek**, belirlenene kadar geçici çözüm: dump'ın başka bir fiziksel diske/hesaba kopyası yoktur, risk açık kalır ve Faz-1 kapanış kriteridir.
- **Medya:** `storage/app` (menü görselleri) haftalık arşive dahil.
- **Geri dönme tatbikatı:** ilk canlı kiracıdan önce bir kez tam restore provası (boş DB'ye dump + `storage` geri yükleme) yapılıp süresi not edilir.
- Sunucu-geneli WHM Backup önerisi projeden bağımsız iletilmiştir (SERVER_AUDIT §9.1); bu ADR ona bel bağlamaz.

**Alternatifler.** "cPanel yedeği vardır" varsayımı: ölçümle çürütüldü (`backupenable: 0`); reddedildi.
**Geri dönüş.** Yedek stratejisi uygulamadan bağımsız (cron + artisan); değiştirmek serbest.

---

## Karar Özeti

| # | Karar | Tek cümle |
|---|---|---|
| 001 | Laravel 13 / PHP 8.3 | Tek çalıştırılabilir seçenek + ekip standardı; 8.3 pini `composer platform` ile |
| 002 | Modüler monolit | `app/Modules/*`, event'le konuşan sınırlar |
| 003 | Vue3+TS+Inertia panelde; public menü Blade | Build sunucu dışında, artefakt rsync (qrmenu kullanıcısı) |
| 004 | Tek DB + `tenant_id` | tenants→branches; 4 katmanlı izolasyon; utf8mb4_unicode_ci açıkça |
| 005 | Database queue + cron-denetimli kalıcıya-yakın worker | flock + `--max-time=3600` → 0–3 sn iş gecikmesi |
| 006 | Polling (3–5 sn, cursor'lı); WS/SSE yok (v1) | KDS dahil; ulaşım katmanı soyut |
| 007 | **Kuruş-integer** (`*_minor` BIGINT) | Yuvarlama tek yerde; TRY |
| 008 | Opak rastgele QR token + rotasyon + guest_session | Artan id / imzalı-URL yok |
| 009 | `print_jobs` kuyruğu + adapter; ajan dışarı-doğru polling | v1 tarayıcı baskısı, v1.x ESC/POS ajanı |
| 010 | `payments` tek doğruluk kaynağı + ProviderInterface | Idempotency key + imza + tutar karşılaştırma |
| 011 | LiteSpeed tam-sayfa public cache + tag purge | IP-throttle kısıtının cevabı; `CacheLookup` doğrulanacak |
| 012 | Gecelik DB dump + rotasyon + offsite (hedef onay bekliyor) | Sunucuda yedek yok; proje kendini korur |
