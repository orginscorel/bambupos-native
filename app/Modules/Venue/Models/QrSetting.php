<?php

namespace App\Modules\Venue\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/** QR çıktı şablonu — kiracı başına tek satır. */
class QrSetting extends Model
{
    use Auditable, BelongsToTenant;

    protected $table = 'venue_qr_settings';

    protected $fillable = [
        'header_text',
        'description',
        'color',
        'bg_color',
        'frame',
        'show_table_no',
    ];

    protected function casts(): array
    {
        return [
            'show_table_no' => 'boolean',
        ];
    }

    /** Kiracının şablonu (yoksa kaydedilmemiş varsayılan örnek). */
    public static function forCurrentTenant(): self
    {
        return static::query()->first() ?? new self;
    }
}
