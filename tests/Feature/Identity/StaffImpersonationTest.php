<?php

namespace Tests\Feature\Identity;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Personel taklidi ("test için giriş"): yalnız staff.manage başlatır,
 * yüksek/eşit yetkili taklit edilemez, kendini taklit edemez, kiracı
 * izolasyonu, başlat/bitir oturum geçişi.
 */
class StaffImpersonationTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    /** Aynı kiracıda verilen izinlere sahip bir personel üretir. */
    private function makeColleague(array $setup, array $permissionKeys = [], bool $systemRole = false): User
    {
        $role = Role::factory()->create(['tenant_id' => $setup['tenant']->id]);

        if ($systemRole) {
            $role->forceFill(['is_system' => true])->save();
        }

        $role->permissions()->sync(
            Permission::query()->whereIn('key', $permissionKeys)->pluck('id')->all(),
        );

        $user = User::factory()->create([
            'tenant_id' => $setup['tenant']->id,
            'branch_id' => $setup['branch']->id,
        ]);
        $user->roles()->sync([$role->id]);

        return $user;
    }

    public function test_staff_manage_olmayan_taklit_baslatamaz(): void
    {
        $setup = $this->makeTenantWithUser(['staff.view']);
        $garson = $this->makeColleague($setup, ['orders.view']);

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/staff/{$garson->id}/impersonate")
            ->assertForbidden();
    }

    public function test_yonetici_personeli_taklit_eder(): void
    {
        $setup = $this->makeTenantWithUser([]); // tüm izinler
        $garson = $this->makeColleague($setup, ['orders.view']);

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/staff/{$garson->id}/impersonate")
            ->assertOk()
            ->assertJsonPath('redirect_to', '/panel');

        // Oturum artık personel; asıl yönetici id'si session'da.
        $this->assertAuthenticatedAs($garson->fresh(), 'web');
    }

    public function test_kendini_taklit_edemez(): void
    {
        $setup = $this->makeTenantWithUser([]);

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/staff/{$setup['user']->id}/impersonate")
            ->assertForbidden();
    }

    public function test_pasif_personel_taklit_edilemez(): void
    {
        $setup = $this->makeTenantWithUser([]);
        $garson = $this->makeColleague($setup, ['orders.view']);
        $garson->forceFill(['is_active' => false])->save();

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/staff/{$garson->id}/impersonate")
            ->assertStatus(422);
    }

    public function test_sistem_rolu_tasiyan_taklit_edilemez(): void
    {
        $setup = $this->makeTenantWithUser([]);
        $owner = $this->makeColleague($setup, [], systemRole: true);

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/staff/{$owner->id}/impersonate")
            ->assertForbidden();
    }

    public function test_staff_manage_yetkili_taklit_edilemez(): void
    {
        $setup = $this->makeTenantWithUser([]);
        $mudur = $this->makeColleague($setup, ['staff.view', 'staff.manage']);

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/staff/{$mudur->id}/impersonate")
            ->assertForbidden();
    }

    public function test_yabanci_kiracinin_personeli_taklit_edilemez(): void
    {
        $setupA = $this->makeTenantWithUser([]);
        $setupB = $this->makeTenantWithUser(['orders.view']);

        $this->actingAs($setupA['user'])
            ->postJson("/api/v1/staff/{$setupB['user']->id}/impersonate")
            ->assertNotFound(); // route binding kiracı süzgeci
    }

    public function test_zaten_taklitteyken_yeni_taklit_baslatilamaz(): void
    {
        $setup = $this->makeTenantWithUser([]);
        $garson = $this->makeColleague($setup, ['orders.view']);

        $this->actingAs($setup['user'])
            ->withSession(['impersonator_id' => $setup['user']->id])
            ->postJson("/api/v1/staff/{$garson->id}/impersonate")
            ->assertStatus(409);
    }

    public function test_yoneticiye_don_asil_hesaba_dondurur(): void
    {
        $setup = $this->makeTenantWithUser([]);
        $garson = $this->makeColleague($setup, ['orders.view']);

        $this->actingAs($garson)
            ->withSession(['impersonator_id' => $setup['user']->id])
            ->postJson('/api/v1/staff/stop-impersonate')
            ->assertOk()
            ->assertJsonPath('redirect_to', '/panel/personel')
            ->assertSessionMissing('impersonator_id');

        $this->assertAuthenticatedAs($setup['user']->fresh(), 'web');
    }

    public function test_taklit_yokken_don_409(): void
    {
        $setup = $this->makeTenantWithUser([]);

        $this->actingAs($setup['user'])
            ->postJson('/api/v1/staff/stop-impersonate')
            ->assertStatus(409);
    }
}
