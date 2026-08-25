# UI_AUDIT — Mevcut Arayüz Denetimi (Faz 0)

> Salt-okunur denetim. Kod DEĞİŞTİRİLMEDİ. Canlı ekranlar `sahip@demo` ile
> browser automation (Playwright) ile 1440 / 768 / 390 px'de incelendi.
> Tarih: 2026-07-26 · Sürüm: 0.18.0

## 1. Teknoloji yığını (tespit edildi)
- **Backend:** Laravel 13.8, PHP 8.3, çok kiracılı (TenantScope), Inertia 3.
- **Frontend:** Vue 3.5 + TypeScript 5.6 + Inertia Vue 2 + **Tailwind 4** + Vite 8.
- **Ölçek:** 428 rota, 106 Vue sayfası/parça, 24 UI bileşeni, `resources/css/app.css` içinde 139 tasarım token'ı, 9 rol.
- Grafikler: harici lib YOK — hepsi elle SVG (ChartLine/Column/StackedBar).

## 2. En kritik bulgular (öncelik sırası)

### K1 — Marka rengi TURUNCU, hedef MAVİ ⛔
Tüm panel turuncu markalı (logo, aktif menü, "Aç" butonu, sürüm rozeti, banner).
Yeni yön **mavi**; turuncu birincil olmayacak. Bu, en yüksek görünür etkiye
sahip değişiklik. `app.css` katman-1 (`--brand-*`) + `.portal-root` paleti
mavi eksene taşınmalı; durum renkleri semantik kalmalı.
- Kanıt: Panel/Siparişler ekran görüntüleri — turuncu logo + aktif "Panel" + "Aç".

### K2 — Masa planı "operasyonel floor-plan" değil, düz kart ızgarası ⛔
Siparişler → Masalar bölümü basit dikdörtgen kartlar (Dolu/Boş rozeti + "+"),
katlara/bölümlere göre gerçek yerleşim, sürükle-bırak, zoom/pan, masa
şekli/kapasitesi, canlı süre halkası YOK. Prompt vizyonu (kroki, taşıma/
birleştirme, yoğunluk görünümü) ile arada büyük fark.
- Kanıt: `Panel/Orders/Board.vue` — flat grid; masa=kart.

### K3 — Dashboard "yan yana kart" admin şablonu hissi
İşleyen KPI'lar + gerçek veri + boş durumlar var (iyi), ama düzen genel admin
kart ızgarası. Prompt: operasyon özeti, canlı satış akışı, darboğaz, aksiyon
listesi, "önceki güne göre / hedefe kalan / en yoğun saat" bağlamı. Şu an
bağlam çoğunlukla yok, sayı+etiket düzeyinde.

### K4 — "Bildirimleri açın" turuncu banner HER panel sayfasının tepesinde
Değerli dikey alanı her sayfada tüketiyor; kalıcı, dikkat dağıtıcı. Zil
menüsüne taşınmalı ya da tek seferlik/daha ince olmalı.

### K5 — Yönetim ekranlarında "Şube: Tümü" görünüyor
Siparişler filtresinde "Şube: Tümü" var. Kullanıcı isteği: yönetici genel
değil SEÇİLİ şubeyi görsün. Şube seçici modeli netleştirilmeli (nav'daki
şube-seçici ile tutarlı).

## 3. Güçlü yanlar (korunacak temeller)
- **Gruplu sidebar** (Operasyon / Menü & Rezervasyon / Stok & Finans / Personel
  & Yönetim / Cihazlar & Entegrasyonlar / Sistem) — mantıklı, başlıklı.
- **Mobil alt-nav** (Panel/Siparişler/Masalar/Kasa/Tümü) — sağlam native temel.
- **Semantik durum renkleri** (Dolu=kırmızı, Boş=yeşil; gecikme vurgusu).
- **Gerçek bileşen kütüphanesi** (24): BaseButton/Input/Select/Modal/Drawer/
  Tabs/Badge/Switch/DataTable/EmptyState/Skeleton/Toast/Pagination/FormField…
- **Token altyapısı** mevcut (139 değişken, açık/koyu tema, `@theme inline`).
- **Gerçek veri + boş/iskelet durumları** var (uydurma değil).
- **Koyu/açık tema** çalışıyor.

## 4. Tekrarlanan/tutarsızlık kalıpları
- İki paralel token seti: panel (`--ui-*`/`--color-*`, turuncu) + portal
  (`.portal-root --p-*`, ayrı palet). Tek kaynak "brand=mavi" ekseninde
  birleştirilmeli; portal kendi vurgu setini bu eksenden türetmeli.
- İkon glifleri elle AppIcon'da; tutarlı tek aile (iyi) ama bazı domain
  ikonları (masa/adisyon/kurye/istasyon) genel.
- Radius/gölge çoğunlukla tutarlı; ama kart-içi gereksiz gölge yerine ton/
  spacing tercih edilmeli (prompt kuralı).

## 5. Responsive ilk gözlem
- 1440: ferah, kart ızgarası dengeli.
- 390: 2-sütun kart yığını + alt-nav; kullanılabilir ama kartlar boşlukça
  yüksek, "büyük başlık altında küçük web kartı" riskine yakın (native-app
  hissi tam değil).
- 768 (tablet POS) ayrıca ele alınmalı — şu an masaüstünün küçültülmüşü.

## 6. AI-slop / hazır-template riskleri (giderilecek)
- Turuncu birincil + genel kart ızgarası → "hazır admin panel" algısı.
- Dashboard kartları homojen; domain'e özgü operasyonel bileşen az.
- Masa "kroki" yerine kutu; POS ürün grid'i domain-zengin değil (görülecek).

Ayrıntılı ekran-ekran görsel eleştiri: `VISUAL_QA.md`.
Hedef sistem: `DESIGN_SYSTEM.md`. Ekran listesi: `SCREEN_INVENTORY.md`.
