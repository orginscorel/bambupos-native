<?php

namespace App\Modules\Orders\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Support\Totp;
use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Enums\ServiceType;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Database\Factories\OrderFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Sipariş / adisyon (Faz-3; Faz-1 iskeletinden genişletildi).
 *
 * - Tutarlar kuruş-integer (ADR-007); döküm alanları OrderService'te TEK
 *   yerden hesaplanır (recomputeTotals).
 * - `status` DB'de string tutulur (Faz-1'in 'open' gibi eski değerleri model
 *   yüklemesini patlatmasın); enum erişimi statusEnum() ile.
 * - `version`: optimistic locking (prompt §12.4) — her mutasyonda artar.
 * - Tüm mutasyonlar OrderService üzerinden yapılır (transaction + satır kilidi).
 */
class Order extends Model
{
    /** @use HasFactory<OrderFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $fillable = [
        'status',
        'total_minor',
        'currency',
        'channel',
        'service_type',
        'guest_count',
        'note',
        'customer_name',
        'customer_phone',
    ];

    protected function casts(): array
    {
        return [
            'total_minor' => 'integer',
            'items_total_minor' => 'integer',
            'discount_minor' => 'integer',
            'discount_percent' => 'decimal:2',
            'comp_total_minor' => 'integer',
            'vat_total_minor' => 'integer',
            'service_charge_minor' => 'integer',
            'service_charge_percent' => 'decimal:2',
            'rounding_minor' => 'integer',
            'paid_minor' => 'integer',
            'refunded_minor' => 'integer',
            'version' => 'integer',
            'guest_count' => 'integer',
            'placed_at' => 'datetime',
            'closed_at' => 'datetime',
            'cancelled_at' => 'datetime',
            // Adisyon-Cari (§ Borçlar): tek-adisyon kuralı + borca taşıma.
            'is_split_child' => 'boolean',
            'debt_amount_minor' => 'integer',
            'debt_transferred_at' => 'datetime',
        ];
    }

    /** Eski/bilinmeyen değerler (Faz-1 'open') Placed'e eşlenir. */
    public function statusEnum(): OrderStatus
    {
        return OrderStatus::tryFrom((string) $this->status) ?? OrderStatus::Placed;
    }

    public function channelEnum(): OrderChannel
    {
        return OrderChannel::tryFrom((string) $this->channel) ?? OrderChannel::Table;
    }

    /**
     * Yapısal servis tipi (masada/gel-al/paket). Eski/boş kayıtlar kanaldan
     * makul biçimde türetilir (dine_in varsayılan) — tek kaynak burasıdır.
     */
    public function serviceTypeEnum(): ServiceType
    {
        return ServiceType::tryFrom((string) $this->service_type)
            ?? ServiceType::fromChannel($this->channelEnum());
    }

    public function isOpen(): bool
    {
        return $this->statusEnum()->isOpen();
    }

    /**
     * Operasyonel olarak henüz ekranda kalması gereken siparişler:
     *   - açık adisyonlar (bugüne kadarki davranış), VEYA
     *   - ÖN-ÖDEMELİ (paid) ama kalemleri henüz TESLİM EDİLMEMİŞ siparişler
     *     (kiosk POS akışı: ödeme başta alınır, sipariş 'paid' olur ama
     *     mutfak/komi'de teslim edilene kadar Board+KDS'te görünmeli).
     *
     * 'paid' dalı `whereHas` ile SINIRLIDIR (yalnız mutfak-hattında kalemi
     * olan paid siparişler) → geçmiş tüm paid siparişleri taramaz.
     *
     * @param  \Illuminate\Database\Eloquent\Builder<Order>  $query
     */
    public function scopeOperationallyVisible($query)
    {
        return $query->where(function ($q): void {
            $q->whereNotIn('status', OrderStatus::closedValues())
                ->orWhere(function ($paid): void {
                    $paid->where('status', OrderStatus::Paid->value)
                        ->whereHas('items', fn ($iq) => $iq->whereIn('status', [
                            'placed', 'sent_to_station', 'accepted', 'preparing', 'ready',
                        ]));
                });
        });
    }

    /** QR müşterisinin durum takibi için opak referans (ADR-008 deseni). */
    public static function generatePublicToken(): string
    {
        return substr(Totp::base32Encode(random_bytes(16)), 0, 26);
    }

    public function items(): HasMany
    {
        return $this->hasMany(OrderItem::class)->orderBy('id');
    }

    public function events(): HasMany
    {
        return $this->hasMany(OrderEvent::class)->orderByDesc('id');
    }

    public function table(): BelongsTo
    {
        return $this->belongsTo(Table::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function openedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'opened_by_id');
    }

    /** Borca taşındıysa (statusEnum()===DebtTransferred) atandığı cari. */
    public function debtReceivable(): BelongsTo
    {
        return $this->belongsTo(\App\Modules\Receivables\Models\Receivable::class, 'debt_receivable_id');
    }

    protected static function newFactory(): Factory
    {
        return OrderFactory::new();
    }
}
