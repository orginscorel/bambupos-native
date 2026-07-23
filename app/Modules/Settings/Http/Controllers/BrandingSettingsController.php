<?php

namespace App\Modules\Settings\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Settings\Services\TenantLogoService;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

/**
 * Panelden işletme / marka ayarları: logo yükleme + kaldırma.
 *
 * Yetki: settings.manage. Kiracı izolasyonu: uçlar KENDİ kiracısından
 * başkasına asla dokunmaz (id parametresi yok, route binding yok) —
 * kiracı her zaman oturumdaki kullanıcının tenant_id'sidir.
 *
 * Cache: public menü sayfası kiracı tag'iyle (t{id}) tam-sayfa
 * cache'lidir (ADR-011). Logo değişince yanıtla birlikte
 * X-LiteSpeed-Purge gönderilir → menü anında yeni logoyu gösterir.
 * Logo dosyasının adı her yüklemede rastgele değişir (doğal ?v=).
 */
class BrandingSettingsController extends Controller
{
    public function __construct(
        private readonly TenantLogoService $logos,
        private readonly AuditLogger $audit,
    ) {
    }

    public function show(Request $request): JsonResponse
    {
        $tenant = $this->tenantOf($this->authorizeManage($request));

        return response()->json(['branding' => $this->dto($tenant)]);
    }

    public function uploadLogo(Request $request): JsonResponse
    {
        $tenant = $this->tenantOf($this->authorizeManage($request));

        $request->validate([
            'logo' => ['required', 'file', 'max:2048'], // asıl içerik doğrulaması serviste (finfo + getimagesize)
        ]);

        $old = $tenant->logo_path;
        $path = $this->logos->store($tenant, $request->file('logo'));

        $this->audit->log('settings.branding.logo_updated', $tenant,
            ['logo_path' => $old], ['logo_path' => $path], (int) $tenant->getKey());

        return $this->purging($tenant, response()->json(['branding' => $this->dto($tenant)], 201));
    }

    public function destroyLogo(Request $request): JsonResponse
    {
        $tenant = $this->tenantOf($this->authorizeManage($request));

        $old = $tenant->logo_path;
        $this->logos->delete($tenant);

        if ($old !== null) {
            $this->audit->log('settings.branding.logo_removed', $tenant,
                ['logo_path' => $old], null, (int) $tenant->getKey());
        }

        return $this->purging($tenant, response()->json(['branding' => $this->dto($tenant)]));
    }

    /** @return array{name: string, logo_url: string|null} */
    private function dto(Tenant $tenant): array
    {
        return [
            'name' => (string) $tenant->name,
            'logo_url' => $tenant->logo_path !== null
                ? Storage::disk('public')->url($tenant->logo_path)
                : null,
        ];
    }

    /** ADR-011: bu kiracının tam-sayfa menü cache'ini tag ile düşür. */
    private function purging(Tenant $tenant, JsonResponse $response): JsonResponse
    {
        return $response->header('X-LiteSpeed-Purge', 'tag=t'.$tenant->getKey());
    }

    private function authorizeManage(Request $request): User
    {
        /** @var User $user */
        $user = $request->user();
        abort_unless($user->hasPermission('settings.manage'), 403);

        return $user;
    }

    private function tenantOf(User $user): Tenant
    {
        return Tenant::query()->findOrFail((int) $user->tenant_id);
    }
}
