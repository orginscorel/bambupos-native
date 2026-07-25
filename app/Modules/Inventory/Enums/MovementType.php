<?php

namespace App\Modules\Inventory\Enums;

/**
 * Hareket defteri satır türleri (§17.4 — TAM liste).
 *
 * direction(): satırın izin verdiği işaret (+1 giriş, -1 çıkış, 0 her ikisi).
 * allowsNegative(): sonuç stoğu eksiye düşürebilir mi?
 *   - Satış/reçete/ikram tüketimi EKSİYE DÜŞEBİLİR: mutfak servis akışı
 *     stok kaydı eksik diye DURDURULMAZ; eksi stok uyarı panosuna düşer.
 *   - Manuel/fire/zayi/transfer çıkışları eksiye düşemez (veri disiplini).
 */
enum MovementType: string
{
    case Purchase = 'purchase';                     // alış (mal kabul)
    case Sale = 'sale';                             // satış tüketimi (reçetesiz doğrudan)
    case PurchaseReturn = 'purchase_return';        // tedarikçiye iade
    case Waste = 'waste';                           // fire
    case Loss = 'loss';                             // zayi
    case CountAdjust = 'count_adjust';              // sayım farkı
    case TransferOut = 'transfer_out';              // transfer çıkış
    case TransferIn = 'transfer_in';                // transfer giriş
    case Production = 'production';                 // üretim (yarı mamul girişi)
    case RecipeConsumption = 'recipe_consumption';  // reçete tüketimi (satıştan)
    case ManualAdjust = 'manual_adjust';            // manuel düzeltme
    case CompConsumption = 'comp_consumption';      // ikram tüketimi

    public function direction(): int
    {
        return match ($this) {
            self::Purchase, self::TransferIn, self::Production => 1,
            self::CountAdjust, self::ManualAdjust => 0,
            default => -1,
        };
    }

    public function allowsNegative(): bool
    {
        return in_array($this, [self::Sale, self::RecipeConsumption, self::CompConsumption], true);
    }

    /** Manuel hareket girişinde seçilebilir türler. */
    public function isManual(): bool
    {
        return in_array($this, [
            self::Purchase, self::Sale, self::PurchaseReturn, self::Waste,
            self::Loss, self::ManualAdjust, self::Production,
        ], true);
    }

    public function label(): string
    {
        return match ($this) {
            self::Purchase => 'Alış',
            self::Sale => 'Satış tüketimi',
            self::PurchaseReturn => 'Tedarikçi iadesi',
            self::Waste => 'Fire',
            self::Loss => 'Zayi',
            self::CountAdjust => 'Sayım farkı',
            self::TransferOut => 'Transfer çıkış',
            self::TransferIn => 'Transfer giriş',
            self::Production => 'Üretim',
            self::RecipeConsumption => 'Reçete tüketimi',
            self::ManualAdjust => 'Manuel düzeltme',
            self::CompConsumption => 'İkram tüketimi',
        };
    }

    public function variant(): string
    {
        return match ($this) {
            self::Purchase, self::TransferIn, self::Production => 'success',
            self::Waste, self::Loss, self::PurchaseReturn => 'danger',
            self::CountAdjust, self::ManualAdjust => 'warning',
            default => 'info',
        };
    }

    /** @return array<int, array{value: string, label: string, variant: string, direction: int, manual: bool}> */
    public static function options(): array
    {
        return array_map(fn (self $t) => [
            'value' => $t->value,
            'label' => $t->label(),
            'variant' => $t->variant(),
            'direction' => $t->direction(),
            'manual' => $t->isManual(),
        ], self::cases());
    }
}
