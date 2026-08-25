<?php

namespace Tests\Feature\Reports;

use App\Modules\Kds\Models\ItemPickup;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * §11 Komi Teslim SLA raporu (`ops-delivery-sla`): izin kapısı, kiracı
 * izolasyonu, ihlal/açık-ihlal hesabı ve komi bazında kırılım.
 *
 * Zaman kontrolü: KDS uçları (pickup/status) GERÇEK akışla kaydı üretir
 * (order_item.status + order_events + kds_item_pickups tutarlı kalsın diye),
 * ardından test yalnız created_at damgalarını (ItemPickup/order_events)
 * geriye çekerek süreyi kontrol eder — NotifySlaAndRoutingTest'teki
 * "pickup->forceFill(created_at)" deseninin genişletilmiş hali.
 */
class DeliverySlaReportTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    public function test_rapor_ucu_izinsiz_403_izinli_200(): void
    {
        $kitchen = $this->makeTenantWithUser(['kds.view']);
        $this->actingAs($kitchen['user']);

        $this->getJson('/api/v1/reports/ops-delivery-sla')->assertForbidden();

        auth('web')->logout();
        $owner = $this->makeTenantWithUser();
        $this->actingAs($owner['user']);

        $this->getJson('/api/v1/reports/ops-delivery-sla')->assertOk();
    }

    public function test_hic_teslim_kaydi_yokken_bos_durum_doner(): void
    {
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);

        $data = $this->getJson('/api/v1/reports/ops-delivery-sla')->assertOk()->json('data');

        $this->assertSame(0, $data['total']);
        $this->assertSame(0, $data['breached_count']);
        $this->assertSame(0, $data['open_breach_count']);
        $this->assertNull($data['avg_duration_minutes']);
        $this->assertSame([], $data['rows']);
        $this->assertSame([], $data['by_staff']);
    }

    /**
     * 3 teslim: (A) süresinde masaya verildi — ihlal DEĞİL; (B) geç masaya
     * verildi — İHLAL; (C) hâlâ masaya verilmedi ve hedefi aştı — AÇIK İHLAL.
     * Komi bazında kırılım: komi1 (A+B, 1 ihlal), komi2 (C, 1 açık ihlal).
     */
    public function test_ihlal_ve_acik_ihlal_dogru_hesaplanir_ve_komi_kirilimi(): void
    {
        $a = $this->makeTenantWithUser();
        $komi1 = $this->makeUserWithPermissions($a, ['kds.deliver', 'kds.view']);
        $komi2 = $this->makeUserWithPermissions($a, ['kds.deliver', 'kds.view']);
        $kitchen = $this->makeUserWithPermissions($a, ['kds.view']);

        $now = now();

        [$itemA, $orderA] = $this->makeReadyItem($a, $kitchen, 'Kebap');
        [$itemB, $orderB] = $this->makeReadyItem($a, $kitchen, 'Pide');
        [$itemC, $orderC] = $this->makeReadyItem($a, $kitchen, 'Lahmacun');

        // (A) komi1 teslim alır, 1 dk sonra masaya verir (hedef 2 dk — İHLAL DEĞİL).
        $this->actingAs($komi1);
        $this->postJson("/api/v1/kds/items/{$itemA}/pickup")->assertCreated();
        $this->postJson("/api/v1/kds/items/{$itemA}/status", ['to' => 'served'])->assertOk();

        // (B) komi1 teslim alır, 5 dk sonra masaya verir (İHLAL — kapalı).
        $this->postJson("/api/v1/kds/items/{$itemB}/pickup")->assertCreated();
        $this->postJson("/api/v1/kds/items/{$itemB}/status", ['to' => 'served'])->assertOk();

        // (C) komi2 teslim alır, HÂLÂ masaya vermedi (AÇIK İHLAL).
        auth('web')->logout();
        $this->actingAs($komi2);
        $this->postJson("/api/v1/kds/items/{$itemC}/pickup")->assertCreated();
        auth('web')->logout();

        // Zaman damgalarını geriye çek (gerçek akış korunur, yalnız süre kontrol edilir).
        $this->backdatePickup($itemA, $now->copy()->subMinutes(6));
        $this->backdateServedEvent($itemA, $now->copy()->subMinutes(5)); // 6→5: 1 dk

        $this->backdatePickup($itemB, $now->copy()->subMinutes(10));
        $this->backdateServedEvent($itemB, $now->copy()->subMinutes(5)); // 10→5: 5 dk

        $this->backdatePickup($itemC, $now->copy()->subMinutes(5)); // hâlâ açık, ~5 dk geçti

        $this->actingAs($a['user']);
        $data = $this->getJson('/api/v1/reports/ops-delivery-sla')->assertOk()->json('data');

        $this->assertSame(2, $data['target_minutes']);
        $this->assertSame(3, $data['total']);
        $this->assertSame(2, $data['breached_count']); // B (kapalı) + C (açık)
        $this->assertSame(1, $data['open_breach_count']); // yalnız C

        $rows = collect($data['rows'])->keyBy('item');
        $this->assertFalse($rows['Kebap']['breached']);
        $this->assertSame(1, $rows['Kebap']['duration_minutes']);
        $this->assertSame('Teslim edildi', $rows['Kebap']['status']);

        $this->assertTrue($rows['Pide']['breached']);
        $this->assertSame(5, $rows['Pide']['duration_minutes']);
        $this->assertSame('Teslim edildi', $rows['Pide']['status']);

        $this->assertTrue($rows['Lahmacun']['breached']);
        $this->assertSame('Beklemede', $rows['Lahmacun']['status']);
        $this->assertNull($rows['Lahmacun']['served_at']);
        $this->assertGreaterThanOrEqual(4, $rows['Lahmacun']['duration_minutes']); // ~5 dk (istek anına kadar akıyor)

        // Komi bazında kırılım.
        $byStaff = collect($data['by_staff'])->keyBy('name');
        $this->assertSame(2, $byStaff[$komi1->name]['deliveries']);
        $this->assertSame(1, $byStaff[$komi1->name]['breaches']);
        $this->assertSame(1, $byStaff[$komi2->name]['deliveries']);
        $this->assertSame(1, $byStaff[$komi2->name]['breaches']);
    }

    public function test_kiraci_izolasyonu_yabanci_teslim_sizmaz(): void
    {
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        $komiB = $this->makeUserWithPermissions($b, ['kds.deliver', 'kds.view']);
        $kitchenB = $this->makeUserWithPermissions($b, ['kds.view']);

        [$itemB] = $this->makeReadyItem($b, $kitchenB, 'B Ürünü');
        $this->actingAs($komiB);
        $this->postJson("/api/v1/kds/items/{$itemB}/pickup")->assertCreated();
        auth('web')->logout();

        $this->actingAs($a['user']);
        $data = $this->getJson('/api/v1/reports/ops-delivery-sla')->assertOk()->json('data');

        $this->assertSame(0, $data['total']);
        $this->assertSame([], $data['rows']);
    }

    /* ---------------- yardımcılar ---------------- */

    /** @param array{tenant: mixed, branch: mixed} $ctx */
    protected function makeUserWithPermissions(array $ctx, array $permissionKeys): \App\Modules\Identity\Models\User
    {
        $role = \App\Modules\Identity\Models\Role::factory()->create(['tenant_id' => $ctx['tenant']->id]);
        $role->permissions()->sync(
            \App\Modules\Identity\Models\Permission::query()->whereIn('key', $permissionKeys)->pluck('id')->all(),
        );

        $user = \App\Modules\Identity\Models\User::factory()->create([
            'tenant_id' => $ctx['tenant']->id,
            'branch_id' => $ctx['branch']->id,
        ]);
        $user->roles()->sync([$role->id]);

        return $user;
    }

    /**
     * Masa + ürün + adisyon + kalem oluşturur (SAHİP — tüm izinler; adisyon/
     * kalem açma orders.* ister, kitchenUser'da genelde yok), sonra mutfak
     * kullanıcısıyla 'ready' durumuna ilerletir.
     *
     * @param  array{tenant: mixed, branch: mixed, user: \App\Modules\Identity\Models\User}  $ctx
     * @return array{0: int, 1: int} [item_id, order_id]
     */
    protected function makeReadyItem(array $ctx, \App\Modules\Identity\Models\User $kitchenUser, string $name): array
    {
        $this->actingAs($ctx['user']);

        $table = $this->makeTable($ctx);
        $orderId = (int) $this->postJson('/api/v1/orders', [
            'branch_id' => $ctx['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertCreated()->json('order.id');

        $product = $this->makeProduct($ctx, ['name' => $name, 'station' => 'kitchen']);
        $res = $this->postJson("/api/v1/orders/{$orderId}/items", [
            'product_id' => $product->id, 'qty' => 1,
        ])->assertCreated();
        $itemId = (int) collect($res->json('order.items'))->last()['id'];
        auth('web')->logout();

        $this->actingAs($kitchenUser);
        $this->postJson("/api/v1/kds/items/{$itemId}/status", ['to' => 'ready'])->assertOk();
        auth('web')->logout();

        return [$itemId, $orderId];
    }

    protected function backdatePickup(int $itemId, \Illuminate\Support\Carbon $at): void
    {
        ItemPickup::withoutTenancy()->where('order_item_id', $itemId)->update(['created_at' => $at]);
    }

    protected function backdateServedEvent(int $itemId, \Illuminate\Support\Carbon $at): void
    {
        DB::table('order_events')
            ->where('order_item_id', $itemId)
            ->where('to_status', 'served')
            ->update(['created_at' => $at]);
    }
}
