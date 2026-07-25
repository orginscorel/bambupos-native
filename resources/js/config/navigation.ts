import type { NavItem } from '@/types/nav';

/**
 * Varsayılan panel menüsü.
 *
 * KURAL: Buraya YALNIZ gerçekten var olan ve çalışan sayfalar eklenir.
 * Henüz yazılmamış bir modülün bağlantısını "ileride olacak" diye koymayın —
 * kullanıcı tıklar ve 404 alır. Modül tamamlandığında satırı ekleyin.
 *
 * (2026-07-22: menüde siparişler/mutfak/raporlar/personel bağlantıları vardı
 * ama karşılık gelen rota yoktu; hepsi 404 veriyordu. Modüller yazıldıkça
 * aşağıdaki "HENÜZ YOK" listesinden buraya taşınacak.)
 *
 * Not: çok kiracılı SaaS — burada işletmeye özel hiçbir ad/marka olmaz.
 *
 * HENÜZ YOK (modül yazılınca ekle):
 *   kds      → /panel/mutfak       permission: kds.view
 *   reports  → /panel/raporlar     permission: reports.view
 */
export const defaultNavigation: NavItem[] = [
    { key: 'dashboard', label: 'Panel', icon: 'dashboard', href: '/panel', exact: true, mobile: true },
    { key: 'orders', label: 'Siparişler', icon: 'orders', href: '/panel/siparisler', permission: 'orders.view', mobile: true },
    { key: 'catalog', label: 'Menü', icon: 'utensils', href: '/panel/menu', permission: 'catalog.view', mobile: true },
    { key: 'tables', label: 'Masalar', icon: 'qr-code', href: '/panel/masalar', permission: 'tables.view', mobile: true },
    { key: 'cashier', label: 'Kasa', icon: 'cart', href: '/panel/kasa', permission: 'payments.take', mobile: true },
    { key: 'receivables', label: 'Borçlar', icon: 'inbox', href: '/panel/borclar', permission: 'receivables.view' },
    { key: 'kds', label: 'Mutfak', icon: 'chef-hat', href: '/panel/mutfak', permission: 'kds.view' },
    { key: 'runner', label: 'Komi', icon: 'utensils', href: '/panel/komi', permission: 'kds.deliver' },
    { key: 'reports', label: 'Raporlar', icon: 'chart', href: '/panel/raporlar', permission: 'reports.view' },
    { key: 'wiki', label: 'Nasıl Çalışır', icon: 'info', href: '/panel/nasil-calisir' },
    { key: 'staff', label: 'Personel', icon: 'users', href: '/panel/personel', permission: 'staff.view' },
    { key: 'branches', label: 'Şubeler', icon: 'store', href: '/panel/subeler', permission: 'tables.view' },
    // 'Hesabım' sidebar'dan kaldırıldı (2026-07-23, kullanıcı talebi) — Profil
    // sayfasına sağ üstteki kullanıcı avatarı menüsünden ulaşılır; /panel/profil
    // rotası KALDI, yalnız bu sidebar kısayolu gitti.
    { key: 'settings', label: 'Ayarlar', icon: 'settings', href: '/panel/ayarlar/e-posta', permission: 'settings.view' },
    { key: 'kiosk', label: 'Kiosk', icon: 'store', href: '/panel/kiosklar', permission: 'kiosk.view' },
    // İzin gerektirmez: herkes sürüm notlarını görebilir (alt bilgi rozetleriyle de bağlantılı).
    { key: 'changelog', label: 'Sürüm Notları', icon: 'info', href: '/panel/surum-notlari' },
];
