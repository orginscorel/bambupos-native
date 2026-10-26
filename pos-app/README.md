# BamBumPOS POS — native uygulama

Flutter ile **native** derlenen POS uygulaması (webview değil). Android · iOS · Windows · macOS tek kod tabanı.
Yalnız POS ekranları: **Masalar (sipariş girişi) · Kasa · Hazırlık (mutfak/barista/nargile) · Servis (komi)**.
İşletme yönetimi, raporlar ve ayarlar web panelinde/konsolda kalır.

## Akış
1. **Aktivasyon** — ilk açılışta cihaz 6 haneli kod üretir (`POST /api/v1/cihaz-aktivasyon/baslat`), 3 sn'de bir durum sorar.
   Yönetici *İşletme Yönetimi › Cihazlar › Yeni tanımlı cihaz* ile kodu girip ad + ekran seçer; uygulama kendiliğinden aktive olur.
2. **PIN** — personel PIN'i (`POST /terminal/operator/pin`).
3. **Ekranlar** — `GET /api/v1/uygulama/oturum`: cihaz → ana ekran, kişi → yetkisine göre ek sekmeler (`lib/ekranlar/kabuk.dart`).
   Cihazda çıkış yok; "Kilitle" yalnız personeli düşürür. Cihaz konsoldan kaldırılınca 401 → aktivasyon ekranı.

Oturum web paneliyle aynıdır: Laravel çerezleri diskte kalıcı (`PersistCookieJar`), yazma isteklerinde `X-XSRF-TOKEN`.

## Hız
- Katalog bellekte + diskte, ETag ile (değişmediyse 304, gövde inmez).
- Ürün dokununca fişte anında görünür; istekler sıralı kuyrukla gider, her eklemede `op_id` + `Idempotency-Key` (çift yazım yok).
- Mutfak ekranı uzun-yoklama (`/api/v1/kds/updates`) — sipariş düştüğü an görünür.
- Son pano diskte; açılışta beklemeden çizilir.

## Geliştirme
```
flutter pub get
flutter analyze && flutter test
GORUNTU_DIZINI=/tmp/goruntu flutter test test/ekran_goruntusu_test.dart   # demo verisiyle ekran görüntüleri
flutter build apk --release --target-platform android-arm,android-arm64
```
Derleme ve yayın: `.github/workflows/pos-app.yml` — `pos-v*` etiketi dört platformu derleyip GitHub Release açar.
Sürüm duyurusu: `https://bambumpos.com/indir/pos/surum.json` (uygulama içi "yeni sürüm" şeridi bunu okur).

## İmza
Android anahtarı depoda DEĞİL: CI'da `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` secret'larından yazılır
(yerelde `android/key.properties` + `android/app/imza.p12`, ikisi de .gitignore'da). Anahtar değişirse kurulu uygulamalar güncellenemez.
