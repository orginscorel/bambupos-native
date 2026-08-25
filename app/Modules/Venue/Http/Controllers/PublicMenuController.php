<?php

namespace App\Modules\Venue\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Venue\Services\QrTokenResolution;
use App\Modules\Venue\Services\QrTokenResolver;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Storage;

/**
 * Public QR ucu: `/m/{token}` (ADR-008).
 *
 * - Kiracı/şube/masa YALNIZ opak token'dan çözülür; URL'de veya istekte
 *   başka hiçbir kimlik kabul edilmez → başka masaya erişim imkânsız.
 * - Rotasyonla eskiyen token 410 + açıklama sayfası döner.
 * - Rate limit: IP başına; aşımda 429 (NAT gerçeği: limit cömert ama
 *   tarama girişimini keser). Şüpheli kullanım denetim kaydına düşer
 *   (QrTokenResolver).
 * - ADR-011: geçerli yanıt LiteSpeed tam-sayfa cache başlıkları taşır;
 *   oturum middleware'i bilinçli olarak YOKTUR (Set-Cookie sızmaz).
 * - Menü içeriği tamamen sunucuda derlenir; arama/filtre/sepet istemci
 *   tarafındadır (ADR-003) → sayfa herkes için aynı kalır, cache korunur.
 */
class PublicMenuController extends Controller
{
    public function __construct(private readonly QrTokenResolver $resolver)
    {
    }

    public function show(Request $request, string $token): Response
    {
        // DİL: ?lang=tr|en|de ile arayüz dili (cache-güvenli — URL'yi çeşitler). Geçersiz/
        // yoksa TR (müşteri menüsü varsayılanı; içerik TR). Buton menu.blade'de. Throttle/
        // gone/not-found sayfaları da BU dilde render edilir (aksi halde token daha
        // çözülmeden dönen hata sayfaları hep TR kalır) — bu yüzden erken çözülür.
        $locale = strtolower((string) $request->query('lang', ''));
        if (! in_array($locale, ['tr', 'en', 'de'], true)) {
            $locale = 'tr';
        }
        app()->setLocale($locale);

        // IP bazlı emniyet supabı (LiteSpeed cache'i ıskalayan istekler için).
        $limiterKey = 'qr-scan:'.sha1((string) $request->ip());

        if (RateLimiter::tooManyAttempts($limiterKey, 120)) {
            return response()->view('venue.qr-throttled', [], 429)
                ->header('Retry-After', (string) RateLimiter::availableIn($limiterKey))
                ->header('X-LiteSpeed-Cache-Control', 'no-cache');
        }

        RateLimiter::hit($limiterKey, 60);

        $resolution = $this->resolver->resolve($token, $request);

        if ($resolution->status === 'revoked' || $resolution->status === 'inactive') {
            // ADR-008: yenilenen QR basılana kadar eski karta açıklama.
            return response()->view('venue.qr-gone', [
                'reason' => $resolution->status,
            ], 410)->header('X-LiteSpeed-Cache-Control', 'no-cache');
        }

        if ($resolution->status !== 'ok') {
            return response()->view('venue.qr-not-found', [], 404)
                ->header('X-LiteSpeed-Cache-Control', 'no-cache');
        }

        $tenant = $resolution->tenant;
        $branch = $resolution->branch;
        $table = $resolution->table;

        // ÖNİZLEME modu (panelden): menü müşteri gözüyle görünür ama sipariş/servis
        // KAPALIDIR (gerçek adisyon/çağrı oluşmaz) + banner gösterilir.
        $preview = $request->boolean('preview');

        [$categories, $products, $payload, $featured] = $this->buildMenu(
            (int) $tenant->getKey(),
            (int) $branch->getKey(),
            (string) ($branch->timezone ?: config('app.timezone')),
        );

        return response()->view('venue.menu', [
            'tenantName' => $tenant->name,
            'branchName' => $branch->name,
            'tableLabel' => $table !== null
                ? trim($table->name.($table->number !== null ? ' · No '.$table->number : ''))
                : null,
            // Masasız "Genel Menü" QR'ı (branchImage, QrController.php) burada table=null
            // olarak çözülür. Sipariş/servis uçları YALNIZ masa QR'ında çalışır (ADR-008 +
            // ServiceRequest.table_id DB'de NOT NULL) — view bu bayrağa göre sepet/servis
            // arayüzünü gizler ve dürüst bir yönlendirme mesajı gösterir (bkz. menu.blade.php).
            'hasTable' => $table !== null,
            'categories' => $categories,
            'products' => $products,
            'payload' => $payload,
            'featured' => $featured,
            'branchInfo' => $this->buildBranchInfo(
                $branch,
                (string) ($branch->timezone ?: config('app.timezone')),
            ),
            /*
             * Sipariş/servis uçları TEK buradan bağlanır (Siparis-Adisyon ajanı).
             * Sipariş ucu routes/orders.php'de tanımlı (POST /api/v1/public/orders,
             * gövde: {token, items:[{product_id, variant_id?, qty, option_ids?, note?}]},
             * Idempotency-Key başlığı destekli). Uç canlıda henüz 404 ise istemci
             * dürüst "henüz devrede değil" mesajı gösterir — sahte başarı yok.
             * Servis ucu (garson/hesap/su): routes/orders.php → public/service-requests.
             */
            // Önizlemede uçlar KAPALI (boş) → müşteri butonları "önizleme" uyarısı verir.
            // ($menuFeatures + eklenti-bazlı gizleme PublicMenuBranding composer'ında.)
            'orderEndpoint' => $preview ? '' : '/api/v1/public/orders',
            'serviceEndpoint' => $preview ? '' : '/api/v1/public/service-requests',
            'preview' => $preview,
            'locale' => $locale,
        ])
            // Önizleme cache'lenmez (her zaman güncel menü); normalde ADR-011 public cache.
            ->header(
                'X-LiteSpeed-Cache-Control',
                $preview ? 'no-cache' : 'public, max-age=120',
            )
            ->header('X-LiteSpeed-Tag', sprintf('t%d, b%d', $tenant->getKey(), $branch->getKey()));
    }

