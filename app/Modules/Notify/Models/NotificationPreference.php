<?php

namespace App\Modules\Notify\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Kişi-bazlı bildirim tercihi (§8): kullanıcı × olay tipi → in_app / push.
 * Satır YOKSA katalog varsayılanı (NotificationType::default*) geçerlidir.
 */
class NotificationPreference extends Model
{
    use BelongsToTenant;

    protected $table = 'notification_preferences';

    protected $fillable = ['user_id', 'type', 'in_app', 'push'];

    protected function casts(): array
    {
        return [
            'in_app' => 'boolean',
            'push' => 'boolean',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
