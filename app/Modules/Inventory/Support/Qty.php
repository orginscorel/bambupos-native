<?php

namespace App\Modules\Inventory\Support;

/**
 * Miktar yardımcıları — paranın kuruş-int kuralının (ADR-007) miktar ikizi.
 * Tüm miktarlar ANA BİRİM × 1000 tamsayıdır ("milli"); float sürüklenmez.
 * Yuvarlama TEK yerde ve half-up'tır.
 */
final class Qty
{
    /** "1,5" / "1.5" (ana birim) → 1500 milli. Geçersiz girdi null. */
    public static function parseToMilli(string|int|float|null $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }

        if (is_int($value)) {
            return $value * 1000;
        }

        $normalized = str_replace(' ', '', (string) $value);

        if (str_contains($normalized, ',')) {
            $normalized = str_replace('.', '', $normalized);
            $normalized = str_replace(',', '.', $normalized);
        }

        if (! is_numeric($normalized)) {
            return null;
        }

        return self::roundHalfUp((float) $normalized * 1000);
    }

    /** Alt birim miktarı → ana birim milli. (160 g, faktör 1000 → 160 milli-kg) */
    public static function subToMilli(int|float $subQty, int $factor): int
    {
        if ($factor <= 0) {
            $factor = 1;
        }

        return self::roundHalfUp($subQty * 1000 / $factor);
    }

    /** Yüzde uygula (fire): 160 milli %5 → 168 milli. */
    public static function withPercent(int $qtyMilli, float $percent): int
    {
        if ($percent <= 0) {
            return $qtyMilli;
        }

        return self::roundHalfUp($qtyMilli * (1 + $percent / 100));
    }

    /** Maliyet: milli miktar × (kuruş / ana birim) → kuruş. */
    public static function cost(int $qtyMilli, int $unitCostMinor): int
    {
        return self::roundHalfUp(abs($qtyMilli) * $unitCostMinor / 1000);
    }

    /** 1500 → "1,5" (birim adı görüntü katmanının işi). */
    public static function toDecimalString(int $milli): string
    {
        $value = $milli / 1000;
        $formatted = number_format($value, 3, ',', '.');

        return rtrim(rtrim($formatted, '0'), ',');
    }

    private static function roundHalfUp(float $value): int
    {
        return (int) round($value, 0, PHP_ROUND_HALF_UP);
    }
}
