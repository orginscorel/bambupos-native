<?php

namespace App\Modules\Payments\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Support\Totp;
use App\Modules\Orders\Models\Order;
use App\Modules\Payments\Enums\PaymentMethod;
use App\Modules\Payments\Enums\PaymentStatus;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Ödeme kaydı — TEK DOĞRULUK KAYNAĞI (ADR-010).
 *
 * - `orders.paid_minor` / `refunded_minor` bu tablodan türetilir; tüm
 *   mutasyonlar PaymentService üzerinden (transaction + kilit + sürüm).
 * - PARA ALANLARI OLUŞTURULDUKTAN SONRA DEĞİŞMEZ (updating guard'ı):
 *   tutar/yöntem/sipariş sonradan sessizce değiştirilemez; düzeltme
 *   void + yeni ödeme ya da iade kaydıyla yapılır.
 */
class Payment extends Model
{
    use BelongsToTenant;

    /** Oluşturulduktan sonra ASLA değişemeyecek kolonlar. */
    private const IMMUTABLE = [
        'tenant_id', 'branch_id', 'order_id', 'reference', 'kind', 'refund_of_id',
        'amount_minor', 'method', 'currency', 'tendered_minor', 'change_minor',
    ];

    protected $fillable = [
        'kind', 'method', 'status', 'amount_minor', 'tip_minor',
        'tendered_minor', 'change_minor', 'currency', 'provider',
        'provider_txn_id', 'terminal_id', 'reason', 'note', 'meta',
    ];

    protected function casts(): array
    {
        return [
            'amount_minor' => 'integer',
            'tip_minor' => 'integer',
            'tendered_minor' => 'integer',
            'change_minor' => 'integer',
            'suspect' => 'boolean',
            'meta' => 'array',
            'paid_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::updating(function (Payment $payment): void {
            $forbidden = array_intersect(array_keys($payment->getDirty()), self::IMMUTABLE);

            if ($forbidden !== []) {
                throw new \LogicException(
                    'Ödeme kaydının para alanları değiştirilemez ('.implode(', ', $forbidden).'); void/iade kullanın.'
                );
            }
        });

        static::deleting(function (): void {
            throw new \LogicException('Ödeme kaydı silinemez; void/iade kullanın.');
        });
    }

    public function statusEnum(): PaymentStatus
    {
        return PaymentStatus::tryFrom((string) $this->status) ?? PaymentStatus::Pending;
    }

    public function methodEnum(): PaymentMethod
    {
        return PaymentMethod::tryFrom((string) $this->method) ?? PaymentMethod::Cash;
    }

    public static function generateReference(): string
    {
        return substr(Totp::base32Encode(random_bytes(16)), 0, 26);
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function cashier(): BelongsTo
    {
        return $this->belongsTo(User::class, 'cashier_id');
    }

    public function session(): BelongsTo
    {
        return $this->belongsTo(CashSession::class, 'cash_session_id');
    }

    public function refundOf(): BelongsTo
    {
        return $this->belongsTo(self::class, 'refund_of_id');
    }

    public function refunds(): HasMany
    {
        return $this->hasMany(self::class, 'refund_of_id');
    }

    /** Bu ödemenin başarıyla iade edilmiş toplamı (kuruş). */
    public function refundedTotalMinor(): int
    {
        return (int) $this->refunds()
            ->where('kind', 'refund')
            ->whereIn('status', [PaymentStatus::Succeeded->value])
            ->sum('amount_minor');
    }
}
