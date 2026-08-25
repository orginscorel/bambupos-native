# BamBumPOS Masaüstü (Tauri) — Offline-first İstemci İskeleti

**Durum: İSKELET.** Bu dizin `cargo`/`node` bu ortamda kurulu OLMADIĞI için
hiç derlenmedi/çalıştırılmadı. Kod, mevcut sunucu altyapısı (aşağıya bkz.)
ve `docs/offline-sync-protocol.md` okunarak, o protokole UYACAK şekilde
elle yazıldı. İlk iş: bir geliştirme makinesinde `cargo check` çalıştırıp
küçük API/imza sapmalarını düzeltmek (Tauri v2 hattı hızlı değişiyor).

Mevcut Laravel uygulaması bu görevde **DEĞİŞTİRİLMEDİ** — yalnız bu
`desktop/` dizini eklendi.

---

## 1. Neden bu mimari

Kilitli kararlar (kullanıcı onaylı): Tauri masaüstü sarmalayıcı,
offline-first masaüstü POS, operasyon-kuyruğu senkronu. Sunucu HER ZAMAN
otoriter; masaüstü yalnız internet/host giderse yerel veriyle çalışmaya
devam eder, internet gelince kuyruğu **idempotent** biçimde oynatır.

Sunucu tarafı temeli zaten atılmış durumda (bu görevden ÖNCE, ayrı bir
görevde):
- `docs/offline-sync-protocol.md` — protokol tasarımı, bu iskelet BUNA
  bağlı kalır. Özellikle: iki farklı idempotency katmanı (`Idempotency-Key`
  header vs. `op_id` gövde alanı — KARIŞTIRILMAZ), sunucunun HER ZAMAN
  otoriter olduğu (stok/masa/sürüm çakışmaları istemci tahminiyle DEĞİL
  gerçek zamanlı sunucu durumuyla çözülür), terminal-önekli geçici sipariş
  numarası tasarımı (§4, kod DEĞİL yalnız tasarım), ödeme çift-tahsilat
  önleme (bugün var, ADR-010).
- `database/migrations/2026_07_31_182511_create_idempotency_keys_table.php`
  — `idempotency_keys` tablosu (`tenant_id`+`op_id` UNIQUE).
- `app/Support/Idempotency/IdempotentRequest.php` — modül-bağımsız `op_id`
  idempotency katmanı (rezerve et → işi çalıştır → sonucu sakla; aynı
  `op_id` tekrar gelirse iş TEKRAR ÇALIŞMAZ, ilk yanıt aynen döner).
- `app/Modules/Orders/Http/Controllers/OrderController.php::addItem` — TEK
  PROOF endpoint: gövdede opsiyonel `op_id` (uuid) kabul eder, VARSA
  `IdempotentRequest` ile sarmalar. **Bugün yalnız bu uç `op_id` destekliyor
  — başka hiçbir uç (adisyon açma, ödeme alma, ...) desteklemiyor.** Bu,
  aşağıdaki "neyin gerçekten senkronlanabilir olduğu" ayrımını belirliyor.

---

## 2. Dosya ağacı ve her dosyanın durumu

