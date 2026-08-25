<?php

declare(strict_types=1);

namespace Tests\Feature\Boss;

use App\Modules\Orders\Models\Order;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * YÖNETİM KOKPİTİ (BOSS) testleri: izin kapısı, çıktı yapısı, kiracı/şube
 * izolasyonu (başka şube/kiracı cirosu sızmaz) ve boş veride çökmezlik.
 */
class BossOverviewTest extends TestCase
{
    use InteractsWithOrders, InteractsWithPayments, InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    public function test_boss_ucu_izinsiz_403_izinli_200_ve_yapi(): void
    {
        // boss.view OLMAYAN personel → 403.
        $staff = $this->makeTenantWithUser(['orders.view', 'catalog.view', 'tables.view']);
        $this->actingAs($staff['user']);
        $this->getJson('/api/v1/boss/overview')->assertForbidden();

        // Sonraki kiracı kurulmadan önce açıkça çıkış (TenantContext sızmasın).
        auth('web')->logout();

        // Tüm izinli sahip (boss.view dahil) → 200 + beklenen bölümler.
        $owner = $this->makeTenantWithUser();
        $this->actingAs($owner['user']);

        $this->getJson('/api/v1/boss/overview')
            ->assertOk()
            ->assertJsonStructure([
                'data' => [
                    'range' => ['from', 'to', 'branch_id', 'timezone'],
                    'sales' => ['revenue_minor', 'orders', 'avg_basket_minor', 'prev', 'delta_pct'],
                    'by_day',
                    'by_hour',
                    'payment_mix' => ['total_minor', 'rows'],
                    'service_types' => ['total_minor', 'rows'],
                    'top_products',
                    'open' => ['open_orders', 'open_amount_minor', 'open_tables', 'receivables' => ['count', 'total_minor', 'enabled']],
                    'staff' => ['rows', 'commission_total_minor', 'sales_total_minor'],
                ],
            ]);
    }

    public function test_ciro_kiraci_ve_sube_izolasyonu(): void
    {
        // Yabancı KİRACI: kendi kapanmış adisyonu A'ya SIZMAMALI.
        $b = $this->makeTenantWithUser();
        $this->makePaidOrder($b, $b['branch']->id, 88800);

        // A kiracısı: geçerli şubesinde (branch1) 100,00 TL'lik kapanmış adisyon.
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);
        $orderId = $this->makeOrderWithTotal($a, 10000);
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000, 'tendered_minor' => 10000,
        ])->assertCreated();

        // A kiracısının BAŞKA şubesinde kapanmış adisyon — geçerli şube branch1
        // olduğu için kokpite SIZMAMALI (şube kapsamı).
        $branch2 = Branch::factory()->create(['tenant_id' => $a['tenant']->id]);
        $this->makePaidOrder($a, (int) $branch2->id, 55500);

        $data = $this->getJson('/api/v1/boss/overview')->assertOk()->json('data');

        // Yalnız A/branch1'in 100,00 TL cirosu — B'nin 888,00 ve branch2'nin 555,00 HARİÇ.
        $this->assertSame(10000, $data['sales']['revenue_minor']);
        $this->assertSame(1, $data['sales']['orders']);
        $this->assertSame((int) $a['branch']->id, $data['range']['branch_id']);
    }

    public function test_bos_veride_cokmez(): void
    {
        $owner = $this->makeTenantWithUser();
        $this->actingAs($owner['user']);

        $data = $this->getJson('/api/v1/boss/overview?period=month')->assertOk()->json('data');

        $this->assertSame(0, $data['sales']['revenue_minor']);
        $this->assertSame(0, $data['sales']['orders']);
        $this->assertSame(0, $data['sales']['avg_basket_minor']);
        $this->assertNull($data['sales']['delta_pct']['revenue']); // önceki dönem 0 → uydurma % yok
        $this->assertCount(24, $data['by_hour']); // saatlik seri her zaman 0-23 dolu
        $this->assertSame([], $data['payment_mix']['rows']);
        $this->assertSame([], $data['top_products']);
        $this->assertSame(0, $data['open']['open_tables']);
    }

    /**
     * Kiracı bağlamında doğrudan KAPANMIŞ (paid) adisyon üretir — belirli
     * şubeye bağlar (izolasyon testleri için, API akışına gerek kalmadan).
     *
     * @param  array{tenant: mixed}  $ctx
     */
    private function makePaidOrder(array $ctx, int $branchId, int $totalMinor): void
    {
        $this->asTenant($ctx['tenant'], function () use ($branchId, $totalMinor): void {
            $order = new Order([
                'status' => 'paid',
                'total_minor' => $totalMinor,
                'currency' => 'TRY',
                'channel' => 'table',
                'service_type' => 'dine_in',
            ]);
            $order->branch_id = $branchId;
            $order->closed_at = now();
            $order->save();
        });
    }
}
