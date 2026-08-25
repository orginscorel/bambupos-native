<?php

namespace Tests\Feature\Identity;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Support\HomeScreen;
use App\Modules\Identity\Support\RoleTemplates;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Personel-Yetki: kişi bazlı izin istisnaları, işten çıkarma,
 * rol kopyalama, varsayılan şablon setleri ve açılış ekranı.
 */
class StaffManagementTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    /** Aynı kiracıda ikinci bir personel üretir. */
    private function makeColleague(array $setup, array $permissionKeys = []): User
    {
        $role = Role::factory()->create(['tenant_id' => $setup['tenant']->id]);
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

    /* ================= Yetki matrisi uygulanıyor ================= */

    public function test_staff_view_izni_olmayan_personel_listesine_erisemez(): void
    {
        $setup = $this->makeTenantWithUser(['orders.view']);

        $this->actingAs($setup['user'])->getJson('/api/v1/staff')->assertForbidden();
        $this->actingAs($setup['user'])->get('/panel/personel')->assertForbidden();
    }

    public function test_roles_view_izni_olmayan_rol_sayfasina_erisemez(): void
    {
        $setup = $this->makeTenantWithUser(['orders.view']);

        $this->actingAs($setup['user'])->get('/panel/personel/roller')->assertForbidden();
        $this->actingAs($setup['user'])->getJson('/api/v1/staff-access/meta')->assertForbidden();
    }

    public function test_staff_view_ile_sayfa_ve_meta_acilir(): void
    {
        $setup = $this->makeTenantWithUser(['staff.view']);

        $this->actingAs($setup['user'])->get('/panel/personel')->assertOk();

        $meta = $this->actingAs($setup['user'])->getJson('/api/v1/staff-access/meta')->assertOk()->json();

        $this->assertNotEmpty($meta['catalog']);
        $this->assertNotEmpty($meta['templates']);
        // Tehlikeli izin işareti taşınıyor
        $orders = collect($meta['catalog'])->firstWhere('module', 'orders');
        $refund = collect($orders['permissions'])->firstWhere('key', 'orders.refund');
        $this->assertTrue($refund['dangerous']);
        $this->assertNotEmpty($refund['warning']);
    }

    /* ================= Kişi bazlı istisna (grant/revoke) ================= */

    public function test_kisisel_grant_rol_setinin_ustune_izin_ekler(): void
    {
        $setup = $this->makeTenantWithUser(['staff.view', 'staff.manage', 'orders.view', 'orders.discount']);
        $garson = $this->makeColleague($setup, ['orders.view']);

        $this->assertFalse($garson->hasPermission('orders.discount'));

        $this->actingAs($setup['user'])
            ->putJson("/api/v1/staff-access/{$garson->id}/overrides", [
                'grants' => ['orders.discount'],
                'revokes' => [],
            ])
            ->assertOk()
            ->assertJsonPath('overrides.grant.0', 'orders.discount');

        $garson->refresh()->flushPermissionCache();
        $this->assertTrue($garson->hasPermission('orders.discount'));
        $this->assertTrue($garson->hasPermission('orders.view')); // rolden gelen korunur
    }

    public function test_kisisel_revoke_rolden_gelen_izni_dusurur(): void
    {
        $setup = $this->makeTenantWithUser(['staff.view', 'staff.manage', 'orders.view', 'orders.create']);
        $garson = $this->makeColleague($setup, ['orders.view', 'orders.create']);

        $this->actingAs($setup['user'])
            ->putJson("/api/v1/staff-access/{$garson->id}/overrides", [
                'grants' => [],
                'revokes' => ['orders.create'],
            ])
            ->assertOk();

        $garson->refresh()->flushPermissionCache();
        $this->assertFalse($garson->hasPermission('orders.create'));
        $this->assertTrue($garson->hasPermission('orders.view'));
    }

    public function test_yetki_yukseltme_kendinde_olmayan_izin_grant_edilemez(): void
    {
        // Aktörde payments.refund YOK
        $setup = $this->makeTenantWithUser(['staff.view', 'staff.manage', 'orders.view']);
        $kasiyer = $this->makeColleague($setup, ['orders.view']);

        $this->actingAs($setup['user'])
            ->putJson("/api/v1/staff-access/{$kasiyer->id}/overrides", [
                'grants' => ['payments.refund'],
                'revokes' => [],
            ])
            ->assertForbidden();

        $kasiyer->refresh()->flushPermissionCache();
        $this->assertFalse($kasiyer->hasPermission('payments.refund'));
    }

    public function test_kendi_istisnalarini_degistiremez(): void
    {
        $setup = $this->makeTenantWithUser([]); // tüm izinler

        $this->actingAs($setup['user'])
            ->putJson("/api/v1/staff-access/{$setup['user']->id}/overrides", [
                'grants' => [],
                'revokes' => ['orders.view'],
            ])
            ->assertForbidden();
    }

    public function test_sistem_rolu_tasiyan_kullanicidan_izin_dusulemez(): void
    {
        $setup = $this->makeTenantWithUser([]); // aktör: tüm izinler

        $ownerRole = Role::factory()->create(['tenant_id' => $setup['tenant']->id]);
        $ownerRole->forceFill(['is_system' => true])->save();
        $ownerRole->permissions()->sync(Permission::query()->pluck('id')->all());

        $owner = User::factory()->create(['tenant_id' => $setup['tenant']->id]);
        $owner->roles()->sync([$ownerRole->id]);

        $this->actingAs($setup['user'])
            ->putJson("/api/v1/staff-access/{$owner->id}/overrides", [
                'grants' => [],
                'revokes' => ['orders.view'],
            ])
            ->assertForbidden();
    }

    public function test_kiraci_izolasyonu_yabanci_personelin_istisnasi_yazilamaz(): void
    {
        $setupA = $this->makeTenantWithUser([]); // A kiracısı, tüm izinler
        $setupB = $this->makeTenantWithUser(['orders.view']);

        $this->actingAs($setupA['user'])
            ->putJson("/api/v1/staff-access/{$setupB['user']->id}/overrides", [
                'grants' => ['orders.view'],
                'revokes' => [],
            ])
            ->assertNotFound(); // route binding kiracı süzgeci: 404
    }

    /* ================= İşten çıkarma / pasifleştirme ================= */

    public function test_isten_cikarma_pasife_alir_ve_kayit_silinmez(): void
    {
        $setup = $this->makeTenantWithUser([]);
        $garson = $this->makeColleague($setup, ['orders.view']);

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/staff-access/{$garson->id}/terminate")
            ->assertOk();

        $this->assertDatabaseHas('users', ['id' => $garson->id, 'is_active' => false]);
    }

    public function test_pasif_personelin_acik_oturumu_dusurulur(): void
    {
        $setup = $this->makeTenantWithUser(['staff.view']);
        $setup['user']->forceFill(['is_active' => false])->save();

        // Oturum sürüyor olsa da EnsureUserIsActive keser
        $this->actingAs($setup['user'])->getJson('/api/v1/staff')->assertForbidden();
    }

    public function test_kendini_isten_cikaramaz(): void
    {
        $setup = $this->makeTenantWithUser([]);

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/staff-access/{$setup['user']->id}/terminate")
            ->assertForbidden();
    }

    public function test_sistem_rolu_tasiyan_isten_cikarilamaz(): void
    {
        $setup = $this->makeTenantWithUser([]);

        $ownerRole = Role::factory()->create(['tenant_id' => $setup['tenant']->id]);
        $ownerRole->forceFill(['is_system' => true])->save();

        $owner = User::factory()->create(['tenant_id' => $setup['tenant']->id]);
        $owner->roles()->sync([$ownerRole->id]);

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/staff-access/{$owner->id}/terminate")
            ->assertForbidden();

        // Aynı koruma is_active=false güncellemesi için de geçerli
        $this->actingAs($setup['user'])
            ->putJson("/api/v1/staff/{$owner->id}", ['is_active' => false])
            ->assertForbidden();
    }

    /* ================= PIN + parola sıfırlama ================= */

    public function test_yonetici_pin_belirler_ve_kaldirir(): void
    {
        $setup = $this->makeTenantWithUser([]);
        $garson = $this->makeColleague($setup, ['orders.view']);

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/staff-access/{$garson->id}/pin", ['pin' => '731942'])
            ->assertOk();

        $this->assertNotNull($garson->fresh()->pin_hash);

        $this->actingAs($setup['user'])
            ->deleteJson("/api/v1/staff-access/{$garson->id}/pin")
            ->assertOk();

        $this->assertNull($garson->fresh()->pin_hash);
    }

    public function test_staff_manage_izni_olmayan_pin_belirleyemez(): void
    {
        $setup = $this->makeTenantWithUser(['staff.view']);
        $garson = $this->makeColleague($setup, ['orders.view']);

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/staff-access/{$garson->id}/pin", ['pin' => '731942'])
            ->assertForbidden();
    }

    /* ================= Rol kopyalama + is_system koruması ================= */

    public function test_rol_kopyalama_izin_setini_klonlar(): void
    {
        $setup = $this->makeTenantWithUser([]); // tüm izinler

        $source = Role::factory()->create(['tenant_id' => $setup['tenant']->id, 'name' => 'Garson']);
        $source->permissions()->sync(
            Permission::query()->whereIn('key', ['orders.view', 'orders.create'])->pluck('id')->all(),
        );

        $response = $this->actingAs($setup['user'])
            ->postJson("/api/v1/roles/{$source->id}/copy")
            ->assertCreated()
            ->json();

        $copy = Role::query()->withoutGlobalScopes()->find($response['role']['id']);
        $this->assertSame('Garson (Kopya)', $copy->name);
        $this->assertFalse((bool) $copy->is_system);
        $this->assertEqualsCanonicalizing(
            ['orders.view', 'orders.create'],
            $copy->permissions()->pluck('key')->all(),
        );
    }

    public function test_rol_kopyalama_yetki_yukseltmeye_kapali(): void
    {
        // Aktörde payments.refund yok; kaynak rolde var → kopyalanamaz
        $setup = $this->makeTenantWithUser(['roles.view', 'roles.manage', 'orders.view']);

        $source = Role::factory()->create(['tenant_id' => $setup['tenant']->id]);
        $source->permissions()->sync(
            Permission::query()->whereIn('key', ['payments.refund'])->pluck('id')->all(),
        );

        $this->actingAs($setup['user'])
            ->postJson("/api/v1/roles/{$source->id}/copy")
            ->assertForbidden();
    }

    public function test_sistem_rolunun_izin_seti_degistirilemez(): void
    {
        $setup = $this->makeTenantWithUser([]);

        $system = Role::factory()->create(['tenant_id' => $setup['tenant']->id]);
        $system->forceFill(['is_system' => true])->save();
        $system->permissions()->sync(Permission::query()->pluck('id')->all());

        $this->actingAs($setup['user'])
            ->putJson("/api/v1/roles/{$system->id}", [
                'permissions' => [Permission::query()->where('key', 'orders.view')->value('id')],
            ])
            ->assertForbidden();
    }

    /* ================= Varsayılan şablon setleri ================= */

    public function test_sablonlar_mantikli_varsayilanlari_icerir(): void
    {
        $templates = RoleTemplates::all();

        // Garson: sipariş + masa + menü + ikram/indirim; kasa-rapor-personel KAPALI
        $garson = $templates['garson']['permissions'];
        foreach (['orders.view', 'orders.create', 'orders.update', 'orders.discount', 'orders.comp', 'tables.view', 'catalog.view'] as $key) {
            $this->assertContains($key, $garson, "garson: {$key} olmalı");
        }
        // DENETİM 2026-08-06: komi rolü yoksa garson "hazır" kalemi servis edebilsin
        // diye komi'deki AYNI izin (kds.deliver) eklendi; kds.view YOK (mutfak işi).
        $this->assertContains('kds.deliver', $garson, 'garson: kds.deliver olmalı (servis edebilsin)');
        $this->assertNotContains('kds.view', $garson, 'garson: kds.view OLMAMALI (mutfak/istasyon işi değil)');
        foreach (['cash.view', 'cash.close', 'payments.take', 'reports.view', 'staff.manage', 'orders.refund'] as $key) {
            $this->assertNotContains($key, $garson, "garson: {$key} OLMAMALI");
        }

        // Kasiyer: ödeme + kasa; İADE AYRI ve kapalı
        $kasiyer = $templates['kasiyer']['permissions'];
        foreach (['payments.take', 'cash.view', 'cash.close', 'orders.view'] as $key) {
            $this->assertContains($key, $kasiyer, "kasiyer: {$key} olmalı");
        }
        $this->assertNotContains('payments.refund', $kasiyer, 'kasiyer: iade AYRI yetkidir');
        $this->assertNotContains('orders.refund', $kasiyer);

        // Mutfak: yalnız KDS — fiyat/ciro/rapor kapalı
        $this->assertSame(['kds.view'], $templates['mutfak']['permissions']);

        // Şube müdürü: operasyon + rapor + sınırlı personel; rol tanımlayamaz
        $mudur = $templates['sube-muduru']['permissions'];
        foreach (['reports.view', 'staff.view', 'staff.manage', 'orders.cancel', 'cash.close'] as $key) {
            $this->assertContains($key, $mudur, "şube müdürü: {$key} olmalı");
        }
        $this->assertNotContains('roles.manage', $mudur);
        $this->assertNotContains('integrations.manage', $mudur);

        // Sahip: katalogdaki HER izin
        $this->assertCount(Permission::query()->count(), $templates['sahip']['permissions']);
    }

    public function test_varsayilan_setler_seedlenir(): void
    {
        $setup = $this->makeTenantWithUser([]);

        $this->seed(\Database\Seeders\StaffRoleDefaultsSeeder::class);

        $garson = Role::query()->withoutGlobalScopes()
            ->where('tenant_id', $setup['tenant']->id)
            ->where('slug', 'garson')
            ->first();

        $this->assertNotNull($garson);
        $this->assertContains('orders.comp', $garson->permissions()->pluck('key')->all());

        $sahip = Role::query()->withoutGlobalScopes()
            ->where('tenant_id', $setup['tenant']->id)
            ->where('slug', 'sahip')
            ->first();

        $this->assertTrue((bool) $sahip->is_system);
        $this->assertSame(Permission::query()->count(), $sahip->permissions()->count());
    }

    /* ================= Role özel açılış ekranı ================= */

    public function test_acilis_ekrani_profile_gore_secilir(): void
    {
        $mutfak = $this->makeTenantWithUser(['kds.view']);
        $this->assertSame('/panel/mutfak', HomeScreen::resolve($mutfak['user']));

        $kasiyer = $this->makeTenantWithUser(['payments.take', 'cash.view', 'orders.view']);
        $this->assertSame('/panel/kasa', HomeScreen::resolve($kasiyer['user']));

        $garson = $this->makeTenantWithUser(['orders.view', 'orders.create', 'tables.view', 'catalog.view']);
        $this->assertSame('/panel/siparisler', HomeScreen::resolve($garson['user']));

        $yonetici = $this->makeTenantWithUser([]); // tüm izinler (reports.view dahil)
        $this->assertSame('/panel', HomeScreen::resolve($yonetici['user']));
    }

    public function test_acilis_ekrani_tercihi_izinliyse_uygulanir(): void
    {
        $setup = $this->makeTenantWithUser(['orders.view', 'tables.view']);

        $setup['user']->forceFill(['default_screen' => 'tables'])->save();
        $this->assertSame('/panel/masalar', HomeScreen::resolve($setup['user']->fresh()));

        // İzinsiz tercih yok sayılır → otomatiğe düşer
        $setup['user']->forceFill(['default_screen' => 'cash'])->save();
        $this->assertSame('/panel/siparisler', HomeScreen::resolve($setup['user']->fresh()));
    }

    public function test_giris_yaniti_redirect_to_icerir(): void
    {
        $setup = $this->makeTenantWithUser(['kds.view']);
        $setup['user']->forceFill(['password' => 'sifre-123456'])->save();

        $this->postJson('/api/v1/auth/login', [
            'email' => $setup['user']->email,
            'password' => 'sifre-123456',
        ])
            ->assertOk()
            ->assertJsonPath('redirect_to', '/panel/mutfak');
    }
}
