<?php

namespace App\Modules\Notify\Enums;

/**
 * §8 Bildirim olay tipleri — TEK KAYNAK katalog.
 *
 * Her tip; etiketi, kategorisi, VARSAYILAN kanalları (in-app / push) ve ALICI
 * YÖNLENDİRME kuralını (hangi izin/istasyon/rol alır) taşır. Dispatcher bu
 * metadatayı okur; Profil "Bildirimler" ekranı ve yönetici politikası da
 * buradan türetilir. Yeni olay = yeni case + burada tanımı.
 *
 * ALICI MODELİ (RecipientResolver):
 *  - targetPermissions(): alıcı bu izinlerden EN AZ BİRİNE sahip olmalı.
 *  - includeManagers(): yöneticiler (reports.view/staff.manage/settings.manage)
 *    her hâlükârda dahildir ("yönetim hepsini görür — kendi şubesi").
 *  - laneScoped(): true ise context['lane'] (kitchen|barista) ile istasyon
 *    ailesine göre süzülür (Mutfak kalemi baristayı, barista kalemi mutfağı
 *    RAHATSIZ ETMEZ; kısıtsız/çok-istasyonlu kullanıcı ikisini de alır).
 *  Tüm alıcılar ŞUBE KAPSAMIYLA süzülür (BranchContext; notifications.branch_id).
 */
enum NotificationType: string
{
    /** Yeni sipariş kuyruğa düştü → o şubenin mutfak/barista personeli. */
    case OrderPlaced = 'order_placed';

    /** Kalem HAZIR, teslim bekliyor → o şubenin komileri. */
    case ItemReady = 'item_ready';

    /** Komi teslim aldı ama süresinde masaya vermedi (§11 SLA) → komi + yönetici. */
    case DeliverySlaBreach = 'delivery_sla_breach';

    /** Sipariş servis edildi → yönetici (varsayılan sessiz). */
    case OrderServed = 'order_served';

    /** Kalem kritik eşiğin altına düştü → depo yetkilisi + yönetici. */
    case LowStock = 'low_stock';

    /** Yaklaşan onaylı rezervasyon → garson/host + yönetici. */
    case ReservationUpcoming = 'reservation_upcoming';

    /** Rezervasyon no-show (gelmedi) → garson/host + yönetici. */
    case ReservationNoShow = 'reservation_no_show';

    /** Masadan servis çağrısı (garson çağır / su / hesap) → o şubenin garsonları + yönetici. */
    case ServiceCall = 'service_call';

    /** Personel mola/tuvalet başlattı ya da bitirdi → yönetici + o an mesaide olanlar. */
    case StaffBreak = 'staff_break';

    /** Bir personele görev atandı → YALNIZ o personel (extra_user_ids). */
    case TaskAssigned = 'task_assigned';

    /** Personel izin talebinde bulundu → yöneticiler (onaylayabilenler). */
    case LeaveRequested = 'leave_requested';

    /** Vardiya başlangıcı yaklaştı (10 dk kala) → YALNIZ o personel. */
    case ShiftReminder = 'shift_reminder';

    /** İzin talebi karara bağlandı (onay/ret/iptal) → YALNIZ talep sahibi. */
    case LeaveDecided = 'leave_decided';

    /** Teslimat kuryeye atandı → YALNIZ o kurye. */
    case DeliveryAssigned = 'delivery_assigned';

    /** Teslimat tamamlandı (kurye teslim etti) → yöneticiler. */
    case DeliveryDelivered = 'delivery_delivered';

    /** Adisyon ödemeye gönderildi (hesap istendi) → KASA + yönetici. */
    case AwaitingPayment = 'awaiting_payment';

    /** Adisyon ödenmeden borca (cari) taşındı → KASA + yönetici. */
    case DebtTransferred = 'debt_transferred';

    /** QR'dan gelen sipariş onay bekliyor → garson + yönetici. */
    case OrderNeedsApproval = 'order_needs_approval';

