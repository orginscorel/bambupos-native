<?php

namespace Tests\Feature\Payments;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Yetki: ödeme alma `payments.take`; void/iade AYRI izin `payments.refund`;
 * kasa görüntüleme `cash.view`; açılış/kapanış/hareket `cash.close`.
 */
class PaymentAuthorizationTest extends TestCase
{
    use InteractsWithOrders, InteractsWithPayments, InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
    }

    public function test_payments_take_izni_olmadan_odeme_alinamaz(): void
    {
        $owner = $this->makeTenantWithUser(); // tüm izinler — adisyonu kurar
        $this->actingAs($owner['user']);
        $orderId = $this->makeOrderWithTotal($owner, 10000);
        auth('web')->logout();

        // Garson: sipariş izinleri var ama payments.take YOK.
        $waiter = $this->makeWaiter($owner);
        $this->actingAs($waiter);

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 1000,
        ])->assertForbidden();

        $this->getJson('/api/v1/payments/pending-orders')->assertForbidden();
        $this->get('/panel/kasa')->assertForbidden();
    }

    public function test_iade_ve_void_ayri_izin_ister(): void
    {
        $owner = $this->makeTenantWithUser();
        $this->actingAs($owner['user']);
        $orderId = $this->makeOrderWithTotal($owner, 10000);
        $paymentId = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->json('payment.id');
        auth('web')->logout();

        // Kasiyer: payments.take VAR ama payments.refund YOK.
        $cashier = $this->makeCashier($owner, withRefund: false);
        $this->actingAs($cashier);

        $this->postJson("/api/v1/payments/{$paymentId}/void", ['reason' => 'deneme void'])->assertForbidden();
        $this->postJson("/api/v1/payments/{$paymentId}/refund", ['amount_minor' => 1000, 'reason' => 'deneme iade'])->assertForbidden();

        auth('web')->logout();

        // payments.refund olan kullanıcı iade edebilir.
        $senior = $this->makeCashier($owner, withRefund: true);
        $this->actingAs($senior);

        $this->postJson("/api/v1/payments/{$paymentId}/refund", ['amount_minor' => 1000, 'reason' => 'kısmi iade'])->assertCreated();
    }

    public function test_kasa_islemleri_cash_close_ister(): void
    {
        $owner = $this->makeTenantWithUser();
        $this->actingAs($owner['user']);
        $register = $this->makeRegister($owner);
        auth('web')->logout();

        // Yalnız cash.view: görebilir, yönetemez.
        $viewer = $this->makeUserWith($owner, ['cash.view', 'payments.take', 'orders.view']);
        $this->actingAs($viewer);

        $this->getJson('/api/v1/cash/registers')->assertOk();
        $this->get('/panel/kasa/yonetim')->assertOk();

        $this->postJson('/api/v1/cash/sessions', [
            'cash_register_id' => $register->id, 'opening_float_minor' => 5000,
        ])->assertForbidden();

        $this->postJson('/api/v1/cash/registers', [
            'branch_id' => $owner['branch']->id, 'name' => 'Kasa 2',
        ])->assertForbidden();

        auth('web')->logout();

        // cash.close olan açabilir/kapatabilir.
        $manager = $this->makeUserWith($owner, ['cash.view', 'cash.close', 'payments.take', 'orders.view']);
        $this->actingAs($manager);

        $sessionId = $this->postJson('/api/v1/cash/sessions', [
            'cash_register_id' => $register->id, 'opening_float_minor' => 5000,
        ])->assertCreated()->json('session.id');

        // cash.view'lı kullanıcı kapatamaz.
        auth('web')->logout();
        $this->actingAs($viewer);
        $this->postJson("/api/v1/cash/sessions/{$sessionId}/close", ['counted_cash_minor' => 5000])->assertForbidden();

        auth('web')->logout();
        $this->actingAs($manager);
        $this->postJson("/api/v1/cash/sessions/{$sessionId}/close", ['counted_cash_minor' => 5000])->assertOk();
    }

    /* ---- yardımcılar ---- */

    private function makeWaiter(array $ctx): \App\Modules\Identity\Models\User
    {
        return $this->makeUserWith($ctx, ['orders.view', 'orders.create', 'orders.update']);
    }

    private function makeCashier(array $ctx, bool $withRefund): \App\Modules\Identity\Models\User
    {
        $keys = ['orders.view', 'payments.take', 'cash.view'];

        if ($withRefund) {
            $keys[] = 'payments.refund';
        }

        return $this->makeUserWith($ctx, $keys);
    }

    /** @param array<int, string> $keys */
    private function makeUserWith(array $ctx, array $keys): \App\Modules\Identity\Models\User
    {
        $role = \App\Modules\Identity\Models\Role::factory()->create(['tenant_id' => $ctx['tenant']->id]);
        $role->permissions()->sync(
            \App\Modules\Identity\Models\Permission::query()->whereIn('key', $keys)->pluck('id')->all(),
        );

        $user = \App\Modules\Identity\Models\User::factory()->create([
            'tenant_id' => $ctx['tenant']->id,
            'branch_id' => $ctx['branch']->id,
        ]);
        $user->roles()->sync([$role->id]);

        return $user;
    }
}
