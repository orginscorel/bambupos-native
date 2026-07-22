<?php

namespace App\Modules\Catalog\Policies;

use App\Modules\Catalog\Models\Allergen;
use App\Modules\Identity\Models\User;

/**
 * Alerjen sözlüğü: küresel satırlar (tenant_id NULL) HERKESE görünür ama
 * hiçbir kiracı tarafından değiştirilemez; kiracı yalnız kendi eklediği
 * satırları yönetir.
 */
class AllergenPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasPermission('catalog.view');
    }

    public function view(User $user, Allergen $allergen): bool
    {
        return $user->hasPermission('catalog.view')
            && ($allergen->isGlobal() || $this->ownedByUserTenant($user, $allergen));
    }

    public function create(User $user): bool
    {
        return $user->hasPermission('catalog.create');
    }

    public function update(User $user, Allergen $allergen): bool
    {
        return ! $allergen->isGlobal()
            && $this->ownedByUserTenant($user, $allergen)
            && $user->hasPermission('catalog.update');
    }

    public function delete(User $user, Allergen $allergen): bool
    {
        return ! $allergen->isGlobal()
            && $this->ownedByUserTenant($user, $allergen)
            && $user->hasPermission('catalog.delete');
    }

    private function ownedByUserTenant(User $user, Allergen $allergen): bool
    {
        return $user->tenant_id !== null
            && (int) $allergen->tenant_id === (int) $user->tenant_id;
    }
}
