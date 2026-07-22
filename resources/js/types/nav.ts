/** Panel navigasyon öğesi. Rol bazlı menü için `permission` alanı hazır:
 *  Çekirdek-Kimlik ajanı sayfa prop'larıyla izin listesini sağladığında
 *  PanelLayout `can` süzgeciyle öğeleri gizler. */
export interface NavItem {
    key: string;
    label: string;
    /** AppIcon adı */
    icon: string;
    href: string;
    /** Gerekli izin anahtarı (ör. "orders.view"); boşsa herkes görür */
    permission?: string;
    /** Rozet sayısı (ör. bekleyen sipariş) */
    badge?: number;
    /** Mobil alt navigasyonda gösterilsin mi (en fazla 4 öğe önerilir) */
    mobile?: boolean;
}
