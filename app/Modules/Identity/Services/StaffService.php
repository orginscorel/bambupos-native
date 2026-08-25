<?php

namespace App\Modules\Identity\Services;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\TenantContext;
use App\Modules\Tenancy\TenantIsolationException;
use Illuminate\Support\Facades\Auth;
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

        // Sahip güvencesi: sistem rolü taşıyan hesap panelden pasife alınamaz
        // (işletme sahibi kilitlenemez; demo hesabı dahil).
        if (array_key_exists('is_active', $attributes)
            && ! $attributes['is_active']
            && $staff->is_active
            && $this->holdsSystemRole($staff)) {
            throw ValidationException::withMessages([
                'is_active' => ['Sistem rolü (ör. Sahip) taşıyan hesap pasife alınamaz.'],
            ])->status(403);
        }

        $old = $staff->only(array_keys($attributes));

        $staff->fill($attributes);

        if ($branchId !== null) {
            $staff->branch_id = $this->assertBranch($branchId)->id;
        }

        $staff->save();

        if ($roleIds !== null) {
            // Önce rolleri doğrula (yabancı-kiracı → 422, yetki-yükseltme → 403).
            $resolved = $this->assertRoles($roleIds);

            // Sonra: kişi KENDİ rollerini değiştiremez (setPersonalPermissions'taki
            // self-engelin karşılığı; kendine "Sahip" ekleme yolunu kapatır).
            $actor = Auth::user();
            if ($actor !== null && $actor->is($staff)) {
                throw ValidationException::withMessages([
                    'roles' => ['Kendi rollerinizi değiştiremezsiniz.'],
                ])->status(403);
            }

            $staff->roles()->sync($resolved);
            $staff->flushPermissionCache();
        }

        $this->audit->log('staff.updated', $staff, $old, $attributes);

        return $staff;
    }

    /**
     * Kişi bazlı izin istisnaları (grant/revoke) — TAM SET olarak yazılır.
     *
     * Kurallar:
     *  - Aktör kendinde olmayan bir izni GRANT edemez (yetki yükseltme engeli).
     *  - Aktör KENDİ istisnalarını değiştiremez.
     *  - is_system rol taşıyan kullanıcıya (ör. Sahip) revoke yazılamaz —
     *    işletme sahibi tek tek izin düşülerek kilitlenemez.
     *
     * @param  array<int, string>  $grantKeys
     * @param  array<int, string>  $revokeKeys
     */
    public function setPersonalPermissions(User $actor, User $staff, array $grantKeys, array $revokeKeys): User
    {
        $tenantId = $this->context->tenantId();

        if ($tenantId === null || (int) $staff->tenant_id !== $tenantId) {
            throw new TenantIsolationException('Personel kaydı bu kiracıya ait değil.');
        }

        if ($actor->is($staff)) {
            throw ValidationException::withMessages([
                'staff' => ['Kendi izin istisnalarınızı değiştiremezsiniz.'],
            ])->status(403);
        }

        $grantKeys = array_values(array_unique($grantKeys));
        $revokeKeys = array_values(array_unique(array_diff($revokeKeys, $grantKeys)));

        // Yetki yükseltme engeli: aktör sahip olmadığı izni bağışlayamaz.
        $actorKeys = $actor->permissionKeys();
        $forbidden = array_diff($grantKeys, $actorKeys);

        if ($forbidden !== []) {
            throw ValidationException::withMessages([
                'grants' => ['Sahip olmadığınız izinleri veremezsiniz: '.implode(', ', $forbidden)],
            ])->status(403);
        }

        if ($revokeKeys !== [] && $this->holdsSystemRole($staff)) {
            throw ValidationException::withMessages([
                'revokes' => ['Sistem rolü (ör. Sahip) taşıyan kullanıcıdan izin düşülemez.'],
            ])->status(403);
        }

        $permissions = Permission::query()
            ->whereIn('key', array_merge($grantKeys, $revokeKeys))
            ->pluck('id', 'key');

        $unknown = array_diff(array_merge($grantKeys, $revokeKeys), $permissions->keys()->all());

        if ($unknown !== []) {
            throw ValidationException::withMessages([
                'permissions' => ['Bilinmeyen izin anahtarı: '.implode(', ', $unknown)],
            ]);
        }

        $old = $staff->personalOverrideKeys();

        $sync = [];
        foreach ($grantKeys as $key) {
            $sync[$permissions[$key]] = ['mode' => 'grant'];
        }
        foreach ($revokeKeys as $key) {
            $sync[$permissions[$key]] = ['mode' => 'revoke'];
        }

        $staff->personalPermissions()->sync($sync);
        $staff->flushPermissionCache();

        $this->audit->log('staff.overrides_set', $staff, $old, ['grant' => $grantKeys, 'revoke' => $revokeKeys]);

        return $staff;
    }

    /**
     * İşten çıkarma = pasife alma. Kayıt SİLİNMEZ (veri kaybı yok);
     * açık oturumlar EnsureUserIsActive katmanıyla düşer.
     */
    public function terminate(User $actor, User $staff): User
    {
        $tenantId = $this->context->tenantId();

        if ($tenantId === null || (int) $staff->tenant_id !== $tenantId) {
            throw new TenantIsolationException('Personel kaydı bu kiracıya ait değil.');
        }

        if ($actor->is($staff)) {
            throw ValidationException::withMessages([
                'staff' => ['Kendi hesabınızı işten çıkaramazsınız.'],
            ])->status(403);
        }

        if ($this->holdsSystemRole($staff)) {
            throw ValidationException::withMessages([
                'staff' => ['Sistem rolü (ör. Sahip) taşıyan hesap işten çıkarılamaz.'],
            ])->status(403);
        }

        $staff->is_active = false;
        $staff->save();

        $this->audit->log('staff.terminated', $staff, ['is_active' => true], ['is_active' => false]);

        return $staff;
    }

    private function holdsSystemRole(User $staff): bool
    {
        return $staff->roles()
            ->withoutGlobalScope(\App\Modules\Tenancy\Scopes\TenantScope::class)
            ->where('roles.tenant_id', $staff->tenant_id)
            ->where('roles.is_system', true)
            ->exists();
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

        $this->assertRolesGrantable($resolved);

        return $resolved;
    }

    /**
     * YETKİ YÜKSELTME ENGELİ (K-1): rol atama yolu, setPersonalPermissions ve
     * RoleService'in uyguladığı korumalara tabidir. Aktör = giriş yapan kullanıcı
     * (seed/konsol bağlamında null → sistem, tam güven):
     *  - Atanan rollerin BİRLEŞİK izin kümesi, aktörün izinlerinin ALT KÜMESİ olmalı
     *    (kimse sahip olmadığı yetkiyi bir rol aracılığıyla dağıtamaz/kendine alamaz).
     *  - is_system (ör. Sahip) rolü yalnızca zaten sistem rolü taşıyan aktör atayabilir.
     *
     * @param  array<int, int>  $resolvedIds
     */
    private function assertRolesGrantable(array $resolvedIds): void
    {
        if ($resolvedIds === []) {
            return;
        }

        /** @var User|null $actor */
        $actor = Auth::user();

        // Sistem/seed bağlamı (HTTP dışı): aktör yok → güvenli iç yol.
        if ($actor === null) {
            return;
        }

        $roles = Role::query()->whereIn('id', $resolvedIds)->with('permissions:id,key')->get();

        // is_system rol yalnız sistem-rollü aktör tarafından atanabilir.
        if ($roles->contains(fn (Role $r): bool => (bool) $r->is_system) && ! $this->holdsSystemRole($actor)) {
            throw ValidationException::withMessages([
                'roles' => ['Sistem rolü (ör. Sahip) yalnızca aynı düzeyde bir yetkili tarafından atanabilir.'],
            ])->status(403);
        }

        // Rollerin birleşik izinleri aktörün izinlerinin alt kümesi olmalı.
        $roleKeys = $roles->flatMap(fn (Role $r) => $r->permissions->pluck('key'))->unique()->all();
        $forbidden = array_diff($roleKeys, $actor->permissionKeys());

        if ($forbidden !== []) {
            throw ValidationException::withMessages([
                'roles' => ['Sahip olmadığınız yetkileri içeren bir rol atayamazsınız: '.implode(', ', $forbidden)],
            ])->status(403);
        }
    }
}
