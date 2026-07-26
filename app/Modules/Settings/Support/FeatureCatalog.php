<?php

namespace App\Modules\Settings\Support;

/**
 * OPSİYONEL özelliklerin (feature-flag) TEK katalog kaynağı — MODULE_MAP §9.
 *
 * Buradaki her anahtar yöneticinin "Eklentiler" ekranında aç/kapa yapabildiği
 * bir modül/davranıştır. **Çekirdek** (siparişler, masalar, kasa, menü,
 * personel, raporlar) BİLİNÇLİ olarak burada YOKTUR → kapatılamaz.
 *
 * Yeni opsiyonel özellik = buraya tek satır (key + ad + açıklama + varsayılan).
 * Varsayılanlar makul: mevcut davranışı bozmamak için temel/opsiyonel
 * özellikler AÇIK gelir; işletme istemezse kapatır.
 */
final class FeatureCatalog
{
    /**
     * @return list<array{key: string, name: string, description: string, default: bool}>
     */
    public static function all(): array
    {
        return [
            [
                'key' => 'branches',
                'name' => 'Çok şube',
                'description' => 'Birden çok şube/tesis yönetimi ve üst çubukta şube değiştirici. Kapalıyken sistem tek-şube modunda çalışır (yeni şube eklenemez, şube seçici gizlenir).',
                'default' => true,
            ],
            [
                'key' => 'kiosk',
                'name' => 'Kiosk (self-servis)',
                'description' => 'Müşterinin dokunmatik ekrandan kendi siparişini verdiği tam-ekran kiosk cihazları ve panel yönetimi.',
                'default' => true,
            ],
            [
                'key' => 'reservations',
                'name' => 'Rezervasyon',
                'description' => 'Masa rezervasyonu takvimi, bekleme listesi ve QR ile rezervasyon talebi.',
                'default' => true,
            ],
            [
                'key' => 'qr_ordering',
                'name' => 'QR menüden sipariş',
                'description' => 'Müşteri masadaki QR menüden doğrudan sipariş verebilir. Kapalıyken menü yalnız görüntülenir, sipariş alınmaz.',
                'default' => true,
            ],
            [
                'key' => 'service_calls',
                'name' => 'Garson / su / hesap çağır',
                'description' => 'QR menüde müşterinin garson çağırma, su isteme ve hesap isteme butonları.',
                'default' => true,
            ],
            [
                'key' => 'inventory',
                'name' => 'Depo / Stok',
                'description' => 'Reçete bazlı otomatik stok düşümü, mal kabul, sayım, tedarikçi ve stok raporları.',
                'default' => true,
            ],
            [
                'key' => 'shifts',
                'name' => 'Vardiya / Mesai',
                'description' => 'Vardiya planlama, mesai takibi (giriş-çıkış), izin ve devam raporları.',
                'default' => true,
            ],
            [
                'key' => 'receivables',
                'name' => 'Borçlar / Cari',
                'description' => 'Cari hesaplar ve açık adisyonu borca (veresiye) taşıma.',
                'default' => true,
            ],
            [
                'key' => 'terminals',
                'name' => 'İstasyon terminalleri',
                'description' => 'Cihaza-bağlı kilitli istasyon terminalleri (Mutfak/Barista/Komi/Kasa/Sipariş-giriş).',
                'default' => true,
            ],
        ];
    }

    /** @return list<string> */
    public static function keys(): array
    {
        return array_map(static fn (array $f): string => $f['key'], self::all());
    }

    public static function isKnown(string $key): bool
    {
        return in_array($key, self::keys(), true);
    }

    /** Bilinmeyen anahtar için varsayılan true (fail-open: yeni yüzey görünür kalır). */
    public static function default(string $key): bool
    {
        foreach (self::all() as $feature) {
            if ($feature['key'] === $key) {
                return $feature['default'];
            }
        }

        return true;
    }

    /**
     * Tüm anahtarların varsayılan durumu.
     *
     * @return array<string, bool>
     */
    public static function defaults(): array
    {
        $out = [];

        foreach (self::all() as $feature) {
            $out[$feature['key']] = $feature['default'];
        }

        return $out;
    }
}
