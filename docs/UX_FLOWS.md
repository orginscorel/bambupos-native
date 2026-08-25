# UX_FLOWS — Roller ve En Sık Akışlar (Faz 0)

Deneyimler AYRIŞTIRILDI: POS (garson/kasiyer) · yönetici · mutfak · müşteri ·
personel. Her rol için "en sık yapılan işlem" en az dokunuşla tamamlanmalı.

## Roller ve birincil işleri
| Rol | Cihaz | En sık işlem |
|---|---|---|
| **Garson** | Terminal / tablet | Masa aç → ürün ekle → gönder; servis çağrısına bak |
| **Kasiyer** | Kasa terminali | Hesabı al → düzelt/ikram → öde → adisyon kapat |
| **Mutfak** | Mutfak KDS (kilitli) | Yeni fişi gör → hazırla → hazır işaretle |
| **Barista** | Barista KDS | Aynı akış (kendi istasyonu) |
| **Komi** | Komi ekranı / portal | Hazır ürünü al → masaya götür → servis |
| **Kurye** | Portal (telefon) | Teslimatı al → yolda → teslim |
| **Şube Müdürü** | Panel / BOSS | Ciro/darboğaz/stok/personel izleme, karar |
| **Sahip/Müdür** | Panel / BOSS | Şube kıyas, raporlar, ayar, entegrasyon |
| **Depo Sorumlusu** | Panel | Mal kabul, sayım, kritik stok |
| **Müşteri** | QR menü / kiosk | Menüye bak → sepet → sipariş / garson çağır / hesap |

## Kritik akış 1 — Masada sipariş (POS)
1. Sipariş-giriş terminalinde **Aktif Personel** (PIN) seçilir *(kuruluyor)*.
2. Masa panosundan boş masa → **adisyon aç** (şube SORMAZ).
3. Kategori → ürün grid → ekstralar/malzeme çıkar (bottom sheet) → adet.
4. **Gönder** → kahve Barista'ya, yemek Mutfak'a düşer; sipariş açan kişiye atfedilir.
- Hız kritik: en fazla dokunuş = kategori→ürün→gönder.

## Kritik akış 2 — Hazırlık → teslim (KDS)
Mutfak/Barista: yeni→hazırlanıyor→hazır. Komi: hazır listesini görür (ses+push),
alır, masaya götürür, "servis edildi". Her adım `order_events`'e (kim/ne zaman).
Geciken kalem renk + ikon + süre ile işaretlenir.

## Kritik akış 3 — Ödeme & kapanış
Kasiyer hesabı açar → kalemleri görür (adet/yanlış/ikram düzelt) → KDV görünür →
öder → **adisyon otomatik kapanır**. (Hedef: POS cihazına tutar gönderme +
ödeme sonrası otomatik kapanış — entegrasyon çerçevesiyle.)

## Kritik akış 4 — Paket/kurye
Sipariş servis-tipi=Paket + adres → Teslimat panosu → kurye ata (bildirim) →
kurye portaldan yolda/teslim. BOSS'ta özet.

## Kritik akış 5 — Yönetici günü (BOSS)
Aç → bugünkü ciro + düne kıyas → darboğaz (mutfak/geciken) → kritik stok →
personel/prim → aksiyon. "Ne oldu / neden / şimdi ne yapmalı".

## Kritik akış 6 — Müşteri (QR menü)
QR okut → kategori/arama → ürün detay (bottom sheet: ekstra/malzeme/alerjen/
besin) → sepet → sipariş (garson onayına düşer) / garson çağır / hesap iste.
Tek elle, iştah açıcı, hızlı; e-ticaret sitesi hissi VERMEZ.

## Cihaz–kimlik matrisi (netleştirildi)
- **Terminal** = cihaz kimliği (token) + şube/istasyon sabit; kişi **PIN** ile
  "Aktif Personel". Yönetim ekranları kapalı, izinli operasyona açık.
- **Personel portalı** = kişisel giriş (parola), kalıcı oturum, kişisel işler.
- **Panel** = kişisel giriş, tam yetki (yönetici).
