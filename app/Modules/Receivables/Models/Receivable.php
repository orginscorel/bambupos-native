<?php

namespace App\Modules\Receivables\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Identity\Models\User;
use App\Modules\Orders\Models\Order;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Database\Factories\ReceivableFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Cari hesap (Borçlar modülü). `balance_minor` HER ZAMAN >= 0 (kuruş —
 * ADR-007) ve receivable_transactions defterinin toplamına EŞİTTİR — tek
 * doğruluk kaynağı defterdir, `balance_minor` yalnız hızlı okuma için
 * ÖNBELLEKtir; tüm mutasyonlar ReceivableService'te (transaction + kilit).
 */
class Receivable extends Model
{
    /** @use HasFactory<ReceivableFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $fillable = [
        'branch_id',
        'name',
        'phone',
        'email',
        'note',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'balance_minor' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by_id');
    }

    public function transactions(): HasMany
    {
        return $this->hasMany(ReceivableTransaction::class)->orderByDesc('id');
    }

    /** Bu cariye borca taşınmış adisyonlar. */
    public function orders(): HasMany
    {
        return $this->hasMany(Order::class, 'debt_receivable_id');
    }

    protected static function newFactory(): Factory
    {
        return ReceivableFactory::new();
    }
}
