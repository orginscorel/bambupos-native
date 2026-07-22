<?php

namespace App\Modules\Kds\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Personel-istasyon ataması: ataması OLAN kullanıcı KDS'de yalnız kendi
 * istasyonlarını görür/işaretler (KdsService sunucu tarafında zorlar).
 */
class UserStation extends Model
{
    use BelongsToTenant;

    protected $table = 'kds_user_stations';

    protected $fillable = ['user_id', 'station_key'];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
