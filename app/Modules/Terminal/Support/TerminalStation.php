<?php

namespace App\Modules\Terminal\Support;

/**
 * Terminal istasyon kataloğu (§13, Faz A + Faz B).
 *
 * Kilitli terminal türleri. Her biri:
 *  - label: panel/rozet etiketi.
 *  - screen: kilitli modda AÇILACAK tek ekran (rota koruması bunu zorlar).
 *  - subpaths: ekranın alt yollarına (örn. adisyon detay) izin verilir mi?
 *    KDS ekranları TEK sayfadır (false); sipariş-giriş adisyon detayına
 *    gitmelidir (/panel/siparisler/{id} → true).
 *  - permissions: gizli terminal kullanıcısına verilecek İZİNLER (yalnız o
 *    istasyonun ihtiyacı). KDS (mutfak/barista/komi) PARA GÖRMEZ. Faz B'nin
 *    kasa/sipariş-giriş terminalleri PARA GÖREBİLİR (kasiyer/adisyon
 *    ekranları); yine de para eylemleri PIN kapısıyla korunur (aşağıya bak).
 *  - stationKeys: kds_user_stations'a atanacak istasyon anahtar(lar)ı —
 *    KDS istasyon-kapsamı bu sayede çalışır (komi = tümü → atama YOK).
 *    Kasa/sipariş-giriş KDS istasyon-kapsamı DIŞINDADIR → [] (atama yok).
 *  - money: bu terminal para/tutar görebilir mi? (KDS hayır; kasa/sipariş evet)
 *
 * Faz B (§13): kasa + sipariş-giriş terminalleri. Hassas eylemler (ödeme al,
 * adisyon iptali, iade, ikram) is_terminal iken PIN ister; eylem PIN sahibi
 * personele atfedilir (bkz. TerminalPinGate). Bu izinler ekranların YÜKlenmesi
 * ve butonların görünmesi içindir; para eylemi yine PIN'e bağlıdır.
 */
final class TerminalStation
{
    public const KITCHEN = 'kitchen';

    public const BARISTA = 'barista';

    public const KOMI = 'komi';

    /** Faz B: kasa terminali (kasiyer ekranı — ödeme/iade/ikram, PIN'li). */
    public const KASA = 'kasa';

    /** Faz B: sipariş-giriş terminali (adisyon aç/ürün ekle + detay eylemleri). */
    public const ORDER_ENTRY = 'order_entry';

    /**
     * @return array<string, array{label: string, screen: string, subpaths: bool, permissions: array<int, string>, stationKeys: array<int, string>, money: bool}>
     */
    public static function all(): array
    {
        return [
            self::KITCHEN => [
                'label' => 'Mutfak',
                'screen' => '/panel/mutfak',
                'subpaths' => false,
                'permissions' => ['kds.view'],
                'stationKeys' => ['kitchen'],
                'money' => false,
            ],
            self::BARISTA => [
                'label' => 'Barista',
                'screen' => '/panel/barista',
                'subpaths' => false,
                'permissions' => ['kds.view'],
                'stationKeys' => ['barista'],
                'money' => false,
            ],
            self::KOMI => [
                'label' => 'Komi',
                'screen' => '/panel/komi',
                'subpaths' => false,
                // Komi teslim eder + hazır kalemleri görür (runner ekranı).
                'permissions' => ['kds.deliver', 'kds.view'],
                'stationKeys' => [], // hepsi (istasyon süzmez)
                'money' => false,
            ],
            self::KASA => [
                'label' => 'Kasa',
                'screen' => '/panel/kasa',
                'subpaths' => false, // kasa TEK ekrandır (yönetim/Z ayrı yetki)
                // Kasiyer ekranı: ödeme alma + bekleyen adisyonlar; ayrıca iade
                // (payments.refund) ve ikram/iptal (orders.comp/cancel/refund)
                // butonlarının GÖRÜNMESİ için — eylem PIN'le personele atfedilir.
                'permissions' => [
                    'payments.take', 'payments.refund', 'cash.view',
                    'orders.view', 'orders.comp', 'orders.cancel', 'orders.refund',
                ],
                'stationKeys' => [], // KDS istasyon-kapsamı DIŞI
                'money' => true,
            ],
            self::ORDER_ENTRY => [
                'label' => 'Sipariş Girişi',
                'screen' => '/panel/siparisler',
                'subpaths' => true, // adisyon detay: /panel/siparisler/{id}
                // Adisyon aç + ürün ekle/güncelle (rutin, PIN'siz). Hassas
                // eylemler (iptal/ikram/iade/ödeme) Detay'da durum-bazlı görünür;
                // backend is_terminal iken PIN ister → yetki PIN sahibinde.
                'permissions' => ['orders.view', 'orders.create', 'orders.update'],
                'stationKeys' => [], // KDS istasyon-kapsamı DIŞI
                'money' => true,
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

    /** Ekranın alt yollarına (adisyon detay vb.) izin verilir mi? */
    public static function allowsSubpaths(?string $station): bool
    {
        return (bool) (self::all()[$station]['subpaths'] ?? false);
    }

    /** Bu terminal para/tutar görebilir mi? (KDS hayır; kasa/sipariş evet) */
    public static function showsMoney(?string $station): bool
    {
        return (bool) (self::all()[$station]['money'] ?? false);
    }

    /** Geçerli istasyon anahtarları (store/update validasyonu için). */
    public static function keys(): array
    {
        return array_keys(self::all());
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
