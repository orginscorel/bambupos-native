<?php

namespace App\Modules\Identity\Support;

use App\Modules\Identity\Models\User;

/**
 * Role özel açılış ekranı (Personel-Yetki).
 *
 * Sıra:
 *  1. Kullanıcı tercihi (users.default_screen) — hâlâ İZİNLİYSE uygulanır.
 *  2. Otomatik: iş profiline göre en uygun ekran
 *     (mutfak → KDS, komi → komi, kasiyer → kasa, garson → sipariş,
 *      yönetici → panel genel bakış).
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

        // Yönetici işaretleri: genel bakış en faydalısı
        if ($can('reports.view') || $can('staff.manage') || $can('settings.manage')) {
            return 'dashboard';
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

    /** @param  array{permission?: string|null}  $screen */
    private static function allowed(User $user, array $screen): bool
    {
        $permission = $screen['permission'] ?? null;

        return $permission === null || $user->hasPermission($permission);
    }
}
