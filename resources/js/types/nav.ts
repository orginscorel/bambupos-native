/** Panel navigasyon öğesi. Rol bazlı menü için `permission` alanı hazır:
 *  Çekirdek-Kimlik ajanı sayfa prop'larıyla izin listesini sağladığında
 *  PanelLayout `can` süzgeciyle öğeleri gizler. */
export interface NavItem {
    key: string;
    label: string;
    /** AppIcon adı */
    icon: string;
    href: string;
    /** true ise yalnız birebir yol eşleşmesinde aktif sayılır (ör. /panel kökü) */
    exact?: boolean;
    /** Gerekli izin anahtarı (ör. "orders.view"); boşsa herkes görür */
    permission?: string;
    /** §12 İstasyon-kapsamı: öğe yalnız bu istasyon AİLELERİNDEN (kitchen/barista)
     *  en az birine atanmış kullanıcıya görünür. Atanmamış/yönetici (auth.stations
     *  boş) → kısıt yok, hepsini görür. Boşsa istasyon süzgeci uygulanmaz. */
    stations?: string[];
    /** Rozet sayısı (ör. bekleyen sipariş) */
    badge?: number;
    /** Mobil alt navigasyonda gösterilsin mi (en fazla 4 öğe önerilir) */
    mobile?: boolean;
}
