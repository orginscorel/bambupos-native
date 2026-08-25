<?php

namespace App\Modules\Payments\Enums;

/**
 * Kasa hareketi türleri (prompt §16). Her tür SABİT bir yöne sahiptir;
 * düzeltme yalnız `Correction` (ters kayıt) ile yapılır.
 */
enum CashMovementType: string
{
    case OpeningFloat = 'opening_float'; // açılış kasası (in)
    case Payment = 'payment';            // nakit tahsilat (in)
    case Refund = 'refund';              // nakit iade (out)
    case CashIn = 'cash_in';             // nakit giriş (in)
    case CashOut = 'cash_out';           // nakit çıkış (out)
    case Expense = 'expense';            // masraf (out)
    case Advance = 'advance';            // avans (out)
    case Correction = 'correction';      // ters kayıt (yönü ters çevrilen kaydın tersi)
    case ReceivableCollection = 'receivable_collection'; // cari (borç) NAKİT tahsilatı (in)

    public function direction(): string
    {
        return match ($this) {
            self::OpeningFloat, self::Payment, self::CashIn, self::ReceivableCollection => 'in',
            self::Refund, self::CashOut, self::Expense, self::Advance => 'out',
            self::Correction => 'in', // gerçek yön ters kayıtta hesaplanır
        };
    }

    /** Kullanıcının elle ekleyebileceği türler (payment/refund sistem üretir). */
    public static function manualTypes(): array
    {
        return [self::CashIn, self::CashOut, self::Expense, self::Advance];
    }

    public function label(): string
    {
        return match ($this) {
            self::OpeningFloat => 'Açılış kasası',
            self::Payment => 'Nakit tahsilat',
            self::Refund => 'Nakit iade',
            self::CashIn => 'Nakit giriş',
            self::CashOut => 'Nakit çıkış',
            self::Expense => 'Masraf',
            self::Advance => 'Avans',
            self::Correction => 'Düzeltme (ters kayıt)',
            self::ReceivableCollection => 'Cari tahsilat',
        };
    }

    /** @return array<int, array{value: string, label: string, direction: string}> */
    public static function manualOptions(): array
    {
        return array_map(fn (self $t) => [
            'value' => $t->value,
            'label' => $t->label(),
            'direction' => $t->direction(),
        ], self::manualTypes());
    }
}
