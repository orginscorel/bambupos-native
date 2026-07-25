<?php

namespace App\Modules\Shifts\Http\Controllers;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Shifts modülü Inertia sayfaları. Veri istemci tarafında /api/v1/shifts
 * uçlarından yüklenir (Katalog/Personel deseni).
 *
 * Erişim: her personel KENDİ vardiya/mesai verisini görür; başkalarını
 * görmek staff.view, yönetmek staff.manage ister (uçlarda denetlenir).
 */
class ShiftPageController extends Controller
{
    /** /panel/vardiya — vardiya takvimi (haftalık/aylık, sürükle-bırak) */
    public function schedule(): Response
    {
        return Inertia::render('Panel/Shifts/Schedule');
    }

    /** /panel/mesai — personel mesai kayıtları */
    public function timeEntries(): Response
    {
        return Inertia::render('Panel/Shifts/TimeEntries');
    }

    /** /panel/mesai/giris-cikis — PIN ile giriş/çıkış (kiosk) */
    public function clock(): Response
    {
        return Inertia::render('Panel/Shifts/Clock');
    }

    /** /panel/mesai/izinler — izin/rapor/devamsızlık */
    public function leaves(): Response
    {
        return Inertia::render('Panel/Shifts/Leaves');
    }

    /** /panel/mesai/talepler — onay bekleyen talepler (yönetici) */
    public function approvals(Request $request): Response
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        return Inertia::render('Panel/Shifts/Approvals');
    }

    /** /panel/mesai/performans — personel performans özeti */
    public function performance(Request $request): Response
    {
        abort_unless(
            $request->user()->hasPermission('staff.view') || $request->user()->hasPermission('staff.manage'),
            403,
        );

        return Inertia::render('Panel/Shifts/Performance');
    }

    /** /panel/mesai/ayarlar — mesai ayarları + KVKK + cihazlar (yönetici) */
    public function settings(Request $request): Response
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        return Inertia::render('Panel/Shifts/Settings');
    }
}
