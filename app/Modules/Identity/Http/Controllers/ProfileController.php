<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rules\Password as PasswordRule;

/**
 * Kullanıcının KENDİ hesabına dair işlemler (yetki anahtarı gerekmez):
 * parola değiştirme, tema/dil tercihi, aktif şube seçimi.
 * Başkasının hesabına dokunamaz — hedef daima $request->user().
 */
class ProfileController extends Controller
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    /** Kendi parolasını değiştirir (mevcut parola doğrulamalı). */
    public function updatePassword(Request $request): JsonResponse
    {
        $data = $request->validate([
            'current_password' => ['required', 'string', 'current_password:web'],
            'password' => ['required', 'confirmed', PasswordRule::defaults()],
        ]);

        $user = $request->user();
        $user->forceFill(['password' => $data['password']])->save();

        $this->audit->log('auth.password_changed', $user);

        return response()->json(['ok' => true]);
    }

    /** Tema tercihi kalıcılaştırılır (arayüz localStorage + kullanıcı kaydı). */
    public function updatePreferences(Request $request): JsonResponse
    {
        $data = $request->validate([
            'theme' => ['sometimes', 'in:light,dark'],
            'locale' => ['sometimes', 'in:tr'],
            // Açılış ekranı tercihi (null = izinlere göre otomatik)
            'default_screen' => ['sometimes', 'nullable', 'string',
                \Illuminate\Validation\Rule::in(array_keys((array) config('authz.screens', [])))],
        ]);

        $request->user()->forceFill($data)->save();

        return response()->json(['ok' => true]);
    }

    /**
     * Üst çubuktaki şube değiştirici: seçim oturumda tutulur.
     * Branch modeli tenant-scope'lu olduğundan başka kiracının şubesi 404 olur.
     */
    public function setActiveBranch(Request $request): JsonResponse
    {
        $data = $request->validate(['branch_id' => ['required', 'integer']]);

        $branch = Branch::query()
            ->where('is_active', true)
            ->findOrFail($data['branch_id']);

        $request->session()->put('panel.active_branch_id', $branch->getKey());

        return response()->json(['branch' => $branch->only(['id', 'name', 'code'])]);
    }
}
