<?php

namespace App\Modules\Kds\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/**
 * İşletmenin KENDİ istasyon tanımı (yerleşikler config/kds.php'de;
 * StationRegistry ikisini birleştirir). `key` ürün kartındaki
 * `products.station` değeriyle eşleşir.
 */
class Station extends Model
{
    use BelongsToTenant;

    protected $table = 'kds_stations';

    protected $fillable = ['key', 'name', 'sort_order', 'is_active'];

    protected function casts(): array
    {
        return [
            'sort_order' => 'integer',
            'is_active' => 'boolean',
        ];
    }
}
