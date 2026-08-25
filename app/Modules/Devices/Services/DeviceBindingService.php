<?php

namespace App\Modules\Devices\Services;

use App\Modules\Devices\Models\AuthorizedDevice;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

/**
 * Cihaz bağlama servisi (A3 — KDS/Kiosk cihaz kilidi temeli).
 *
 * Kavramlar:
 *  - "link"  : bir ekranın/kaynağın kararlı kimliği (ör. route adı ya da
 *              route'taki opak token). EnsureDeviceAuthorized middleware'i
 *              bunu her istekte türetip authorize()'a verir.
 *  - "device_token": tarayıcıda saklanan opak sır (çerez/localStorage).
 *
 * Akış (authorize):
 *  1) Bu tenant+kind+link için kayıt var mı bak (satır = "slot").
 *  2) Yoksa: sunulan token ön-yetkili BAĞLANMAMIŞ bir slot'a mı ait (admin
 *     "yeni ekle" ile üretip cihaza vermiş) → varsa o slot'u bu link'e bağla.
 *     Yoksa tamamen otomatik yeni bir slot oluştur (ilk-ziyaretçi kazanır).
 *  3) Varsa ve revoked ise reddet.
 *  4) Varsa ve henüz bağlanmamışsa (first_bound_at NULL): sunulan token
 *     slot'un token'ıyla eşleşiyorsa ya da hiç token sunulmamışsa (gerçek
 *     ilk ziyaret) bağla; başka bir token sunulmuşsa reddet.
 *  5) Varsa ve bağlıysa: token eşleşmiyorsa reddet ("başka cihaza kilitli").
 *
 * Eşzamanlılık: linkKey başına yarış durumunu önlemek için tüm okuma+yazma
 * bir DB transaction + lockForUpdate içinde yapılır (MySQL InnoDB varsayımı;
 * bu projede tüm tablolar InnoDB).
 */
class DeviceBindingService
{
    /** Tarayıcı çerezinin adı (middleware bunu yazar/okur). */
    public const COOKIE_NAME = 'qm_device_token';

    /** Ön-yetkili "paylaşım linki" oluştururken kullanılan sorgu parametresi. */
    public const CLAIM_QUERY_PARAM = 'dt';

    public function __construct(private readonly TenantContext $context)
    {
    }

    /* =========================================================
     * Kapı (middleware bunu çağırır)
     * ========================================================= */

    public function authorize(string $kind, string $linkKey, ?string $presentedToken): DeviceAuthorizationResult
    {
        $this->assertKind($kind);

        return DB::transaction(function () use ($kind, $linkKey, $presentedToken): DeviceAuthorizationResult {
            $device = AuthorizedDevice::query()
                ->where('kind', $kind)
                ->where('bound_link', $linkKey)
                ->lockForUpdate()
                ->first();

            if ($device === null) {
                return $this->bindFreshLink($kind, $linkKey, $presentedToken);
            }

            if ($device->isRevoked()) {
                return DeviceAuthorizationResult::deny('revoked', $device);
            }

            if (! $device->isBound()) {
                return $this->claimUnboundSlot($device, $presentedToken);
            }

            if ($presentedToken !== null && hash_equals($device->device_token, $presentedToken)) {
                $this->touch($device);

                return DeviceAuthorizationResult::allow($device);
            }

            return DeviceAuthorizationResult::deny('locked_to_other_device', $device);
        });
    }

    private function bindFreshLink(string $kind, string $linkKey, ?string $presentedToken): DeviceAuthorizationResult
    {
        // Sunulan token, admin tarafından ÖN-YETKİLİ üretilmiş ama henüz
        // hiçbir link'e bağlanmamış bir slot'a mı ait? (paylaşım linki akışı)
        if ($presentedToken !== null) {
            $claimable = AuthorizedDevice::query()
                ->where('device_token', $presentedToken)
                ->where('status', AuthorizedDevice::STATUS_ACTIVE)
                ->whereNull('bound_link')
                ->lockForUpdate()
                ->first();

            if ($claimable !== null) {
                $claimable->kind = $kind; // provision sırasında verilen kind ile tutarlı olmalı ama garanti altına al
                $claimable->bound_link = $linkKey;
                $claimable->first_bound_at = now();
                $this->touch($claimable, save: false);
                $claimable->save();

                return DeviceAuthorizationResult::allow($claimable);
            }
        }

        // Tamamen otomatik ilk bağlanma: link'i ilk açan tarayıcı kazanır.
        $device = new AuthorizedDevice([
            'kind' => $kind,
            'bound_link' => $linkKey,
            'status' => AuthorizedDevice::STATUS_ACTIVE,
        ]);
        $device->first_bound_at = now();
        $this->touch($device, save: false);
        $device->save();

        return DeviceAuthorizationResult::allow($device, $device->device_token);
    }

