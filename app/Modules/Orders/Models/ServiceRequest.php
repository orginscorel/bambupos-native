<?php

namespace App\Modules\Orders\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Masadan servis talebi (garson çağır / hesap iste / su iste). */
class ServiceRequest extends Model
{
    use BelongsToTenant;

    public const KINDS = ['waiter', 'bill', 'water'];

    protected $fillable = [
        'kind',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'handled_at' => 'datetime',
        ];
    }

    public function kindLabel(): string
    {
        return match ($this->kind) {
            'waiter' => 'Garson çağırıyor',
            'bill' => 'Hesap istiyor',
            'water' => 'Su istiyor',
            default => (string) $this->kind,
        };
    }

    public function kindIcon(): string
    {
        return match ($this->kind) {
            'waiter' => 'bell',
            'bill' => 'cart',
            'water' => 'inbox',
            default => 'bell',
        };
    }

    public function table(): BelongsTo
    {
        return $this->belongsTo(Table::class);
    }

    public function handledBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'handled_by_id');
    }
}
