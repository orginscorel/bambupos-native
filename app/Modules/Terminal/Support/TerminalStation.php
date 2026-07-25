<?php

namespace App\Modules\Terminal\Support;

/**
 * Terminal istasyon kataloğu (§13, Faz A).
 *
 * Üç kilitli terminal türü. Her biri:
 *  - screen: kilitli modda AÇILACAK tek ekran (rota koruması bunu zorlar).
 *  - permissions: gizli terminal kullanıcısına verilecek İZİNLER (yalnız o
 *    istasyonun ihtiyacı — mutfak/barista sadece kds.view, komi ayrıca
 *    kds.deliver). PARA izni YOK (KDS para görmez).
 *  - stationKeys: kds_user_stations'a atanacak istasyon anahtar(lar)ı —
 *    istasyon-kapsamı bu sayede çalışır (komi = tümü → atama YOK).
 *
 * Sipariş-giriş/POS terminali Faz B'de eklenecektir (PIN + kasa/adisyon).
 */
final class TerminalStation
{
    public const KITCHEN = 'kitchen';

    public const BARISTA = 'barista';

    public const KOMI = 'komi';

    /**
     * @return array<string, array{label: string, screen: string, permissions: array<int, string>, stationKeys: array<int, string>}>
     */
    public static function all(): array
    {
        return [
            self::KITCHEN => [
                'label' => 'Mutfak',
                'screen' => '/panel/mutfak',
                'permissions' => ['kds.view'],
                'stationKeys' => ['kitchen'],
            ],
            self::BARISTA => [
                'label' => 'Barista',
                'screen' => '/panel/barista',
                'permissions' => ['kds.view'],
                'stationKeys' => ['barista'],
            ],
            self::KOMI => [
                'label' => 'Komi',
                'screen' => '/panel/komi',
                // Komi teslim eder + hazır kalemleri görür (runner ekranı).
                'permissions' => ['kds.deliver', 'kds.view'],
                'stationKeys' => [], // hepsi (istasyon süzmez)
            ],
        ];
    }

    public static function isValid(string $station): bool
    {
        return array_key_exists($station, self::all());
    }

    /** Kilitli modda açılacak ekran yolu (geçersiz istasyonda panel köküne). */
    public static function screenFor(?string $station): string
    {
        return self::all()[$station]['screen'] ?? '/panel';
    }

    public static function labelFor(?string $station): string
    {
        return self::all()[$station]['label'] ?? (string) $station;
    }

    /** @return array<int, string> */
    public static function permissionsFor(string $station): array
    {
        return self::all()[$station]['permissions'] ?? [];
    }

    /** @return array<int, string> */
    public static function stationKeysFor(string $station): array
    {
        return self::all()[$station]['stationKeys'] ?? [];
    }

    /** BaseSelect / validation için istasyon seçenekleri. */
    public static function options(): array
    {
        $out = [];

        foreach (self::all() as $key => $meta) {
            $out[] = ['value' => $key, 'label' => $meta['label']];
        }

        return $out;
    }
}
