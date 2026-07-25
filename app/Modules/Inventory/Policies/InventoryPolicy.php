<?php

namespace App\Modules\Inventory\Policies;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Policies\TenantOwnedPolicy;
use Illuminate\Database\Eloquent\Model;

/**
 * Inventory modelleri için ortak policy. İzin kataloğunda stok modülünün
 * YALNIZ iki anahtarı vardır (config/authz.php): `stock.view` ve
 * `stock.adjust`. Tüm yazma eylemleri stock.adjust'a bağlanır — TenantOwned
 * temelindeki create/update/delete anahtarları (stock.create vb.) katalogda
 * OLMADIĞINDAN burada override edilir.
 */
class InventoryPolicy extends TenantOwnedPolicy
{
    protected string $module = 'stock';

    public function create(User $user): bool
    {
        return $user->hasPermission('stock.adjust');
    }

    public function update(User $user, Model $model): bool
    {
        return $this->ownedByUserTenant($user, $model) && $user->hasPermission('stock.adjust');
    }

    public function delete(User $user, Model $model): bool
    {
        return $this->ownedByUserTenant($user, $model) && $user->hasPermission('stock.adjust');
    }

    /** Manuel hareket / sayım onayı / mal kabul gibi stok değiştiren eylemler. */
    public function adjust(User $user, ?Model $model = null): bool
    {
        if ($model !== null && ! $this->ownedByUserTenant($user, $model)) {
            return false;
        }

        return $user->hasPermission('stock.adjust');
    }
}