    /**
     * İşletme Vitrini: public menüde görünen bilgi kartı (adres/telefon +
     * WiFi, çalışma saatleri, konum, sosyal medya). Tüm türetmeler (açık/kapalı
     * durumu, harita linki, sosyal URL normalizasyonu) SUNUCUDA yapılır →
     * cache uyumlu, istemciye ham handle sızmaz. Boş alanlar tamamen atlanır.
     *
     * @return array<string, mixed>
     */
    private function buildBranchInfo(object $branch, string $timezone): array
    {
        $info = [];

        $address = trim((string) ($branch->address ?? ''));
        $phone = trim((string) ($branch->phone ?? ''));
        if ($address !== '') {
            $info['address'] = $address;
        }
        if ($phone !== '') {
            $info['phone'] = $phone;
        }

        $sc = is_array($branch->showcase ?? null) ? $branch->showcase : [];

        // WiFi (ssid zorunlu; şifre opsiyonel — sadece bakışta "şifresiz" demeyiz).
        $ssid = trim((string) ($sc['wifi_ssid'] ?? ''));
        if ($ssid !== '') {
            $info['wifi'] = [
                'ssid' => $ssid,
                'password' => trim((string) ($sc['wifi_password'] ?? '')),
            ];
        }

        // Çalışma saatleri: 0=Pzt … 6=Paz. Bugünü işaretle + "şu an açık mı".
        $hours = $this->buildHours($sc['hours'] ?? null, $timezone, $info);

        if ($hours !== []) {
            $info['hours'] = $hours;
        }

        // Konum: açık maps_url öncelikli; yoksa adresten Google Haritalar linki.
        $mapsUrl = trim((string) ($sc['maps_url'] ?? ''));
        $showMap = ! array_key_exists('show_map', $sc) || (bool) $sc['show_map'];
        if ($showMap) {
            if ($mapsUrl !== '' && preg_match('~^https?://~i', $mapsUrl)) {
                $info['maps_url'] = $mapsUrl;
            } elseif ($address !== '') {
                $info['maps_url'] = 'https://www.google.com/maps/search/?api=1&query='.rawurlencode($address);
            }
        }

        // Sosyal medya: handle → tam URL (istemciye normalize edilmiş çıkar).
        $social = $this->buildSocial($sc['social'] ?? null);
        if ($social !== []) {
            $info['social'] = $social;
        }

        return $info;
    }

