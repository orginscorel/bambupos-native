<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Personel-Yetki ajanı: Inertia panel sayfaları.
 * Veri istemci tarafında /api/v1 uçlarından yüklenir (Katalog deseni).
 */
class StaffPageController extends Controller
{
    /** /panel/personel — personel listesi */
    public function index(Request $request): Response
    {
        $this->authorize('viewAny', User::class);

        return Inertia::render('Panel/Staff/Index');
    }

    /** /panel/personel/roller — rol yönetimi + yetki matrisi */
    public function roles(Request $request): Response
    {
        $this->authorize('viewAny', Role::class);

        return Inertia::render('Panel/Staff/Roles');
    }
}
