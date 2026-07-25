# QR Menü — Modül Haritası & Ajan Kılavuzu (CANLI HAFIZA)

> **Bu dosya her ajanın İLK okuyacağı tek referanstır.** Amaç: ağacı yeniden
> taramadan (token yakmadan) mevcut modüllerde hızlı ilerlemek. Bir modülü
> değiştiren ajan **işi bitince bu dosyanın ilgili satırını günceller**.
> Buraya YANLIŞ yazma — yazdığını doğrula. Son güncelleme: 2026-07-25

## 0. Temel gerçekler
- **Yol:** `/home/qrmenu/apps/qrmenu` — hesap `qrmenu`, `https://qrmenu.bogahostdeveloper.com.tr`, docroot `.../public`.
- **Yığın:** Laravel 13 · PHP **`/usr/local/bin/ea-php83`** (sistem `php`=8.2 KULLANMA) · Vue 3+TS+Inertia+Vite+Tailwind 4.
- **DB:** MariaDB 10.11 utf8mb4_unicode_ci. **Redis YOK** → queue/cache/lock = `database`.
- **Node:** v22 `/root/.local/bin`. Build: root node ile derle → **`chown -R qrmenu:qrmenu`**; sonra **`find ... -user root`→0**.
- **Giriş:** `demo@demo.com`/`demo1234`. Eski sistem `oritoriu`/`oritoriu_menu` SALT-OKUNUR.
- Çok-kiracılı SaaS, marka yok "powered by bogahost", palet turuncu-beyaz (token).

## 1. Değişmez kurallar
- APP_DEBUG=false; site 200. Migration yazınca HEMEN çalıştır; bayat rota/config cache bırakma.
- Commit et PUSH ETME; dosya yedeği al.
- Para = kuruş-integer `*_minor` + `Money`, float yok.
- Tenant izolasyonu 4 katman (global scope fail-closed + policy + scoped binding + servis).
- Masada TEK açık adisyon (`orders.table_open_slot` UNIQUE + trigger + lockForUpdate); yeni sipariş açık masaya eklenir.
- Ciro = kapalı sipariş (`paid`+`debt_transferred`); Tahsilat=`paid`; açık masa/borç ayrı. Her sipariş ciro DEĞİL.
- KDS (mutfak/komi) PARA GÖRMEZ.
- Public menü `/m/{token}` LiteSpeed full-page cache, Set-Cookie YOK, oturumsuz.
- Sahte veri/yarım buton yok. **Fable KULLANMA.** Ucuz doğrula (curl/DB/`artisan test --filter`).

