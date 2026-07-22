<?php

namespace App\Modules\Catalog\Support;

/**
 * Kuruş-integer para yardımcıları (ADR-007).
 * Yuvarlama TEK yerde ve half-up'tır; dağınık round() yasak.
 */
final class Money
{
    /** "125,50" / "125.50" / "125" → 12550 kuruş. Geçersiz girdi null. */
    public static function parseToMinor(string|int|float|null $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }

        if (is_int($value)) {
            return $value * 100;
        }

        $normalized = str_replace(' ', '', (string) $value);

        // TR biçimi: binlik "." + ondalık "," → önce binlikleri at, sonra virgülü noktaya çevir
        if (str_contains($normalized, ',')) {
            $normalized = str_replace('.', '', $normalized);
            $normalized = str_replace(',', '.', $normalized);
        }

        if (! is_numeric($normalized)) {
            return null;
        }

        return self::roundHalfUp((float) $normalized * 100);
    }

    /** KDV DAHİL brüt tutardan KDV payı (kuruş). rate: yüzde (ör. 10.0). */
    public static function vatPortionOfGross(int $grossMinor, float $rate): int
    {
        if ($rate <= 0) {
            return 0;
        }

        return $grossMinor - self::netFromGross($grossMinor, $rate);
    }

    /** KDV DAHİL brüt tutardan net (KDV hariç) tutar (kuruş). */
    public static function netFromGross(int $grossMinor, float $rate): int
    {
        if ($rate <= 0) {
            return $grossMinor;
        }

        return self::roundHalfUp($grossMinor / (1 + $rate / 100));
    }

    /** Net (KDV hariç) tutara KDV ekle → brüt (kuruş). */
    public static function grossFromNet(int $netMinor, float $rate): int
    {
        if ($rate <= 0) {
            return $netMinor;
        }

        return self::roundHalfUp($netMinor * (1 + $rate / 100));
    }

    /** Yüzde hesabı (ör. indirim): amount × pct% (kuruş, half-up). */
    public static function percent(int $amountMinor, float $pct): int
    {
        return self::roundHalfUp($amountMinor * $pct / 100);
    }

    /** 12550 → "125,50" (₺ işareti görüntü katmanının işi). */
    public static function toDecimalString(int $minor): string
    {
        return number_format($minor / 100, 2, ',', '.');
    }

    /** Tek yuvarlama noktası: half-up. */
    private static function roundHalfUp(float $value): int
    {
        return (int) round($value, 0, PHP_ROUND_HALF_UP);
    }
}
