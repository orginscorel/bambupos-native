<?php

namespace App\Modules\Tables\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Identity\Support\Totp;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Venue\Enums\TableStatus;
use App\Modules\Venue\Models\Area;
use Database\Factories\TableFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Masa. qr_token: ADR-008 — random_bytes(16) → base32, 26 karakter,
 * global benzersiz, rotasyonla anında geçersiz kılınabilir.
 *
 * Faz-2 (Venue): masa no / alan / kapasite / şekil / durum /
 * birleştirilebilirlik + rotasyon izi (previous_qr_token → 410).
 * Kiracılık omurgası (tenant_id/branch_id/qr_token) değişmedi.
 */
class Table extends Model
{
    /** @use HasFactory<TableFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $table = 'tables';

    protected $fillable = [
        'name',
        'number',
        'capacity',
        'shape',
        'status',
        'is_joinable',
        'notes',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'number' => 'integer',
            'capacity' => 'integer',
            'status' => TableStatus::class,
            'is_joinable' => 'boolean',
            'is_active' => 'boolean',
            'qr_rotated_at' => 'datetime',
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

    /** ADR-008: eski token anında geçersiz; 410 sayfası için iz bırakılır. */
    public function rotateQrToken(): void
    {
        $this->previous_qr_token = $this->qr_token;
        $this->qr_token = self::generateQrToken();
        $this->qr_rotated_at = now();
        $this->save();
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function area(): BelongsTo
    {
        return $this->belongsTo(Area::class, 'area_id');
    }

    /** Public menü adresi (QR içeriği — ADR-008: URL'de yalnız opak token). */
    public function menuUrl(): string
    {
        return rtrim((string) config('app.url'), '/').'/m/'.$this->qr_token;
    }

    protected static function newFactory(): Factory
    {
        return TableFactory::new();
    }
}
