import { computed } from 'vue';
import { usePage } from '@inertiajs/vue3';

/**
 * İzin okuma yardımcısı (arayüz gizleme).
 *
 * Kaynak: Inertia paylaşılan `auth.permissions` (HandleInertiaRequests →
 * User::permissionKeys). İzinler TAM AÇILMIŞ gelir (Sahip/Müdür 'all'
 * şablonu tüm katalog anahtarlarına genişletilir) → burada wildcard'a gerek
 * yoktur; yine de savunma amaçlı `*` (tümü) desteklenir.
 *
 * ÖNEMLİ: Bu yalnız ARAYÜZ gizlemesidir; gerçek koruma backend
 * policy/authorize + hasPermission'dadır (ADR-004). Buton gizlemek
 * yetkisiz kullanıcının 403 almasını değiştirmez.
 *
 * `permissions` prop'u YOKSA (henüz auth yüklenmemiş) — PanelLayout nav
 * süzgeciyle aynı konvansiyon: süzme yapılmaz (true döner).
 */
export function usePermissions() {
    const page = usePage();

    const permissions = computed<string[] | null>(() => {
        const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
        return auth?.permissions ?? null;
    });

    /** Tek izin anahtarı kontrolü (ör. `can('tables.create')`). */
    function can(key: string): boolean {
        const perms = permissions.value;
        if (perms === null) return true; // auth yok → süzme yok (nav ile aynı)
        return perms.includes('*') || perms.includes(key);
    }

    /** Verilen anahtarlardan EN AZ BİRİ varsa true. */
    function canAny(...keys: string[]): boolean {
        return keys.some((k) => can(k));
    }

    return { can, canAny, permissions };
}

/** Kısa yol: tekil `can()` gereken yerlerde. */
export function can(key: string): boolean {
    return usePermissions().can(key);
}