    public function label(): string
    {
        return match ($this) {
            self::OrderPlaced => 'Yeni sipariş',
            self::ItemReady => 'Sipariş hazır (teslim bekliyor)',
            self::DeliverySlaBreach => 'Teslim gecikmesi (SLA)',
            self::OrderServed => 'Servis edildi',
            self::LowStock => 'Düşük stok uyarısı',
            self::ReservationUpcoming => 'Yaklaşan rezervasyon',
            self::ReservationNoShow => 'Rezervasyon gelmedi (no-show)',
            self::ServiceCall => 'Servis çağrısı',
            self::StaffBreak => 'Personel molası',
            self::TaskAssigned => 'Görev atandı',
            self::LeaveRequested => 'İzin talebi',
            self::ShiftReminder => 'Mesai hatırlatması',
            self::LeaveDecided => 'İzin sonucu',
            self::DeliveryAssigned => 'Teslimat atandı',
            self::DeliveryDelivered => 'Teslimat tamamlandı',
            self::AwaitingPayment => 'Ödeme bekliyor',
            self::DebtTransferred => 'Borca taşındı',
            self::OrderNeedsApproval => 'Sipariş onayı bekliyor',
        };
    }

    /** Profil ekranındaki kısa açıklama. */
    public function description(): string
    {
        return match ($this) {
            self::OrderPlaced => 'Şubene yeni bir sipariş düştüğünde (mutfak/barista).',
            self::ItemReady => 'Bir ürün hazırlanıp teslim beklerken (komi).',
            self::DeliverySlaBreach => 'Teslim alınan ürün süresinde masaya götürülmediğinde.',
            self::OrderServed => 'Bir sipariş masaya servis edildiğinde.',
            self::LowStock => 'Bir stok kalemi kritik eşiğin altına indiğinde.',
            self::ReservationUpcoming => 'Onaylı bir rezervasyonun saati yaklaştığında.',
            self::ReservationNoShow => 'Rezervasyon sahibi gelmediğinde.',
            self::ServiceCall => 'Bir masa QR menüden garson/su/hesap çağırdığında.',
            self::StaffBreak => 'Bir personel molaya/tuvalete çıktığında veya döndüğünde.',
            self::TaskAssigned => 'Size yeni bir görev atandığında.',
            self::LeaveRequested => 'Bir personel izin/rapor talebinde bulunduğunda.',
            self::ShiftReminder => 'Vardiyanızın başlamasına az kaldığında.',
            self::LeaveDecided => 'İzin talebiniz onaylandığında veya reddedildiğinde.',
            self::DeliveryAssigned => 'Size bir paket teslimatı atandığında.',
            self::DeliveryDelivered => 'Bir paket teslimatı tamamlandığında.',
            self::AwaitingPayment => 'Bir adisyon kasaya ödemeye gönderildiğinde.',
            self::DebtTransferred => 'Bir adisyon ödenmeden borca (cari) taşındığında.',
            self::OrderNeedsApproval => 'QR menüden gelen bir sipariş onay beklediğinde.',
        };
    }

    /** Profil ekranında gruplama başlığı. */
    public function category(): string
    {
        return match ($this) {
            self::OrderPlaced, self::OrderServed, self::DeliveryAssigned, self::DeliveryDelivered,
            self::AwaitingPayment, self::DebtTransferred, self::OrderNeedsApproval => 'orders',
            self::ItemReady, self::DeliverySlaBreach => 'kitchen',
            self::LowStock => 'stock',
            self::ReservationUpcoming, self::ReservationNoShow => 'reservations',
            self::ServiceCall => 'service',
            self::StaffBreak, self::TaskAssigned, self::LeaveRequested, self::ShiftReminder, self::LeaveDecided => 'staff',
        };
    }

    public static function categoryLabel(string $category): string
    {
        return match ($category) {
            'orders' => 'Siparişler',
            'kitchen' => 'Mutfak & Teslim',
            'stock' => 'Stok',
            'reservations' => 'Rezervasyonlar',
            'service' => 'Servis çağrıları',
            'staff' => 'Personel',
            default => $category,
        };
    }

    public function defaultInApp(): bool
    {
        // OrderServed dışında hepsi varsayılan açık.
        return $this !== self::OrderServed;
    }

    public function defaultPush(): bool
    {
        // Gürültüyü azaltmak için: yeni-sipariş push varsayılan açık (operasyon
        // kritik); servis-edildi push varsayılan kapalı.
        return $this !== self::OrderServed;
    }

