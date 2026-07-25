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
/*
 * Sıralama = operasyon akışı: önce canlı vardiya ekranları (sipariş/masa/kasa/
 * mutfak/barista/komi), sonra kurulum (menü/rezervasyon), sonra stok-finans
 * (depo/borç/rapor), sonra yönetim (personel/vardiya/şube/kiosk/ayar), en sonda
 * yardım (nasıl çalışır/sürüm). İKONLAR BİRBİRİNDEN FARKLI olmalı (her modül
 * ayrı glif) — yinelenen ikon kullanma.
 */
export const defaultNavigation: NavItem[] = [
    { key: 'dashboard', label: 'Panel', icon: 'dashboard', href: '/panel', exact: true, mobile: true },
    // --- Operasyon (canlı vardiya) ---
    { key: 'orders', label: 'Siparişler', icon: 'orders', href: '/panel/siparisler', permission: 'orders.view', mobile: true },
    { key: 'tables', label: 'Masalar', icon: 'qr-code', href: '/panel/masalar', permission: 'tables.view', mobile: true },
    { key: 'cashier', label: 'Kasa', icon: 'cart', href: '/panel/kasa', permission: 'payments.take', mobile: true },
    { key: 'kds', label: 'Mutfak', icon: 'chef-hat', href: '/panel/mutfak', permission: 'kds.view', stations: ['kitchen'], mobile: true },
    { key: 'barista', label: 'Barista', icon: 'coffee', href: '/panel/barista', permission: 'kds.view', stations: ['barista'] },
    { key: 'runner', label: 'Komi', icon: 'bell', href: '/panel/komi', permission: 'kds.deliver' },
    // --- Kurulum ---
    { key: 'catalog', label: 'Menü', icon: 'utensils', href: '/panel/menu', permission: 'catalog.view' },
    { key: 'reservations', label: 'Rezervasyonlar', icon: 'calendar', href: '/panel/rezervasyonlar', permission: 'reservations.view' },
    // --- Stok & Finans ---
    { key: 'inventory', label: 'Depo / Stok', icon: 'package', href: '/panel/stok', permission: 'stock.view' },
    { key: 'receivables', label: 'Borçlar', icon: 'inbox', href: '/panel/borclar', permission: 'receivables.view' },
    { key: 'reports', label: 'Raporlar', icon: 'chart', href: '/panel/raporlar', permission: 'reports.view' },
    // --- Yönetim ---
    { key: 'staff', label: 'Personel', icon: 'users', href: '/panel/personel', permission: 'staff.view' },
    { key: 'shifts', label: 'Vardiya', icon: 'clock', href: '/panel/vardiya', permission: 'staff.view' },
    { key: 'branches', label: 'Şubeler', icon: 'store', href: '/panel/subeler', permission: 'tables.view' },
    { key: 'kiosk', label: 'Kiosk', icon: 'monitor', href: '/panel/kiosklar', permission: 'kiosk.view' },
    { key: 'terminals', label: 'Terminaller', icon: 'tablet', href: '/panel/terminaller', permission: 'terminals.manage' },
    // 'Hesabım' sidebar'dan kaldırıldı (2026-07-23) — Profil'e avatar menüsünden ulaşılır.
    { key: 'settings', label: 'Ayarlar', icon: 'settings', href: '/panel/ayarlar/e-posta', permission: 'settings.view' },
    // --- Yardım ---
    { key: 'wiki', label: 'Nasıl Çalışır', icon: 'info', href: '/panel/nasil-calisir' },
    // İzin gerektirmez: herkes sürüm notlarını görebilir (alt bilgi rozetleriyle de bağlantılı).
    { key: 'changelog', label: 'Sürüm Notları', icon: 'tag', href: '/panel/surum-notlari' },
];
