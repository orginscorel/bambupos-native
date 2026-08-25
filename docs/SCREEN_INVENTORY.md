# SCREEN_INVENTORY — Ekran / Rota / Rol Envanteri (Faz 0)

106 Vue dosyası; aşağıda ANA ekranlar (rota + birincil rol + öncelik).
Öncelik: P0 (operasyon-kritik) · P1 · P2. Durum: `pending` (hepsi).

## Panel — Operasyon (P0)
| Ekran | Rota | Rol | Öncelik |
|---|---|---|---|
| Dashboard | `/panel` | Yönetici/tüm | P0 |
| Yönetim Kokpiti (BOSS) | `/panel/boss` | Sahip/Müdür/Şube Müd. | P1 |
| Siparişler + Masa panosu | `/panel/siparisler` | Garson | P0 |
| Sipariş detay/adisyon | `/panel/siparisler/{id}` (Detail) | Garson | P0 |
| Kasa | `/panel/kasa` (Cashier) | Kasiyer | P0 |
| Kasa çekmecesi | CashDesk | Kasiyer | P1 |
| Z Raporu | ZReport | Kasiyer/Yön. | P1 |
| Ödeme fişi | PaymentReceipt | Kasiyer | P2 |
| Mutfak KDS | `/panel/mutfak` (Kitchen) | Mutfak | P0 |
| Barista KDS | `/panel/barista` | Barista | P0 |
| Komi | `/panel/komi` (Runner) | Komi | P0 |
| İstasyon yönetimi | StationManager | Yönetici | P2 |
| Teslimat panosu | `/panel/teslimat` | Yön./Kurye | P1 |

## Panel — Menü & Katalog (P1)
Menü kategorileri, ürünler (Index/Edit), varyant/opsiyon (Options), menüler,
alerjenler — `/panel/menu*`. Rol: Yönetici/Şube Müd.

## Panel — Rezervasyon (P1)
Genel bakış, takvim (Index), bekleme listesi (Waitlist), no-show raporu,
rezervasyon çekmecesi — `/panel/rezervasyonlar*`.

## Panel — Stok & Finans (P1)
Depo/Stok: Overview, Items, Recipes, Movements, Counts, Purchasing, Suppliers,
Alerts, Reports — `/panel/stok*` (Depo Sorumlusu/Yön.). Borçlar/Cari
`/panel/borclar`. Prim/Komisyon `/panel/prim`. Raporlar `/panel/raporlar`
(9 sekme: Overview/Sales/Finance/Profit/Ops/Staff/Eod/Reconciliation/Exports).

## Panel — Personel & Yönetim (P1/P2)
Personel + roller `/panel/personel*`, Görevler `/panel/gorevler`, Vardiya
(Overview/Clock/Approvals/Leaves/Performance) `/panel/vardiya*`, Şubeler
`/panel/subeler`.

## Panel — Cihazlar & Entegrasyon & Sistem (P2)
Kiosk `/panel/kiosklar`, Terminaller `/panel/terminaller`, Entegrasyonlar
`/panel/entegrasyonlar`, Ayarlar (Mail/Branding/Features) `/panel/ayarlar/*`,
Nasıl Çalışır (Wiki), Sürüm Notları (Changelog).

## Müşteri (public) — P0
| QR Menü | `/m/{token}` (Blade + menu.js) | Müşteri | P0 |
| Kiosk self-servis | Kiosk (public assets) | Müşteri | P1 |
| Giriş/PIN/Parola-sıfırla | `/giris`, `/giris/pin`, `/parola-sifirla` | — | P1 |

## Personel Portalı (personel.* subdomain) — P0/P1
Panelim (Dashboard), Mesaim (Shift), Görevlerim (Tasks), Takvim (Schedule),
Raporlarım (Reports), Profilim (Profile), Teslimatlarım (Deliveries).
Rol: tüm personel (kişisel). Zaten `.portal-root` özel kimlikli — MAVİ eksene
taşınacak.

## Pazarlama sitesi — P1 (Faz 4)
Ana sayfa `/` (home). Hedef: ürün-odaklı çok bölümlü site + ürün sayfaları
(Restoran/Kafe/QR menü/Kiosk/Personel/Rapor) + Referanslarımız + Fiyatlandırma
+ Demo CTA. (Şu an minimal.)

## Not
- Sipariş-detay/adisyon (`Orders/Detail.vue`) ve Kasa (`Cashier.vue`) sistemin
  EN kritik iki ekranı — Faz 3'te POS akışının kalbi.
- Masa panosu bugün flat grid; hedef floor-plan (bkz. UI_AUDIT K2).
