<?php

namespace App\Modules\Shifts\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/**
 * İşletme başına mesai ayarları (tek satır / kiracı).
 * KVKK: location_tracking_enabled VARSAYILAN false — konum takibi ancak
 * işletme bunu açar VE personel açık rıza verirse çalışır.
 */
class ShiftSetting extends Model
{
    use Auditable, BelongsToTenant;

    protected $fillable = [
        'standard_daily_min',
        'late_tolerance_min',
        'early_leave_tolerance_min',
        'default_break_min',
        'location_tracking_enabled',
        'location_policy',
    ];

    protected function casts(): array
    {
        return [
            'standard_daily_min' => 'integer',
            'late_tolerance_min' => 'integer',
            'early_leave_tolerance_min' => 'integer',
            'default_break_min' => 'integer',
            'location_tracking_enabled' => 'boolean',
        ];
    }

    /** Bağlamdaki kiracının ayarları (yoksa varsayılanlarla oluşturur). */
    public static function current(): self
    {
        return static::query()->firstOrCreate([]);
    }
}
