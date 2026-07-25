<?php

namespace App\Modules\Kiosk\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/**
 * Kiosk menü verisi (kanal = kiosk).
 *
 * PublicMenuController::buildMenu deseninin kiosk uyarlaması: kiracı süzgeci
 * HER sorguda token'dan çözülen tenant_id'dir; Eloquent tenant scope'una
 * yaslanılmaz (public istekte bağlam yoktur, açık filtre daha güvenlidir).
 *
 * Farklar:
 *  - Kanal süzgeci 'kiosk' (channels boş = her kanal).
 *  - Efektif fiyat: kiosk_price_minor ?? discounted_price_minor ?? price_minor.
 *  - Çıktı anahtarları okunur adlıdır (kiosk sayfası cache'lenmez; ADR-011
 *    baskısı yok, tek cihaz okur).
 */
class KioskMenuBuilder
{
    /**
     * @return array{categories: array<int, array<string, mixed>>, products: array<int, array<string, mixed>>, allergens: array<string, array<string, mixed>>, featured: array<int, int>}
     */
    public function build(int $tenantId, int $branchId, string $timezone): array
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
                'id', 'name', 'description', 'category_id',
                'price_minor', 'kiosk_price_minor', 'discounted_price_minor',
                'prep_minutes', 'calories', 'spiciness', 'portion', 'unit',
                'is_new', 'is_chef_pick', 'is_bestseller',
                'is_available', 'channels', 'available_from', 'available_until',
                'track_stock', 'stock_quantity', 'min_order_qty', 'max_order_qty',
            ]);

        // Kanal süzgeci: channels boş = her kanal; doluysa 'kiosk' içermeli.
        $rows = $rows->filter(function ($p): bool {
            $channels = json_decode((string) ($p->channels ?? ''), true);

            return ! is_array($channels) || $channels === [] || in_array('kiosk', $channels, true);
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

        // Günlük servis penceresi; gece devri (from > until) desteklenir.
        $nowTime = now($timezone)->format('H:i:s');
        $inWindow = static function (?string $from, ?string $until) use ($nowTime): bool {
            if ($from === null || $until === null) {
                return true;
            }

            return $from <= $until
                ? ($nowTime >= $from && $nowTime <= $until)
                : ($nowTime >= $from || $nowTime <= $until);
        };

        $products = [];
        $featured = [];
        $usedCategoryIds = [];

        foreach ($rows as $p) {
            $cat = $p->category_id !== null ? $catById->get($p->category_id) : null;
            $catId = $cat?->id ?? 0;

            $base = (int) $p->price_minor;
            $effective = (int) ($p->kiosk_price_minor ?? $p->discounted_price_minor ?? $p->price_minor);
            $oldPrice = $effective < $base ? $base : null;

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
                $a->kind === 'diet' ? $dietIds[] = (int) $a->id : $allergenIds[] = (int) $a->id;
            }

            $vList = $variants->get($p->id, collect())->map(fn ($v) => [
                'id' => (int) $v->id, 'name' => $v->name,
                'price_minor' => (int) $v->price_minor, 'is_default' => (bool) $v->is_default,
            ])->values()->all();

            $gList = [];
            foreach ($groupLinks->get($p->id, collect()) as $link) {
                $g = $groups->get($link->option_group_id);
                if ($g === null) {
                    continue;
                }
                $opts = $options->get($g->id, collect())->map(fn ($o) => [
                    'id' => (int) $o->id, 'name' => $o->name,
                    'price_minor' => (int) $o->price_minor, 'is_default' => (bool) $o->is_default,
                ])->values()->all();
                if ($opts === []) {
                    continue;
                }
                $gList[] = [
                    'id' => (int) $g->id, 'name' => $g->name, 'description' => $g->description,
                    'type' => $g->selection_type, 'required' => (bool) $g->is_required,
                    'min' => (int) $g->min_select, 'max' => $g->max_select !== null ? (int) $g->max_select : null,
                    'free_limit' => (int) $g->free_limit, 'options' => $opts,
                ];
            }

            $img = $imageRows->get($p->id)?->first();

            $products[] = [
                'id' => (int) $p->id,
                'category_id' => (int) $catId,
                'name' => $p->name,
                'description' => $p->description,
                'price_minor' => $effective,
                'old_price_minor' => $oldPrice,
                'image' => $img !== null ? Storage::disk('public')->url($img->path) : null,
                'sold_out' => $soldOut,
                'out_reason' => $outOfStock ? 'stock' : 'window',
                'is_new' => (bool) $p->is_new,
                'is_chef_pick' => (bool) $p->is_chef_pick,
                'is_bestseller' => (bool) $p->is_bestseller,
                'spiciness' => (int) ($p->spiciness ?? 0),
                'calories' => $p->calories !== null ? (int) $p->calories : null,
                'portion' => $p->portion,
                'min_qty' => max(1, (int) ($p->min_order_qty ?? 1)),
                'max_qty' => $p->max_order_qty !== null ? (int) $p->max_order_qty : null,
                'allergen_ids' => $allergenIds,
                'diet_ids' => $dietIds,
                'variants' => $vList,
                'option_groups' => $gList,
            ];

            $usedCategoryIds[$catId] = true;

            if (! $soldOut && ($p->is_bestseller || $p->is_chef_pick)) {
                $featured[] = (int) $p->id;
            }
        }

        $categories = [];
        foreach ($catRows as $c) {
            if (isset($usedCategoryIds[$c->id])) {
                $categories[] = ['id' => (int) $c->id, 'name' => $c->name];
            }
        }
        if (isset($usedCategoryIds[0])) {
            $categories[] = ['id' => 0, 'name' => 'Diğer'];
        }

        return [
            'categories' => $categories,
            'products' => $products,
            'allergens' => $allergenRows->mapWithKeys(fn ($a) => [
                (string) $a->id => ['kind' => $a->kind, 'name' => $a->name, 'description' => $a->description],
            ])->all(),
            'featured' => array_slice($featured, 0, 8),
        ];
    }
}