    /**
     * @param  mixed  $raw
     * @param  array<string, mixed>  $info  ('open_now' bu diziye yazılır)
     * @return array<int, array<string, mixed>>
     */
    private function buildHours($raw, string $timezone, array &$info): array
    {
        if (! is_array($raw) || $raw === []) {
            return [];
        }

        $now = now($timezone);
        $todayIdx = (int) $now->dayOfWeekIso - 1; // 1..7 → 0..6 (0=Pzt)
        $nowHm = $now->format('H:i');

        $out = [];
        $openNow = null;
        foreach ($raw as $row) {
            if (! is_array($row) || ! isset($row['d'])) {
                continue;
            }
            $d = (int) $row['d'];
            if ($d < 0 || $d > 6) {
                continue;
            }
            $closed = ! empty($row['closed']);
            $open = trim((string) ($row['open'] ?? ''));
            $close = trim((string) ($row['close'] ?? ''));
            $isToday = $d === $todayIdx;

            if ($isToday) {
                if ($closed || $open === '' || $close === '') {
                    $openNow = false;
                } else {
                    // Gece devri desteği (ör. 18:00 → 02:00).
                    $openNow = $open <= $close
                        ? ($nowHm >= $open && $nowHm <= $close)
                        : ($nowHm >= $open || $nowHm <= $close);
                }
            }

            $out[$d] = [
                'd' => $d,
                'closed' => $closed,
                'open' => $closed ? null : ($open !== '' ? $open : null),
                'close' => $closed ? null : ($close !== '' ? $close : null),
                'today' => $isToday,
            ];
        }

        if ($out === []) {
            return [];
        }

        // 0..6 sırasına diz (eksik günler "belirtilmemiş" olarak atlanır).
        ksort($out);
        if ($openNow !== null) {
            $info['open_now'] = $openNow;
        }

        return array_values($out);
    }

    /**
     * @param  mixed  $raw
     * @return array<int, array<string, string>>
     */
    private function buildSocial($raw): array
    {
        if (! is_array($raw)) {
            return [];
        }

        $out = [];
        foreach (['instagram', 'facebook', 'x', 'tiktok', 'youtube', 'whatsapp', 'website'] as $key) {
            $v = trim((string) ($raw[$key] ?? ''));
            if ($v === '') {
                continue;
            }
            $url = $this->socialUrl($key, $v);
            if ($url !== null) {
                $out[] = ['key' => $key, 'url' => $url];
            }
        }

        return $out;
    }

    private function socialUrl(string $key, string $v): ?string
    {
        $handle = ltrim($v, '@');
        $isUrl = (bool) preg_match('~^https?://~i', $v);

        return match ($key) {
            'instagram' => $isUrl ? $v : 'https://instagram.com/'.rawurlencode($handle),
            'facebook' => $isUrl ? $v : 'https://facebook.com/'.rawurlencode($handle),
            'x' => $isUrl ? $v : 'https://x.com/'.rawurlencode($handle),
            'tiktok' => $isUrl ? $v : 'https://tiktok.com/@'.rawurlencode($handle),
            'youtube' => $isUrl ? $v : 'https://youtube.com/@'.rawurlencode($handle),
            'whatsapp' => 'https://wa.me/'.preg_replace('/[^\d]/', '', $v),
            'website' => $isUrl ? $v : 'https://'.$v,
            default => null,
        };
    }

