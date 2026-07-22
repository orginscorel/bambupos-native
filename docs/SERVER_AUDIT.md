# QR Menü Platformu — Sunucu Denetim Raporu (Faz 0)

**Ajan:** Sunucu-Denetim · **Tarih:** 2026-07-22 · **Mod:** SALT-OKUNUR (hiçbir yapılandırma değiştirilmedi)
**Hedef hesap:** `qrmenu` (yeni açıldı). `oritoriu` yalnız *eski sistemin barındığı yer* olarak değerlendirildi.
Tüm değerler bu sunucuda **ölçülmüştür**.

---

## 1. Mevcut Durum

### Sunucu

| Bileşen | Ölçülen Değer |
|---|---|
| OS / Panel | AlmaLinux 8.10 · cPanel 134.0 (build 30) |
| Web sunucu | **LiteSpeed 6.3.5 Enterprise**, PHP handler **lsapi** (`/etc/cpanel/ea4/php.conf`) |
| MariaDB | 10.11.18-MariaDB-log (slow log açık) |
| Donanım | 8 çekirdek · 31 GB RAM (21.8 GB available) · load avg 1.60 · uptime 37 gün |
| Swap | 4 GB'ın **3.76 GB'ı dolu** (geçmiş bellek baskısı izi; şu an RAM bol) |
| Disk `/home` | 151 GB toplam, **66 GB boş** |
| crond | aktif (6 hesap cron kullanıyor — kanıtlı) |
| Güvenlik | Imunify360 aktif · **CloudLinux/CageFS YOK** (izolasyon = klasik Unix izinleri) |
| Composer | 2.10.2 (`/usr/local/bin/composer`, herkese açık) |
| Node | v22.14.0 **yalnız `/root/.local/bin`** — cPanel kullanıcıları erişemez |
| Redis / Supervisor / pm2 / Passenger | **hiçbiri yok** |

### Hesap `qrmenu` (ölçülen)

