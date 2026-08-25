# Teslim Notları — canlıya almadan önce gereken gerçek entegrasyonlar

Bu doküman, sistemin **bugün gerçekten ne yaptığını** ve **canlı kullanım için hâlâ gerçek
donanım/kimlik bilgisi/entegrasyon gerektiren** noktaları dürüstçe listeler. Hiçbiri
uydurulmamıştır; her madde ilgili kod dosyasına/satırına ve (varsa) kullanıcıya zaten
gösterilen dürüstlük mesajına atıfta bulunur. Aşağıdaki dört maddenin kodu bu teslim
kapsamında **değiştirilmedi** — gerçek merchant/ECR kimlik bilgisi olmadan güvenli bir
değişiklik yapılamaz; bu doküman yalnızca mevcut durumu belgeler.

## 1. Kart/ECR ödemesi — `SandboxPosProvider` gerçek bir POS/ECR'a bağlı DEĞİL

`app/Modules/Payments/Providers/SandboxPosProvider.php`

Bu sınıf **bilinçli olarak çalışmaz**: kendi docblock'unda da yazdığı gibi (satır 10-16),
gerçek bir sağlayıcının (iyzico/PayTR/banka sanal POS/Ingenico-Verifone ECR) yerine geçen
bir **iskelet**tir. Yapılandırma (`PAYMENTS_SANDBOX_*` env) boşken her çağrı sahte bir
"başarı" ÜRETMEZ, açıkça `ERROR` döner. Yedi entegrasyon noktası `TODO(entegrasyon)` olarak
işaretli ve gerçek bir sağlayıcıya bağlanmayı bekliyor:

- `initiatePayment()` — satır 50-53: ödeme başlatma isteği
- `sendAmountToTerminal()` — satır 62-65: tutarı ECR/bulut-POS'a gönderme
- `queryPayment()` — satır 74-76: sağlayıcıdan durum sorgulama
- `cancelPayment()` — satır 85-87: void/iptal
- `refundPayment()` — satır 96-98: kısmi/tam iade
- `reconcilePayment()` — satır 107-108: gün sonu (settlement) mutabakatı
- `verifyCallback()` — satır 113-117: sağlayıcının imza şeması (HMAC vb.) doğrulaması

**Canlıya geçmeden önce gereken:** seçilecek gerçek sağlayıcının (banka sanal POS, ÖKC/
yazarkasa entegratörü, ödeme kuruluşu) API kimlik bilgileri (API key, terminal ID, imza
anahtarı) + sandbox ortamında uçtan uca test. Adım adım rehber zaten kod tabanında hazır:
`app/Modules/Payments/README.md` §"Gerçek sağlayıcı ekleme".

**Kullanıcıya zaten dürüstçe gösteriliyor:** Kasiyer ekranı (Cashier.vue) bu durumu
gizlemiyor — bkz. madde 3.

## 2. `IyzicoProvider` — SaaS abonelik tahsilatı, sahte KYC verisi + doğrulanmamış webhook

`app/Modules/Billing/Payments/Providers/IyzicoProvider.php:26-41` (sınıf docblock'u,
"VARSAYIM/DOĞRULANMAMIŞ NOKTALAR" başlığı altında) bu maddeleri zaten kendi içinde itiraf
ediyor:

- **Sahte kimlik/adres verisi** — `checkoutUrl()` içinde iyzico'nun Checkout Form
  Initialize isteğinin zorunlu tuttuğu alanlar, Tenant modelinde bu veri toplanmadığı için
  placeholder ile dolduruluyor: `identityNumber => '11111111111'` (satır 96, sahte TCKN),
  `gsmNumber => '+905000000000'` (satır 94, sahte telefon), `city => 'İstanbul'` /
  `country => 'Turkey'` / `address => 'Türkiye'` (satır 97-112, hem `buyer.registrationAddress`
  hem `shippingAddress` hem `billingAddress` için sabit).
- **Webhook URL'in iyzico panelinde otomatik kayıtlı olduğu doğrulanmamış** — satır 82-87'deki
  yorum: API isteğindeki `callbackUrl` alanı, iyzico Merchant Panel'deki "Webhook URL"
  ayarını OTOMATİK yapmaz; `TODO(entegrasyon): panelden teyit et.`
