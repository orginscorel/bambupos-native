# VISUAL_QA — Canlı Ekran İncelemesi (Faz 0)

> Yöntem: Playwright ile CANLI panel (`sahip@demo`) 1440 / 390 px'de açıldı,
> ekran görüntüsü alındı, kod DEĞİL görüntü üzerinden eleştirildi. (Faz 3+'ta
> her ekran için 1440/768/390 tekrarlanacak.)
> Puanlama 10 üzerinden; ≥8.5 olmayan "tamamlanmadı".

## Ekran 1 — Dashboard (`/panel`) · 1440 & 390
**Görülen:** koyu tema; gruplu sidebar; KPI kartları (bugünkü ciro/tahsilat/açık
masa tutarı/sipariş, ort. sepet, masa doluluğu); açık adisyon sayaçları; servis
çağrıları; son-14-gün ciro (boş); ödeme dağılımı (boş); kasa durumu; iptal/
indirim/ikram. Üstte turuncu "Bildirimleri açın" banner.
**Eleştiri (acımasız):**
- Marka **turuncu** → kurumsal-mavi olmalı (K1). En göze batan sorun.
- Düzen genel "admin kart ızgarası"; domain'e özgü operasyonel bileşen az.
- Boş grafikler yer tutuyor ama bağlam yok ("düne göre %", "en yoğun saat",
  "hedefe kalan" YOK).
- Turuncu banner her sayfada dikey alan yiyor.
- Sayı hiyerarşisi iyi ama kartlar homojen, hatırlanır değil.
**Puan:** Design 6 · Originality 4.5 · Craft 6.5 · Functionality 7 · DomainFit 6
· Responsive 6.5 → **Ort. ~6.1** (yetersiz; yeniden tasarlanacak).
- Mobil (390): 2-sütun kart yığını + alt-nav (Panel/Siparişler/Masalar/Kasa/
  Tümü) — kullanılabilir ama "büyük başlık altında küçük web kartı" riski;
  native-app hissi tam değil.

## Ekran 2 — Siparişler / Masa panosu (`/panel/siparisler`) · 1440
**Görülen:** filtre çubuğu (Şube/Alan/Masa durumu/Ara/Paket-GelAl-Kiosk); masa
kartları — Dolu(kırmızı)/Boş(yeşil) rozet, kişi sayısı, tutar, kalem, servis
çubuğu; boş masada yeşil "+" ve "adisyon aç".
**Eleştiri:**
- Bu sistemin en kritik ekranı ama **düz kart ızgarası** — gerçek floor-plan
  değil (kat/bölüm yerleşimi, sürükle-bırak, masa şekli/kapasite, canlı süre
  halkası, yoğunluk görünümü YOK) (K2).
- "Şube: Tümü" yönetici filtrede görünüyor — seçili-şube modeliyle çelişir (K5).
- Kartlar operasyonel bilgi taşıyor (iyi) ama görsel dil generic; POS hızına
  özgü büyük dokunma hedefleri/kısayollar zayıf.
**Puan:** Design 6 · Originality 4 · Craft 6.5 · Functionality 7 · DomainFit 5.5
· Responsive ? → **Ort. ~5.8** (yetersiz).

## Ekran 3 — Giriş (`/giris`) · 1440
**Görülen:** sade giriş formu. **Eleştiri:** marka anı zayıf, ürün-yüzeyi/
güven göstergesi yok; kurumsal giriş deneyimi (marka + ince ürün görseli)
kurgulanmalı. **Puan:** ~6.

## Genel AI-slop / hazır-template kontrol listesi
- [x] Turuncu birincil + kart ızgarası → hazır-admin algısı (giderilecek).
- [x] Homojen dashboard kartları.
- [ ] Mor gradient / glassmorphism / aşırı blur — YOK (iyi).
- [x] Domain'e özgü kararlar YETERSİZ (masa krokisi, POS ürün grid'i).
- [x] Mobil = masaüstünün küçültülmüşü riskine yakın (native model tam değil).
- [ ] Lorem ipsum / sahte veri — YOK (gerçek demo verisi, iyi).

## Sonuç
Sağlam işlevsel temel + gerçek veri + bileşen kütüphanesi VAR; ama görsel kimlik
(marka mavi), domain-özgü ekranlar (floor-plan, POS, KDS, QR menü) ve native
his eksik. Hiçbir ekran şu an ≥8.5 değil → tümü Faz 1-3'te yeniden ele alınacak.

## Ekran görüntüleri (denetim anı)
`/root/dash-1440.jpeg`, `/root/dash-390.jpeg`, `/root/orders-1440.jpeg`,
`/root/giris-1440.jpeg` (geçici; repo dışı).