```
desktop/
├── SYNC.md                              bu dosya
├── dist/
│   └── index.html                       BİTMİŞ (iskelet kapsamında) — bağlantı durumu + kuyruk/hata
│                                         sayacı gösteren, plain HTML/JS (npm build YOK)
└── src-tauri/
    ├── Cargo.toml                       BİTMİŞ (derlenmedi, sürümler doğrulanmalı)
    ├── build.rs                         BİTMİŞ (standart tauri-build çağrısı)
    ├── tauri.conf.json                  BİTMİŞ (v2 şeması, minimal pencere+CSP)
    ├── capabilities/default.json        BİTMİŞ (v2 izin modeli) — http/shell/store izinleri, TODO: daralt
    ├── icons/icon.png                   YER TUTUCU — gerçek marka ikonu DEĞİL (bkz. §5)
    ├── migrations/schema.sql            BİTMİŞ şema (ayna + pending_ops + failed_ops)
    └── src/
        ├── main.rs                      İSKELET — pencere/plugin kurulumu + arka plan döngüsü BİTMİŞ tasarım,
        │                                 birkaç TODO (auth, event-emit) işaretli
        ├── state.rs                     BİTMİŞ (basit paylaşılan durum)
        ├── db.rs                        BİTMİŞ (aç + şema uygula, 1 unit test var)
        ├── commands.rs                  KISMİ — get_status/force_sync/enqueue_add_item/list+ack_failed_ops
        │                                 BİTMİŞ; open_local_order BİLEREK STUB (bkz. §4); tam POS
        │                                 komutları (masa/menü listeleme, kalem güncelleme/silme, ödeme) YOK
        └── sync/
            ├── mod.rs                   BİTMİŞ (run_cycle: replay → pull sırası)
            ├── client.rs                İSKELET + AÇIK RİSK: kimlik doğrulama YOK (bkz. §3)
            ├── queue.rs                 BİTMİŞ (enqueue/fetch/remove/retry/failed_permanent)
            ├── pull.rs                  STUB — HTTP çağrısı + upsert iskeleti var ama sunucu yanıt
            │                                 şekli DOĞRULANMADI (bkz. §6); delta_pull bugün baseline_pull'a
            │                                 eşdeğer (gerçek delta/cursor sunucuda YOK)
            └── replay.rs                BİTMİŞ akış + 2 TODO: 409 alt-tür ayrımı sezgisel (server'da
                                          machine-readable alan yok), sadece order.item.add için
                                          mirror-güncelleme yazıldı
```

---

## 3. AÇIK RİSK #1 (EN ÖNEMLİSİ): Kimlik doğrulama