    /**
     * Menü verisini derler: kategoriler + kart listesi + istemci JSON'u.
     * Kiracı süzgeci HER sorguda token'dan çözülen tenant_id'dir; Eloquent
     * global scope'larına (TenantContext) bilinçli olarak yaslanılmaz —
     * public istekte bağlam yoktur, DB::table + açık filtre daha güvenlidir.
     *
     * @return array{0: array<int, array<string, mixed>>, 1: array<int, array<int, array<string, mixed>>>, 2: array<string, mixed>, 3: array<int, array<string, mixed>>}
     */
    private function buildMenu(int $tenantId, int $branchId, string $timezone): array
    {
        $rows = DB::table('products')
            ->where('tenant_id', $tenantId)
            ->where(function ($q) use ($branchId): void {
                $q->whereNull('branch_id')->orWhere('branch_id', $branchId);
            })
            ->where('is_active', true)
            ->orderBy('sort_order')->orderBy('name')
            ->limit(500)
            ->get([
                'id', 'name', 'description', 'category_id', 'currency',
                'price_minor', 'qr_price_minor', 'discounted_price_minor',
                'prep_minutes', 'weight_grams', 'calories', 'protein', 'carbs', 'fat',
                'spiciness', 'portion', 'unit',
                'is_new', 'is_chef_pick', 'is_bestseller',
                'is_available', 'channels', 'available_from', 'available_until',
                'track_stock', 'stock_quantity', 'min_order_qty', 'max_order_qty',
            ]);

        // Kanal süzgeci: channels boş = her kanal; doluysa 'qr' içermeli.
        $rows = $rows->filter(function ($p): bool {
            $channels = json_decode((string) ($p->channels ?? ''), true);

            return ! is_array($channels) || $channels === [] || in_array('qr', $channels, true);
        })->values();

        $ids = $rows->pluck('id')->all();

        $catRows = DB::table('categories')
            ->where('tenant_id', $tenantId)->where('is_active', true)
            ->orderBy('sort_order')->orderBy('name')
            ->get(['id', 'name', 'available_from', 'available_until']);
        $catById = $catRows->keyBy('id');

        $variants = $ids === [] ? collect() : DB::table('product_variants')
            ->whereIn('product_id', $ids)->where('is_active', true)
            ->orderBy('sort_order')->get(['id', 'product_id', 'name', 'price_minor', 'is_default'])
            ->groupBy('product_id');

        $groupLinks = $ids === [] ? collect() : DB::table('option_group_product')
            ->whereIn('product_id', $ids)->orderBy('sort_order')
            ->get(['product_id', 'option_group_id'])->groupBy('product_id');

        $groupIds = $groupLinks->flatten(1)->pluck('option_group_id')->unique()->values()->all();

        $groups = $groupIds === [] ? collect() : DB::table('option_groups')
            ->where('tenant_id', $tenantId)->whereIn('id', $groupIds)->where('is_active', true)
            ->get(['id', 'name', 'description', 'selection_type', 'is_required', 'min_select', 'max_select', 'free_limit'])
            ->keyBy('id');

        $options = $groupIds === [] ? collect() : DB::table('options')
            ->whereIn('option_group_id', $groupIds)->where('is_active', true)
            ->orderBy('sort_order')->get(['id', 'option_group_id', 'name', 'price_minor', 'is_default'])
            ->groupBy('option_group_id');

        $allergenLinks = $ids === [] ? collect() : DB::table('allergen_product')
            ->whereIn('product_id', $ids)->get(['product_id', 'allergen_id'])->groupBy('product_id');

        $allergenRows = DB::table('allergens')
            ->where(function ($q) use ($tenantId): void {
                $q->whereNull('tenant_id')->orWhere('tenant_id', $tenantId);
            })
            ->orderBy('sort_order')->get(['id', 'kind', 'code', 'name', 'description']);
        $allergenById = $allergenRows->keyBy('id');

        $imageRows = $ids === [] ? collect() : DB::table('product_images')
            ->whereIn('product_id', $ids)
            ->orderByDesc('is_primary')->orderBy('sort_order')
            ->get(['product_id', 'path'])->groupBy('product_id');

        // Zaman penceresi: ürün/kategori TIME kolonları günlük penceredir,
        // şube saat dilimine göre hesaplanır; gece devri (from>until) desteklenir.
        $nowTime = now($timezone)->format('H:i:s');
        $inWindow = static function (?string $from, ?string $until) use ($nowTime): bool {
            if ($from === null || $until === null) {
                return true;
            }

            return $from <= $until
                ? ($nowTime >= $from && $nowTime <= $until)
                : ($nowTime >= $from || $nowTime <= $until);
        };

        $cards = [];          // kategori_id => kart dizisi (Blade)
        $payloadProducts = [];// id => istemci verisi (detay + sepet)

        foreach ($rows as $p) {
            $cat = $p->category_id !== null ? $catById->get($p->category_id) : null;
            $catId = $cat?->id ?? 0;

            $base = (int) $p->price_minor;
            $effective = (int) ($p->qr_price_minor ?? $p->discounted_price_minor ?? $p->price_minor);
            $oldPrice = $effective < $base ? $base : null;

            // Sipariş edilemez iki ayrı sebep: stok (tükendi) / servis saati dışı.
            $outOfStock = ! $p->is_available || ($p->track_stock && (int) $p->stock_quantity <= 0);
            $offHours = ! $inWindow($p->available_from, $p->available_until)
                || ($cat !== null && ! $inWindow($cat->available_from, $cat->available_until));
            $soldOut = $outOfStock || $offHours;

            $allergenIds = [];
            $dietIds = [];
            foreach ($allergenLinks->get($p->id, collect()) as $link) {
                $a = $allergenById->get($link->allergen_id);
                if ($a === null) {
                    continue;
                }
                $a->kind === 'diet' ? $dietIds[] = $a->id : $allergenIds[] = $a->id;
            }

            $vList = $variants->get($p->id, collect())->map(fn ($v) => [
                'i' => $v->id, 'n' => $v->name, 'p' => (int) $v->price_minor, 'def' => (bool) $v->is_default,
            ])->values()->all();

            $gList = [];
            foreach ($groupLinks->get($p->id, collect()) as $link) {
                $g = $groups->get($link->option_group_id);
                if ($g === null) {
                    continue;
                }
                $opts = $options->get($g->id, collect())->map(fn ($o) => [
                    'i' => $o->id, 'n' => $o->name, 'p' => (int) $o->price_minor, 'def' => (bool) $o->is_default,
                ])->values()->all();
                if ($opts === []) {
                    continue;
                }
                $gList[] = [
                    'i' => $g->id, 'n' => $g->name, 'd' => $g->description,
                    't' => $g->selection_type, 'req' => (bool) $g->is_required,
                    'min' => (int) $g->min_select, 'max' => $g->max_select !== null ? (int) $g->max_select : null,
                    'free' => (int) $g->free_limit, 'o' => $opts,
                ];
            }

            $img = $imageRows->get($p->id)?->first();
            $imgUrl = $img !== null ? Storage::disk('public')->url($img->path) : null;

            $card = [
                'id' => $p->id,
                'name' => $p->name,
                'description' => $p->description,
                'price_minor' => $effective,
                'old_price_minor' => $oldPrice,
                'image' => $imgUrl,
                'sold_out' => $soldOut,
                'out_reason' => $outOfStock ? 'stock' : 'window',
                'is_new' => (bool) $p->is_new,
                'is_chef_pick' => (bool) $p->is_chef_pick,
                'is_bestseller' => (bool) $p->is_bestseller,
                'spiciness' => (int) ($p->spiciness ?? 0),
                // Kartta ince ikincil satır: "≈ 320 g · 780 kcal" (yalnız değer varsa).
                'weight_grams' => $p->weight_grams !== null ? (int) $p->weight_grams : null,
                'calories' => $p->calories !== null ? (int) $p->calories : null,
                'diets' => array_values(array_map(fn ($id) => $allergenById->get($id)->name, $dietIds)),
                'has_config' => $vList !== [] || $gList !== [],
            ];
            $cards[$catId][] = $card;

            $payloadProducts[$p->id] = [
                'n' => $p->name, 'd' => $p->description, 'c' => $catId,
                'p' => $effective, 'op' => $oldPrice, 'img' => $imgUrl,
                'prep' => $p->prep_minutes !== null ? (int) $p->prep_minutes : null,
                'wg' => $p->weight_grams !== null ? (int) $p->weight_grams : null,
                'cal' => $p->calories !== null ? (int) $p->calories : null,
                'prot' => $p->protein !== null ? (float) $p->protein : null,
                'carb' => $p->carbs !== null ? (float) $p->carbs : null,
                'fat' => $p->fat !== null ? (float) $p->fat : null,
                'spicy' => (int) ($p->spiciness ?? 0),
                'portion' => $p->portion, 'unit' => $p->unit,
                'new' => (bool) $p->is_new, 'chef' => (bool) $p->is_chef_pick, 'best' => (bool) $p->is_bestseller,
                'out' => $soldOut,
                'outr' => $outOfStock ? 'stock' : 'window',
                'minq' => max(1, (int) ($p->min_order_qty ?? 1)),
                'maxq' => $p->max_order_qty !== null ? (int) $p->max_order_qty : null,
                'al' => $allergenIds, 'diet' => $dietIds,
                'v' => $vList, 'g' => $gList,
            ];
        }

        // Kategori listesi: yalnız ürünü olanlar; kategorisiz ürünler "Diğer".
        $categories = [];
        foreach ($catRows as $c) {
            if (! empty($cards[$c->id])) {
                $categories[] = ['id' => (int) $c->id, 'name' => $c->name];
            }
        }
        if (! empty($cards[0])) {
            $categories[] = ['id' => 0, 'name' => __('menu.other')];
        }

        $payload = [
            'currency' => '₺',
            'allergens' => $allergenRows->mapWithKeys(fn ($a) => [
                (string) $a->id => ['k' => $a->kind, 'n' => $a->name, 'd' => $a->description],
            ])->all(),
            'products' => (object) $payloadProducts,
        ];

        return [$categories, $cards, $payload, $this->buildFeatured($categories, $cards)];
    }

