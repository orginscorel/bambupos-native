<?php

declare(strict_types=1);

namespace App\Modules\Integrations\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Integrations\Models\TenantIntegration;
use App\Modules\Integrations\Support\IntegrationCatalog;
use App\Modules\Integrations\Support\Integrations;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * "Entegrasyonlar" ekranının API'si — takılabilir çerçeve yönetimi.
 *
 * Yönetici her entegrasyonu (ödeme/teslimat/e-fatura/muhasebe) tek tek
 * AÇAR/KAPATIR ve yapılandırır. İzin: integrations.manage. Kiracı YALNIZ
 * oturumdan çözülür (istekten tenant id ALINMAZ). GİZLİ config alanları
 * asla ham dönmez: maskelenir; boş gönderilen gizli alan mevcut değeri korur.
 */
class IntegrationController extends Controller
{
    /** Gizli alan kayıtlıyken panele dönen maske (gerçek değer sızmaz). */
    private const SECRET_MASK = '••••••••';

    /** Katalog + bu kiracının durumları (maskeli config ile). */
    public function index(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('integrations.manage'), 403);

        $tenantId = (int) $request->user()->tenant_id;
        $rows = TenantIntegration::query()->get()->keyBy('key');

        $integrations = array_map(function (array $def) use ($rows): array {
            /** @var TenantIntegration|null $row */
            $row = $rows->get($def['key']);

            return $this->present($def, $row);
        }, IntegrationCatalog::all());

        return response()->json(['integrations' => $integrations]);
    }

    /** Tek entegrasyonu aç/kapat. */
    public function toggle(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('integrations.manage'), 403);

        $data = $request->validate([
            'key' => ['required', 'string', Rule::in(IntegrationCatalog::keys())],
            'is_enabled' => ['required', 'boolean'],
        ]);

        $row = TenantIntegration::query()->firstOrNew(['key' => $data['key']]);
        $row->is_enabled = (bool) $data['is_enabled'];
        $row->config ??= [];
        $row->save();

        Integrations::flush((int) $request->user()->tenant_id);

        $def = IntegrationCatalog::find($data['key']);

        return response()->json(['integration' => $this->present($def, $row)]);
    }

    /** Entegrasyonun yapılandırmasını kaydet (gizli alanlar korunur/maskelenir). */
    public function saveConfig(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('integrations.manage'), 403);

        $data = $request->validate([
            'key' => ['required', 'string', Rule::in(IntegrationCatalog::keys())],
            'config' => ['present', 'array'],
        ]);

        $def = IntegrationCatalog::find($data['key']);
        $secretKeys = IntegrationCatalog::secretFieldKeys($data['key']);

        $row = TenantIntegration::query()->firstOrNew(['key' => $data['key']]);
        $existing = is_array($row->config) ? $row->config : [];

        $merged = [];

        // Yalnız katalogdaki alanları kabul et (istekten fazla anahtar sızmasın).
        foreach ($def['config_fields'] as $field) {
            $fieldKey = $field['key'];
            $incoming = $data['config'][$fieldKey] ?? null;
            $isSecret = in_array($fieldKey, $secretKeys, true);

            // Gizli alan: boş/eksik VEYA maske değeri geldiyse ESKİ değeri koru.
            if ($isSecret && ($incoming === null || $incoming === '' || $incoming === self::SECRET_MASK)) {
                if (array_key_exists($fieldKey, $existing) && $existing[$fieldKey] !== '') {
                    $merged[$fieldKey] = $existing[$fieldKey];
                }

                continue;
            }

            if ($incoming === null || $incoming === '') {
                continue; // boş açık alanı saklamaya gerek yok
            }

            $merged[$fieldKey] = is_string($incoming) ? trim($incoming) : $incoming;
        }

        $row->config = $merged;
        $row->is_enabled = (bool) ($row->is_enabled ?? false); // toggle durumu korunur
        $row->save();

        Integrations::flush((int) $request->user()->tenant_id);

        return response()->json(['integration' => $this->present($def, $row)]);
    }

    /**
     * Bir entegrasyonun panele dönen güvenli gösterimi. Gizli alanların GERÇEK
     * değeri asla dönmez; yalnız "kayıtlı mı" bilgisi + maske gösterilir.
     *
     * @param  array{key: string, name: string, category: string, description: string, config_fields: list<array{key: string, label: string, secret?: bool}>}  $def
     */
    private function present(array $def, ?TenantIntegration $row): array
    {
        $stored = ($row !== null && is_array($row->config)) ? $row->config : [];
        $secretKeys = IntegrationCatalog::secretFieldKeys($def['key']);

        $config = [];
        $configured = false;

        foreach ($def['config_fields'] as $field) {
            $fieldKey = $field['key'];
            $hasValue = array_key_exists($fieldKey, $stored) && $stored[$fieldKey] !== '' && $stored[$fieldKey] !== null;

            if ($hasValue) {
                $configured = true;
            }

            if (in_array($fieldKey, $secretKeys, true)) {
                // Gizli: gerçek değer YOK; yalnız maske + kayıtlı bayrağı.
                $config[$fieldKey] = $hasValue ? self::SECRET_MASK : '';
            } else {
                $config[$fieldKey] = $hasValue ? (string) $stored[$fieldKey] : '';
            }
        }

        $isEnabled = $row?->is_enabled ?? false;

        return [
            'key' => $def['key'],
            'name' => $def['name'],
            'category' => $def['category'],
            'description' => $def['description'],
            'config_fields' => array_map(static fn (array $f): array => [
                'key' => $f['key'],
                'label' => $f['label'],
                'secret' => (bool) ($f['secret'] ?? false),
            ], $def['config_fields']),
            'is_enabled' => (bool) $isEnabled,
            'configured' => $configured,
            // Durum: aktif (açık+yapılandırılmış) / unconfigured (açık ama eksik) /
            //        off (kapalı). Panel rozeti bundan türetilir.
            'status' => $isEnabled ? ($configured ? 'active' : 'unconfigured') : 'off',
            'config' => $config,
        ];
    }
}