Panel API'si (`routes/orders.php`, `routes/venue.php`) `['web', 'auth:web',
'tenant']` middleware zinciriyle korunuyor — yani **oturum çerezi**
(`config/auth.php` → `guards.web.driver = session`) tabanlı, Sanctum/token
tabanlı DEĞİL. Bu, webview'da APP_URL'i açtığınızda normal login akışıyla
sorunsuz çalışır (kullanıcı panelde oturum açar, çerez webview'a yazılır) —
ama arka planda çalışan **bağımsız Rust `reqwest` istemcisi**
(`sync/client.rs::ApiClient`) bu çerezi PAYLAŞMAZ. Bugün `auth_token` her
zaman `None` — yani arka plan `baseline_pull`/`replay_queue` çağrıları
muhtemelen `401`/`302` (login yönlendirmesi) alır ve hiçbir şey
senkronlanmaz.

**Bu görevin kapsamı dışında** (Laravel'e dokunulmuyor) ama net bir sonraki
adım var: `terminal_devices` deseni (bugün yalnız mutfak/barista/komi
istasyon ekranları için, `migrations/2026_07_26_100100_create_terminal_
devices_table.php`) masaüstü terminaline de genişletilip, kurulumda
üretilen `token` ile `Authorization: Bearer <token>` kabul eden yeni bir
guard/middleware eklenmeli. `sync/client.rs` bu günü bekleyecek şekilde
tasarlandı (`auth_token: Option<String>` alanı zaten var, doldurulması
yeter).

## 4. AÇIK RİSK #2: Yalnız `addItem` gerçekten senkronlanabilir

Sunucu tarafında `op_id` idempotency YALNIZ `OrderController::addItem`'e
uygulandı (protokol dokümanı §7 "kapsam dışı"). Bu yüzden bu iskelette:

- `commands::enqueue_add_item` → GERÇEK kuyruklama + replay yapıyor
  (`scope = "order.item.add"`, endpoint `/api/v1/orders/{order}/items`).
- `commands::open_local_order` (adisyon AÇMA) → **bilerek sunucuya hiç
  göndermiyor**, yalnız yerel `mirror_orders` satırı oluşturuyor
  (`origin='local'`, `server_id=NULL`, protokol §4'teki terminal-önekli
  geçici numara — `{terminal_code}-{seq}`). Sunucu `OrderController::store`
  op_id desteklemediği için bunu kuyruğa koyup replay etmek ÇİFT ADİSYON
  riski taşırdı — bu yüzden bilinçli olarak yapılmadı.
- Ödeme (`pay`), iptal/refund, masa taşıma/birleştirme, ödeme kapama gibi
  uçlar için **hiç kuyruklama komutu YOK** — aynı sebepten (protokol §5:
  kart ödemeleri zaten offline alınamaz; nakit/diğerleri için sunucu
  desteği henüz yok).

**Sonraki adım #1** (bu görevin dışında): `PaymentController::store`'a ve
`OrderController::store`'a `addItem`'deki AYNI `op_id` deseni uygulanmalı —
protokol dokümanı §5 zaten bunu "önerilen sonraki adım" olarak tarif
ediyor. O yapılınca `commands.rs`'e `enqueue_open_order` / `enqueue_pay`
eklemek mekanik bir iş (queue.rs/replay.rs zaten scope-bağımsız).

## 5. Diğer bilinen eksikler / STUB'lar

- **İkon** (`icons/icon.png`): Python ile üretilmiş 128×128 düz turuncu
  kare — GERÇEK marka ikonu DEĞİL. Gerçek bundling öncesi:
  `cargo tauri icon path/to/logo.png` (tam ikon setini — .ico/.icns/çoklu
  PNG boyutu — otomatik üretir).
- **`sync/pull.rs`**: HTTP çağrısı + upsert SQL'i yazıldı ama
  `/api/v1/venue/tables`, `/api/v1/orders/catalog`, `/api/v1/orders/board`
  yanıtlarının GERÇEK JSON şekli bu görevde doğrulanmadı (sunucuya istek
  ATILMADI, yalnız controller/route isimlerinden çıkarım yapıldı). İlk
  entegrasyon adımı: bu üç uca panelde oturum açıkken tarayıcıdan/`curl
  --cookie` ile bakıp `extract_array`/alan adlarını gerçek şemaya göre
  düzeltmek.
- **Delta pull**: sunucuda `updated_at`/cursor tabanlı artımlı çekme
  YOK — `delta_pull` bugün dürüstçe `baseline_pull`'u tekrar çağırıyor (tam
  yenileme). Küçük menü/masa sayılarında sorun değil; sipariş hacmi
  artınca sunucu tarafında bir `?since=` parametresi eklenmesi önerilir.
- **409 alt-tür ayrımı** (`sync/replay.rs`): `IdempotentRequest` "hâlâ
  işleniyor" ile "aynı op_id farklı gövdeyle" durumlarının ikisinde de aynı
  `HttpException(409, mesaj)` atıyor — makine tarafından ayırt edilemiyor.
  İstemci bugün `tries >= 5` sonrası "muhtemelen çakışma" varsayıp kalıcı
  hataya düşürüyor (sezgisel). Önerilen sunucu iyileştirmesi: 409 gövdesine
  `{"reason": "processing" | "conflict"}` eklemek.
- **Kurulum sihirbazı** yok: `meta.tenant_id`/`branch_id`/`terminal_code`/
  `app_url`/`auth_token` bugün ya boş ya da ortam değişkeninden
  (`BAMBUMPOS_APP_URL`, `BAMBUMPOS_AUTH_TOKEN`) okunuyor. İlk gerçek
  kullanım için bir "kurulum ekranı" (dist/ içine eklenecek ikinci bir HTML
  sayfa + `commands::save_setup` komutu) TODO.
- **`commands::force_sync` / `main.rs::run_background_cycle` içindeki
  `MutexGuard` + `block_on` deseni**: kodda açıkça işaretlendi — senkron
  `rusqlite::Connection` kilidini async sınırın içinde tutup `tauri::
  async_runtime::block_on` ile HTTP çağrılarını sarmalıyoruz. Çalışır ama
  ideal değil (worker thread'i geçici bloklar). `cargo check` sonrası
  gözden geçirilmeli — muhtemel düzeltme: DB işlemlerini küçük senkron
  fonksiyonlara bölüp kilidi yalnız o an tutmak, HTTP `.await`'i kilit
  DIŞINDA yapmak.
- **Tam POS UI'ı yok** (görev kısıtı gereği): `dist/index.html` yalnız
  bağlantı durumu + kuyruk/hata sayacı gösterir. Masa ızgarası, menüden
  ürün seçme, adisyon detay ekranı, ödeme ekranı YAZILMADI.

---

## 6. Senkron akışı — kısa özet

```
Kullanıcı "çaya 1 adet ekle" der
        │
        ▼
