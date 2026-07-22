import type { NavItem } from '@/types/nav';

/**
 * Varsayılan panel menüsü (iskelet). İçerik ve izin anahtarları
 * modül ajanları tarafından doldurulacak; yapı buradan değişmez.
 * Not: çok kiracılı SaaS — burada işletmeye özel hiçbir ad/marka olmaz.
 */
export const defaultNavigation: NavItem[] = [
    { key: 'dashboard', label: 'Panel', icon: 'dashboard', href: '/panel', mobile: true },
    { key: 'orders', label: 'Siparişler', icon: 'orders', href: '/panel/siparisler', permission: 'orders.view', mobile: true },
    { key: 'catalog', label: 'Menü', icon: 'utensils', href: '/panel/menu', permission: 'catalog.view', mobile: true },
    { key: 'tables', label: 'Masalar', icon: 'qr-code', href: '/panel/masalar', permission: 'tables.view', mobile: true },
    { key: 'kds', label: 'Mutfak (KDS)', icon: 'chef-hat', href: '/panel/mutfak', permission: 'kds.view' },
    { key: 'reports', label: 'Raporlar', icon: 'chart', href: '/panel/raporlar', permission: 'reports.view' },
    { key: 'staff', label: 'Personel', icon: 'users', href: '/panel/personel', permission: 'staff.view' },
    { key: 'settings', label: 'Ayarlar', icon: 'settings', href: '/panel/ayarlar', permission: 'settings.view' },
];
