# Offline senkron protokolü — sunucu temeli (görev B)

**Durum:** SUNUCU tarafı temel atıldı (bu doküman + `op_id` idempotency
katmanı, PROOF olarak `OrderController::addItem`'e uygulandı). Offline
istemci (Tauri) BU DOKÜMANIN KAPSAMI DIŞINDA — burada yalnız istemcinin
uyması gereken PROTOKOL ve sunucunun buna verdiği garantiler tarif edilir.

**Karar (kilitli):** tam DB aynası (full mirror/replicate) DEĞİL,
**OPERASYON KUYRUĞU + idempotent oynatma**. İstemci yerelde bir "yapılacak
işlemler" kuyruğu tutar (adisyon aç, kalem ekle, ödeme al, ...), ağ dönünce
bunları SIRAYLA sunucuya oynatır. Sunucu her işlemi TAM BİR KEZ uygular;
mevcut `orders.version` (optimistic locking, ADR bkz. `OrderService::
withLockedOrder`) ve `payments` tek-doğruluk-kaynağı (ADR-010) modellerine
dokunulmaz — kuyruk bunların ÜZERİNE ince bir tekrar-güvenli katmandır.

---

## 1. İki farklı idempotency katmanı — birbirine KARIŞTIRILMAZ

| | `Idempotency-Key` (header) | `op_id` (gövde) |
|---|---|---|
| Servis | `App\Modules\Orders\Services\IdempotencyStore` | `App\Support\Idempotency\IdempotentRequest` |
| Tablo | `order_idempotency_keys` | `idempotency_keys` (yeni, modül-bağımsız) |
| Üretilme anı | istemci bu HTTP isteğini göndermeden hemen önce (ör. fetch retry sarmalayıcısı) | istemci işlemi YEREL KUYRUĞA eklerken (ağ isteğinden ÇOK ÖNCE, hatta hiç ağ yokken) |
| Ömrü | tek ağ denemesi + kısa retry penceresi | işlemin YAŞAM BOYU kimliği — kuyrukta günlerce bekleyip geç senkron olsa bile AYNI kalır |
| Kapsam | endpoint bazlı (`orders.items.add`, `payments.store`, ...) — Orders modülüne özgü | `scope` alanıyla modül-bağımsız; aynı tabloyu payments/başka mutasyonlar da kullanabilir |
| Çakışma denetimi | yok (aynı anahtar = aynı çağrı varsayılır) | `request_hash`: aynı `op_id` FARKLI gövdeyle gelirse 409 (istemci hatası sessizce yutulmaz) |

**Neden ikisi birden?** Header katmanı "aynı ağ isteği iki kez gitti" (çift
dokunma, tarayıcı retry) sorununu çözer — buna offline'da da ihtiyaç var.
`op_id` katmanı ONDAN TAMAMEN FARKLI bir sorunu çözer: "istemci bu işlemi
ÇEVRİMDIŞIYKEN kuyruğa koydu, saatler/günler sonra senkronladı, senkron
YARIDA KESİLİP TEKRAR BAŞLADI (uygulama kapandı, batarya bitti, ağ koptu
tam ortada)" — bu durumda istemcinin elinde AYNI op_id ile işlemi yeniden
gönderme dışında bir seçenek yok, çünkü hangi noktada kesildiğini bilemez.
`addItem`'de ikisi İÇ İÇE çalışır (bkz. kod): dıştaki `op_id` katmanı bir kez
başarıyla tamamlanınca içteki header katmanına bir daha hiç uğranmaz.

## 2. `op_id` akışı (istemci → sunucu sözleşmesi)

1. İstemci, kullanıcı bir eylemi (ör. "çaya 1 adet ekle") tetiklediği ANDA
   yerelde bir UUID v4 üretir → bu, o işlemin KALICI kimliğidir. Kuyruk
   satırına yazılır: `{op_id, scope, endpoint, payload, created_at}`.
2. Kuyruk oynatıcı sırayla POST eder; gövdeye `op_id` alanı eklenir
   (mevcut alanların YANINA — bugünkü alan sözleşmesi bozulmaz).
3. Sunucu yanıtı:
   - `201` + `replayed: false` → gerçekten işlendi, kuyruktan SİL.
   - `200` + `replayed: true` → DAHA ÖNCE işlenmiş, yanıt (ilk sonucun
     özeti) aynen döner → kuyruktan SİL (idempotent — güvenle atılabilir).
   - `409` → ya "hâlâ işleniyor" (kısa süre sonra TEKRAR aynı `op_id` ile
     dene) ya da "aynı `op_id` farklı gövdeyle kullanılmış" (istemci
     hatası — kuyruk satırı BOZUK, insan müdahalesi/log; ASLA otomatik farklı
     bir `op_id` üretip sessizce tekrar deneme, çünkü ilk deneme aslında
     işlenmiş olabilir).
   - `4xx` (validasyon/yetki) → kalıcı hata, kuyruktan SİL + kullanıcıya göster
     (retry ETMEZ — sonsuz döngü riski).
   - ağ hatası/`5xx`/timeout → kuyrukta KALIR, aynı `op_id` ile sonra tekrar
     denenir (idempotent olduğu için güvenli).
4. Kuyruk oynatma SIRALI olmalı (bir order'ın kalemleri sırayla eklenmeli);
   paralel oynatma yalnız FARKLI order'lar arasında güvenlidir (satır kilidi
   `withLockedOrder` zaten aynı order'a eşzamanlı yazımı serileştirir, ama
   sıra karışırsa "önce iptal sonra ekle" gibi mantık hataları oluşabilir).

### Sunucu tarafı garantisi (bugün canlı, `addItem` PROOF'unda)

- `op_id` YOKSA: davranış BUGÜNKÜYLE BİREBİR AYNI (mevcut istemciler / diğer
  uçlar kırılmaz).
- `op_id` VARSA: `(tenant_id, op_id)` UNIQUE ile TEK satır rezerve edilir;
  iş TAM BİR KEZ çalışır; sonraki tüm tekrarlar saklanan yanıtı döner.
- İş exception atarsa rezervasyon SİLİNİR → dürüst tekrar deneme mümkün
  (yarım kalan işlem "hayalet kilit" bırakmaz).

## 3. Çakışma kuralları — SUNUCU HER ZAMAN OTORİTER

Offline kuyruk, istemcinin YEREL ve ESKİMİŞ görüşüyle çalışır. Sunucu,
kuyruktaki bir işlemi ALDIĞI ANDAKİ gerçek veritabanı durumuna göre karar
verir — istemcinin "ben kuyruğa koyarken böyleydi" varsayımı ASLA otorite
değildir. Bu zaten bugünkü mimarinin doğal sonucu:

- **Stok:** `OrderService` kalem eklerken `product.stock_quantity` kontrolünü
  İŞ ÇALIŞIRKEN (transaction içinde, canlı satırdan) yapar — istemcinin
  kuyruğa koyduğu andaki stok bilgisi DEĞİL. İki terminal çevrimdışıyken
  "son 1 adet"i ayrı ayrı kuyruğa koyup ikisi de sonradan senkronlarsa,
  sunucuya ÖNCE ULAŞAN kazanır, ikincisi normal "tükendi" hatasıyla 422
  döner (bugünkü `addItem` validasyonu zaten budur — offline'a ekstra kod
  gerektirmez, yalnız istemcinin bu 422'yi "kalıcı hata, kuyruktan sil ve
  kullanıcıya göster" olarak ele alması gerekir, §2 madde 3). Not: stok bugün
  kalem eklenirken DÜŞÜLMEZ, yalnız `served` anında düşer (bkz.
  `App\Modules\Inventory\Services\ConsumptionService` — teslim = tek
  birincil tetik, `paid` güvenlik-ağı yedek tetik, ikisi de kalem başına
  idempotent). Offline senkron bu modele DOKUNMAZ; served/paid olayları
  zaten sunucuda, gerçek zamanda üretilir.
- **Masa:** `orders.version` (optimistic locking) + satır kilidi
  (`withLockedOrder`) hangi terminalin "son sürümü" gördüğünü zorunlu kılar.
  Offline istemci `expected_version` göndermeye devam etmeli; sunucudaki
  gerçek sürümle uyuşmuyorsa 409 (bugünkü davranış) — istemci EN GÜNCEL
  order'ı çekip kuyruktaki sonraki işlemlerini KULLANICIYA sorarak
  (ör. "bu masaya başka biri de dokundu") çözer. Otomatik/sessiz "kazanan
  benim" birleştirme YAPILMAZ — parasal/operasyonel risk.
- **Genel ilke:** kuyruk yalnız NİYETİ taşır ("bu ürünü ekle", "bu tutarı
  öde"); SONUCU asla taşımaz. Sonuç her zaman sunucunun o anki hesaplamasıdır
  (`OrderPresenter::detail` fresh read).

## 4. Terminal-önekli sipariş numarası — çakışma önleme (TASARIM, kod DEĞİL)

**Bugünkü durum:** sipariş "numarası" diye ayrı bir alan YOK — adisyon/fiş
numarası olarak doğrudan `orders.id` (auto-increment) gösteriliyor
(`useReceiptPrint.ts` → `Fiş #${orderNo}`, `orderNo = order.id`). Bu, ÇEVRİMİÇİ
akışta sorunsuz çünkü `id` sunucuda, tek noktada, sıralı üretiliyor.

**Sorun (offline'da):** istemci çevrimdışıyken "adisyon aç" işlemini kuyruğa
koyduğunda henüz bir `id`'si YOKTUR (sunucu henüz görmedi) — ama garson
ekranda HEMEN bir numara görmeli (mutfağa sözlü/yazılı iletişim, fiş basımı
gecikemez). İki terminal aynı anda çevrimdışı adisyon açarsa, ikisi de
"geçici numara" üretmek zorunda — bunlar ÇARPIŞMAMALI ve sunucuya
ulaştıklarında GERÇEK `id`'ye temiz biçimde eşlenmeli.

**Önerilen tasarım — terminal önekli GEÇİCİ numara:**

1. Her terminal/cihazın (bugünkü `terminal_devices.token` ya da `is_terminal`
   oturumun bağlı olduğu kısa bir cihaz kodu — ör. `token`'ın ilk 4 karakteri,
   kurulumda tek sefer üretilip cihaza yerel olarak saklanır) bir KISA HARF
   kodu vardır: `T1`, `T2`, `KS1` (kasa-1) gibi. Bu kod tenant+branch içinde
   TEKİL olmalı (bugün `terminal_devices` her cihaz için zaten satır tutuyor
   — kod bu satıra kurulumda bir kez atanıp saklanabilir).
2. İstemci çevrimdışıyken adisyon açtığında GEÇİCİ numara üretir:
   `{terminal_kodu}-{yerel_sayaç}` (ör. `T2-007`) — yerel sayaç cihazda
   basit, sıfırlanmayan bir artan sayı (senkron olsun olmasın hep artar, bu
   yüzden ÇAKIŞMAZ; iki cihaz aynı sayaç değerini üretse bile ÖNEK farklı
   olduğundan GLOBAL olarak tekil kalır).
3. Fişte/ekranda GEÇİCİ numara `(çevrimdışı)` rozetiyle gösterilir — personel
   bunun henüz sunucuya ulaşmadığını bilir.
4. Sunucuya `op_id` ile senkronlanınca gerçek `orders.id` atanır; istemci
   yerel kayıtta `local_temp_no → server_id` eşlemesini saklar ve EKRANDAKİ
   numarayı sunucu `id`'siyle GÜNCELLER (fiş yeniden basılmaz, yalnız ekran/
   sonraki fişler gerçek numarayı kullanır). Zaten basılmış geçici numaralı
   fiş operasyonel olarak geçerlidir — mutfak/kasa geçici numarayla da
   adisyonu bulabilmeli (bu yüzden sunucu tarafında `local_temp_no` alanının
   `orders` tablosuna GERİYE UYUMLU (nullable, indexli) eklenmesi ayrı bir
   migration gerektirir — bu görevin kapsamı DIŞINDA, yalnız burada tasarım
   olarak not edilir).
5. **Neden sunucu `id`'sini DEĞİL, önekli geçici numarayı üretiyoruz?**
   Auto-increment `id` TANIM GEREĞİ tek bir sunucuda, tek sırada üretilir —
   birden fazla çevrimdışı istemci ASLA kendi başına gerçek `id` tahmin/
   üretemez (çakışma kaçınılmaz olur). Terminal öneki, ayrı cihazların
   birbirinden HABERSİZ, ÇAKIŞMASIZ numara üretebilmesinin TEK yoludur
   (dağıtık sistemlerde klasik "node-prefixed ID" deseni).

## 5. Ödeme çift-tahsilat önleme — bugünkü temel + önerilen sonraki adım

**Bugün zaten var (dokunulmadı, ADR-010):**
- `Idempotency-Key` header (`PaymentController::store` → `IdempotencyStore`,
  bkz. `PaymentIdempotencyTest`): aynı header iki kez gelirse ikinci
  tahsilat YAPILMAZ.
- `UNIQUE(provider, provider_txn_id)`: sağlayıcı işlem kimliği DB düzeyinde
  ikinci satır açamaz.
- İmzalı + zaman damgalı callback (`verifyCallback`, `hash_equals`), replay
  ikinci kez İŞLEMEZ; tutar uyuşmazlığında `suspect` + alarm (asla sessizce
  kabul etmez).
- `OrderService::withLockedOrder` + `expected_version`: aynı adisyona
  eşzamanlı iki ödeme satır kilidiyle serileşir; kalan tutarı aşan tahsilat
  reddedilir (`amount_minor > kalan - bekleyen terminal ödemeleri` → 422).

**Önerilen sonraki adım (BU GÖREVDE UYGULANMADI — yalnız öneri):**
`addItem`'deki AYNI desen `PaymentController::store`'a da uygulanır: gövdeye
`op_id` eklenir, `IdempotentRequest` ile sarmalanır (header katmanının
İÇİNE, `addItem`'deki gibi). Böylece offline istemci "ödeme al" işlemini de
kuyruğa koyup güvenle geç senkronlayabilir. EK dikkat noktaları:
- Ödemede `request_hash` çakışma denetimi ÖZELLİKLE kritik: aynı `op_id`
  farklı `amount_minor` ile gelirse bu YALNIZ istemci hatası değil, olası bir
  DOLANDIRICILIK/ekran-kilit sinyali olabilir — 409'un yanı sıra audit log +
  alarm eklenmesi önerilir (bugünkü `suspect` mekanizmasına benzer).
- Nakit ödemeler offline alınabilir (kayıt-onaylı, `CashProvider`) ama KART/
  terminal ödemeleri (`usesTerminal()`) ÇEVRİMDIŞI ALINAMAZ — sağlayıcıya
  ağ gerekir; istemci bu ayrımı UI'da netleştirmeli (kart ödemesi kuyruğa
  YAZILMAZ, ağ dönene kadar bekletilir).
- Z-raporu/kasa oturumu kapatma offline kuyruğa ALINMAMALI (parasal
  mutabakat; ağ zorunlu).

## 6. Lisans / grace ile ilişki

Kiracı askı durumu (`Tenant::isSuspended()`) `EnsureTenantContext`
middleware'inde, PANEL API'sindeki HER istekte (dolayısıyla `addItem` dahil)
CONTROLLER'DAN ÖNCE denetlenir ve askıdaysa `402`/yönlendirme döner —
`op_id` katmanı bu middleware'in ARKASINDA çalışır, önüne geçmez.

Bunun offline kuyruk için sonucu:
- İstemci çevrimdışıyken (kiracı o an aktifken) kuyruğa koyduğu işlemler,
  senkron ANINDA kiracı ASKIYA ALINMIŞSA `402` ile reddedilir — `op_id`
  rezervasyonu bile OLUŞMAZ (middleware controller'dan önce keser). Kuyrukta
  BEKLEYEN işlemler bu durumda KALICI HATA sayılmalı (§2 madde 3, `4xx`
  kategorisi) — istemci kullanıcıya "işletme hesabı askıda" göstermeli,
  sonsuz retry YAPMAMALI.
- Deneme/abonelik süresi (`tenants.trial_ends_at`, `subscribed_until`) aynı
  yoldan işler — grace bitince aynı `402` davranışı devreye girer.
- Bu nedenle offline istemci senkron öncesi (ya da senkron 402 aldığında)
  kiracı durumunu AYRICA sorgulayıp kullanıcıyı UYARMALI; kuyruk günlerce
  büyürken sessizce "hepsi reddedildi" ile karşılaşmak kötü deneyim olur.
- `idempotency_keys` tablosu da `tenant_id` FK ile kiracıya bağlıdır
  (`BelongsToTenant`, cascade-delete) — kiracı silinirse/askıya alınıp asla
  dönmezse birikmiş kayıtlar kiracıyla birlikte temizlenir; ayrı bir retention
  job GEREKMEZ (yalnız normal büyüme için ileride `created_at` bazlı bir
  temizlik cron'u düşünülebilir — bugün gerekli değil, hacim düşük).

## 7. Kapsam dışı / bu görevde YAPILMAYAN

- Offline istemci (Tauri) kodu — yalnız yukarıdaki protokole UYMASI beklenir.
- `PaymentController@store`, diğer `orders.php`/`payments.php` uçları —
  yalnız `addItem` PROOF olarak değiştirildi (görev kuralı).
- `orders.local_temp_no` migration'ı (§4) — yalnız tasarım, kod yazılmadı.
- Kuyruk temizlik/retention cron'u — hacim düşükken gerekmiyor.
