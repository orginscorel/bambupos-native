<?php

namespace App\Modules\Payments\Enums;

/**
 * Ödeme yöntemi (prompt §15). "Terminal" yöntemleri POS adapter'a gider;
 * diğerleri anında (kayıt-onaylı) tahsil edilir.
 */
enum PaymentMethod: string
{
    case Cash = 'cash';                 // nakit
    case CreditCard = 'credit_card';    // kredi kartı (terminal)
    case DebitCard = 'debit_card';      // banka kartı (terminal)
    case MealCard = 'meal_card';        // yemek kartı
    case Transfer = 'transfer';         // havale/EFT
    case Qr = 'qr';                     // QR ödeme
    case Online = 'online';             // online ödeme (sağlayıcı)
    case OnAccount = 'on_account';      // açık hesap (cari)
    case GiftCard = 'gift_card';        // hediye kartı

    /** POS terminaline gitmesi gereken yöntemler (asenkron doğrulama). */
    public function usesTerminal(): bool
    {
        return in_array($this, [self::CreditCard, self::DebitCard], true);
    }

    /** Fiziksel nakit çekmecesini etkiler mi (kasa hareketi üretir)? */
    public function affectsCashDrawer(): bool
    {
        return $this === self::Cash;
    }

    public function label(): string
    {
        return match ($this) {
            self::Cash => 'Nakit',
            self::CreditCard => 'Kredi kartı',
            self::DebitCard => 'Banka kartı',
            self::MealCard => 'Yemek kartı',
            self::Transfer => 'Havale/EFT',
            self::Qr => 'QR ödeme',
            self::Online => 'Online ödeme',
            self::OnAccount => 'Açık hesap',
            self::GiftCard => 'Hediye kartı',
        };
    }

    /** Tasarım sistemi AppIcon adı (mevcut ikon setiyle sınırlı). */
    public function icon(): string
    {
        return match ($this) {
            self::Cash => 'cart',
            self::CreditCard, self::DebitCard => 'dashboard',
            self::MealCard => 'utensils',
            self::Transfer => 'arrow-right',
            self::Qr => 'qr-code',
            self::Online => 'orders',
            self::OnAccount => 'user',
            self::GiftCard => 'inbox',
        };
    }

    /** @return array<int, array{value: string, label: string, icon: string, terminal: bool}> */
    public static function options(): array
    {
        return array_map(fn (self $m) => [
            'value' => $m->value,
            'label' => $m->label(),
            'icon' => $m->icon(),
            'terminal' => $m->usesTerminal(),
        ], self::cases());
    }
}
