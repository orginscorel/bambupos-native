# FRONTEND_PROGRESS — Dönüşüm İlerleme Takibi

> Her iterasyonda ÖNCE bu dosyayı oku, git geçmişine bak, uygulamayı çalıştır,
> temel akışı test et, EN yüksek öncelikli `pending` ekranı seç, uygula,
> 1440/768/390'da browser automation ile test et, VISUAL_QA yaz, YALNIZ gerçekten
> test edileni `completed` işaretle, commit et. Test edilmemiş = completed YASAK.

## Kurallar
- Tek iterasyon = tek ekran veya sıkı bağlı küçük component grubu.
- Backend/şema/API/auth/route/ödeme/hesaplama mantığı DEĞİŞTİRİLMEZ (onaysız).
- Her ekran 6 kriterde ≥8.5 olmadan `completed` sayılmaz.

## Faz durumu
| Faz | İçerik | Durum |
|---|---|---|
| 0 | Audit + dokümanlar + browser QA | ✅ tamam (bu belge seti) |
| 1 | Design foundation (mavi token + tipografi + bileşenler) | ✅ tamam (canlı+QA) |
| 2 | Uygulama shell (sidebar/header/mobil-nav/şube seçici/⌘K/bildirim) | ✅ tamam (canlı+QA) |
| 3 | Ekranlar: Dashboard→POS→Masa planı→Mutfak→QR menü→Personel→Rapor→Stok→Paket→Şube | ⛔ pending |
| 4 | Pazarlama sitesi | ⛔ pending |
| 5 | Motion & polish | ⛔ pending |
| 6 | Native hazırlık | ⛔ pending |

## Faz 1 kontrol listesi (onay sonrası)
- [x] `app.css` katman-1: marka MAVİ (`--brand` #2563EB ekseni), semantik durum
      token'ları (order-*/table-*/stock-critical), serin-slate yüzeyler (açık+
      koyu), portal `.portal-root` mavi, @theme inline eşlemeleri. + sabit-kodlu
      turuncu kalıntılar temizlendi (progress bar, PWA theme-color, kiosk brand).
      → **canlıda + 1440 browser-doğrulandı** (2026-07-26).
- [x] Tipografi: Poppins korundu (self-host + Türkçe latin-ext); tabular-nums
      MetricTile/NumberStepper + sayısal bağlamlarda. (Font swap ileride opsiyon.)
- [x] Bileşenler: mevcut 24 token-tabanlı (mavi otomatik) + YENİ 6 → StatusPill,
      MetricTile, SegmentedControl, NumberStepper, BottomSheet, Tooltip +
      AppIcon (arrow-up/down, minus). DesignSystem.vue galeri güncel. **canlı+QA.**
- [ ] Spacing 4/8, radius/gölge ölçekleri.
- [ ] İkon ailesi genişletme (domain ikonları).
- [ ] Bileşenleri MAVİ token'a taşı + eksikler (Tooltip/BottomSheet/CommandPalette/
      MetricTile/StatusPill/SegmentedControl/NumberStepper/DeviceFrame/DateRange).
- [ ] `DesignSystem.vue` galeri sayfasını güncelle (canlı referans).

## Ekran durumları (özet — ayrıntı frontend-features.json)
Tümü `pending`. P0: dashboard, orders-board, order-detail, cashier, kitchen-kds,
barista-kds, runner, qr-menu. P1: boss, delivery-board, reservations, reports,
inventory, staff, portal-*, marketing. 

## Değişmeyecek backend alanları (kilitli)
Orders/Payments/Inventory hesaplama, OrderService/PaymentService, API sözleşmeleri,
auth (LoginController/PinService), authz (authz.php/policies), TenantScope,
route yapısı, ödeme akışı. Zorunlu değişiklik → önce rapor + onay.

## Iterasyon günlüğü
- 2026-07-26 — Faz 0 audit tamam (UI_AUDIT, DESIGN_SYSTEM, SCREEN_INVENTORY,
  UX_FLOWS, VISUAL_QA, frontend-features.json). Onaylandı.
- 2026-07-26 — Faz 1 tamam: mavi token sistemi + domain durum token'ları + 6
  yeni bileşen (StatusPill/MetricTile/SegmentedControl/NumberStepper/BottomSheet/
  Tooltip). Canlı + /tasarim QA.
- 2026-07-27 — Faz 3 Ekran 1: **Dashboard** yeniden tasarlandı (MetricTile KPI +
  aksiyon bölümü + StatusPill + ince push şeridi). 1440+390 browser-QA. ✅