commands::enqueue_add_item
  - op_id = UUID v4 (ŞİMDİ üretilir, ağ isteğinden ÖNCE)
  - pending_ops'a INSERT (status=pending)
  - mirror_order_items'a iyimser (optimistic) satır INSERT
  - UI ANINDA güncellenir (ağ beklenmez)
        │
        ▼  (arka plan döngüsü, main.rs, 30sn'de bir — ya da kullanıcı "şimdi senkronla")
sync::run_cycle
  1) replay::replay_queue
       - pending_ops'u created_at SIRASINA göre SIRAYLA (paralel DEĞİL) okur
       - {order} yer tutucusunu order_local_id -> mirror_orders.server_id ile çözer
         (order henüz senkronlanmadıysa bu op BU TURDA atlanır — sıra bozulmaz)
       - payload'a op_id eklenir, POST edilir
       - 201 / 200+replayed:true  -> pending_ops'tan SİL, mirror güncelle
       - 409                       -> birkaç deneme "hâlâ işleniyor" say (retry),
                                       sonra "çakışma" say (failed_ops'a taşı)
       - 4xx (validasyon/402 askı) -> failed_ops'a taşı, kullanıcıya göster
       - ağ hatası / 5xx           -> pending_ops'ta KALIR, tries++, sonra tekrar dene
  2) pull::delta_pull (bugün = baseline_pull, bkz. §5)
       - masalar / ürünler / açık adisyonları GET edip mirror_* tablolarını tazeler
        │
        ▼
dist/index.html, get_status'u polling ile okuyup rozet/sayaçları günceller
```

**"Birebir yedek + eksiksiz aktarım" garantisi nasıl sağlanıyor:**
`op_id` UUID v4, kullanıcı eylemi anında üretilip kalıcı olarak
`pending_ops`'a yazıldığı için — uygulama kapansa, batarya bitse, ağ saatler/
günlerce kopuk kalsa bile kuyruk SQLite'ta durur; her yeniden açılışta
`pending_ops` aynen okunur ve AYNI `op_id` ile tekrar denenir. Sunucudaki
`(tenant_id, op_id)` UNIQUE kısıtı + `IdempotentRequest` sayesinde bu tekrar
denemeler asla ikinci bir gerçek işlem YARATMAZ — ya "ilk kez işlendi" ya da
"zaten işlenmişti, aynı sonuç" olur. Kayıp yalnız şu ANDA mümkün: bir op
`failed_ops`'a düşerse (4xx/kalıcı çakışma) bilinçli olarak BİR DAHA
denenmiyor — bu doğru davranış (protokol §2.3: kalıcı hatalar sonsuz retry
YAPMAMALI) ama kullanıcının bunu görüp elle çözmesi gerekir (`dist/
index.html` bu yüzden `failed_ops`'u ayrı bir listede gösterir, "kapat"
butonuyla `acknowledged=1` yapılır — veri KAYBOLMAZ, yalnız susturulur).

---

## 7. Derleme talimatı (bu ortamda ÇALIŞTIRILMADI)

Ön koşullar (geliştirme makinesinde):
- Rust toolchain (`rustup`, stable ≥ 1.77) — https://rustup.rs
- Platform bağımlılıkları: Tauri v2 ön koşulları (Linux: `libwebkit2gtk-
  4.1-dev`, `build-essential`, `libssl-dev`, `libgtk-3-dev`,
  `librsvg2-dev`, `patchelf` vb. — dağıtıma göre değişir, bkz.
  https://v2.tauri.app/start/prerequisites/)
- **Node GEREKMEZ** — `dist/` elle yazılmış statik HTML, npm build adımı
  yok. (İleride gerçek bir SPA'ya geçilirse Vite eklenir.)

Adımlar:
```bash
cd desktop/src-tauri

