<?php

declare(strict_types=1);

namespace App\Modules\Payments\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Payments\Providers\ProviderRegistry;
use App\Modules\Payments\Services\PosConfigResolver;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * POS ENTEGRATÖR YÖNETİMİ — işletme kendi ödeme cihazını/sağlayıcısını buradan
 * seçip yapılandırır (çok-işletmeli; her tenant bağımsız). Sırlar maskeli döner;
 * yalnız settings.manage yetkisi.
 */
class PosIntegrationController extends Controller
{
    public function __construct(
        private readonly ProviderRegistry $registry,
        private readonly PosConfigResolver $resolver,
        private readonly TenantContext $tenants,
    ) {
    }

    /** Katalog (yetenekler) + presetler + işletmenin mevcut yapılandırması (maskeli). */
    public function show(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('settings.manage'), 403);

        $row = DB::table('tenant_integrations')
            ->where('tenant_id', (int) $this->tenants->tenantId())
            ->where('key', 'pos_terminal')
            ->first();

        $config = $row !== null ? (array) json_decode((string) $row->config, true) : [];

        // Preset kataloğu (marka + kategori + doküman linki + hangi adaptör) — UI listeler.
        $presets = [];
        foreach ((array) config('payments.preset_catalog', []) as $key => $meta) {
            $presets[] = ['key' => $key, 'provider' => (string) config("payments.presets.$key.provider", 'generic_rest')] + (array) $meta;
        }

        return response()->json([
            'catalog' => (array) config('payments.catalog', []),
            'presets' => $presets,
            'categories' => [
                'okc' => 'Yeni Nesil ÖKC / YN-POS cihazı',
                'bank' => 'Banka Sanal POS',
                'psp' => 'Ödeme Kuruluşu',
                'other' => 'Diğer / Genel',
            ],
            'default_provider' => (string) config('payments.default_terminal_provider', 'mock'),
            'enabled' => $row !== null ? (bool) $row->is_enabled : false,
            'config' => $this->mask($config),
        ]);
    }

    /** İşletmenin POS yapılandırmasını kaydeder (sırlar birleştirilir, silinmez). */
    public function update(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('settings.manage'), 403);

        $data = $request->validate([
            'enabled' => ['required', 'boolean'],
            'provider' => ['required', 'string', 'max:40'],
            'config' => ['array'],
        ]);

        if (! $this->registry->has($data['provider'])) {
            return response()->json(['message' => 'Bilinmeyen ödeme sağlayıcısı: '.$data['provider']], 422);
        }

        $tenantId = (int) $this->tenants->tenantId();

        // Mevcut sırları koru: gelen config'te maskeli (••••) alanlar eskisini EZMESİN.
        $existing = DB::table('tenant_integrations')
            ->where('tenant_id', $tenantId)->where('key', 'pos_terminal')->first();
        $old = $existing !== null ? (array) json_decode((string) $existing->config, true) : [];

        $incoming = (array) ($data['config'] ?? []);
        $incoming['provider'] = $data['provider'];
        $merged = $this->preserveSecrets($old, $incoming);

        DB::table('tenant_integrations')->updateOrInsert(
            ['tenant_id' => $tenantId, 'key' => 'pos_terminal'],
            [
                'is_enabled' => (bool) $data['enabled'],
                'config' => json_encode($merged, JSON_UNESCAPED_UNICODE),
                'updated_at' => now(),
                'created_at' => $existing->created_at ?? now(),
            ],
        );

        $this->resolver->flush();

        return response()->json(['ok' => true, 'config' => $this->mask($merged)]);
    }

    /** Yapılandırılan sağlayıcıda terminal erişilebilirlik testi. */
    public function test(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('settings.manage'), 403);

        $key = $this->resolver->providerKey() ?? (string) config('payments.default_terminal_provider', 'mock');

        if (! $this->registry->has($key)) {
            return response()->json(['online' => false, 'message' => 'Sağlayıcı yapılandırılmadı.'], 422);
        }

        $terminalId = $request->string('terminal_id')->toString() ?: null;
        $status = $this->registry->get($key)->getTerminalStatus($terminalId);

        return response()->json([
            'provider' => $key,
            'online' => $status->online,
            'terminal_id' => $status->terminalId,
            'message' => $status->message,
        ]);
    }

    /**
     * Sır alanlarını maskeler (secret/password/api_key/token) — değer varsa "••••".
     *
     * @param  array<string, mixed>  $config
     * @return array<string, mixed>
     */
    private function mask(array $config): array
    {
        foreach ($config as $key => $value) {
            if (is_array($value)) {
                $config[$key] = $this->mask($value);
            } elseif ($this->isSecretKey((string) $key) && is_string($value) && $value !== '') {
                $config[$key] = '••••';
            }
        }

        return $config;
    }

    /**
     * Gelen config'teki maskeli (••••) sır alanları eski gerçek değeri korur.
     *
     * @param  array<string, mixed>  $old
     * @param  array<string, mixed>  $incoming
     * @return array<string, mixed>
     */
    private function preserveSecrets(array $old, array $incoming): array
    {
        foreach ($incoming as $key => $value) {
            if (is_array($value) && isset($old[$key]) && is_array($old[$key])) {
                $incoming[$key] = $this->preserveSecrets($old[$key], $value);
            } elseif ($value === '••••' && array_key_exists($key, $old)) {
                $incoming[$key] = $old[$key];
            }
        }

        return $incoming;
    }

    private function isSecretKey(string $key): bool
    {
        $k = strtolower($key);

        foreach (['secret', 'password', 'api_key', 'apikey', 'token'] as $needle) {
            if (str_contains($k, $needle)) {
                return true;
            }
        }

        return false;
    }
}