## 2. Modüller — routes / Pages / menü / durum
- Identity (identity.php) — OK
- Tenancy (middleware) — OK
- Catalog (catalog.php, Catalog/**, menü catalog `/panel/menu`) — OK (ürün+65 görsel)
- Venue (venue.php, tables `/panel/masalar`) — OK (masa+QR)
- Orders (orders.php, Orders/{Board,Detail}, orders `/panel/siparisler`) — OK
- Kds (kds.php, Kds/{Kitchen,Runner}, kds `/panel/mutfak`+runner `/panel/komi`) — OK (ayrı tam-ekran, açık tema+dark/light, para görmez)
- Payments (payments.php, cashier `/panel/kasa`) — OK (mock POS)
- Receivables (receivables.php, receivables `/panel/borclar`) — OK (cari+adisyonu-borca-taşı)
- Staff (staff.php, staff `/panel/personel`) — OK (kişi-bazlı izin, switch)
- Settings (settings.php, settings `/panel/ayarlar/e-posta`) — OK (SMTP manuel)
- Reports (reports.php, Reports/**, reports `/panel/raporlar`) — OK (ciro fix)
- Reservations (reservations.php, Reservations/**, rezervasyonlar `/panel/rezervasyonlar`) — OK (panel gün/hafta takvim+liste, oluştur/düzenle/iptal/durum makinesi, çakışma+tampon denetimi AvailabilityService, bekleme listesi, masa-durumu bağı ReservationTableSync yaklaşan-pencere/late/no-show cron, public QR talebi /api/v1/public/reservations rate-limit+doğrulama "beklemede", alerji-notu hassas izin. **Timezone kök neden:** app.timezone=UTC iken şube tz=Europe/Istanbul → reserved_at 19:30 yerine 16:30 okunuyordu; config/app.php global değişimi kapsam dışı olduğundan modül-yerel `BranchLocalDateTime` cast'i ile çözüldü: DB'de UTC SAKLANIR (cron/now() bind'leri tutarlı), OKUMADA şube tz'ye çevrilir; Carbon karşılaştırmaları instant-tabanlı olduğundan yaklaşan/gecikme hesapları etkilenmez. Feature-flag kancası `ReservationFeature::enabled` (yer tutucu true, §9 TODO; kapalı=panel+public 404). izin reservations.view/manage vb. authz.php'de; menü tek satır calendar ikonu.)
- Shifts (shifts.php, Shifts/**, vardiya `/panel/vardiya` + mesai `/panel/mesai/*`) — OK. **Planlama:** vardiya (ad/pozisyon, başlangıç-bitiş, şube, mola dk), haftalık/aylık grid + tıkla-ata, personele atama (Staff/User kaynağı), çakışma denetimi (Shift::scopeOverlapping, aynı kişi kesişen aralık→422, bitişik≠çakışma, allow_overlap ile bilinçli), tekrarlayan seri (repeat_group), min. personel kuralı uyarısı. **Attendance (mesai):** clock in/out (TimeClockService tek kapı, dakika-integer), plan vs gerçek, geç kalma/erken çıkış (tolerans) + fazla mesai + eksik + devamsızlık; finalize() türetilmiş alanları TEK yerden hesaplar; manuel düzeltme neden-zorunlu+audit. **Device-clock (§13):** `POST /api/v1/shifts/device-clock` oturumsuz+CSRF dışı, kimlik = `X-Device-Token` (ClockDevice, token SHA-256 hash) → tenant/şube cihazdan; personel **PIN** (+çakışırsa staff_code) ile çözülür (identifyByPin, PIN kilidi). Ortak tablet=tam panel girişi değil. **Rapor:** Performans>Devam Takibi kişi bazlı gün/hafta/ay (çalışılan saat, fazla/eksik, geç kalma ×+dk, erken çıkış, izin/devamsızlık). **İzin/talep:** leave_requests (annual/sick/unpaid/holiday/absence/other) + swap-requests, onay akışı. **Feature kancası** `ShiftsFeature::enabled` (Support/, yer tutucu true, §9 TODO; panel rotaları 404 gate — ShiftPageController::featureGate). **İzin adı:** yeni izin YOK — Staff'ın `staff.view`/`staff.manage`'ini kullanır (herkes KENDİ verisini görür; başkasını görmek staff.view, yönetmek staff.manage). Menü tek satır `calendar` ikonu (permission staff.view). **Demo:** ShiftsSeeder (DemoTenantSeeder'dan SONRA; 3 PIN'li personel garson/mutfak/komi, 20 vardiya=bu hafta, 15 mesai kaydı geç/fazla/erken varyasyonlu + 1 açık kayıt, 3 izin/devamsızlık, 1 clock cihazı; idempotent). Test: tests/Feature/Shifts (27 yeşil). **Tuzak:** süreler dakika-integer (float yok); konum KVKK varsayılan KAPALI (ayar+rıza yoksa koordinat sessizce atılır).
- Inventory (inventory.php, Inventory/**, stok `/panel/stok`) — OK (§7 tam). Depo/kalem (kg/g/lt/adet, kritik eşik, hareketli-ort maliyet), reçete (ürün→hammadde, versiyonlu, şube/varyant çözümü, gramaj=recipe_line qty; kalori products.calories/portion kolonlarında hazır) + yarı-mamul üretim. **Otomatik düşüm hook'u:** Orders'a DOKUNMADAN `InventoryServiceProvider` Eloquent model olaylarından: OrderItem `served`→reçete tüketimi düşer, Order `paid`→güvenlik ağı, kalem-başı idempotent (ledger ref order_item), best-effort+report() (sipariş akışı bozulmaz). **İptal→iade:** OrderItem `cancelled` olayı→`ConsumptionService::revertOrderItem` stoğu geri ekler, cancel_reason SEBEP yazılır, idempotent (ref order_item_return). **Değişmez ledger** inv_movements (StockLedger tek kapı, lockForUpdate seviye senkron, reverse=ters kayıt). Panel: Stok Kartları/Hareket Defteri/Reçeteler/Sayım/Mal Kabul-Satın Alma/Tedarikçiler/Uyarılar/**Rapor** (InventoryNav). **Rapor** (ReportService): gün/ay/aralık dönem mutabakatı (açılış→giriş→çıkış→kapanış) + gün sonu "stoktan azalan" + tüketim/giriş maliyeti (kâr-maliyet bağı). **Tuzak:** `lines` MariaDB rezerve kelime→dayEnd alias `move_count` (SQLite'ta yakalanmaz). Feature-flag kancası `InventoryFeature::enabled` (yer tutucu true, §9 TODO; panel rotaları 404 gate'i buna bakar). İzin `stock.view`/`stock.adjust` (authz.php + templates, seed'li). Demo: InventorySeeder (8 kalem+6 reçete+13 hareket, CatalogSeeder'dan SONRA). Menü tek satır `package` ikonu.
- Kiosk (kiosk.php, Kiosk/**, panel Kiosk/Index `/panel/kiosklar`) — OK (opak cihaz token=ADR-008 26-char base32, kiracı/şube token'dan türer + rotasyon 410 + uzaktan kilit; oturumsuz tam-ekran /kiosk/{token}, sepet yalnız bellekte→reset=location.reload; sipariş kanal=kiosk + tek-adisyon, mock POS §22 dürüst pending/fail; izin kiosk.view/kiosk.manage; feature-flag kancası KioskFeature::enabled (yer tutucu true, §9 TODO))
- Changelog (changelog.php, changelog `/panel/surum-notlari`) — OK
- Wiki (Wiki.vue, wiki `/panel/nasil-calisir`) — OK
- **Notifications/Push** — YOK, YAPILACAK (§8)
- **Features/Eklentiler (feature-flag)** — YOK, YAPILACAK (§9)

> Rota grupları `bootstrap/app.php` `then:` bloğunda kayıtlı.

## 3. Paylaşılan/çekişmeli dosyalar (tek yerden)
- `resources/js/config/navigation.ts` — sidebar TEK KAYNAK (yeni modül=tek satır).
- `resources/js/Components/panel/PanelShell.vue` — kabuk; menü buradan gelmez; Ctrl+K + bildirim zili burada.
- `bootstrap/app.php` — rota kaydı + guest→401(api). Her modül kendi satırı.
- Staff izin kataloğu — yeni modül izinleri (`x.view`) buraya.

## 4. Tuzaklar
- `delayed` MariaDB rezerve kelime → alias'ta backtick.
- Relation eklersen migration'ı çalıştır (yoksa panel 500).
- Guest `/api/v1/*`: `redirectGuestsTo` api'de null (401).
- Demo tarih: MySQL `NOW()` UTC+3 kayması → `UTC_TIMESTAMP()`.
- Menü "iki kaynak" tuzağı → sadece navigation.ts.
- Public menüde Set-Cookie olursa cache bozulur.
- `Pages/Panel/Kiosk/Index.vue` TS hatası (kiosk ajanı düzeltecek).
- `python open('w')` YASAK — Edit/Write kullan.

## 5. Ucuz doğrulama
- `curl -s -o /dev/null -w "%{http_code}" https://qrmenu.bogahostdeveloper.com.tr/giris`
- `/usr/local/bin/ea-php83 artisan test --filter=<Modül>`

## 6. Öncelik sırası (kalan fazlar)
Kiosk → Rezervasyon(+timezone) → Depo/Stok(§7) → Vardiya → Bildirim/Push(§8) → Eklenti/feature-flag(§9) → Public menü ürün-modal redesign(§10) → Komi SLA(§11). Sonra: tema editörü, native/PWA, sadakat/kampanya, yazıcı adapteri.

---

## 7. DEPO / STOK (Inventory) — detaylı gereksinim (kullanıcı 2026-07-25)
- **Reçete-bazlı otomatik düşüm:** ürün siparişe/servise girince reçete içeriğine göre depodan otomatik azalır. "Kola verildi masaya" → kola stoğundan 1 adet otomatik düş.
- **İptal → geri iade:** yanlış/iptal edilen kalem stoğa geri eklenir; **sebep zorunlu yazılır** (ledger).
- **Gramaj + kalori:** "200 kg et geldi" → ürünün gramajı ve kalori değeri sistemde tanımlı; her serviste tanımlı gramaj kadar otomatik düşer. İstisna/fazla verilen porsiyon → **sebep bildirilir** ve loglanır.
- **Değişmez ledger (stok hareketleri):** her giriş/çıkış/iade/düzeltme kaydı — kim, ne, ne kadar, sebep, tarih-saat, ilişkili sipariş. **Detaylı log arayüzü** (açıklamalı).
- **Raporlama:** gün / ay / geçmiş-günler bazlı. Gün sonu: "bugün stoktan şu kadar X ürün azaldı." Profesyonel kontrol mekanizması (giriş vs çıkış vs kalan mutabakatı).
- **Birimler:** kg/g/lt/adet + porsiyon→hammadde dönüşümü (reçete kalemi birim çarpanı). Para değil miktar; ama maliyet raporuyla ciroya bağlanır (kâr/maliyet raporu Reports'ta).

## 8. BİLDİRİM & PUSH mimarisi — YOK, yapılacak (kullanıcı 2026-07-25)
- **Alan/rol bazlı ayrı kanallar:** mutfak, komi, kiosk-sipariş, kasa, yönetici — her rol yalnız KENDİ ilgili bildirim+push'unu alır.
- **Yönetim hepsini görür/alır.**
- **Açma/kapama — detaylı, kalem kalem:** "şunu al, bunu alma" seviyesinde tekil olay tipleri (yeni sipariş, hazır, gecikme, düşük stok, rezervasyon, komi-SLA ihlali, gün sonu vb.) ayrı ayrı switch.
- **İki yer:** (a) yönetici genel/rol-bazlı politika, (b) **kişi kendi profilinden** kendi bildirim tercihlerini ayarlar (profil sayfasında bölüm).
- **Push altyapısı:** web push (VAPID) + panel içi bildirim zili (PanelShell). Redis yok → queue/db.
- **Staff yetkileri güncel:** bildirim izinleri personel-yetki kataloğuna dahil edilir.

## 9. EKLENTİLER / FEATURE-FLAG — YOK, yapılacak (kullanıcı 2026-07-25)
- Yöneticide **Eklentiler** alanı: tüm özellikler tek tek aç/kapa. **Görünürlük açık/kapalıya göre değişir.**
- Örnekler: QR menüde "su/garson çağır" olabilir/olmayabilir; rezervasyon sistemi olabilir/olmayabilir; QR'dan sipariş alma olabilir/olmayabilir.
- Tenant bazlı `features` tablosu/servisi; hem panel menüsü (navigation) hem public menü davranışı bu flag'lere bakar. Kapalı özellik hiç render edilmez (ADR: kapalı=yok).

## 10. PUBLIC MENÜ ürün-modal redesign — kötü tasarım (kullanıcı 2026-07-25)
- Ürüne basınca açılan **seçenek/eklenti + ALERJEN bölümü** tasarımı kötü → yeniden tasarlanacak (public menü, vanilla JS, cache bozmadan).

## 11. KOMI TESLİM SLA — yapılacak (kullanıcı 2026-07-25)
- Komi ürünü istasyondan **teslim aldığında** sayaç başlar; **1-2 dk içinde masaya teslim etmezse** → "XXX ürün XXX masasına tarafınızdan alındı ama teslim edilmedi" push+bildirim **komiye VE yöneticiye** (personel ad-soyad ile).
- **Rapor menüsünde loglanır:** kim geç verdi, tarih-saat, ne zaman aldı, ne zaman teslim etti. (KDS pickup→deliver zaman damgaları + SLA raporu.)

## 12. İSTASYON YÖNLENDİRME: Mutfak ↔ Barista ayrı — yapılacak (kullanıcı 2026-07-25)
- **Barista/Bar diye ayrı bir hazırlık istasyonu YOK, kurulacak.** Mutfakta kimse kahve/içecek yapmaz.
- **Ürün→istasyon ataması:** her ürün (veya kategori) bir hazırlık istasyonuna atanır: Mutfak, Barista/Bar (gerekirse Tatlı/Izgara vb. genişletilebilir olsun). Kahve/içecek/bar ürünleri Barista'ya, yemekler Mutfak'a. Demo ürünleri **doğru istasyonlara ata** (kahve/çay/soğuk içecek → Barista).
- **Her istasyonun KENDİ KDS ekranı:** Mutfak yalnız kendi kalemlerini, Barista yalnız kendi kalemlerini görür (KDS zaten var — çok-istasyonlu hale getir; istasyon filtreli ayrı ekran/sekme). İstasyon KDS'i PARA GÖRMEZ (mevcut kural).
- **Komi = hepsi:** komi ekranı TÜM istasyonların (Mutfak+Barista+...) hazır kalemlerini görüp teslim alabilir — istasyon farkı komiyi bölmez.
- **İstasyon yönetimi:** yönetici istasyon ekleyip ürünleri atayabilsin (Catalog/KDS ayarı). "İstasyon" kavramı kullanıcıyı önce karıştırıyordu → net etiket (Mutfak/Barista) + basit atama UI.
- Not: mevcut `station` alanı/kavramı Orders & KDS'te var; bunu gerçek Mutfak/Barista ayrımına oturt, yeni kavram uydurma.

## 13. İSTASYON CİHAZ MODU (kiosk gibi kilitli terminaller) — yapılacak (kullanıcı 2026-07-25)
- **Sektör standardı:** kiosk müşteri içindir; personel istasyonları (Mutfak, Barista, Komi, Sipariş-giriş/POS) da **cihaza-bağlı, tam-ekran, KİLİTLİ terminal** olmalı. O cihaz yalnız KENDİ istasyonunun ekranını gösterir; personel tüm paneli/sistemi görmez (KDS bump-screen deseni). Amaç: "herkes her şeyi görmesin".
- **Kimlik = kiosk deseni (ADR-008):** her istasyon terminaline opak **cihaz token'ı** (Mutfak/Barista/Komi/POS ayrı). URL token'la açılır, tenant+şube+istasyon token'dan türer. Hassas eylemler (sipariş kapatma/iptal/iade) için **PIN** (tam panel girişi değil).
- **Kapsam:** Mutfak→yalnız Mutfak kuyruğu; Barista→yalnız Barista; Komi→tüm istasyonların HAZIR kalemleri (§12); Sipariş-giriş→sadece adisyon açma/ürün ekleme. Para: mutfak/barista/komi PARA GÖRMEZ; sipariş-giriş görebilir.
- **Panelden yönetim:** kiosk cihaz yönetiminin aynısı (ekle/kaldır, token yenile, kilit, istasyon/şube). Kiosk `KioskDevice`/token altyapısı genelleştirilebilir.
- **İlişki:** §12 tamamlanınca üstüne kurulur; Barista dalgasıyla planla.
