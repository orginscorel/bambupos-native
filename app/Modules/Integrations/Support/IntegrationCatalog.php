<?php

declare(strict_types=1);

namespace App\Modules\Integrations\Support;

/**
 * Takılabilir entegrasyonların TEK katalog kaynağı — çerçeve + iskelet.
 *
 * Buradaki her anahtar, yöneticinin "Entegrasyonlar" ekranından aç/kapa
 * yapıp yapılandırabildiği bir DIŞ sistem bağlantısıdır (ödeme, teslimat
 * platformu, e-fatura, muhasebe). Bu katalog GERÇEK sağlayıcı çağrısı
 * İÇERMEZ; yalnız çerçevenin bileşim/yapılandırma sözleşmesini tanımlar.
 * Sistemin geri kalanı bir entegrasyonun açık olup olmadığını Integrations
 * cephesine sorar; AKTİFSE uyum sağlar, PASİFSE (varsayılan) çerçeve sessizdir.
 *
 * Yeni entegrasyon = buraya tek giriş (key + ad + kategori + açıklama +
 * config_fields). Yeni tablo/kod gerekmez.
 *
 * config_fields[].secret = true olan alanlar API'de MASKELİ döner ve panelde
 * password input olarak sunulur; boş gönderilirse mevcut değer korunur.
 */
final class IntegrationCatalog
{
    /**
     * @return list<array{
     *     key: string,
     *     name: string,
     *     category: string,
     *     description: string,
     *     config_fields: list<array{key: string, label: string, secret?: bool}>
     * }>
     */
    public static function all(): array
    {
        return [
            /* ----------------------------- Ödeme ----------------------------- */
            [
                'key' => 'iyzico',
                'name' => 'iyzico',
                'category' => 'payment',
                'description' => 'Online kart tahsilatı (iyzico sanal POS). Aktifken ödeme akışına iyzico seçeneği eklenir.',
                'config_fields' => [
                    ['key' => 'api_key', 'label' => 'API Anahtarı', 'secret' => true],
                    ['key' => 'secret_key', 'label' => 'Gizli Anahtar (Secret)', 'secret' => true],
                    ['key' => 'sandbox', 'label' => 'Test Ortamı (sandbox: 1/0)'],
                ],
            ],
            [
                'key' => 'paytr',
                'name' => 'PayTR',
                'category' => 'payment',
                'description' => 'Online kart tahsilatı (PayTR iFrame). Aktifken ödeme akışına PayTR seçeneği eklenir.',
                'config_fields' => [
                    ['key' => 'merchant_id', 'label' => 'Mağaza No (Merchant ID)'],
                    ['key' => 'merchant_key', 'label' => 'Mağaza Anahtarı', 'secret' => true],
                    ['key' => 'merchant_salt', 'label' => 'Mağaza Salt', 'secret' => true],
                ],
            ],

            /* ----------------------- Teslimat platformu ---------------------- */
            [
                'key' => 'yemeksepeti',
                'name' => 'Yemeksepeti',
                'category' => 'delivery',
                'description' => 'Yemeksepeti siparişlerini otomatik panele düşürür ve durum senkronu yapar.',
                'config_fields' => [
                    ['key' => 'vendor_id', 'label' => 'Restoran (Vendor) Kodu'],
                    ['key' => 'api_key', 'label' => 'API Anahtarı', 'secret' => true],
                ],
            ],
            [
                'key' => 'getir',
                'name' => 'Getir Yemek',
                'category' => 'delivery',
                'description' => 'Getir Yemek siparişleri + durum senkronu. Aktifken gelen siparişler panele akar.',
                'config_fields' => [
                    ['key' => 'restaurant_id', 'label' => 'Restoran Kodu'],
                    ['key' => 'app_secret', 'label' => 'Uygulama Gizli Anahtarı', 'secret' => true],
                ],
            ],
            [
                'key' => 'trendyol',
                'name' => 'Trendyol Yemek',
                'category' => 'delivery',
                'description' => 'Trendyol Yemek sipariş akışı ve durum güncellemeleri.',
                'config_fields' => [
                    ['key' => 'supplier_id', 'label' => 'Satıcı (Supplier) ID'],
                    ['key' => 'api_key', 'label' => 'API Anahtarı', 'secret' => true],
                    ['key' => 'api_secret', 'label' => 'API Gizli Anahtarı', 'secret' => true],
                ],
            ],

            /* ------------------------- E-fatura ------------------------------ */
            [
                'key' => 'efatura',
                'name' => 'e-Fatura / e-Arşiv',
                'category' => 'invoice',
                'description' => 'GİB uyumlu elektronik fatura/arşiv kesimi. Aktifken kapatılan adisyona e-belge üretilebilir.',
                'config_fields' => [
                    ['key' => 'integrator', 'label' => 'Entegratör (ör. foriba/mikro)'],
                    ['key' => 'username', 'label' => 'Kullanıcı Adı'],
                    ['key' => 'password', 'label' => 'Parola', 'secret' => true],
                ],
            ],

            /* ------------------------- Muhasebe ------------------------------ */
            [
                'key' => 'parasut',
                'name' => 'Paraşüt',
                'category' => 'accounting',
                'description' => 'Satış/tahsilat kayıtlarını Paraşüt muhasebe yazılımına aktarır.',
                'config_fields' => [
                    ['key' => 'company_id', 'label' => 'Firma (Company) ID'],
                    ['key' => 'client_id', 'label' => 'İstemci (Client) ID'],
                    ['key' => 'client_secret', 'label' => 'İstemci Gizli Anahtarı', 'secret' => true],
                ],
            ],
        ];
    }

    /** @return list<string> */
    public static function keys(): array
    {
        return array_map(static fn (array $i): string => $i['key'], self::all());
    }

    public static function isKnown(string $key): bool
    {
        return in_array($key, self::keys(), true);
    }

    /**
     * Tek entegrasyonun katalog tanımı (yoksa null).
     *
     * @return array{key: string, name: string, category: string, description: string, config_fields: list<array{key: string, label: string, secret?: bool}>}|null
     */
    public static function find(string $key): ?array
    {
        foreach (self::all() as $integration) {
            if ($integration['key'] === $key) {
                return $integration;
            }
        }

        return null;
    }

    /**
     * Bir entegrasyonun config alan anahtarları (bilinmeyen key → boş).
     *
     * @return list<string>
     */
    public static function fieldKeys(string $key): array
    {
        $integration = self::find($key);

        if ($integration === null) {
            return [];
        }

        return array_map(static fn (array $f): string => $f['key'], $integration['config_fields']);
    }

    /**
     * Bir entegrasyonun GİZLİ (maskelenecek) config alan anahtarları.
     *
     * @return list<string>
     */
    public static function secretFieldKeys(string $key): array
    {
        $integration = self::find($key);

        if ($integration === null) {
            return [];
        }

        $secrets = [];

        foreach ($integration['config_fields'] as $field) {
            if (($field['secret'] ?? false) === true) {
                $secrets[] = $field['key'];
            }
        }

        return $secrets;
    }
}
