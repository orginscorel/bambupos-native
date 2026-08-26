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
    // "Yönetim Kokpiti" / "Patron Paneli" operasyon panelinde YOK — patron
    // AYRI bir uygulamadır, kendi subdomain'inden (patron.*) girilir.

    // ===== Operasyon (canlı vardiya) =====
    { key: 'orders', label: 'Siparişler', icon: 'orders', href: '/panel/siparisler', permission: 'orders.view', group: 'Operasyon', mobile: true },
    { key: 'tables', label: 'Masalar', icon: 'qr-code', href: '/panel/masalar', permission: 'tables.view', group: 'Operasyon', mobile: true },
    { key: 'cashier', label: 'Kasa', icon: 'cart', href: '/panel/kasa', permission: 'payments.take', group: 'Operasyon', mobile: true },
    { key: 'kds', label: 'Mutfak', icon: 'chef-hat', href: '/panel/mutfak', permission: 'kds.view', stations: ['kitchen'], group: 'Operasyon', mobile: true },
    { key: 'barista', label: 'Barista', icon: 'coffee', href: '/panel/barista', permission: 'kds.view', stations: ['barista'], group: 'Operasyon' },
    { key: 'nargile', label: 'Nargile', icon: 'nargile', href: '/panel/nargile', permission: 'kds.view', stations: ['hookah'], feature: 'nargile', group: 'Operasyon' },
    { key: 'runner', label: 'Komi', icon: 'bell', href: '/panel/komi', permission: 'kds.deliver', group: 'Operasyon' },
    { key: 'delivery', label: 'Teslimat', icon: 'truck', href: '/panel/teslimat', permission: 'delivery.view', feature: 'delivery', group: 'Operasyon' },

    // ===== Menü & Rezervasyon =====
    { key: 'catalog', label: 'Menü', icon: 'utensils', href: '/panel/menu', permission: 'catalog.view', group: 'Menü & Rezervasyon' },
    { key: 'reservations', label: 'Rezervasyonlar', icon: 'calendar', href: '/panel/rezervasyonlar', permission: 'reservations.view', feature: 'reservations', group: 'Menü & Rezervasyon' },

    // ===== Stok & Finans =====
    { key: 'inventory', label: 'Depo / Stok', icon: 'package', href: '/panel/stok', permission: 'stock.view', feature: 'inventory', group: 'Stok & Finans' },
    { key: 'receivables', label: 'Borçlar', icon: 'inbox', href: '/panel/borclar', permission: 'receivables.view', feature: 'receivables', group: 'Stok & Finans' },
    { key: 'commission', label: 'Prim / Komisyon', icon: 'wallet', href: '/panel/prim', permission: 'commission.view', feature: 'commission', group: 'Stok & Finans' },
    { key: 'discounts', label: 'İndirim Tanımları', icon: 'tag', href: '/panel/ayarlar/indirimler', permission: 'orders.discount', group: 'Stok & Finans' },
    { key: 'reports', label: 'Raporlar', icon: 'chart', href: '/panel/raporlar', permission: 'reports.view', group: 'Stok & Finans' },

    // ===== Personel & Yönetim =====
    { key: 'staff', label: 'Personel', icon: 'users', href: '/panel/personel', permission: 'staff.view', group: 'Personel & Yönetim' },
    { key: 'tasks', label: 'Görevler', icon: 'clipboard', href: '/panel/gorevler', permission: 'tasks.view', group: 'Personel & Yönetim' },
    { key: 'shifts', label: 'Vardiya', icon: 'clock', href: '/panel/vardiya', permission: 'staff.view', feature: 'shifts', group: 'Personel & Yönetim' },
    { key: 'branches', label: 'Şubeler', icon: 'store', href: '/panel/subeler', permission: 'branches.view', group: 'Personel & Yönetim' },

    // ===== Cihazlar & Entegrasyonlar =====
    { key: 'kiosk', label: 'Kiosk', icon: 'monitor', href: '/panel/kiosklar', permission: 'kiosk.view', feature: 'kiosk', group: 'Cihazlar & Entegrasyonlar' },
    { key: 'terminals', label: 'Terminaller', icon: 'tablet', href: '/panel/terminaller', permission: 'terminals.view', feature: 'terminals', group: 'Cihazlar & Entegrasyonlar' },
    { key: 'printers', label: 'Cihazlar & Yazıcılar', icon: 'plug', href: '/panel/ayarlar/cihazlar', permission: 'settings.view', group: 'Cihazlar & Entegrasyonlar' },
    { key: 'devices', label: 'İzinli Cihazlar', icon: 'monitor', href: '/panel/izinli-cihazlar', permission: 'devices.view', group: 'Cihazlar & Entegrasyonlar' },
    { key: 'integrations', label: 'Entegrasyonlar', icon: 'plug', href: '/panel/entegrasyonlar', permission: 'integrations.manage', group: 'Cihazlar & Entegrasyonlar' },

    // ===== Sistem =====
    // 'Hesabım' sidebar'dan kaldırıldı (2026-07-23) — Profil'e avatar menüsünden ulaşılır.
    { key: 'settings', label: 'Ayarlar', icon: 'settings', href: '/panel/ayarlar/e-posta', permission: 'settings.view', group: 'Sistem' },
    { key: 'wiki', label: 'Nasıl Çalışır', icon: 'info', href: '/panel/nasil-calisir', group: 'Sistem' },
    { key: 'changelog', label: 'Sürüm Notları', icon: 'tag', href: '/panel/surum-notlari', group: 'Sistem' },
];
