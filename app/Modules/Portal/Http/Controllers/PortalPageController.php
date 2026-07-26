<?php

namespace App\Modules\Portal\Http\Controllers;

use App\Http\Controllers\Controller;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Personel Portalı Inertia sayfaları (mobil-öncelikli PWA).
 *
 * Bölümler: Mesaim · Raporlarım · Profilim (Görevlerim ileride).
 * Ortak paylaşılan `auth` prop'u (HandleInertiaRequests) portal layout'unca
 * da kullanılır; PanelShell KULLANILMAZ (kendi sade layout'u).
 */
class PortalPageController extends Controller
{
    public function shift(): Response
    {
        return Inertia::render('Portal/Shift');
    }

    public function reports(): Response
    {
        return Inertia::render('Portal/Reports');
    }

    public function profile(): Response
    {
        return Inertia::render('Portal/Profile');
    }
}
