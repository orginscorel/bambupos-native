<?php

namespace App\Modules\Receivables\Policies;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Policies\TenantOwnedPolicy;
use App\Modules\Receivables\Models\Receivable;

/**
 * Borçlar/Cari yetkileri (config/authz.php: receivables.*).
 *
 *  - view/create/update: cari kaydı yönetimi (şube müdürü ve üzeri).
 *  - transfer: "adisyonu borca taşı" — garson da yapabilir (hesabı
 *    kapatmadan masayı boşaltmak operasyonel bir karardır, para GİRİŞİ
 *    doğurmaz — yalnız tahsilatı ERTELER).
 *  - collect: TAHSİLAT — parayı sisteme "girmiş" sayan işlemdir (kasa.close
 *    gibi hassas); varsayılan olarak kasiyer/yönetici seviyesindedir.
 */
class ReceivablePolicy extends TenantOwnedPolicy
{
    protected string $module = 'receivables';

    public function transfer(User $user): bool
    {
        return $user->hasPermission('receivables.transfer');
    }

    public function collect(User $user, Receivable $receivable): bool
    {
        return $this->ownedByUserTenant($user, $receivable) && $user->hasPermission('receivables.collect');
    }
}
