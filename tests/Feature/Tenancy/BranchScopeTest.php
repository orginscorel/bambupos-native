<?php

namespace Tests\Feature\Tenancy;

use App\Modules\Identity\Models\User;
use App\Modules\Orders\Models\Order;
use App\Modules\Settings\Models\TenantFeature;
use App\Modules\Tenancy\BranchContext;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * ŞUBE KAPSAMI (izolasyonun 2. boyutu) — güvenlik testleri.
 *
 * Tek kiracı, İKİ şube (A/B). Personel kendi şubesine KİLİTLİ; yönetici
 * aktif seçili şubeyi görür ve değiştirebilir; başka şube verisi (sipariş/
 * rapor/ödeme/masa/rezervasyon) ASLA sızmaz; çok-şube kapalıysa tek-şube.
 */
class BranchScopeTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    private array $tenant;

    private Branch $branchA;

    private Branch $branchB;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();

        // Yönetici + A şubesi (makeTenantWithUser tüm izinleri verir = yönetici).
        $this->tenant = $this->makeTenantWithUser();
        $this->branchA = $this->tenant['branch'];

        $this->branchB = $this->asTenant(
            $this->tenant['tenant'],
            fn (): Branch => Branch::factory()->create([
                'tenant_id' => $this->tenant['tenant']->id,
                'name' => 'B Şube',
            ])
        );
    }

    /** Belirli izin setiyle (personel) kullanıcı — verilen şubeye atanmış. */
    private function staffOn(Branch $branch, array $permissions): User
    {
        $role = \App\Modules\Identity\Models\Role::factory()->create(['tenant_id' => $this->tenant['tenant']->id]);
        $role->permissions()->sync(
            \App\Modules\Identity\Models\Permission::query()->whereIn('key', $permissions)->pluck('id')->all()
        );

        $user = User::factory()->create([
            'tenant_id' => $this->tenant['tenant']->id,
            'branch_id' => $branch->id,
        ]);
        $user->roles()->sync([$role->id]);

        return $user;
    }

    private function openOrderOn(Branch $branch): Order
    {
        return $this->asTenant($this->tenant['tenant'], function () use ($branch): Order {
            $order = Order::factory()->create([
                'tenant_id' => $this->tenant['tenant']->id,
                'branch_id' => $branch->id,
                'status' => 'open',
            ]);

            return $order;
        });
    }

    /* ---------------- Çözücü birim davranışı ---------------- */

    public function test_personel_kendi_subesine_kilitli_session_ezmesi_yoksayilir(): void
    {
        $staff = $this->staffOn($this->branchB, ['orders.view']);
        $this->actingAs($staff);

        // Session'a A şubesini dayatmaya çalışsa bile B'ye kilitli kalır.
        session(['panel.active_branch_id' => $this->branchA->id]);

        $ctx = app(BranchContext::class);
        $this->assertSame($this->branchB->id, $ctx->currentBranchId());
        $this->assertTrue($ctx->isLocked($staff));
        $this->assertFalse($ctx->canSwitch($staff));
    }

    public function test_yonetici_aktif_secili_subeyi_gorur_ve_degistirir(): void
    {
        $manager = $this->tenant['user'];
        $this->actingAs($manager);

        $ctx = app(BranchContext::class);
        $this->assertFalse($ctx->isLocked($manager));
        $this->assertTrue($ctx->canSwitch($manager)); // 2 şube + yönetici

        // Varsayılan = kendi şubesi (A).
        $this->assertSame($this->branchA->id, $ctx->currentBranchId());

        session(['panel.active_branch_id' => $this->branchB->id]);
        app()->forgetInstance(BranchContext::class);
        $this->assertSame($this->branchB->id, app(BranchContext::class)->currentBranchId());
    }

    /* ---------------- Sipariş / pano izolasyonu ---------------- */

    public function test_personel_baska_sube_siparisini_goremez(): void
    {
        $orderA = $this->openOrderOn($this->branchA);
        $orderB = $this->openOrderOn($this->branchB);

        // B personeli yalnız B'yi görür.
        $staffB = $this->staffOn($this->branchB, ['orders.view']);
        $this->actingAs($staffB);

        $ids = collect($this->getJson('/api/v1/orders')->assertOk()->json('orders.data'))->pluck('id');
        $this->assertTrue($ids->contains($orderB->id));
        $this->assertFalse($ids->contains($orderA->id));

        // A şubesi siparişine doğrudan erişim de kapalı (403).
        $this->getJson("/api/v1/orders/{$orderA->id}")->assertForbidden();
    }

    public function test_yonetici_aktif_sube_degisince_pano_degisir(): void
    {
        $this->openOrderOn($this->branchA);
        $this->openOrderOn($this->branchB);

        $manager = $this->tenant['user'];
        $this->actingAs($manager);

        // A aktif (varsayılan) → yalnız A siparişleri panoda.
        $boardA = $this->getJson('/api/v1/orders/board')->assertOk()->json('channel_orders');
        $this->assertCount(1, $boardA);

        // B'ye geç → yalnız B.
        $this->postJson('/api/v1/auth/active-branch', ['branch_id' => $this->branchB->id])->assertOk();
        $boardB = $this->getJson('/api/v1/orders/board')->assertOk()->json('channel_orders');
        $this->assertCount(1, $boardB);
        $this->assertNotSame($boardA[0]['id'], $boardB[0]['id']);
    }

    /* ---------------- Ödeme / kasa izolasyonu ---------------- */

    public function test_kasa_yalnizca_gecerli_sube_acik_adisyonlarini_gorur(): void
    {
        $this->openOrderOn($this->branchA);
        $this->openOrderOn($this->branchB);

        $cashierB = $this->staffOn($this->branchB, ['payments.take', 'cash.view', 'orders.view']);
        $this->actingAs($cashierB);

        $pending = $this->getJson('/api/v1/payments/pending-orders')->assertOk()->json('orders');
        $this->assertCount(1, $pending);
        $this->assertSame($this->branchB->id, $this->openOrderBranchOf($pending[0]['id']));
    }

    private function openOrderBranchOf(int $orderId): int
    {
        return (int) Order::withoutTenancy()->whereKey($orderId)->value('branch_id');
    }

    /* ---------------- Şube değiştirici güvenliği ---------------- */

    public function test_kilitli_personel_sube_degistiremez_403(): void
    {
        $staff = $this->staffOn($this->branchB, ['orders.view']);
        $this->actingAs($staff);

        $this->postJson('/api/v1/auth/active-branch', ['branch_id' => $this->branchA->id])
            ->assertForbidden();

        // Session kirlenmedi → hâlâ B.
        $this->assertSame($this->branchB->id, app(BranchContext::class)->currentBranchId());
    }

    public function test_yonetici_yabanci_kiracinin_subesine_gecemez(): void
    {
        $other = $this->makeTenantWithUser();

        $manager = $this->tenant['user'];
        $this->actingAs($manager);

        // Başka kiracının şubesi → Branch model tenant-scope'lu → 404.
        $this->postJson('/api/v1/auth/active-branch', ['branch_id' => $other['branch']->id])
            ->assertNotFound();
    }

    /* ---------------- Çok-şube kapalı = tek-şube modu ---------------- */

    public function test_cok_sube_kapaliysa_switcher_gizli_ve_kilitli(): void
    {
        // branches feature'ı kapat.
        $this->asTenant($this->tenant['tenant'], function (): void {
            TenantFeature::query()->updateOrCreate(
                ['tenant_id' => $this->tenant['tenant']->id, 'feature' => 'branches'],
                ['enabled' => false],
            );
        });

        $manager = $this->tenant['user'];
        $this->actingAs($manager);

        $ctx = app(BranchContext::class);
        // Yönetici bile tek-şube modunda kilitli → switcher yok.
        $this->assertTrue($ctx->isLocked($manager));
        $this->assertFalse($ctx->canSwitch($manager));

        // Şube değiştirme ucu 403.
        $this->postJson('/api/v1/auth/active-branch', ['branch_id' => $this->branchB->id])
            ->assertForbidden();
    }
}