# 1) Rust tarafını doğrula (Node'a gerek yok)
cargo check

# 2) tauri-cli'yi cargo ile kur (npm gerekmez)
cargo install tauri-cli --version "^2"

# 3) Geliştirme modunda çalıştır (dist/index.html'i doğrudan yükler)
cargo tauri dev

# 4) Gerçek ikon seti üret (icons/icon.png yalnız yer tutucu, bkz. §5)
cargo tauri icon path/to/gercek-logo.png

# 5) Release paketle (yükleyici üretir - .deb/.AppImage/.msi/.dmg vb.)
cargo tauri build
```

Ortam değişkenleri (kurulum sihirbazı yazılana kadar geçici):
```bash
export BAMBUMPOS_APP_URL="https://qrmenu.bogahostdeveloper.com.tr"  # ya da bambumpos.com kiracı host'u
export BAMBUMPOS_AUTH_TOKEN=""   # bkz. §3 - bugun sunucu tarafi hazir degil, bos birakilabilir
```

İlk `cargo check` muhtemelen küçük hatalar verecek (Tauri v2 API'leri hızlı
değişiyor, bu kod derlenmeden yazıldı) — özellikle şüpheli noktalar:
`app.path().app_data_dir()` imzası, `WebviewWindowBuilder` import yolu,
plugin `init()` imzaları, `tauri::async_runtime::block_on` kullanımı
(bkz. §5 son madde). `Cargo.toml`'daki sürümleri `cargo update` ile
kesinleştirin.

---

## 8. Sonraki adımlar (öncelik sırasıyla)

1. **Sunucu**: `terminal_devices` desenini masaüstüne genişlet + token
   guard ekle (bkz. §3) — bu OLMADAN arka plan senkronu hiç çalışmaz.
2. **Sunucu**: `OrderController::store` ve `PaymentController::store`'a
   `addItem`'deki `op_id` desenini uygula (protokol §5, §7) — bu OLMADAN
   adisyon açma/ödeme alma offline'da güvenle kuyruklanamaz.
3. `sync/pull.rs`'teki üç uca gerçek istekle bakıp alan adlarını doğrula.
4. `cargo check` çalıştır, derleme hatalarını düzelt (bkz. §7 şüpheli
   noktalar).
5. Gerçek POS UI'ını yaz (masa ızgarası, adisyon detay, kalem
   ekle/güncelle/sil, ödeme ekranı) — `commands.rs`'e karşılık gelen
   komutları ekleyerek.
6. Kurulum sihirbazı (tenant/terminal seçimi, `meta` tablosunu doldurma).
7. `sync/replay.rs`'teki 409 sezgisel ayrımını sunucu `reason` alanıyla
   değiştir (bkz. §5).
8. `main.rs::run_background_cycle` sonuna `app.emit("sync-status", ...)`
   ekleyip `dist/index.html`'i polling'den olay-tabanlı güncellemeye
   geçir.
