<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\ValidationException;

/**
 * Personel taklidi (impersonation) — "test için giriş yap".
 *
 * Yönetici, bir personelin oturumuna geçip o kişinin gördüğü ekran/yetkiyi
 * bire bir test edebilir. Oturum-tabanlıdır (migration YOK): asıl yöneticinin
 * kimliği `impersonator_id` olarak session'da tutulur; "Yöneticiye dön" ile
 * geri alınır.
 *
 * Güvenlik:
 *  - Yalnız `staff.manage` iznine sahip aktör başlatabilir.
 *  - Kendini taklit edemez; pasif personel taklit edilemez.
 *  - Daha yüksek/eşit yetkiliyi taklit engeli: hedef sistem rolü (ör. Sahip)
 *    taşıyorsa VEYA `staff.manage` iznine sahipse reddedilir. Bu sayede taklit
 *    edilen oturum ASLA personel/rol yönetimi gibi hassas eylemleri yapamaz.
 *  - Aynı kiracı (route binding kiracı süzgeci uygular → yabancı personel 404).
 *  - İç içe taklit yasak (zaten taklitteyken yeni taklit başlatılamaz).
 *  - Denetim kaydı (AuditLogger) başlat/bitir olaylarını yazar.
 */
class ImpersonationController extends Controller
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    /** Taklidi başlat: aktörün oturumunu hedef personele geçirir. */
    public function start(Request $request, User $staff): JsonResponse
    {
        /** @var User $actor */
        $actor = $request->user();

        if (! $actor->hasPermission('staff.manage')) {
            abort(403);
        }

        if ($request->session()->has('impersonator_id')) {
            throw ValidationException::withMessages([
                'staff' => ['Zaten bir personeli görüntülüyorsunuz. Önce yöneticiye dönün.'],
            ])->status(409);
        }

        if ($actor->is($staff)) {
            throw ValidationException::withMessages([
                'staff' => ['Kendinizi taklit edemezsiniz.'],
            ])->status(403);
        }

        if (! $staff->is_active) {
            throw ValidationException::withMessages([
                'staff' => ['Pasif (işten çıkmış) personel için test girişi yapılamaz.'],
            ])->status(422);
        }

        if ($this->holdsSystemRole($staff) || $staff->hasPermission('staff.manage')) {
            throw ValidationException::withMessages([
                'staff' => ['Bu personel en az sizin kadar yetkili; test için giriş yapılamaz.'],
            ])->status(403);
        }

        $this->audit->log('staff.impersonation_started', $staff, null, [
            'impersonator_id' => $actor->getKey(),
        ]);

        Auth::guard('web')->login($staff);
        $request->session()->regenerate();
        // Oturum kimliği yenilendikten SONRA yaz: asıl yöneticiye dönebilmek için.
        $request->session()->put('impersonator_id', $actor->getKey());

        return response()->json(['ok' => true, 'redirect_to' => '/panel']);
    }

    /** Taklidi bitir: asıl yönetici oturumuna geri döner. */
    public function stop(Request $request): JsonResponse
    {
        $impersonatorId = $request->session()->get('impersonator_id');

        if ($impersonatorId === null) {
            throw ValidationException::withMessages([
                'staff' => ['Aktif bir test oturumu yok.'],
            ])->status(409);
        }

        $current = $request->user();
        $original = User::query()->find($impersonatorId);

        // Asıl yönetici artık yoksa/pasifse ya da farklı kiracıya kaymışsa:
        // güvenli düşüş — oturumu tamamen kapat.
        if ($original === null
            || ! $original->is_active
            || ($current !== null && (int) $original->tenant_id !== (int) $current->tenant_id)) {
            Auth::guard('web')->logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();

            return response()->json(['ok' => true, 'redirect_to' => '/giris']);
        }

        Auth::guard('web')->login($original);
        $request->session()->regenerate();
        $request->session()->forget('impersonator_id');

        $this->audit->log('staff.impersonation_stopped', $current, null, [
            'impersonator_id' => $original->getKey(),
        ]);

        return response()->json(['ok' => true, 'redirect_to' => '/panel/personel']);
    }

    private function holdsSystemRole(User $staff): bool
    {
        return $staff->roles()
            ->withoutGlobalScope(\App\Modules\Tenancy\Scopes\TenantScope::class)
            ->where('roles.tenant_id', $staff->tenant_id)
            ->where('roles.is_system', true)
            ->exists();
    }
}
