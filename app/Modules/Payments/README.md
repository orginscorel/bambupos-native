# Payments Modülü (Faz-5, ADR-010)

Kasa + ödeme + POS adapter. **`payments` tablosu tek doğruluk kaynağıdır**;
`orders.paid_minor` / `orders.refunded_minor` bu tablodan, aynı transaction
içinde türetilir. Para = kuruş-integer (ADR-007), kayan nokta yasak.

## Mimari özet

```
Http/Controllers/   PaymentController (tahsilat/void/iade/sorgu)
                    PaymentCallbackController (oturumsuz, imzalı callback)
                    CashController (kasa/oturum/hareket/Z)
                    ServiceChargeController (servis bedeli → OrderService)
                    PaymentPageController (Inertia sayfaları)
Services/           PaymentService (para değişmezlerinin sahibi)
                    CashSessionService (kasa defteri; değişmez kayıt + ters kayıt)
Providers/          CashProvider, CardPresentProvider (kayıt-onaylı, anında)
                    MockPosProvider (TAM simülasyon), SandboxPosProvider (iskelet)
                    ProviderRegistry (config/payments.php 'providers' haritası)
Contracts/          PaymentProviderInterface
Models/             Payment, CashRegister, CashSession, CashMovement
```

Orders ile ilişki: sipariş kilidi/sürümü `OrderService::withLockedOrder`
üzerinden alınır; `paid/refunded` yalnız `OrderService::applyPaidDelta`
/ `applyRefundDelta` ile değişir (Payments bu metotları kilit içinde çağırır).

## KRİTİK KURAL — terminale gönderim ≠ tahsilat

`sendAmountToTerminal` sonucu ödemeyi TAMAMLAMAZ. Bir ödeme yalnız:

1. sağlayıcının **doğrulanmış senkron onayı** (`ProviderResult::APPROVED`),
2. **imzalı + zaman damgalı callback** (`verifyCallback`),
3. **queryPayment** onayı

ile `pending → succeeded` geçer (tek yön, tek sefer — replay ikinci kez işlemez).
`timeout/error` asla "başarısız" sayılmaz; durum belirsizdir, sorgu netleştirir.
Callback'te tutar bizim kayıttan alınır; sağlayıcının bildirdiğiyle yalnız
**karşılaştırılır** — uyuşmazlık `suspect` + denetim alarmı.

## Yeni sağlayıcı ekleme (adapter rehberi)

1. `app/Modules/Payments/Providers/AcmePosProvider.php` oluştur;
   `PaymentProviderInterface`'i uygula (şablon: `SandboxPosProvider`,
   davranış referansı: `MockPosProvider`).
2. `config/payments.php` → `providers` haritasına `'acme' => AcmePosProvider::class`
   ekle; kimlik bilgilerini `.env`'den oku (koda gömme).
3. Terminal yöntemlerinin varsayılanı yapılacaksa `PAYMENTS_TERMINAL_PROVIDER=acme`.
4. Uyulması ZORUNLU sözleşme kuralları:
   - `sendAmountToTerminal` HTTP timeout'u kısa tut (5–10 sn); zaman aşımını
     `TIMEOUT` olarak dön, **asla `DECLINED`'a çevirme**.
   - `verifyCallback`: imzayı `hash_equals` ile doğrula; timestamp/nonce
     penceresi uygula; tutarı yalnız karşılaştırma için çıkar.
   - `providerTxnId` üret/aktar — `UNIQUE(provider, provider_txn_id)`
     çift işlemeyi DB düzeyinde de keser.
   - Adapter DB'ye yazmaz, Order'a dokunmaz; yalnız sağlayıcıyla konuşur.
5. Test et: `tests/Feature/Payments/MockProviderCallbackTest.php` desenlerini
   kopyalayıp sağlayıcının kendi imza şemasıyla tekrarla.

## Mock sağlayıcının simüle ettiği senaryolar

Tutarın son iki hanesi senaryo seçer (`MockPosProvider`):

