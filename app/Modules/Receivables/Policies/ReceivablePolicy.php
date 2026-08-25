<?php

namespace App\Modules\Receivables\Policies;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Policies\TenantOwnedPolicy;
use App\Modules\Receivables\Models\Receivable;
use Illuminate\Database\Eloquent\Model;

/**
 * Borçlar/Cari yetkileri (config/authz.php: receivables.*).
 *
 *  - view/create/update: cari kaydı yönetimi (şube müdürü ve üzeri).
 *  - transfer: "adisyonu borca taşı" — garson da yapabilir (hesabı
 *    kapatmadan masayı boşaltmak operasyonel bir karardır, para GİRİŞİ
 *    doğurmaz — yalnız tahsilatı ERTELER).
 *  - collect: TAHSİLAT — parayı sisteme "girmiş" sayan işlemdir (kasa.close
 *    gibi hassas); varsayılan olarak kasiyer/yönetici seviyesindedir.
 *
 * ŞUBE KAPSAMI (OrderPolicy ile AYNI desen — `inCurrentBranch()`):
 * view/update/collect YALNIZ geçerli şubenin carisinde izinlidir. Şubesiz
 * (branch_id = null) cariler kiracı-geneli sayılır, kısıtlanmaz (bkz.
 * TenantOwnedPolicy::inCurrentBranch, ReceivableController::index).
 */
class ReceivablePolicy extends TenantOwnedPolicy
{
    protected string $module = 'receivables';

    public function view(User $user, Model $receivable): bool
    {
        return parent::view($user, $receivable) && $this->inCurrentBranch($receivable);
    }

    public function update(User $user, Model $receivable): bool
    {
        return parent::update($user, $receivable) && $this->inCurrentBranch($receivable);
    }

    public function transfer(User $user): bool
    {
        return $user->hasPermission('receivables.transfer');
    }

    public function collect(User $user, Receivable $receivable): bool
    {
        return $this->ownedByUserTenant($user, $receivable) && $this->inCurrentBranch($receivable)
            && $user->hasPermission('receivables.collect');
    }
}
