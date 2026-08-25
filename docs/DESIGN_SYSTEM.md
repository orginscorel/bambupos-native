# DESIGN_SYSTEM — Hedef Tasarım Sistemi (Faz 1 planı)

> Amaç: hazır-admin görünümünden çıkıp, kendine özgü kimlikli, kurumsal SaaS
> kalitesinde, native-app'e hazır bir ürün. Marka ekseni **MAVİ**. Turuncu
> BİRİNCİL değildir (yalnız gerekirse ikincil/uyarı vurgusunda).
> Uygulama mekanizması: Tailwind 4 `@theme` + CSS custom properties (token).
> Renkler component içine sabit yazılmaz.

## 1. Renk sistemi (semantik token — TEK KAYNAK)
CSS değişkenleri (`resources/css/app.css`), açık+koyu tema. Marka mavi; sipariş/
masa/stok/ödeme durumları renk TAŞIR (dekorasyon değil, anlam).

| Token | Rol | Açık (öneri) | Koyu (öneri) |
|---|---|---|---|
| `--brand` | Marka/etkileşim | #2563EB (blue-600) | #3B82F6 |
| `--brand-strong` | hover/active | #1D4ED8 | #60A5FA |
| `--background` | sayfa zemini | #F6F8FB | #0B1020 |
| `--surface` | kart/panel | #FFFFFF | #131A2A |
| `--elevated-surface` | modal/dropdown | #FFFFFF | #1B2436 |
| `--text-primary` | ana metin | #0F172A | #F1F5F9 |
| `--text-secondary` | ikincil | #475569 | #C2CBDA |
| `--text-muted` | üçüncül | #64748B | #8A97AC |
| `--border` | kenarlık | #E5EAF1 | #263145 |
| `--success` | onay/ödeme | #16A34A | #4ADE80 |
| `--warning` | uyarı | #D97706 | #FBBF24 |
| `--danger` | hata/iptal | #DC2626 | #F87171 |
| `--info` | bilgi | #0EA5E9 | #38BDF8 |
| `--order-new` | yeni sipariş | #2563EB | #3B82F6 |
| `--order-preparing` | hazırlanıyor | #D97706 | #FBBF24 |
| `--order-ready` | hazır | #16A34A | #4ADE80 |
| `--order-served` | serviste/tamam | #64748B | #94A3B8 |
| `--table-empty` | boş masa | #16A34A | #4ADE80 |
| `--table-occupied` | dolu masa | #DC2626 | #F87171 |
| `--table-delayed` | gecikmiş masa | #B91C1C + puls | #FCA5A5 |
| `--stock-critical` | kritik stok | #DC2626 | #F87171 |

Kural: durum yalnız renkle değil **ikon + metin** ile de anlatılır (a11y).
Kontrast ≥ AA. Panel + Portal ikisi de bu eksenden türetilir (iki kopuk palet
YOK — portalın `--p-*`'i `--brand` üzerinden hesaplanır).

## 2. Tipografi
- Değişken font, tam Türkçe desteği (öneri: **Inter** veya **Manrope** —
  self-host, no CDN). Poppins yerine daha nötr/kurumsal + `tabular-nums`.
- Hiyerarşi: `display` (KPI/ciro), `heading`, `body`, `label`, `caption`,
  `numeric`. Ciro/fiyat/adet → **tabular numbers**.
- Dashboard metriklerinde SAYI, başlıktan baskın (değer > etiket).
- Aynı ekranda 2-3 ağırlık (400/600/700) yeter.

## 3. Spacing & grid
- **4/8 px** tabanlı ölçek (4,8,12,16,24,32,48).
- Tutarlı container genişlikleri; masaüstünde veri yoğunluğu KONTROLLÜ.
- Tablet (POS) landscape ayrı düzen; mobilde başparmak erişimi.

## 4. Radius (sınırlı, semantik)
`--r-input:8px` · `--r-button:8px` · `--r-card:14px` · `--r-modal:18px` ·
`--r-sheet:20px` · `--r-pill:9999px` · `--r-device:28px`. Her şey kapsül DEĞİL.

## 5. Gölge & derinlik
Derinlik yalnız: modal, dropdown, floating action, sürüklenen masa, device
mockup, önemli popover. Normal kartlar: **border + ton + spacing** ile ayrım
(gölge değil). Gölge ölçekleri: `--shadow-pop`, `--shadow-modal`, `--shadow-drag`.

## 6. İkonlar
Tek aile (mevcut AppIcon stroke seti genişletilir). Aynı işlem → aynı ikon her
yerde. Domain ikonları (masa, adisyon, istasyon, kurye, ocak, KDS) için özel SVG.

## 7. Motion
Mikro etkileşim 160–240 ms; `prefers-reduced-motion` desteği. İzinli: sayfa
reveal, sidebar/tab geçişi, modal/sheet, listeye sipariş ekleme, durum değişimi,
sayı sayaç (count-up), grafik açılışı, drag-drop, bildirim, sepet, ödeme başarı,
skeleton, success feedback. Sürekli/loop/bounce/gradient-animasyon YOK.

## 8. Bileşen envanteri (mevcut → hedef)
Mevcut 24 UI bileşeni korunur, MAVİ token'a taşınır + eksikler eklenir:
- Var: Button, Input, Select, Checkbox, RadioGroup, Switch, Tabs, Badge,
  Card, Modal, Drawer, Dropdown, DataTable, Pagination, EmptyState, Skeleton,
  Toast, FormField, SearchInput, Tooltip(?).
- Eklenecek: **Tooltip** (yoksa), **BottomSheet** (mobil/tablet), **Command
  Palette** (⌘K), **StatCard/MetricTile** (bağlamlı KPI), **StatusPill**
  (order/table/stock), **SegmentedControl**, **NumberStepper** (POS adet),
  **FloorPlanCanvas** (masa krokisi), **KdsTicket** (var, elden geçer),
  **DeviceFrame** (pazarlama mockup), **DateRangePicker** (rapor).

## 9. Uygulama kabuğu (shell)
- Masaüstü: daraltılabilir sidebar (var) + marka/şube seçici + **⌘K command
  palette** + hızlı işlem + bildirim merkezi + profil + **aktif vardiya** +
  bağlantı/sync durumu.
- Tablet: POS/adisyon için özel landscape (masaüstünün küçültülmüşü DEĞİL).
- Mobil: alt-nav (var) + safe-area + bottom sheet + swipe + hızlı sipariş +
  offline/sync durumu. Native navigation modeline hazır.

## 10. Uygulama sırası (özet — ayrıntı FRONTEND_PROGRESS.md)
Faz1 tokens+bileşen → Faz2 shell → Faz3 ekranlar (Dashboard, POS/adisyon, masa
planı, mutfak, QR menü, personel mobil, raporlar, stok, paket, şube) → Faz4
pazarlama → Faz5 motion/polish → Faz6 native hazırlık.