| Son iki hane | Davranış |
|---|---|
| `..99` | Terminal **DECLINED** (kart reddi) |
| `..98` | Gönderim **TIMEOUT**; `queryPayment` sonra **APPROVED** ("aslında çekilmişti") |
| `..97` | **PENDING**; imzalı **callback** bekler |
| `..96` | PENDING; sorguda **DECLINED** |
| `..95` | Gönderimde **ERROR** (ağ hatası, durum bilinmiyor) |
| `..89` (iade) | İade **DECLINED** |
| diğer | Doğrulanmış senkron **APPROVED** |

Ek: `terminal_id = OFFLINE` → terminal çevrimdışı + gönderim TIMEOUT.
Gecikme: `PAYMENTS_MOCK_DELAY_MS`. Callback imzası:
`HMAC-SHA256(timestamp . '.' . rawBody, secret)` — `X-Pos-Signature` +
`X-Pos-Timestamp`; tolerans `PAYMENTS_CALLBACK_TOLERANCE` (varsayılan 300 sn).

## GERÇEK entegrasyon için gerekenler (yapılMAdı — bilinçli)

Bu fazda **hiçbir gerçek sağlayıcıya bağlanılmadı, gerçek para işlemi yok.**
Canlıya bir sağlayıcı bağlamak için gerekenler:

1. **Sözleşme/hesap:** sağlayıcıdan (iyzico, PayTR, banka sanal POS, entegre
   ECR: Ingenico/Verifone/Beko) üye işyeri hesabı + API anahtarları
   (merchant_id, key, salt/secret) — `.env`'e, asla repoya değil.
2. **Callback URL kaydı:** `https://<alan>/api/v1/public/payments/callback/{provider}`
   sağlayıcı paneline tanımlanmalı; IP kısıtı varsa sunucu IP'si bildirilmeli.
3. **İmza şeması:** sağlayıcının kendi HMAC/hash formülü `verifyCallback`'te
   uygulanmalı (PayTR örneği README'de, kurumsal deneyim mevcut).
4. **3-D Secure akışı** (online ödemede): initiate → redirect → callback;
   `initiatePayment` RedirectData döndürecek şekilde genişletilebilir.
5. **Fiziksel terminal (ECR) entegrasyonu:** restoran içi terminale tutar
   basmak için sağlayıcının yerel ağ SDK'sı/bulut ECR API'si gerekir; NAT
   arkasında olduğundan ADR-009'daki "ajan dışarı-doğru bağlanır" deseni
   uygulanır (print-agent benzeri pos-agent).
6. **Test ortamı:** sağlayıcının sandbox'ı ile uçtan uca senaryolar
   (onay/red/timeout/iade/void/mutabakat) koşulmalı; `..98` timeout-sorgu
   davranışının gerçek karşılığı doğrulanmalı.
7. **Mutabakat:** gün sonu settlement raporu `reconcilePayment` ile
   eşleştirilmeli (zamanlanmış görev + uyuşmazlık alarmı).
8. **KVKK/PCI:** kart verisi BİZE HİÇ GELMEZ (redirect/terminal); log ve
   `meta` alanlarında PAN/CVV benzeri veri saklanmadığı gözden geçirilmeli.

## Para değişmezleri (test kanıtları)

`tests/Feature/Payments/` altında:

- `SUM(payments başarılı) == orders.paid_minor` → her testte `assertMoneyInvariant`
- Aşırı tahsil reddi / fazlalık açık bahşiş → `PaymentInvariantsTest`
- Çift işleme yok (Idempotency-Key, callback replay, UNIQUE txn) → `PaymentIdempotencyTest`
- Kuruş kaybı yok (3'e bölme 3334+3333+3333) → `PaymentInvariantsTest`
- Başarısız ödeme adisyonu kapatmaz → `PaymentInvariantsTest`, `MockProviderCallbackTest`
- Eşzamanlı iki ödeme → `PaymentConcurrencyTest` + MySQL iki-süreç kanıtı (rapor)
- Kasa defteri değişmezliği / ters kayıt → `CashSessionTest`
- Kiracı izolasyonu → `PaymentIsolationTest`; yetkiler → `PaymentAuthorizationTest`

## Menü bağlantısı (navigation.ts'e eklenecek — tek kaynak kuralı)

```ts
{ key: 'cashier', label: 'Kasa', icon: 'cart', href: '/panel/kasa', permission: 'payments.take', mobile: true },
```