- **İmza şeması sandbox'ta teyit edilmemiş** — `verifyCallback()` (satır 140-186) resmi
  dokümandan (docs.iyzico.com) alınan HMAC-SHA256 formülünü uyguluyor ve `hash_equals` ile
  karşılaştırıyor (satır 165-169, doğru pratik), ama `status` alanının gerçek değer kümesi
  ("SUCCESS"/"FAILURE" vb., satır 172-178'deki `approved`/`declined` eşlemesi) sandbox'ta
  hiç doğrulanmadı.

**Canlıya geçmeden önce gereken:** (a) Tenant modeline gerçek fatura/KYC alanları (TCKN/VKN,
telefon, açık adres) eklenip işletme onboarding formundan toplanmalı; (b) iyzico sandbox
hesabıyla uçtan uca bir test ödemesi yapılıp webhook'un panelde doğru URL'e kayıtlı olduğu +
`status` alanının gerçek değerleri teyit edilmeli; (c) gerçek merchant `IYZICO_API_KEY` /
`IYZICO_SECRET` üretim ortamına girilmeli.

## 3. Kasiyer ekranı sandbox durumunu zaten dürüstçe gösteriyor (referans, değişiklik yok)

`resources/js/Pages/Panel/Payments/Cashier.vue:190-201` ve `:1222-1243` — kart ödeme
yöntemi seçildiğinde, aktif sağlayıcının GERÇEK durumu sunucudan okunup (uydurma yok) bir
rozetle gösteriliyor. Sağlayıcı simülasyon/sandbox modundaysa (bugünkü durum — madde 1)
kasiyer ekranında şu uyarı çıkıyor:

> "Fiziksel kart okuyucu **bağlı değil** — bu sağlayıcı test/simülasyon amaçlıdır, **GERÇEK
> tahsilat yapmaz**. Kartı harici POS cihazınızdan siz okutup tutarı burada **manuel
> onaylayın**."

Bu davranış zaten doğru ve dokunulmadı; burada yalnız teslim notuna referans olarak
kayıtlı — madde 1 çözülene kadar kasiyerler bu uyarıyla çalışmaya devam edecek.

## 4. Gerçek termal yazıcı sürücüsü yok — tarayıcı-yazdırma yöntemi kullanılıyor

Fiş yazdırma (KDS istasyon fişi + kasa/müşteri fişi, `docs/MODULE_MAP.md` §13 Faz C-1/C-2,
2026-07-26'da tamamlandı) **gerçek bir termal yazıcı sürücüsü/ESC-POS entegrasyonu ile
ÇALIŞMIYOR**. Yöntem bilinçli bir tasarım kararı ("tüm cihaz/yazıcı uyumu"): fiş, gizli bir
`<iframe>`'e kendi belgesi olarak yazılıp `iframe.contentWindow.print()` ile basılıyor —
yani cihazın işletim sistemi/tarayıcısının varsayılan yazdırma diyaloğu (fiziksel yazıcı ya
da PDF) devreye giriyor, 58/80mm termal ya da A4 boyutu otomatik algılanıyor
(`resources/js/Pages/Panel/Kds/useReceiptPrint.ts`, `resources/js/Pages/Panel/Payments/
usePaymentReceiptPrint.ts`). Bu, her cihazda çalışır ama gerçek bir donanım
sürücüsü/adaptör DEĞİLDİR — yazıcı seçimi, kağıt kesme komutu, çekmece açma gibi
ESC-POS'a özgü donanım kontrolleri yoktur. Gerçek bir termal yazıcı adaptörü hâlâ
roadmap'te (`docs/MODULE_MAP.md` §6, "yazıcı adapteri").

## 5. Roadmap'te hiç başlanmamış diğer kalemler (bilgi amaçlı, teslimatın parçası değil)

`docs/MODULE_MAP.md` §6 "Öncelik sırası (kalan fazlar)" sonunda listelenen, bu teslime dahil
OLMAYAN büyük kalemler:

- **Tema editörü** — yalnız temel ayarlar var (marka rengi, vurgu rengi, yazı tipi, açık/koyu
  mod); tam/görsel bir tema editörü yok.
- **Native/PWA paketleme** — uygulama şu an yalnızca tarayıcı üzerinden çalışıyor; native
  mobil paket ya da PWA (yükle/offline-ikon) paketlemesi yapılmadı.
- **Sadakat/kampanya sistemi** — müşteri sadakat puanı, indirim kampanyası vb. hiç yok.
- **Gerçek termal yazıcı adaptörü** — madde 4'te açıklanan tarayıcı-yazdırma yönteminin
  yerine geçecek, donanıma özel (ESC-POS) bir sürücü/adaptör; henüz başlanmadı.

---

*Bu doküman teslim öncesi son cila (2026-08-05) kapsamında eklendi; kaynak: iç denetim
(audit madde 3, 4) + `docs/MODULE_MAP.md` §6 roadmap taraması. Ödeme/sipariş mantığına
dokunulmadı — yalnızca mevcut durumun belgelenmesidir.*
