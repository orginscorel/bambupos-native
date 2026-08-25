<?php

namespace App\Modules\Orders\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Orders\Models\DiscountPreset;
use App\Modules\Orders\Models\Order;
use Illuminate\Support\Facades\DB;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Hazır indirim tanımları: LİSTE herkese (adisyon görebilene) açıktır —
 * kasa/sepet uygulayabilsin diye; TANIMLAMA `orders.discount` ister
 * (indirim uygulama yetkisiyle aynı kapı, ayrı bir izin icat edilmedi).
 */
class DiscountPresetController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Order::class);

        $all = $request->boolean('all');

        $presets = DiscountPreset::query()
            ->when(! $all, fn ($q) => $q->where('is_active', true))
            ->orderBy('sort_order')->orderBy('name')
            ->get();

        // KULLANIM İSTATİSTİĞİ: kaç adisyonda uygulandı, toplam ne kadar indirim
        // yapıldı — genel ve İÇİNDE BULUNULAN AY. Tek sorgu; tanım başına döngü
        // içinde sorgu atmak (N+1) uzun listelerde ekranı yavaşlatırdı.
        $usage = $this->usageMap($presets->pluck('id')->all());

        return response()->json([
            'presets' => $presets->map(fn (DiscountPreset $p) => array_merge(
                $this->present($p),
                $usage[$p->id] ?? ['used_count' => 0, 'used_minor' => 0, 'month_count' => 0, 'month_minor' => 0],
            ))->all(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('discountAny', Order::class);

        $data = $this->validated($request);
        $preset = new DiscountPreset($data);
        $preset->save();

        return response()->json(['preset' => $this->present($preset)], 201);
    }

    public function update(Request $request, DiscountPreset $discountPreset): JsonResponse
    {
        $this->authorize('discountAny', Order::class);

        $discountPreset->fill($this->validated($request, $discountPreset->id));
        $discountPreset->save();

        return response()->json(['preset' => $this->present($discountPreset)]);
    }

    public function destroy(DiscountPreset $discountPreset): JsonResponse
    {
        $this->authorize('discountAny', Order::class);

        $discountPreset->delete();

        return response()->json(['deleted' => true]);
    }

    /**
     * Tanım başına kullanım (genel + bu ay).
     *
     * @param  array<int, int>  $ids
     * @return array<int, array{used_count: int, used_minor: int, month_count: int, month_minor: int}>
     */
    private function usageMap(array $ids): array
    {
        if ($ids === []) {
            return [];
        }

        $monthStart = now()->startOfMonth();

        $rows = Order::query()
            ->whereIn('discount_preset_id', $ids)
            ->where('discount_minor', '>', 0)
            ->groupBy('discount_preset_id')
            ->select([
                'discount_preset_id',
                DB::raw('COUNT(*) as used_count'),
                DB::raw('SUM(discount_minor) as used_minor'),
                DB::raw('SUM(CASE WHEN created_at >= ? THEN 1 ELSE 0 END) as month_count'),
                DB::raw('SUM(CASE WHEN created_at >= ? THEN discount_minor ELSE 0 END) as month_minor'),
            ])
            ->addBinding([$monthStart, $monthStart], 'select')
            ->get();

        $out = [];
        foreach ($rows as $r) {
            $out[(int) $r->discount_preset_id] = [
                'used_count' => (int) $r->used_count,
                'used_minor' => (int) $r->used_minor,
                'month_count' => (int) $r->month_count,
                'month_minor' => (int) $r->month_minor,
            ];
        }

        return $out;
    }

    /**
     * Tek tanımın AY BAZLI dökümü (son 12 ay) — "hangi ay kaç kez, ne kadar".
     */
    public function stats(DiscountPreset $discountPreset): JsonResponse
    {
        $this->authorize('discountAny', Order::class);

        $rows = Order::query()
            ->where('discount_preset_id', $discountPreset->getKey())
            ->where('discount_minor', '>', 0)
            ->where('created_at', '>=', now()->startOfMonth()->subMonths(11))
            ->groupBy(DB::raw("DATE_FORMAT(created_at, '%Y-%m')"))
            ->select([
                DB::raw("DATE_FORMAT(created_at, '%Y-%m') as ym"),
                DB::raw('COUNT(*) as used_count'),
                DB::raw('SUM(discount_minor) as used_minor'),
            ])
            ->orderBy('ym')
            ->get();

        return response()->json([
            'preset' => $this->present($discountPreset),
            'months' => $rows->map(fn ($r) => [
                'month' => (string) $r->ym,
                'used_count' => (int) $r->used_count,
                'used_minor' => (int) $r->used_minor,
            ])->values()->all(),
        ]);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, ?int $ignoreId = null): array
    {
        $data = $request->validate([
            'name' => [
                'required', 'string', 'min:2', 'max:80',
                Rule::unique('discount_presets', 'name')
                    ->where('tenant_id', $request->user()?->tenant_id)
                    ->ignore($ignoreId),
            ],
            'type' => ['required', Rule::in(['percent', 'amount'])],
            // Yüzde 0'dan büyük ve 100'ü aşamaz; sabit tutar kuruştur.
            'value_percent' => ['required_if:type,percent', 'nullable', 'numeric', 'gt:0', 'max:100'],
            'value_minor' => ['required_if:type,amount', 'nullable', 'integer', 'gt:0'],
            'note' => ['nullable', 'string', 'max:255'],
            'requires_approval' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:9999'],
        ]);

        // Türe uymayan değer sütunu TEMİZLENİR (yüzde tanımında kuruş kalıntısı kalmasın).
        if ($data['type'] === 'percent') {
            $data['value_minor'] = null;
        } else {
            $data['value_percent'] = null;
        }

        return $data;
    }

    /** @return array<string, mixed> */
    private function present(DiscountPreset $p): array
    {
        return [
            'id' => $p->id,
            'name' => $p->name,
            'type' => $p->type,
            'value_percent' => $p->value_percent !== null ? (float) $p->value_percent : null,
            'value_minor' => $p->value_minor !== null ? (int) $p->value_minor : null,
            'value_label' => $p->valueLabel(),
            'note' => $p->note,
            'requires_approval' => (bool) $p->requires_approval,
            'is_active' => (bool) $p->is_active,
            'sort_order' => (int) $p->sort_order,
        ];
    }
}
