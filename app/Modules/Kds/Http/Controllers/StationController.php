<?php

namespace App\Modules\Kds\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Kds\Models\Station;
use App\Modules\Kds\Models\UserStation;
use App\Modules\Kds\Services\StationRegistry;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * İstasyon tanımları: yerleşikler + işletmenin KENDİ istasyonları (CRUD)
 * + personel-istasyon ataması. Listeleme kds.view; değişiklik kds.manage.
 */
class StationController extends Controller
{
    public function __construct(private readonly StationRegistry $stations)
    {
    }

    public function index(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('kds.view') || $request->user()->hasPermission('kds.deliver'), 403);

        return response()->json(['stations' => $this->stations->all(activeOnly: false)->all()]);
    }

    public function store(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('kds.manage'), 403);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:80'],
            'sort_order' => ['nullable', 'integer', 'min:0', 'max:1000'],
        ]);

        $station = $this->stations->create($data['name'], (int) ($data['sort_order'] ?? 0));

        return response()->json(['station' => $station], 201);
    }

    public function update(Request $request, Station $station): JsonResponse
    {
        abort_unless($request->user()->hasPermission('kds.manage'), 403);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:80'],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:1000'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        $station->update($data); // key SABİT kalır (ürün yönlendirmesi bozulmasın)

        return response()->json(['station' => $station->fresh()]);
    }

    public function destroy(Request $request, Station $station): JsonResponse
    {
        abort_unless($request->user()->hasPermission('kds.manage'), 403);

        $inUse = \App\Modules\Catalog\Models\Product::query()
            ->where('station', $station->key)
            ->exists();

        if ($inUse) {
            throw ValidationException::withMessages([
                'station' => ['Bu istasyona yönlendirilmiş ürünler var; önce ürünleri başka istasyona alın ya da istasyonu pasifleştirin.'],
            ]);
        }

        UserStation::query()->where('station_key', $station->key)->delete();
        $station->delete();

        return response()->json(['ok' => true]);
    }

    /** Personel-istasyon atamaları (kds.manage): user_id → station_keys[]. */
    public function assignments(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('kds.manage'), 403);

        // User modeli global tenant-scope'lu DEĞİL — kiracı süzgeci açıkça.
        $users = User::query()
            ->where('tenant_id', $request->user()->tenant_id)
            ->where('is_active', true)
            ->orderBy('first_name')->orderBy('last_name')
            ->get(['id', 'first_name', 'last_name', 'position']);

        $map = UserStation::query()->get()
            ->groupBy('user_id')
            ->map(fn ($rows) => $rows->pluck('station_key')->values()->all());

        return response()->json([
            'users' => $users->map(fn (User $u): array => [
                'id' => $u->id,
                'name' => $u->name,
                'position' => $u->position,
                'station_keys' => $map->get($u->id, []),
            ])->values()->all(),
        ]);
    }

    /** Bir personelin istasyon atamasını değiştir (boş = tümünü görür). */
    public function assign(Request $request, User $user): JsonResponse
    {
        abort_unless($request->user()->hasPermission('kds.manage'), 403);

        // User binding tenant-scope'suz — yabancı kiracının personeli 404.
        abort_unless((int) $user->tenant_id === (int) $request->user()->tenant_id, 404);

        $data = $request->validate([
            'station_keys' => ['present', 'array', 'max:30'],
            'station_keys.*' => ['string', 'max:40'],
        ]);

        foreach ($data['station_keys'] as $key) {
            if (! $this->stations->isValid($key)) {
                throw ValidationException::withMessages(['station_keys' => ["Geçersiz istasyon: {$key}"]]);
            }
        }

        UserStation::query()->where('user_id', $user->getKey())->delete();

        foreach (array_values(array_unique($data['station_keys'])) as $key) {
            UserStation::query()->create(['user_id' => $user->getKey(), 'station_key' => $key]);
        }

        return response()->json(['ok' => true, 'station_keys' => $data['station_keys']]);
    }
}