| Özellik | Değer |
|---|---|
| UID / shell | 1013 · **`/bin/bash`** → SSH ve cPanel Terminal **kullanılabilir** |
| Quota | **yok** (limitsiz) · MAXSQL=unlimited · FEATURELIST=default (cron dahil açık) · PLAN=default |
| Alan adı | `qrmenu.bogahostdeveloper.com.tr` · docroot şu an `/home/qrmenu/public_html` · **phpversion: ea-php83** |
| DNS | ns1/ns2.cprapid.com (yerel zone), A → 46.224.208.126 doğrudan — **Cloudflare yok** |
| SSL | **Aktif ve canlı** — `curl -I https://qrmenu.…` → `HTTP/2 200` (AutoSSL/Let's Encrypt, `_SSL` userdata mevcut) |
| Cron | crontab boş (henüz eklenmemiş, erişim var) |
| Home | temiz; `find /home/qrmenu -user root` → 0 |

---

## 2. PHP: Gerçekte Kurulu Sürümler ve Karar

**NET TESPİT: ea-php84 ve ea-php85 SİSTEME KURULU DEĞİL.** `/opt/cpanel/ea-php84|85/` dizinleri var ama içlerinde yalnız Imunify'ın bıraktığı `modules/i360.so` bulunuyor; `rpm -qa`'da tek bir ea-php84/85 paketi yok, PHP ikilisi (`bin/php`) mevcut değil. Modern sürümlerden gerçekten kurulu olanlar: **ea-php82 (8.2.32)** ve **ea-php83 (8.3.32)**.

**Karar: ea-php83 — tek seçenek.** Laravel 13 `php: ^8.3` istiyor; 8.2 dışarıda, 8.4/8.5 kurulu değil. ea-php83 hesaba zaten atandı.

⚠️ Doğrulama notu: Laravel 13.3+ sürümlerinin Symfony 8 bağımlılıklarının pratikte 8.4 istediği yönünde raporlar var (teyitsiz). `composer create-project` anında sorun çıkarsa `composer.json` → `"config": {"platform": {"php": "8.3.32"}}` ile 8.3-uyumlu çözümleme sabitlenir; 8.4 kaçınılmaz olursa WHM » EasyApache 4'ten kurulum gerekir (ayrı onay).

### Gerekli PHP Eklentileri — ea-php83 `php -m` doğrulaması

| Eklenti | Var? | | Eklenti | Var? |
|---|---|---|---|---|
| pdo_mysql | ✅ | | bcmath | ✅ |
| mbstring | ✅ | | fileinfo | ✅ |
| openssl | ✅ | | curl | ✅ |
| tokenizer | ✅ | | zip | ✅ |
| xml / dom / xmlwriter / simplexml | ✅ | | gd | ✅ (**imagick yok** — QR üretimi için gd yeterli) |
| ctype | ✅ | | intl | ✅ |
| json (core) | ✅ | | sodium | ✅ |
| pcntl | ✅ (worker sinyal/timeout) | | exif, gmp, soap, sockets, iconv | ✅ |
| **OPcache** | ✅ **kurulu ve etkin** — §3'te ayrıntı | | redis | ❌ (Redis sunucusu da yok; database sürücüsü kullanılacak) |

`disable_functions` **boş** → composer/artisan/proc_open engelsiz.

---

## 3. OPcache — Ölçüm, Çelişki Düzeltmesi ve Risk Değerlendirmesi

**Ölçülen gerçek (4 bağımsız kanıt):** ea-php83'te OPcache **kuruludur ve web dahil etkindir** — koordinasyon notundaki "ea-php83'te OPcache yok" tespiti bu ölçümlerle **doğrulanamadı**:

1. `rpm -q ea-php83-php-opcache` → `ea-php83-php-opcache-8.3.32-1.2.1.cpanel.x86_64`
2. `/opt/cpanel/ea-php83/root/usr/lib64/php/modules/opcache.so` mevcut; `/opt/cpanel/ea-php83/root/etc/php.d/10-opcache.ini` → `opcache.enable=1`
3. CLI: `php -m` → `Zend OPcache`
4. **Web SAPI:** `lsphp -i` → `opcache.enable => On => On` (Loaded ini: `/opt/cpanel/ea-php83/root/etc/php.ini`)

**Ölçülen ayarlar:** `memory_consumption=128M`, `max_accelerated_files=4000`, `validate_timestamps=On`, `jit=tracing`, `enable_cli=Off`.

**Risk çerçevesi (karar sunucu sahibinin — hiçbir şey değiştirilmedi):**
- ea-php83'ü şu an **2 site** kullanıyor: `qrmenu` (biz) ve `perpa.bogahostdeveloper.com.tr` (başka proje, oritoriu hesabında — userdata'dan doğrulandı). ea-php83 ini'sine yapılacak her değişiklik **perpa'yı da etkiler**.
- Bu sunucuda geçmişte OPcache **ea-php74'te** WHMCS'e zarar verdiği için kapatılmıştı. Bu karar 7.4'e özgüdür; 8.3'te OPcache halen açık ve `validate_timestamps=On` (dosya değişikliği anında görülür) olduğundan aynı risk profili yoktur. **Kapatılması önerilmez.**
- **Tek gerçek eksik:** `max_accelerated_files=4000` bir Laravel uygulaması için düşük (vendor dahil ~15–25 bin dosya; cache dolunca yeni dosyalar cache'siz çalışır). Önerilen değişiklik (uygulanmadı): WHM » MultiPHP INI Editor » PHP 8.3 → `opcache.max_accelerated_files=20000`, `opcache.memory_consumption=192`. Güvenli uygulama: değişiklik yalnız cache kapasitesini büyütür, davranış değiştirmez; yine de perpa etkileneceği için düşük trafik saatinde yapılmalı ve sonrasında perpa ana sayfası test edilmelidir. İstenirse per-vhost ayrım da mümkündür (lsapi `.htaccess` `php_value` / hesap bazında `.user.ini`).

---

## 4. PHP Limitleri (ea-php83, `/opt/cpanel/ea-php83/root/etc/php.ini`)

| Ayar | Web (lsapi) | CLI | Yorum |
|---|---|---|---|
| memory_limit | 2048M | 2048M | Toplu QR/PDF üretimi için fazlasıyla yeterli |
| max_execution_time | 30000 s | 0 | Aşırı cömert; engel yok |
| upload_max_filesize / post_max_size | 1000M / 1000M | — | Menü görselleri için bol |
| max_file_uploads | 20 | — | Çoklu görsel formunda tavan; yeterli |
| max_input_vars | 10000 | — | Büyük menü formları için yeterli |

Vite build PHP değil Node işidir → §5 Eksikler.

---

## 5. Eksik Bileşenler

| Eksik | Etkisi | Öneri (uygulanmadı) |
|---|---|---|
| **Redis (sunucu + ext)** | Horizon yok; queue/cache/session → `database` | Faz 0 için database yeterli (§7); hacim büyürse Faz-2'de Redis |
| **ea-php84/85** | Kurulu değil (yalnız i360.so iskeleti) | Gerekmedikçe kurma; Laravel 8.4 dayatırsa EA4'ten kur |
| **Node kullanıcı erişimi** | `qrmenu` kullanıcısı `node` bulamaz (yalnız `/root/.local/bin`) | Vite build lokalde/root'ta yapılıp `public/build` artefaktı deploy edilir; veya kullanıcı home'una nvm (ayrı onay) |
| **Supervisor / pm2 / systemd linger** | Daemon queue worker yok | Dakikalık cron worker (§7) |
| **imagick** | gd mevcut | QR PNG/SVG için gd yeterli |
| **Sunucu yedeği** | Hiç yok (§9) | Acil, projeden bağımsız |

---

## 6. Deployment Yöntemi — docroot `/home/qrmenu/apps/qrmenu/public`

**Ölçülen engel:** WHM Tweak `publichtmlsubsonly = 1` → cPanel **arayüzü** docroot'u public_html altına zorlar.
**Ölçülen çözüm — bu sunucunun yerleşik deseni:** Diğer Laravel uygulamaları tam olarak istenen deseni kullanıyor ve nasıl yapıldığı userdata'dan okundu:

| Hesap | documentroot (ölçülen) |
|---|---|
| finansboga | `/home/finansboga/finans/public` |
| dcimboga | `/home/dcimboga/dcim/public` |
| taskboga | `/home/taskboga/laravel/public` |

Yöntem (üçünde de aynı): root, `/var/cpanel/userdata/<hesap>/<domain>` ve `<domain>_SSL` dosyalarındaki `documentroot:` satırını uygulamanın `public/` yoluna çevirmiş; ardından `/scripts/rebuildhttpdconf` + LiteSpeed restart. Tweak ayarı yalnız cPanel UI'sını kısıtladığından bu root-düzeyi yöntem çalışıyor (3 canlı kanıt).

**qrmenu için adımlar (uygulanmadı, onay sonrası ~2 dk):**
1. `/var/cpanel/userdata/qrmenu/qrmenu.bogahostdeveloper.com.tr` ve `…_SSL` → `documentroot: /home/qrmenu/apps/qrmenu/public` (önce her iki dosyanın `.bak`'ı — docroot dışına)
2. `/scripts/rebuildhttpdconf && systemctl restart lsws`
3. AutoSSL DCV `.well-known`'ı yeni docroot'tan sunulur — finans/dcim/task'ta sertifikalar bu düzenle yenileniyor (kanıtlı, sorun yok)

**Kurulum akışı:** kod git ile `/home/qrmenu/apps/qrmenu` → `composer install --no-dev` (kullanıcının shell'i var, SSH/Terminal'den) → `.env` izin **600** → `php artisan key:generate && migrate && storage:link && optimize` → Vite build lokalde/root'ta, `public/build` rsync (sonrası `chown -R qrmenu:qrmenu`) → cron'lar (§7).
**DB:** cPanel'den `qrmenu_app` + ayrı DB kullanıcısı; oluşturma SQL'i açıkça `CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci` (sunucu default'u latin1 — §8).

---

## 7. Queue ve Cron Yöntemi

**Ölçülen:** crond aktif; `qrmenu` featurelist'i cron'a açık (crontab şu an boş); shell `/bin/bash` → SSH + cPanel Terminal var (kurulum/bakım kolay). Ancak Supervisor/pm2/linger olmadığından **kalıcı daemon worker güvenilir değil** (SSH'da `nohup` reboot'ta ölür).

**Yöntem: database queue + dakikalık cron** (Redis yok → tek sağlam seçenek):

```cron
* * * * * /opt/cpanel/ea-php83/root/usr/bin/php /home/qrmenu/apps/qrmenu/artisan schedule:run >> /dev/null 2>&1
* * * * * /usr/bin/flock -n /home/qrmenu/apps/qrmenu/storage/worker.lock /opt/cpanel/ea-php83/root/usr/bin/php /home/qrmenu/apps/qrmenu/artisan queue:work database --stop-when-empty --max-time=55 --memory=256 --tries=3 >> /dev/null 2>&1
```

PHP **tam yolla** (`/usr/local/bin/php` wrapper'ı dizin bağlamına bakar, cron'da güvenilmez); `flock` üst üste binmeyi önler.

**Database queue sınırları (bilinçli kabul):**
- İlk iş gecikmesi 60 sn'e kadar (cron aralığı) → anlık işler buna göre tasarlanmalı.
- Her poll = paylaşımlı MySQL'e sorgu; MariaDB 10.11 `FOR UPDATE SKIP LOCKED` destekler (Laravel kullanır) → kilit çekişmesi düşük, ama worker `--stop-when-empty` ile kısa yaşamalı.
- `jobs`/`failed_jobs` şişmesi: schedule'a `queue:prune-failed` + `queue:prune-batches` eklenmeli.
- Horizon, pub/sub, gerçek eşzamanlılık yok. Yoğun çok-kiracılı PDF/e-posta hacminde Redis'e geçiş Faz-2 konusu.

---

## 8. MariaDB — Laravel 13 Uyumu (ölçülen)

| Değişken | Değer | Yorum |
|---|---|---|
| Sürüm | 10.11.18 (LTS) | Laravel 13 ✅ · `SKIP LOCKED` ✅ |
| innodb_buffer_pool_size | 8 GB | 31 GB RAM'de makul; **tüm hesaplarla ortak** |
| max_connections / max_used | 1000 / 51 | Bol pay |
| sql_mode | `NO_ENGINE_SUBSTITUTION` | **ONLY_FULL_GROUP_BY ve STRICT sunucuda yok** — Laravel `strict => true` bunları oturum bazında kendisi uygular; sunucu ayarına dokunmaya gerek yok. Sorgular Laravel strict moduna göre yazılmalı |
| character_set_server / collation | **latin1** / latin1_swedish_ci | DB açıkça `utf8mb4` / `utf8mb4_unicode_ci` ile oluşturulmalı (§6); Laravel config zaten utf8mb4 |
| slow_query_log | ON, long_query_time=1s, bugün 3 kayıt | Sağlıklı ve sakin — yeni projenin yavaş sorguları anında görünür |
| innodb_flush_log_at_trx_commit / file_per_table | 1 / ON | Dayanıklılık tam |
| max_allowed_packet / tmp_table_size | 512 MB / 256 MB | Yeterli |

---

## 9. Yedekleme

**Ölçülen: sunucuda hiçbir otomatik yedek yok.** cPanel Backup `backupenable: 0`, JetBackup kurulu değil/inaktif, `/backup` 8 KB boş.

1. **Sunucu geneli (projeden bağımsız acil risk):** WHM Backup uzak hedefe (SFTP/S3) aktifleştirilmeli; 66 GB yerel boşluk tüm hesaplar için yeterli olmayabilir → `keeplocal` düşük + uzak kopya.
2. **Proje düzeyi (Faz 1'de kur):** kod git'te; DB için schedule'da gecelik `mysqldump` → `apps/qrmenu/storage/backups/` (docroot dışı) + 7 gün rotasyon + mümkünse offsite. `spatie/laravel-backup` (yalnız DB modu) uygun.
3. Ev kuralı: her canlı dosya değişikliğinden önce `.bak` — **asla docroot altına değil** (§10'daki sızıntı dersi).

---

## 10. Güvenlik Bulguları

### Eski sistem (`oritoriu` docroot'u) — bilgi amaçlı, DOKUNULMADI

`https://bogahostdeveloper.com.tr/` altında web'den indirilebilir arşivler (HTTP kodları canlı ölçüldü): `cafe-menu-system.zip` **200**, `admin.zip` **200**, `keycrypt.bogahostdeveloper.com.tr.zip` **200**, `__MACOSX.zip` **200**, `KURULUM.md`/`README.md` **200**; `database/schema.sql` 403 (.htaccess koruyor) ama docroot'ta duruyor; `EN GÜNCEL VERSİYON KALICI.zip` de docroot'ta. `.htaccess` yalnız `cache|logs|database` dizinlerini F'liyor; `tests/`, `tools/`, `__MACOSX/`, `uploads/` korumasız ve `uploads/` için PHP-çalıştırma engeli yok. **Öneri:** arşivler docroot dışına taşınmalı (ayrı onay).

### Yeni hesap `qrmenu` için

- Hesap izolasyonu: CloudLinux/CageFS yok → yalnız Unix izinleri. Home `drwx--x--x` (listelenemez ama bilinen yol erişilebilir) → **`.env` 600 zorunlu**, `apps/` zaten `drwxr-x---`.
- Kod docroot dışında (`apps/qrmenu`), web'e yalnız `public/` açılacak (§6) — eski sistemin zip sızıntısı bu ayrımın gerekçesidir.
- `disable_functions` boş olduğundan yüklenen dosya asla docroot içinde çalıştırılabilir olmamalı: yükleme hedefi `storage/app` (docroot dışı), `public/storage` yalnız symlink; `uploads` benzeri dizin açılırsa PHP handler kapatılmalı.
- Sahiplik kuralı: her şey `qrmenu:qrmenu`; `find /home/qrmenu -user root` → **0 (doğrulandı)**.

---

## 11. Mevcut Yük ve Kaynak Paylaşım Riski

Canlı sistemler: WHMCS bogahost.com + DCIM + Task + LiveChat + finans + qbinet cron'ları + oritoriu siteleri. Ölçülen boşluk: load 1.60 / 8 çekirdek, 21.8 GB available RAM → **yer var**, ancak:

1. **MySQL ortak** — şema baştan indeksli tasarlanmalı; `long_query_time=1s` logu izlenmeli; queue poll hafif ama worker kısa yaşamalı (§7).
2. **LiteSpeed per-IP throttle ~50 PHP istek/sn** (mevcut L7 koruması) — restoran senaryosunda onlarca müşteri **aynı Wi-Fi NAT IP'sinden** gelir; menü görüntüleme agresif cache'lenmeli (LiteSpeed public cache / statik JSON), aksi halde tek restoranın yoğun saati throttle yiyebilir. **Mimarî kararı etkileyen en somut paylaşım riskidir.**
3. **Swap 3.76/4 GB dolu** + root'ta boşta 2.3 GB RSS'lik Gradle daemon (eski APK build kalıntısı) — temizlenmesi önerilir (dokunulmadı).
4. Vite/npm build sunucuda yapılacaksa kısa CPU sıçraması → yoğun saat dışında.