    private function claimUnboundSlot(AuthorizedDevice $device, ?string $presentedToken): DeviceAuthorizationResult
    {
        if ($presentedToken === null || hash_equals($device->device_token, $presentedToken)) {
            $device->first_bound_at = now();
            $this->touch($device, save: false);
            $device->save();

            // Tarayıcı zaten doğru token'ı sunmuşsa yeniden yazmaya gerek yok;
            // hiç sunmamışsa (gerçek ilk ziyaret) middleware çerezi yazsın.
            $tokenToPersist = $presentedToken === null ? $device->device_token : null;

            return DeviceAuthorizationResult::allow($device, $tokenToPersist);
        }

        return DeviceAuthorizationResult::deny('invalid_token', $device);
    }

    private function touch(AuthorizedDevice $device, bool $save = true): void
    {
        $device->last_seen_at = now();

        $meta = $device->meta ?? [];
        $request = request();
        if ($request !== null) {
            $meta['last_ip'] = $request->ip();
            $meta['last_user_agent'] = (string) $request->userAgent();
        }
        $device->meta = $meta;

        if ($save) {
            $device->save();
        }
    }

    /* =========================================================
     * Yönetim (panel controller'ı bunları çağırır)
     * ========================================================= */

    /** Ön-yetkili slot üret: bound_link boş bırakılabilir (paylaşım linkiyle sonra bağlanır). */
    public function provision(string $kind, ?string $name, ?string $boundLink = null): AuthorizedDevice
    {
        $this->assertKind($kind);

        return DB::transaction(function () use ($kind, $name, $boundLink): AuthorizedDevice {
            if ($boundLink !== null) {
                $exists = AuthorizedDevice::query()
                    ->where('kind', $kind)
                    ->where('bound_link', $boundLink)
                    ->lockForUpdate()
                    ->exists();

                if ($exists) {
                    throw new InvalidArgumentException('Bu link zaten başka bir cihaza atanmış.');
                }
            }

            $device = new AuthorizedDevice([
                'kind' => $kind,
                'name' => $name,
                'bound_link' => $boundLink,
                'status' => AuthorizedDevice::STATUS_ACTIVE,
            ]);

            if ($boundLink !== null) {
                // Admin bound_link'i baştan biliyorsa (ör. belirli bir kiosk
                // token'ı) satırı hemen "bağlı" sayabiliriz; yine de gerçek
                // tarayıcı ilk istekte device_token'ı sunmalıdır (claimUnboundSlot
                // yolu first_bound_at'ı zaten NULL bırakarak bunu doğal olarak sağlar).
                $device->first_bound_at = null;
            }

            $device->save();

            return $device;
        });
    }

    /** İzni tamamen kaldır: hiçbir tarayıcı (eski dahil) artık geçemez. */
    public function revoke(AuthorizedDevice $device): AuthorizedDevice
    {
        $device->status = AuthorizedDevice::STATUS_REVOKED;
        $device->save();

        return $device;
    }

    /** İzni geri ver (revoke'u geri al); mevcut bağlama korunur. */
    public function reactivate(AuthorizedDevice $device): AuthorizedDevice
    {
        $device->status = AuthorizedDevice::STATUS_ACTIVE;
        $device->save();

        return $device;
    }

    /**
     * Boşa düşür: mevcut tarayıcı bağını çöz + token'ı ANINDA geçersiz kıl
     * (rotate). bound_link AYNI KALIR (aynı ekran/kaynak) — bir sonraki
     * ziyaretçi (çerezsiz) otomatik olarak yeni sahip olur. Eski tarayıcının
     * çerezi artık yeni token'la eşleşmediği için o da otomatik reddedilir.
     */
    public function release(AuthorizedDevice $device): AuthorizedDevice
    {
        $device->device_token = AuthorizedDevice::generateToken();
        $device->first_bound_at = null;
        $device->last_seen_at = null;
        $device->save();

        return $device;
    }

    /**
     * "Başka cihaza aktar": mekanik olarak release() ile AYNIDIR (mevcut
     * token boşa düşer + yeni bağlanma izni doğar). Ayrı isimle tutuluyor
     * çünkü admin panelinde niyet farklı okunur (kaybolan cihaz yerine yenisi
     * takılıyor); ileride farklı davranması istenirse burada dallanabilir.
     */
    public function transfer(AuthorizedDevice $device): AuthorizedDevice
    {
        return $this->release($device);
    }

    /* =========================================================
     * Yardımcılar
     * ========================================================= */

    /** Paylaşım linkine eklenecek sorgu parametresi (ön-yetkili slot'u cihaza vermek için). */
    public static function claimQueryFor(AuthorizedDevice $device): string
    {
        return self::CLAIM_QUERY_PARAM.'='.$device->device_token;
    }

    private function assertKind(string $kind): void
    {
        if (! in_array($kind, AuthorizedDevice::KINDS, true)) {
            throw new InvalidArgumentException("Geçersiz cihaz türü: {$kind}");
        }
    }
}