    /** @return array<int, string> alıcı bu izinlerden en az birine sahip olmalı */
    public function targetPermissions(): array
    {
        return match ($this) {
            self::OrderPlaced => ['kds.view'],
            self::ItemReady => ['kds.deliver'],
            self::DeliverySlaBreach => ['kds.deliver'],
            self::OrderServed => ['orders.view'],
            self::LowStock => ['stock.view', 'stock.adjust'],
            self::ReservationUpcoming, self::ReservationNoShow => ['reservations.view', 'reservations.manage'],
            // Garson (orders.create) = masaya bakan personel + KASA (payments.take):
            // özellikle "hesap iste" çağrısının kasaya da ulaşması için. Yönetici
            // includeManagers ile dahil.
            self::ServiceCall => ['orders.create', 'payments.take'],
            // Ödemeye gönderilen / borca taşınan adisyon → kasa (+ yönetici).
            self::AwaitingPayment, self::DebtTransferred => ['payments.take'],
            // QR sipariş onayı → onaylayan garson (+ yönetici).
            self::OrderNeedsApproval => ['orders.create'],
            // Personel molası izne göre HEDEFLENMEZ: alıcılar yönetici
            // (includeManagers) + o an mesaide olan diğer personel (emitter'ın
            // extra_user_ids'i ile) → hangi izne sahip olduklarından bağımsız.
            self::StaffBreak => [],
            // Görev atama: yalnız atanan kişi (extra_user_ids); izin hedefi yok.
            self::TaskAssigned => [],
            // İzin talebi: onaylayabilen yöneticiler.
            self::LeaveRequested => ['staff.manage'],
            // Mesai hatırlatması: yalnız o personel (extra_user_ids).
            self::ShiftReminder => [],
            // İzin sonucu: yalnız talep sahibi (extra_user_ids).
            self::LeaveDecided => [],
            // Teslimat atandı: yalnız o kurye (extra_user_ids).
            self::DeliveryAssigned => [],
            // Teslimat tamamlandı: teslimat panosunu görenler + yönetici.
            self::DeliveryDelivered => ['delivery.view', 'delivery.manage'],
        };
    }

    public function includeManagers(): bool
    {
        // Yeni sipariş & hazır & servis: operasyon personeline gider; yönetici
        // panoyu izler (gürültü olmasın). SLA/stok/rezervasyon: yönetici de alır.
        return match ($this) {
            self::OrderPlaced, self::ItemReady, self::OrderServed => false,
            // Kişiye özel bildirimler: YALNIZ ilgili kişi (extra_user_ids) —
            // yönetici her göreve/hatırlatmaya boğulmasın.
            self::TaskAssigned, self::ShiftReminder, self::LeaveDecided, self::DeliveryAssigned => false,
            // Servis çağrısı: garsona gider + yönetici de görür (masa bekliyor).
            default => true,
        };
    }

    /** İstasyon kulvarına (kitchen/barista) göre süzülsün mü? */
    public function laneScoped(): bool
    {
        return $this === self::OrderPlaced;
    }

    /** Zil/push için ikon adı (AppIcon glifi). */
    public function icon(): string
    {
        return match ($this) {
            self::OrderPlaced => 'orders',
            self::ItemReady => 'check',
            self::DeliverySlaBreach => 'clock',
            self::OrderServed => 'check',
            self::LowStock => 'package',
            self::ReservationUpcoming, self::ReservationNoShow => 'calendar',
            self::ServiceCall => 'bell',
            self::StaffBreak => 'clock',
            self::TaskAssigned => 'clipboard',
            self::LeaveRequested => 'calendar',
            self::ShiftReminder => 'clock',
            self::LeaveDecided => 'check',
            self::DeliveryAssigned => 'store',
            self::DeliveryDelivered => 'check',
            self::AwaitingPayment => 'wallet',
            self::DebtTransferred => 'inbox',
            self::OrderNeedsApproval => 'bell',
        };
    }

    /**
     * Frontend (Profil tercihleri + yönetici politikası) için katalog dökümü.
     *
     * @return array<int, array{
     *   key:string, label:string, description:string, category:string,
     *   category_label:string, default_in_app:bool, default_push:bool
     * }>
     */
    public static function catalog(): array
    {
        return array_map(fn (self $t): array => [
            'key' => $t->value,
            'label' => $t->label(),
            'description' => $t->description(),
            'category' => $t->category(),
            'category_label' => self::categoryLabel($t->category()),
            'default_in_app' => $t->defaultInApp(),
            'default_push' => $t->defaultPush(),
        ], self::cases());
    }
}
