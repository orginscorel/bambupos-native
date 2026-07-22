<?php

namespace App\Modules\Tables\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Identity\Support\Totp;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Database\Factories\TableFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * Masa. qr_token: ADR-008 — random_bytes(16) → base32, 26 karakter,
 * global benzersiz, rotasyonla anında geçersiz kılınabilir.
 */
class Table extends Model
{
    /** @use HasFactory<TableFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $table = 'tables';

    protected $fillable = [
        'name',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (self $table): void {
            $table->qr_token ??= self::generateQrToken();
        });
    }

    public static function generateQrToken(): string
    {
        return substr(Totp::base32Encode(random_bytes(16)), 0, 26);
    }

    public function rotateQrToken(): void
    {
        $this->qr_token = self::generateQrToken();
        $this->save();
    }

    protected static function newFactory(): Factory
    {
        return TableFactory::new();
    }
}
