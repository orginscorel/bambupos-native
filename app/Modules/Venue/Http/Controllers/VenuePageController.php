<?php

namespace App\Modules\Venue\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Venue\Enums\AreaType;
use App\Modules\Venue\Enums\TableShape;
use App\Modules\Venue\Enums\TableStatus;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Panel Inertia sayfaları. Enum sözlükleri (durum/tür/şekil) tek
 * kaynaktan (PHP enum) prop olarak gider; TS tarafında kopya tutulmaz.
 */
class VenuePageController extends Controller
{
    public function tables(): Response
    {
        return Inertia::render('Panel/Venue/Tables', $this->meta());
    }

    public function areas(): Response
    {
        return Inertia::render('Panel/Venue/Areas', $this->meta());
    }

    public function branches(): Response
    {
        return Inertia::render('Panel/Venue/Branches', $this->meta());
    }

    public function qr(): Response
    {
        return Inertia::render('Panel/Venue/Qr', $this->meta());
    }

    /** @return array<string, mixed> */
    private function meta(): array
    {
        return [
            'statuses' => TableStatus::options(),
            'areaTypes' => AreaType::options(),
            'shapes' => TableShape::options(),
        ];
    }
}