    /**
     * "Öne çıkanlar" şeridi: ürün kartlarıyla AYNI biçimi kullanır (Blade
     * kartla birebir aynı veri şekli → ayrı bir partial'a ihtiyaç yok, tıklama
     * mevcut data-detail/data-add sözleşmesiyle çalışır).
     *
     * Öncelik: yönetici işaretli "şef önerisi" / "çok satan" ürünler (panelde
     * bilinçli seçilmiş sinyal — is_featured/is_popular gibi ayrı bir kolon
     * şemada YOK, bkz. database/migrations). Görselsiz veya tükenmiş ürünler
     * şeride alınmaz (tıklanabilir ama boş/ölü kart olmasın diye).
     *
     * Yeterli sayıda (< 4) yoksa sezgisel yedek devreye girer: kategori
     * görünüm sırasına göre ilk birkaç kategorinin ilk görselli/satıştaki
     * ürünü (kategori başına en fazla 1) eklenir. Toplam üst sınır 8 — şerit
     * kısa ve "el ile seçilmiş" hissi versin, tüm menü tekrar edilmesin.
     *
     * @param  array<int, array<string, mixed>>  $categories
     * @param  array<int, array<int, array<string, mixed>>>  $cards
     * @return array<int, array<string, mixed>>
     */
    private function buildFeatured(array $categories, array $cards): array
    {
        $limit = 8;
        $featured = [];
        $usedIds = [];

        foreach ($cards as $catCards) {
            foreach ($catCards as $card) {
                if (count($featured) >= $limit) {
                    break 2;
                }
                if (($card['is_chef_pick'] || $card['is_bestseller']) && $card['image'] !== null && ! $card['sold_out']) {
                    $featured[] = $card;
                    $usedIds[$card['id']] = true;
                }
            }
        }

        if (count($featured) < 4) {
            foreach ($categories as $cat) {
                if (count($featured) >= $limit) {
                    break;
                }
                foreach ($cards[$cat['id']] ?? [] as $card) {
                    if (isset($usedIds[$card['id']]) || $card['image'] === null || $card['sold_out']) {
                        continue;
                    }
                    $featured[] = $card;
                    $usedIds[$card['id']] = true;
                    break; // bu kategoriden yalnız bir tane
                }
            }
        }

        return $featured;
    }
}
