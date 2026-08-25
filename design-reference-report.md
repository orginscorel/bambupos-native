# BamBumPOS — KardoPOS Referans Görsel Analiz Raporu

Referans: **kardopos.com/tr** · Analiz tarihi: 2026-07-31 · Ölçüm aracı: Playwright (gerçek `getComputedStyle` + `getBoundingClientRect` + ekran görüntüsü).
Amaç: KardoPOS'un **görsel geometrisi, sayfa ritmi, bileşen yoğunluğu ve menü mantığını** BamBumPOS markasına (mavi #2563eb, Poppins, slate nötrler) uyarlamak. Kod/metin/marka kopyalanmaz; **geometri yeniden üretilir**.

---

## 0. Teknoloji tespiti
- KardoPOS **Tailwind** ile kurulmuş (utility class'lar: `max-w-7xl`, `py-24`, `bg-slate-900`, `rounded-full`, sistem-sans font yığını).
- Bizim taraf: Laravel Blade + elle yazılmış `site.css` (token'lı). Tailwind'e geçmiyoruz; **aynı ölçüleri kendi token sistemimizde** üretiyoruz.

## 1. Ölçülen değerler (masaüstü 1440×1200)

| Öğe | KardoPOS ölçümü | BamBumPOS hedefi |
|---|---|---|
| İçerik container (baskın) | **1280px** (`max-w-7xl`) | `--container: min(1280px, 100%-48px)` |
| Geniş görsel container | ~1360–1440px | `--container-wide: min(1440px, 100%-40px)` |
| Metin genişliği | 760–896px | `--container-text: 760px` |
| H1 | **48px / lh 1.1 / 800**, genişlik ~592px | clamp(34px, 5vw, 48px), 800 |
| H2 (section başlığı) | **60px / lh 1.0 / 700**, vurgu kelimeler mor-gradient | clamp(30px, 4.5vw, 56px), 800, mavi gradient vurgu |
| Lead metni | 18–20px, ~600px genişlik | 18–20px, max 620px |
| Gövde | 16px, sistem-sans (biz: Poppins) | 16px Poppins |
| Section dikey boşluk | **96–112px** (py-24/py-28), bazı 64px | `--sec: clamp(64px, 8vw, 112px)` |
| Buton (birincil) | h **52–58px**, radius **14px**, padding 14–16/32, 16px | h 54, radius 14 |
| Buton (büyük CTA) | h 68, radius 16, **amber #f59e0b** | ikincil accent olarak amber |
| Kart radius | 16–24px (sektör kartı ~24) | `--radius: 16 / --radius-lg: 24` |
| Sayfa toplam yüksekliği | **10.881px** (çok içerikli) | eşdeğer yoğunluk hedefi |

## 2. Renk paleti (ölçülen)
- **Birincil**: indigo-mor `lab(38 53 -92)` ≈ `#4f46e5`/`#5b3df5` ailesi. → BamBumPOS markası **mavi #2563eb**'te kalır (uygulama paneliyle aynı); KardoPOS'un canlı-indigo enerjisi korunur.
- **Accent**: amber `#f59e0b` (büyük CTA, vurgu). → BamBumPOS'a **amber accent** eklenecek.
- **Koyu bölüm**: `slate-900` ≈ `#0f172a`.
- **Açık bölümler**: beyaz, `#f8fafc`, `#f1f5f9`.
- **Vurgu kelime**: H2 içinde mavi→indigo **gradient text**.

## 3. Header (KRİTİK FARK)
KardoPOS header'ı benim düz tam-genişlik bar'ımdan tamamen farklı:
- **Yüzen "hap" (floating pill) header**: hero üzerinde, kenardan ~16px kopuk, **yuvarlak köşeli** (radius ~999px kapsül), beyaz, yumuşak gölge.
- Scroll'da → **tam-genişlik beyaz sticky bar**'a geçer (hafif border/shadow, backdrop blur).
- Yükseklik ~**64–72px** (iç).
- Yerleşim: **Logo sol** · **merkez nav** (POS Sistemleri, Sipariş Çözümleri, İşletme Çözümleri, Kurumsal, Fiyatlandırma) · **sağ** (🌐 TR, Giriş Yap, Kayıt Ol, **Demo Talep Et** = belirgin indigo pill).
- **Yapılacak**: mevcut düz header'ı at, floating-pill→solid-on-scroll header'ı kur.

## 4. Mega menü
- Header altında geniş panel (~1100–1250px), 3–4 sütun, her sütun başlıklı, her linkte küçük ikon + başlık + tek satır açıklama, sağda öne-çıkan tanıtım kartı.
- Panel köşe radius ~20–28px, yumuşak gölge, az border, yumuşak açılma.

## 5. Hero (ana sayfa)
- Görünür yükseklik ~**847px** (pt-112 / pb-64), beyaz zemin.
- **%45 metin / %55 görsel** iki sütun.
- Metin: eyebrow-hap ("Kardo BOSS Uygulaması" gibi lavanta pill) → **48px H1** (2–3 satır, güçlü) → lead (3 satır) → **tek birincil CTA** (indigo pill) → ince ayraç → **3 satır-içi istatistik** (ikon + büyük sayı + küçük caps label: "11700+ LOKASYON", "%99.9 ÇALIŞMA SÜRESİ", "< 15 dk YANIT SÜRESİ").
- Görsel: yumuşak lavanta panel üzerinde **telefon mockup** (BOSS app dashboard — koyu tema, ciro grafiği, metrik grid).
- Hero altında: **5'li ürün-ailesi sekme şeridi** (küçük ekran görselli thumbnaillar: HEPSİ BİR ARADA POS / BOSS UYGULAMASI [aktif, çerçeveli] / PERSONEL / QR & SİPARİŞ / WEB ÇÖZÜMLERİ).

## 6. Ana sayfa bölüm ritmi (ölçülen sıralama + zemin)
1. Hero (beyaz, 847px) + istatistikler + ürün-ailesi şeridi
2. Ürün/özellik (beyaz, py-112)
3. Açık slate `#F8FAFC` bölüm (py-64)
4. **KOYU `slate-900` bölüm** (py-96, ~1200px) — güçlü ürün demo/operasyon
5. `gray-50` bölüm (py-96)
6–8. Beyaz bölümler (py-64/80)
9. **Gradient kapanış CTA** (py-160, ~940px)
+ Footer öncesi **newsletter bandı** (koyu)
→ Zemin ritmi: beyaz → açık → **koyu** → açık → beyaz → gradient. Arka arkaya aynı beyaz kart YOK.

## 7. Sektör kartları
- **4'lü satır** (2×2 değil — KardoPOS 4-across), her kart:
  - Gerçek mekan **fotoğrafı** zemin (kafe/restoran/market/ofis-fabrika) + **koyu gradient overlay**.
  - Üstte beyaz yuvarlak **ikon-çip**.
  - Altta ortalı **başlık** (bold, ~24px, beyaz) + kısa açıklama.
  - Radius ~24px, gölge, hover'da görsel zoom.
- Altında yuvarlak outline **yardım pill**'i ("Hangisini seçeceğinizden emin değil misiniz? → …").

## 8. Footer
- Koyu navy (`slate-900/950`), toplam ~**700px**.
- Üstünde **newsletter bandı** (başlık+açıklama sol, e-posta input + "Abone Ol" sağ).
- Sol: logo (beyaz) + marka açıklaması + iletişim (e-posta/telefon/2 adres pin'li) + **sosyal ikon çipleri**.
- **5 link kolonu**: POS SİSTEMLERİ · SİPARİŞ ÇÖZÜMLERİ · İŞLETME ÇÖZÜMLERİ · KURUMSAL · YASAL.
- Alt bar: telif sol · **App Store + Google Play** rozetleri sağ.

## 9. Kabul kriteri oranları (talimat §4)
İçerik genişliği ≤%5, section boşluk ≤%10, kart oranı ≤%10, header yüksekliği ≤%10, hero metin/görsel oranı ≤%10, başlık boyutu ≤%10 fark. Grid sütun yapısı aynı/eşdeğer, mobil sıralama aynı.

---

## 10. BamBumPOS uyarlama token seti (üretilecek)
```css
:root{
  --container-wide: min(1440px, 100% - 40px);
  --container: min(1280px, 100% - 48px);
  --container-content: 1180px;
  --container-text: 760px;
  --sec: clamp(64px, 8vw, 112px);       /* section dikey boşluk */
  --radius-sm: 12px; --radius: 16px; --radius-lg: 24px; --radius-xl: 32px;
  --btn-h: 54px; --input-h: 54px;
  --brand: #2563eb; --brand-ink:#1d4ed8; --accent:#f59e0b;
  --ink:#0f172a; --dark:#0f172a; --soft:#f8fafc; --soft-2:#f1f5f9;
  --shadow-soft: 0 20px 60px rgba(15,23,42,.08);
  --shadow-card: 0 12px 32px rgba(15,23,42,.06);
}
```
Font boyutları `clamp()` ile akışkan.

## 11. Uygulama sırası (talimat §29 — takip edilecek)
1. ✅ Görsel analiz + bu rapor.
2. Backend/veri korunur (sadece frontend/tasarım).
3. Token sistemi (`site.css` :root) yeniden yaz.
4. **Header + mega menü** yeniden (floating-pill → solid-on-scroll).
5. **Hero** yeniden (45/55, eyebrow, 48px H1, tek CTA, 3 istatistik, mockup + ürün-ailesi şeridi).
6. Ana sayfa **section ritmi** (koyu bölüm dahil) yeniden.
7. **Sektör kartları** (fotoğraf + overlay + çip).
8. **Footer** (koyu, newsletter, 5 kolon, app rozetleri).
9. Ana sayfayı referansla yan-yana karşılaştır → farkları düzelt.
10. Alt sayfa hero şablonu + çözüm sayfaları (her biri özgün ürün demosu).
11. **Fiyatlandırma** (satış-odaklı, büyük paket kartları).
12. Demo sayfası.
13. Responsive (mobil header 64–72, tam ekran menü, tek sütun hero, accordion footer).
14. Her sayfada ekran görüntüsü karşılaştırması + console/perf testi.

## 12. Bu turda alınan referans ekran görüntüleri
- `kardo-hero.jpeg` — header + hero + ürün-ailesi şeridi
- `kardo-sectors.jpeg` — solid header + SEKTÖRLER bölümü + sektör kartları
- `kardo-footer.jpeg` — newsletter bandı + footer
(1024/768/430/390/375 kırılımları ve fiyatlandırma/QR/personel/blog alt sayfaları ilgili sayfa inşa edilirken o sayfa için ayrıca ölçülüp karşılaştırılacak — talimat §3.)
