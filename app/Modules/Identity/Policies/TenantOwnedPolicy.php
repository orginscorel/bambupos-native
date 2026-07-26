<?php

namespace App\Modules\Identity\Policies;

use App\Modules\Identity\Models\User;
use Illuminate\Database\Eloquent\Model;

/**
 * Katman 2 (ADR-004): policy'ler global scope'tan BAĞIMSIZ olarak
 * kiracı eşitliğini yeniden doğrular + modül izinlerini denetler.
 * Scope bir gün yanlışlıkla kaldırılsa bile policy sızıntıyı keser.
 */
abstract class TenantOwnedPolicy
{
    /** İzin kataloğundaki modül anahtarı (ör. "catalog"). */
    protected string $module;

    public function viewAny(User $user): bool
    {
        return $user->hasPermission("{$this->module}.view");
    }

    public function view(User $user, Model $model): bool
    {
        return $this->ownedByUserTenant($user, $model) && $user->hasPermission("{$this->module}.view");
    }

    public function create(User $user): bool
    {
        return $user->hasPermission("{$this->module}.create");
    }

    public function update(User $user, Model $model): bool
    {
        return $this->ownedByUserTenant($user, $model) && $user->hasPermission("{$this->module}.update");
    }

    public function delete(User $user, Model $model): bool
    {
        return $this->ownedByUserTenant($user, $model) && $user->hasPermission("{$this->module}.delete");
    }

    protected function ownedByUserTenant(User $user, Model $model): bool
    {
        return $user->tenant_id !== null
            && (int) $model->getAttribute('tenant_id') === (int) $user->tenant_id;
    }

    /**
     * ŞUBE KAPSAMI (izolasyonun 2. boyutu): şube-bağlı bir kayıt YALNIZ
     * kullanıcının GEÇERLİ şubesindeyse erişilebilir. Personel kendi
     * şubesine, yönetici aktif seçili şubesine kilitlidir (BranchContext).
     *
     * Şubesiz (branch_id = null) kayıtlar tenant-geneli sayılır, kısıtlanmaz.
     * Bu yardımcı YALNIZ şube-bağlı modüllerin (Orders/Payments/...) policy'
     * lerinde bilinçle çağrılır — Catalog/Menü gibi tenant-geneli modüllerde
     * KULLANILMAZ.
     */
    protected function inCurrentBranch(Model $model): bool
    {
        $branchId = $model->getAttribute('branch_id');

        if ($branchId === null) {
            return true;
        }

        return (int) $branchId === (int) app(\App\Modules\Tenancy\BranchContext::class)->currentBranchId();
    }
}
