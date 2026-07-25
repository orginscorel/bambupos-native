<?php

namespace App\Modules\Identity\Support;

use App\Modules\Identity\Models\User;
use App\Modules\Kds\Services\KdsService;

/**
 * Role özel açılış ekranı (Personel-Yetki).
 *
 * Sıra:
 *  1. Kullanıcı tercihi (users.default_screen) — hâlâ İZİNLİYSE uygulanır.
 *  2. Otomatik: iş profiline göre en uygun ekran. Önce ATANMIŞ istasyon
 *     (KDS §12 — barista istasyonu → Barista, mutfak istasyonu → KDS),
 *     yoksa role/izinden türetilir (komi → komi, kasiyer → kasa,
 *     garson → sipariş, yönetici → panel genel bakış).
 */
class HomeScreen
{
    /** Kullanıcının açılış ekranı yolu (ör. "/panel/mutfak"). */
    public static function resolve(User $user): string
    {
        $screens = (array) config('authz.screens', []);

        // 1) Açık tercih — izin hâlâ yerindeyse geçerli
        $preferred = $user->default_screen;

        if ($preferred !== null && isset($screens[$preferred]) && self::allowed($user, $screens[$preferred])) {
            return $screens[$preferred]['path'];
        }

        // 2) Otomatik seçim
        $auto = self::autoKey($user);

        if (isset($screens[$auto]) && self::allowed($user, $screens[$auto])) {
            return $screens[$auto]['path'];
        }

        return '/panel';
    }

    /**
     * Kullanıcı "Otomatik" mi (açık, hâlâ izinli bir ekran tercihi YOK)?
     * Dashboard'a doğrudan gelen dar-yetkili personeli kendi ekranına
     * yönlendirmek için kullanılır — açık tercih varsa yönlendirme YAPILMAZ.
     */
    public static function isAutomatic(User $user): bool
    {
        $preferred = $user->default_screen;
        $screens = (array) config('authz.screens', []);

        return ! ($preferred !== null && isset($screens[$preferred]) && self::allowed($user, $screens[$preferred]));
    }

    /**
     * Kullanıcının SEÇEBİLECEĞİ ekranlar (tercih listesi için).
     *
     * @return array<int, array{key: string, label: string, path: string}>
     */
    public static function optionsFor(User $user): array
    {
        $options = [];

        foreach ((array) config('authz.screens', []) as $key => $screen) {
            if (self::allowed($user, $screen)) {
                $options[] = ['key' => $key, 'label' => $screen['label'], 'path' => $screen['path']];
            }
        }

        return $options;
    }

    /** Otomatik profil çıkarımı: dar yetkili roller kendi ekranına düşer. */
    private static function autoKey(User $user): string
    {
        $can = fn (string $key): bool => $user->hasPermission($key);

        // Yönetici işaretleri: genel bakış en faydalısı (istasyon ataması olsa
        // bile yönetimi kendi ekranına zorlamayız).
        if ($can('reports.view') || $can('staff.manage') || $can('settings.manage')) {
            return 'dashboard';
        }

        // Atanmış istasyon önce (KDS §12): kişi kendi istasyon ekranına düşer
        // — barista istasyonu Barista'ya, mutfak/karışık istasyon KDS'ye.
        if ($can('kds.view')) {
            $stationScreen = self::stationScreenKey($user);

            if ($stationScreen !== null) {
                return $stationScreen;
            }
        }

        // Mutfak personeli: yalnız KDS
        if ($can('kds.view') && ! $can('orders.view')) {
            return 'kds';
        }

        // Komi: teslim ekranı
        if ($can('kds.deliver') && ! $can('kds.view') && ! $can('orders.view')) {
            return 'runner';
        }

        // Kasiyer: kasa
        if ($can('payments.take')) {
            return 'cash';
        }

        // Garson: sipariş panosu
        if ($can('orders.create') || $can('orders.view')) {
            return 'orders';
        }

        if ($can('tables.view')) {
            return 'tables';
        }

        if ($can('catalog.view')) {
            return 'catalog';
        }

        return 'dashboard';
    }

    /**
     * Atanmış istasyona göre KDS ekranı anahtarı (null = atama yok / türet).
     * Atanan istasyonların HEPSİ barista ailesindeyse Barista ekranı, aksi
     * halde (yemek ya da karışık) Mutfak ekranı. Boş atama → null.
     */
    private static function stationScreenKey(User $user): ?string
    {
        $stations = app(KdsService::class)->allowedStations($user);

        if ($stations === null || $stations === []) {
            return null;
        }

        $barista = (array) config('authz.barista_stations', []);

        $onlyBarista = array_diff($stations, $barista) === [];

        return $onlyBarista ? 'barista' : 'kds';
    }

    /** @param  array{permission?: string|null}  $screen */
    private static function allowed(User $user, array $screen): bool
    {
        $permission = $screen['permission'] ?? null;

        return $permission === null || $user->hasPermission($permission);
    }
}
