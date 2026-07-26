<?php

namespace App\Modules\Notify\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Panel-içi bildirim / zil kaydı (§8). Alıcı = user_id. Kalıcı; okunmuş
 * bildirim de listede bir süre görünür (bell_list_limit). Şube kapsamlı.
 */
class Notification extends Model
{
    use BelongsToTenant;

    protected $table = 'notifications';

    protected $fillable = [
        'branch_id', 'user_id', 'type', 'title', 'body', 'data', 'dedup_key', 'read_at',
    ];

    protected function casts(): array
    {
        return [
            'data' => 'array',
            'read_at' => 'datetime',
        ];
    }

    public function typeEnum(): ?NotificationType
    {
        return NotificationType::tryFrom((string) $this->type);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function isRead(): bool
    {
        return $this->read_at !== null;
    }
}