- 2026-07-27 — Faz 2 **uygulama shell** yapısal dönüşüm: PanelLayout sidebar
  (sabit ikon kutusu → hizalama, aktif sol accent bar, ikon-only RAY modu,
  şube seçici üstte) + ürün header (⌘K arama, Çevrimiçi göstergesi) + PanelShell
  başlık bloğu. DataTable responsive yeniden yazıldı (<md kart-liste, sticky
  aksiyon kolonu, kolon önceliği hideBelow) → **768px tablo taşması çözüldü**
  (Personel kanıtlı kusur). + TableToolbar. Staff/Index yeni DataTable'a taşındı.
  1440/768/390 browser-QA. ✅
- 2026-07-27 — Dashboard KPI **yerleşim düzeltme** (kullanıcı: kayma/sıkışma/
  taşma): 6-eşit-kart → hiyerarşi (öne çıkan ciro + mini sparkline geniş tile /
  destek para tile'ları / kompakt operasyon satırı). MetricTile'a `size='sm'` +
  değer taşma koruması (min-w-0/truncate/leading-snug). Açık-adisyon rozet
  kırpılması giderildi (kısa etiket + eşik alt-not). 1440/768/390 QA. ✅
- 2026-07-27 — Faz 3 **Masa panosu** (Orders/Board.vue) gelişmiş grid (kullanıcı
  onayı: backend'e dokunma, koordinatlı kroki ayrı faz — masalarda x/y YOK):
  pano özet şeridi (doluluk %/bar, dolu-boş, açık tutar ₺, açık adisyon), slim
  filtre satırı (masaüstü) + **mobil filtre BottomSheet'i** (masalar üstte kalır)
  + rafine masa jetonları (kompakt boş kart, min-h 40→36). Tüm sipariş/adisyon/
  ödeme akışı + endpoint + polling DEĞİŞMEDİ. AppIcon'a `filter` eklendi. 1440/
  390 browser-QA + filtre çekmecesi işlevsel test. ✅
- 2026-07-27 — Faz 3 **POS / Adisyon** (Orders/Detail.vue) üst şerit yeniden
  düzenlendi: 5-rozet+isim+meta tek yoğun satır → **üst satır** (isim belirgin +
  kaynak/servis + meta, sağda eylemler) / ayraç / **alt satır** durum rozetleri.
  Ödeme/sipariş mantığı DEĞİŞMEDİ. 1440 QA. ✅
- 2026-07-28 — Faz 3 **KDS Mutfak/Komi/Barista** kartı (Kitchen.vue) yeniden
  tasarlandı: alerjen → "Alerjen:" etiketli hafif outline şerit (kırmızı blok
  seli yok), diyet ayrı satır, **reçete/hazırlama aç-kapa** (backend: KdsPresenter
  `recipe` = products.description; eager-load'a description). Not kutulandı. 3
  istasyon birden düzeldi. 1440 QA + reçete işlevsel. ✅
- 2026-07-28 — **Kasa** (/panel/kasa) incelendi: zaten profesyonel (iki-panel +
  ödeme yöntemi ikon grid'i) → değişiklik gerekmedi. ✅
- 2026-07-28 — **Terminal**: personel giriş GATE'i (liste+PIN, arka plan blur,
  girişte oto clock-in) + sağ-alt personel barı (mesai/mola/açtığı adisyon/
  eklediği ürün + oturum kapat, veri silinmez) + **heartbeat** (Çevrimdışı bug
  fix) + termal yazıcı (kiosk/WebUSB + kalem-bazlı oto-fiş). ✅
- 2026-07-28 — **Personel PIN**: yönetici Personel bölümünden PIN atar +
  GÖRÜNTÜLER (pin_encrypted Crypt kolonu; bcrypt doğrulama korunur; audit). ✅
- 2026-07-28 — **QR menü önizleme**: panel Katalog başlığına "Müşteri menüsünü
  önizle" butonu (`CatalogShell.vue`) → `/api/v1/catalog/preview-url` boş
  (available) masanın QR token'ını alıp `/m/{token}?preview=1` yeni sekmede açar.
  Public menü preview modunda: sarı önizleme şeridi + `QRM_CFG.orders/service=""`
  (sipariş/çağrı gönderilmez) + no-cache. curl ile doğrulandı. ✅
- 2026-07-28 — **Native-mobil dönüşüm (Kardo-HR referans hissi) — İterasyon 1**:
  temel + shell. (a) `app.css`'e mobil token'lar (h-list-row/tabbar/fab, native
  gölgeler: shadow-tabbar/fab/sheet). (b) 10 native bileşen: `ListRow`,
  `MobileListGroup`, `InfoRow`, `SectionHeader`, `FilterChip`, `ErrorState`,
  `SkeletonRow`, `Accordion`, `Timeline`, `FabButton`. (c) shell: eski mobil
  alt-nav → **native `MobileTabBar`** (2 sekme · orta QR **FAB** · 1 sekme ·
  Tümü) + mobil üst-barda **sayfa başlığı görünür**. (d) Dashboard para satırı
  native: ciro tam-genişlik hero + tahsilat/açık-masa yan-yana kompakt (3
  yığılmış büyük kart yok). Masaüstü sidebar + tüm veri/iş mantığı DEĞİŞMEDİ.
  390px açık+koyu tema browser-QA. ✅
- 2026-07-28 — **Native-mobil — İterasyon 2**: liste ekranları. (a) **DataTable
  kart modu** yeniden yazıldı: her satır ayrı bordürlü kart → **native gruplu
  liste** (tek yüzey, hairline ayraç, ebeveyn çerçevesine flush). TÜM tablo
  ekranlarını birden yükseltir (Personel, Borçlar, No-show, Şube/Alan/QR).
  (b) **Vardiya/Mesai** (`TimeEntries`): 900px yatay-kaydırmalı tablo → mobilde
  **native gruplu vardiya kartı** (prompt anatomisi: gün+tarih · durum rozeti ·
  Giriş/Çıkış/Mola/Çalışılan inset grid · geç/erken/FM etiketleri · Düzelt/
  Onayla); masaüstünde tam tablo korunur (`hidden lg:block`). Veri/iş mantığı
  DEĞİŞMEDİ. Personel + Mesai 390px browser-QA. ✅
- 2026-07-28 — **İterasyon 3 (kısmi)**: (a) **PIN giriş ekranı animasyonları**
  (`TerminalOperatorGate`): gate giriş (`animate-gate-in`), PIN noktası dolunca
  `animate-pop`, yanlış PIN'de `animate-shake`, native tuş takımı (h-14 yuvarlak,
  `active:scale-90` basış). Yeni util'ler app.css: gate-in/sheet-up/pop/shake/rise
  (reduced-motion'da durur). (b) **BUG FIX (kullanıcı bildirdi)**: görev atama
  personel listesi boştu — `User.name` gerçek kolon, `get([...])` kolon kısıtında
  'name' yoktu → null. 3 yerde düzeltildi (StaffTaskAdmin/StationController/
  CommissionService) + first/last yedeği. Görev-atama dropdown 6 personel doğrulandı.
- 2026-07-28 — **İterasyon 3 (devam)**: **Personel filtreleri native** — 4
  yığılmış select → mobilde arama + **durum chip'leri** (Tüm/Aktif/Pasif) +
  **"Filtrele" BottomSheet** (şube/rol/durum + Temizle/Uygula, aktif-sayı rozeti);
  masaüstü toolbar `hidden md:block` ile korundu. 390px'te chip + sheet
  (sürükleme tutamaçlı) doğrulandı. Personel ekranı artık uçtan uca native
  (gruplu liste + chip + sheet).
- 2026-07-28 — **Mutfak KDS profesyonelleştirme** (kullanıcı: gridler dengesiz,
  reçete kötü yerde, kabul alanları yamuk): (a) kart ızgarası **masonry (çoklu-
  sütun) → dengeli eşit-sütun grid** (auto-fill minmax, soldan-sağa nizami; 390
  tek sütun, 768 iki eşit sütun doğrulandı). (b) **Reçete inline aç-kapa →
  odaklı MODAL** (ürün+alerjen+reçete metni, temiz). (c) alerjen/diyet/reçete
  alt-meta satırı sadeleşti; Kabul/adım butonu orantılı. (d) **Terminal personel
  barı yeniden**: mesai **ilerleme çubuğu** + kompakt 3'lü performans (Adisyon/
  Ürün/İptal) + mola bilgisi — profesyonel, az yer. (e) **BUG: terminal PIN
  gate mobilde sığmıyordu** → gate scrollable + mobilde tek-seferde-tek-panel
  (liste → seç → PIN pad tam ekrana sığar) + geri düğmesi. PIN pad native
  (56px yuvarlak tuş, pop/shake). Kitchen 390/768 QA; gate mobil fix terminal
  cihazında görünür (build+typecheck geçti).
- 2026-07-28 — **Mutfak KDS kartı BAŞTAN yeniden** (kullanıcı: önceki berbat,
  hepsi aynı, alerjen/reçete/buton/boyut saçma): (a) **aciliyet-renkli başlık**
  (fresh nötr / warn amber / late kırmızı) + renkli kart kenarı + "GECİKTİ"
  şeridi → kartlar bakışta ayrışır ("hepsi aynı" bitti). (b) **adet kare rozeti**
  solda. (c) **alerjen TEK kompakt kırmızı satır** (dağınık çip seli yok).
  (d) reçete → sessiz metin link + modal. (e) yemek fotoğrafı karttan kaldırıldı
  (metin-öncelikli profesyonel fiş; foto reçete modalinde). (f) Kabul/adım butonu
  tutarlı genişlik; hazır = yeşil "Hazır" çipi; footer "Tümünü hazırla". 390 tek
  sütun + 768 iki-eşit-sütun QA. Barista aynı bileşen → otomatik düzeldi.
- 2026-07-28 — **Bildirim + masa + ödeme akışı**: (a) Toast baloncuk —
  `useNotifications` yeni okunmamışta görünür tıklanabilir toast (canlı doğrulandı);
  ToastHost ikon+URL. (b) Masa bug'ı — ödeme sonrası `TableStatusSynchronizer`
  Cleaning yerine Available → masa otomatik boşalır (repair çalıştırıldı). (c)
  Ödeme rol akışı (onaylı): garson "Ödemeye gönder" (pay ucu payments.take ister),
  kasa "Tekrar siparişe gönder" (yeni send-to-service, bill_requested→served) +
  "Borca yaz" (kasiyere receivables.transfer) + "Ödeme al". (d) Ürün ekleme
  onay+adet modalı (basit ürün direkt eklenmez; canlı doğrulandı). (e) Mutfak:
  yeni-sipariş şeridi + oto-fiş etiketli anahtar.
- 2026-07-28 — **5-ajan denetim + onaylı 3-faz düzeltme**:
  · **Faz A (bildirim erişimi)**: Board yeni-servis-çağrısı toast+ses; Runner
    (Komi) gate+heartbeat; ServiceCall→KASA (verified); 3 yeni tip
    (awaiting_payment/debt_transferred/order_needs_approval) + emitter+hook'lar
    (requestBill/approve/markDebtTransferred/public-create); QR onay-öncesi
    mutfak bildirimi engellendi (feed zaten güvenli).
  · **Faz B (ödeme/masa doğruluğu)**: pending_approval'da ödeme butonu gizlendi
    (payReady); **parseMoney/parseAmountMinor TR binlik-nokta** düzeltildi
    (1.234→1234 TL, eksik-tahsilat bug'ı; node ile doğrulandı); pay çift-tık
    kilidi await öncesine + promptPin resolver yetim-bırakmama; void×masa-
    oto-boşaltma yarış guard'ı (applyPaidDelta).
  · **Faz C (sağlamlaştırma)**: operatör bar giriş-sonrası stats watch; ürün
    modalı min/max adet + zorunlu opsiyon + max_select; changeQty/removeItem/
    saveNote expected_version; idempotency-key niyet-başı; terminal nav denylist
    Menü/Rezervasyon/Stok/Borçlar kapatıldı; low_stock+yeni tipler sesli+toast;
    KDS vurgu-timer iptali + Kabul 44px; operatör bar safe-area + z-index.
  · **Kalanların tamamı (2. tur)**: SUNUCU terminal-kilidi sızıntısı kapatıldı
    (EnsureTerminalLocked'a panel/menu+api/catalog, rezervasyonlar+reservations,
    stok+inventory eklendi; borclar/receivables BİLİNÇLİ dışarıda — kasa cari
    tahsilatı; normal kullanıcı etkilenmedi, canlı doğrulandı); Runner `delivered()`
    hata-yutma bug'ı (runAction→boolean, yalnız başarıda "son götürülenler"e ekler);
    Kitchen ölü importlar (BaseBadge/waitChipClass); Kitchen fullscreen-ikon
    fullscreenchange senkronu; Runner vurgu-timer iptali; gate body-scroll-lock;
    Dashboard büyük-ciro responsive wrap (3xl→4xl). Typecheck temiz, build 0
    root-owned. Kalan gerçekten-minör (KdsItemImage computed, StationManager iç
    modal dokunma, heartbeat-hidden, clearActiveOperator toast) ihmal edilebilir.
- 2026-07-28 — **Patron Paneli (ayrı boss sistemi) + servis-çağrı paketi + testler**:
  · **Patron Paneli**: yeni `BossLayout` (operasyon panelinden AYRI executive kabuk,
    marka-gradyanlı üst bar, "Panele dön"); Boss/Index premium hero + KPI + grafikler
    ("Yönetim Kokpiti" operasyon sidebar'ından KALDIRILDI; giriş kullanıcı menüsünden
    "Patron Paneli"). 1440 + 390 QA. Yetki `boss.view` korunur.
  · **Servis-çağrı eklentisi**: zaten feature-flag ile aç/kapa (`service_calls`,
    Settings/Features). Sürüm **0.19.0**'a bump (changelog.php, doğru notlar).
  · **Testler**: tam suite **605 passed** (2987 assertion). Yeni davranışa göre 2 test
    güncellendi (ServiceCall→kasa artık 1; masa ödeme sonrası 'available'). 7 geçici
    hata yalnız test-storage kök-sahiplik artefaktıydı (chown ile giderildi, kod
    regresyonu YOK).
- 2026-07-28 — **Patron Paneli AYRI SİSTEM + zenginleştirme + sürüm bildirimi +
  Faz 5 başlangıç**:
  · Patron subdomain kod altyapısı (`config/boss.php`, `BossHost`, `Route::domain
    (patron.*)` → Patron Paneli kökte; kalıcı oturum; route kayıtlı doğrulandı).
    Kalan: cPanel subdomain + SSL (infra).
  · Patron paneli zenginleştirme (agent): `on_shift` ("şu an mesaide" — canlı
    doğrulandı: Ayşe Yıldız · Garson · 82sa) + `upcoming_today` ("bugün gelecekler")
    BossService + Boss/Index 2 yeni kart.
  · **Sürüm güncelleme bildirimi** (agent): `GET /api/v1/app-version` + `useVersionWatch`
    (3 dk poll, sürüm değişince kalıcı "Yenile →" toast → reload); panel/portal/
    patron/KDS kabuklarına bağlı. Toast `reload` alanı + AppIcon `refresh-cw`.
  · **Faz 5 (motion başlangıç)**: sayfa-yolu değişince yumuşak beliriş (animate-rise)
    — PanelLayout + PortalLayout main; reduced-motion'da kapalı.
  · Konsolide typecheck+build temiz, 0 root-owned; iki agent + Faz 5 birlikte doğrulandı.
- 2026-07-28 — **Patron subdomain CANLI + QR menü koyu mod**:
  · **patron.bogahostdeveloper.com.tr KURULDU** (personel.* deseni): DNS A kaydı
    (whmapi1) + `serveralias.conf` (std+ssl) + rebuild/restart. Origin doğrulandı:
    `/` → 302 `/giris` (Patron Paneli host'u). SSL AutoSSL ile ekleniyor (patron
    SAN). Genel DNS propagasyonu birkaç dk/saat. Not: [[qrmenu-patron-subdomain]].
  · **Public QR menü KOYU MOD** (kullanıcı seçimi): menu.css'e manuel
    `data-theme` override (cihaz tercihi varsayılan, elle geçersiz kılınır,
    localStorage kalıcı, flash'sız head-init), header'a tema düğmesi (ay/güneş),
    yumuşak geçiş. Canlı doğrulandı (toggle → data-theme=dark, body koyu, kalıcı).
- 2026-07-28 — **İşletme Vitrini + Patron vardiya/görev (v0.20.0)**:
  · **İşletme Vitrini** (public QR menü): `branches.showcase` JSON kolonu +
    Branch cast + BranchController doğrulama + PublicMenuController `buildBranchInfo`
    (açık/kapalı SUNUCUDA hesaplanır, adresten harita, sosyal handle→URL) +
    menu.blade zengin kart (WiFi kopyala, haftalık saatler+rozet, harita, sosyal)
    + Branches.vue form editörü. Reflection + blade-render ile doğrulandı.
  · **Patron Paneli** artık sekmeli (Özet·Vardiya·Görevler): BossLayout nav +
    routes/boss.php (her iki host) + `Boss/Shifts.vue` (haftalık vardiya
    ekle/düzenle/sil → mevcut shifts uçları, staff.manage) + `Boss/Tasks.vue`
    (görev ata/izle → mevcut tasks uçları, tasks.assign).
  · Sürüm 0.19→0.20 bump → tüm oturumlara "yenile" bildirimi.
- 2026-07-28 — **Faz 5 (stagger/press) + Patron nav redesign + patron SSL**:
  · **Faz 5**: `.stagger-in` (liste cascade, ilk ~10 kademeli, reduced-motion'da
    kapalı) → MobileListGroup + DataTable kart modu → TÜM liste ekranları; ListRow
    `.press-row` dokunsal geri bildirim. Boss listeleri de cascade.
  · **Patron nav** (kullanıcı isteği "daha iyi konumlandır + görsel/ikon"):
    BossLayout'ta düz sekme → premium **segmented pill** kontrol (rounded track,
    aktif=beyaz pill + marka ikon çipi + shadow, flex-1 eşit genişlik). Playwright
    ile canlı doğrulandı (Vardiya + Görevler).
  · **Patron SSL ÇÖZÜLDÜ**: acme RSA cert 3 SAN (qrmenu+personel+patron) →
    apache_tls store'a doğrudan deploy (uapi/hook bozuk) → patron.* HTTPS geçerli,
    personel bozulmadı. Yöntem: [[qrmenu-patron-subdomain]].
- 2026-07-29 — **v0.21.0: menü çoklu dil + patron operasyon metrikleri +
  QR menü mavi tema + sipariş-eklenti doğrulama**:
  · **EN/DE**: lang/{en,de}/menu.php tam çeviri (90 anahtar, İşletme Vitrini dahil).
  · **Patron operasyon metrikleri**: BossService `operationsSection` (misafir/kişi
    başı ciro, ort. servis süresi, masa devir, QR self-servis payı, iptal oranı,
    yoğun saat, en iyi gün) + Index.vue kart bölümü. Playwright DOM doğrulandı.
  · **QR menü turuncu→MAVİ**: menu.css `--brand-*` app.css mavi ölçeğiyle eşitlendi
    (panel/menü tutarlılığı); ?v=20260729.1, canlı doğrulandı (#2563eb/#1d4ed8).
  · **"Sadece menü" modu ZATEN VAR**: Ayarlar→Eklentiler "QR menüden sipariş" +
    "Garson/su/hesap çağır" toggle'ları. Uçtan uca kurulu: FeatureCatalog +
    PublicMenuBranding composer (token→tenant→feature→blade m-no-order/@if) +
    backend guard (PublicOrderController:82, ServiceRequestController:76). Kod
    gerekmedi; controller'a eklediğim gereksiz wiring geri alındı.
  · **#147/#157**: tüm operasyon ekranlarında state/loading/filtre zaten kapsamlı
    (Reservations/Inventory/Reports-tabs doğrulandı); Faz5 cila (stagger+press)
    DataTable/MobileListGroup/ListRow'a uygulandı. KDS canlı-pano → stagger HARİÇ
    (poll'de replay olmasın).
- 2026-07-29 — **QR menü tema tam nötrleme**: menu.css `--m-*` yüzey/metin/kenar
  tokenleri app.css SLATE paletiyle eşitlendi (açık #f6f8fb/#e5eaf1/#0f172a/#475569,
  koyu #0b1120/#0f1729/#26314a/#f1f5f9/#c2cbda). Sıcak-kahve ton tamamen kalktı;
  menü artık panelle birebir (mavi accent + serin nötr). ?v=20260729.2, canlı OK.
- 2026-07-29 — **v0.22.0 Patron paneli yeni grafikler**: BossService'e
  `by_weekday` (tz-doğru by_day'den türetilir, ek sorgu yok) + `top_categories`
  (SalesReportService::categories). Index.vue: günlük seyir + saatlik AYRI kartlar
  (eskiden biri-veya-diğeri), "Haftanın günleri" ChartColumn (çok-günlük aralıkta),
  "Kategori satışları" normalize bar listesi. Canlı DOM doğrulandı, SQL hatasız.
  · Ek: `channel_mix` (sales->channels, donut), `top_tables` (sales->tables, bar),
    `discounts` (orders discount_minor+comp_total_minor). Index'e Sipariş kanalı
    donut + Masa bazlı ciro bar + Operasyon grid'ine İndirim/İkram kartları.
    Canlı DOM doğrulandı. Patron özeti artık: hero+4 KPI+9 operasyon metriği+
    5 grafik türü (günlük/saatlik/haftalık/kategori/masa)+3 donut(ödeme/servis/kanal)
    +en çok satanlar+personel+canlı mesai+stok/teslimat.
