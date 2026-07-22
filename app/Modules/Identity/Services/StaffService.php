<?php

namespace App\Modules\Identity\Services;

use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\TenantContext;
use App\Modules\Tenancy\TenantIsolationException;
use Illuminate\Validation\ValidationException;

/**
 * Personel yönetimi (katman 4: servis).
 *  - Yeni personel DAİMA bağlamdaki kiracıya yazılır; istekten tenant_id alınmaz.
 *  - branch_id ve rol id'leri kiracının kendi kayıtlarından doğrulanır
 *    (Branch/Role global scope'lu olduğundan yabancı id çözülmez → reddedilir).
 */
class StaffService
{
    public function __construct(
        private readonly TenantContext $context,
        private readonly AuditLogger $audit,
    ) {
    }

    /**
     * @param  array<string, mixed>  $attributes
     * @param  array<int, int>  $roleIds
     */
    public function create(array $attributes, ?int $branchId, array $roleIds): User
    {
        $tenantId = $this->context->tenantId();

        if ($tenantId === null) {
            throw new TenantIsolationException('Kiracı bağlamı olmadan personel oluşturulamaz.');
        }

        $user = new User($attributes);
        $user->tenant_id = $tenantId;
        $user->branch_id = $branchId !== null ? $this->assertBranch($branchId)->id : null;
        $user->save();

        if ($roleIds !== []) {
            $user->roles()->sync($this->assertRoles($roleIds));
        }

        $this->audit->log('staff.created', $user, null, $user->only([
            'first_name', 'last_name', 'email', 'staff_code', 'branch_id', 'is_active',
        ]));

        return $user;
    }

    /**
     * @param  array<string, mixed>  $attributes
     * @param  array<int, int>|null  $roleIds
     */
    public function update(User $staff, array $attributes, ?int $branchId, ?array $roleIds): User
    {
        $tenantId = $this->context->tenantId();

        if ($tenantId === null || (int) $staff->tenant_id !== $tenantId) {
            throw new TenantIsolationException('Personel kaydı bu kiracıya ait değil.');
        }

        $old = $staff->only(array_keys($attributes));

        $staff->fill($attributes);

        if ($branchId !== null) {
            $staff->branch_id = $this->assertBranch($branchId)->id;
        }

        $staff->save();

        if ($roleIds !== null) {
            $staff->roles()->sync($this->assertRoles($roleIds));
            $staff->flushPermissionCache();
        }

        $this->audit->log('staff.updated', $staff, $old, $attributes);

        return $staff;
    }

    private function assertBranch(int $branchId): Branch
    {
        // Branch global scope'lu: yabancı kiracının şubesi asla çözülmez.
        $branch = Branch::query()->find($branchId);

        if ($branch === null) {
            throw ValidationException::withMessages([
                'branch_id' => ['Şube bulunamadı.'],
            ]);
        }

        return $branch;
    }

    /**
     * @param  array<int, int>  $roleIds
     * @return array<int, int>
     */
    private function assertRoles(array $roleIds): array
    {
        // Role global scope'lu: yabancı kiracının rol id'si listede çözülmez.
        $resolved = Role::query()->whereIn('id', $roleIds)->pluck('id')->all();

        if (count($resolved) !== count(array_unique($roleIds))) {
            throw ValidationException::withMessages([
                'roles' => ['Bir veya daha fazla rol bu işletmeye ait değil.'],
            ]);
        }

        return $resolved;
    }
}
