<?php

namespace App\Modules\Tenancy;

use App\Modules\Identity\Models\User;
use App\Modules\Settings\Support\Features;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;

/**
 * ŞUBE BAĞLAMI — "geçerli şube" tek çözücü (istek başına singleton).
 *
 * Kiracı izolasyonunun (ADR-004) İKİNCİ boyutu. TenantContext hangi
 * KİRACI'ya baktığımızı çözer; bu servis o kiracının hangi ŞUBE'sine
 * baktığımızı çözer ve GÜVENLİK SINIRIDIR:
 *
 *  - **Personel (yönetici DEĞİL) → kendi `users.branch_id`'sine KİLİTLİ.**
 *    Session'daki aktif-şube seçimi yok sayılır; başka şube verisi ASLA.
 *  - **Terminal cihazı (is_terminal) → cihazın şubesine KİLİTLİ.**
 *  - **Yönetici (reports.view / staff.manage / settings.manage) →**
 *    session'daki AKTİF seçili şube (tek şube; "tümü/all" YOK). Kiracısının
 *    şubeleri arasında geçiş yapabilir.
 *  - **Çok-şube (`branches` feature) KAPALI → tek-şube modu:** herkes
 *    varsayılan/kendi şubesine bağlanır, switcher gizlenir.
 *
 * Tüm liste/rapor/ödeme sorguları `currentBranchId()` ile süzülmelidir.
 * Kiracı kimliği gibi, geçerli şube de ASLA istek parametresinden alınmaz;
 * kullanıcı istekle başka şube dayatamaz.
 */
class BranchContext
{
    /** Yönetici tanımı: bu izinlerden HERHANGİ biri = aktif şubeyi seçebilir. */
    private const MANAGER_PERMISSIONS = ['reports.view', 'staff.manage', 'settings.manage'];

    /** Public/sistem akışı (QR, seed, test) için bilinçli sabitleme. */
    private ?int $explicitBranchId = null;

    private bool $explicitlySet = false;

    /** @var array<int, Collection<int, Branch>> tenant_id → şubeler (istek-içi memo) */
    private array $branchCache = [];

    public function setBranch(Branch|int|null $branch): void
    {
        $this->explicitBranchId = $branch instanceof Branch
            ? (int) $branch->getKey()
            : ($branch === null ? null : (int) $branch);
        $this->explicitlySet = true;
    }

    public function forget(): void
    {
        $this->explicitBranchId = null;
        $this->explicitlySet = false;
        $this->branchCache = [];
    }

    /* ---------------- Rol/mod sorguları ---------------- */

    /** Yönetici mi? (aktif şubeyi seçebilen — personel değil.) */
    public function isManager(?User $user = null): bool
    {
        $user ??= Auth::user();

        if ($user === null) {
            return false;
        }

        foreach (self::MANAGER_PERMISSIONS as $key) {
            if ($user->hasPermission($key)) {
                return true;
            }
        }

        return false;
    }

    /** Çok-şube özelliği (branches feature-flag) açık mı? Kapalı = tek-şube modu. */
    public function multiBranchEnabled(?User $user = null): bool
    {
        $user ??= Auth::user();

        if ($user === null || $user->tenant_id === null) {
            return false;
        }

        return Features::enabled((int) $user->tenant_id, 'branches');
    }

    /** Bu kullanıcı geçerli şubeye KİLİTLİ mi (değiştiremez)? */
    public function isLocked(?User $user = null): bool
    {
        $user ??= Auth::user();

        if ($user === null) {
            return true;
        }

        // Terminal cihazı daima kendi şubesine kilitli.
        if ($user->is_terminal) {
            return true;
        }

        // Personel (yönetici değil) kendi şubesine kilitli.
        if (! $this->isManager($user)) {
            return true;
        }

        // Tek-şube modunda (feature kapalı) kimse şube değiştiremez.
        return ! $this->multiBranchEnabled($user);
    }

    /** Şube değiştirici görünmeli mi? (yönetici + çok-şube açık + >1 şube) */
    public function canSwitch(?User $user = null): bool
    {
        $user ??= Auth::user();

        if ($user === null || $this->isLocked($user)) {
            return false;
        }

        return $this->branches($user)->count() > 1;
    }

    /* ---------------- Şube listesi ---------------- */

    /**
     * Kiracının aktif şubeleri (switcher + doğrulama). İstek-içi memo.
     *
     * @return Collection<int, Branch>
     */
    public function branches(?User $user = null): Collection
    {
        $user ??= Auth::user();

        if ($user === null || $user->tenant_id === null) {
            return collect();
        }

        $tenantId = (int) $user->tenant_id;

        return $this->branchCache[$tenantId] ??= Branch::query()
            ->withoutGlobalScopes()
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->orderBy('name')
            ->get();
    }

    /* ---------------- Geçerli şube (güvenlik sınırı) ---------------- */

    /**
     * GEÇERLİ ŞUBE kimliği. Tüm liste/rapor/ödeme sorguları buna süzülür.
     * null yalnız kullanıcı/şube yoksa (o durumda çağıran fail-closed davranır).
     */
    public function currentBranchId(?User $user = null): ?int
    {
        if ($this->explicitlySet) {
            return $this->explicitBranchId;
        }

        $user ??= Auth::user();

        if ($user === null) {
            return null;
        }

        $ownBranchId = $user->branch_id !== null ? (int) $user->branch_id : null;

        // Kilitli kullanıcı: DAİMA kendi/cihaz şubesi. Session ezmesi yok sayılır.
        if ($this->isLocked($user)) {
            return $this->ownOrFirst($user, $ownBranchId);
        }

        // Yönetici + çok-şube açık: session'daki aktif şube (doğrulanır).
        $sessionId = (int) (session('panel.active_branch_id') ?: 0);
        $branches = $this->branches($user);

        if ($sessionId > 0 && $branches->contains(fn (Branch $b): bool => (int) $b->id === $sessionId)) {
            return $sessionId;
        }

        return $this->ownOrFirst($user, $ownBranchId, $branches);
    }

    /** Geçerli şubenin modeli (timezone vb. için). */
    public function currentBranch(?User $user = null): ?Branch
    {
        $id = $this->currentBranchId($user);

        if ($id === null) {
            return null;
        }

        return $this->branches($user)->firstWhere('id', $id);
    }

    /**
     * Verilen şube bu kullanıcı için GEÇERLİ mi? (aktif-şube ucu doğrulaması)
     * Kilitli kullanıcıda yalnız kendi şubesi geçerlidir.
     */
    public function isAllowed(int $branchId, ?User $user = null): bool
    {
        $user ??= Auth::user();

        if ($user === null) {
            return false;
        }

        if ($this->isLocked($user)) {
            return $branchId === ($user->branch_id !== null ? (int) $user->branch_id : null);
        }

        return $this->branches($user)->contains(fn (Branch $b): bool => (int) $b->id === $branchId);
    }

    /**
     * @param  Collection<int, Branch>|null  $branches
     */
    private function ownOrFirst(User $user, ?int $ownBranchId, ?Collection $branches = null): ?int
    {
        $branches ??= $this->branches($user);

        if ($ownBranchId !== null && $branches->contains(fn (Branch $b): bool => (int) $b->id === $ownBranchId)) {
            return $ownBranchId;
        }

        $first = $branches->first();

        return $first !== null ? (int) $first->id : $ownBranchId;
    }
}
