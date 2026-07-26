<?php

namespace App\Modules\Settings\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Settings\Support\FeatureCatalog;
use App\Modules\Settings\Support\Features;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * "Eklentiler" ayar ekranının API'si — MODULE_MAP §9.
 *
 * Yönetici opsiyonel özellikleri (kiosk, rezervasyon, qr-sipariş, garson-çağır,
 * stok, vardiya, borçlar, terminaller) tek tek aç/kapatır. Çekirdek özellikler
 * katalogda olmadığından buradan da kapatılamaz. İzin: settings.manage.
 *
 * Kiracı YALNIZ oturumdan çözülür (istekten tenant id alınmaz).
 */
class FeatureSettingsController extends Controller
{
    /** Katalog + bu kiracının efektif durumu. */
    public function show(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('settings.manage'), 403);

        $state = Features::all((int) $request->user()->tenant_id);

        $features = array_map(static fn (array $f): array => [
            'key' => $f['key'],
            'name' => $f['name'],
            'description' => $f['description'],
            'enabled' => $state[$f['key']] ?? $f['default'],
        ], FeatureCatalog::all());

        return response()->json(['features' => $features]);
    }

    /** Tek özelliği aç/kapat. */
    public function update(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('settings.manage'), 403);

        $data = $request->validate([
            'feature' => ['required', 'string', Rule::in(FeatureCatalog::keys())],
            'enabled' => ['required', 'boolean'],
        ]);

        Features::set((int) $request->user()->tenant_id, $data['feature'], (bool) $data['enabled']);

        return response()->json([
            'feature' => $data['feature'],
            'enabled' => (bool) $data['enabled'],
        ]);
    }
}
