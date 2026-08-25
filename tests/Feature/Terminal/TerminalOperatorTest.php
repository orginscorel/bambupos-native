<?php

namespace Tests\Feature\Terminal;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Orders\Models\Order;
use App\Modules\Payments\Models\Payment;
use App\Modules\Terminal\Models\TerminalDevice;
use App\Modules\Terminal\Services\TerminalProvisioner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * §13 İstasyon Cihaz Modu — FAZ C: AKTİF OPERATÖR (paylaşımlı cihazda "kim
 * çalışıyor"). Personel PIN'iyle kendini aktif eder; açtığı adisyon / aldığı
 * ödeme ONA atfedilir (gizli terminal kullanıcısına DEĞİL). NORMAL (terminal
 * olmayan) oturum davranışı DEĞİŞMEZ; hassas-eylem PIN kapısı BOZULMAZ.
 */
class TerminalOperatorTest extends TestCase
{
    use InteractsWithOrders, InteractsWithPayments, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser(); // yönetici (tüm izinler)
    }

    private function makeDevice(string $station, string $name = 'Terminal'): TerminalDevice
    {
        return $this->asTenant($this->a['tenant'], fn (): TerminalDevice => app(TerminalProvisioner::class)
            ->createDevice($name, (int) $this->a['branch']->id, (int) $this->a['tenant']->id, $station));
    }

    /** Aynı kiracı+şubede PIN'li + istenen izinlere sahip GERÇEK personel. */
    private function makeStaffWithPin(array $perms, string $pin, array $attrs = []): User
    {
        $role = Role::factory()->create(['tenant_id' => $this->a['tenant']->id]);
        $role->permissions()->sync(Permission::query()->whereIn('key', $perms)->pluck('id')->all());

        $user = User::factory()->create(array_merge([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'is_active' => true,
        ], $attrs));
        $user->roles()->sync([$role->id]);
        $user->forceFill(['pin_hash' => Hash::make($pin)])->save();

        return $user;
    }

    /** Terminalin şubesinde masa+ürün kurar, adisyon body'si döner. */
    private function orderBody(): array
    {
        $this->actingAs($this->a['user']);
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['price_minor' => 5000]);

        return [
            'body' => ['branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id],
            'product' => $product,
        ];
    }

    /* ---------------- Operatör seçimi (PIN) ---------------- */

    public function test_operator_secmeden_terminalden_siparis_acilamaz_422(): void
    {
        $ctx = $this->orderBody();

        $device = $this->makeDevice('order_entry');
        $this->actingAs(User::find($device->user_id));

        // Aktif operatör seçilmeden adisyon açma reddedilir.
        $this->postJson('/api/v1/orders', $ctx['body'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('operator');

        $this->assertSame(0, Order::withoutTenancy()->where('branch_id', $this->a['branch']->id)->count());
    }

    public function test_yanlis_pin_ile_operator_ayarlanamaz_422(): void
    {
        $staff = $this->makeStaffWithPin(['orders.create'], '246813');

        $device = $this->makeDevice('order_entry');
        $this->actingAs(User::find($device->user_id));

        $this->postJson('/terminal/operator', ['staff_id' => $staff->id, 'pin' => '999999'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('pin');
    }

    public function test_dogru_pin_ile_operator_ayarlanir(): void
    {
        $staff = $this->makeStaffWithPin(['orders.create'], '246813');

        $device = $this->makeDevice('order_entry');
        $this->actingAs(User::find($device->user_id));

        $this->postJson('/terminal/operator', ['staff_id' => $staff->id, 'pin' => '246813'])
            ->assertOk()
            ->assertJsonPath('operator.id', (int) $staff->id)
            ->assertJsonPath('operator.name', $staff->name);
    }

    public function test_baska_subedeki_personel_operator_olamaz_422(): void
    {
        // Başka şubede (ama aynı kiracıda) personel: bu terminalde operatör OLAMAZ.
        $other = $this->makeTenantWithUser();
        $staff = $this->makeStaffWithPin(['orders.create'], '246813', ['branch_id' => $other['branch']->id]);

        $device = $this->makeDevice('order_entry');
        $this->actingAs(User::find($device->user_id));

        $this->postJson('/terminal/operator', ['staff_id' => $staff->id, 'pin' => '246813'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('staff_id');
    }

    /* ---------------- Atıf: adisyon açılışı ---------------- */

    public function test_terminalde_acilan_siparis_aktif_operatore_atfedilir(): void
    {
        $ctx = $this->orderBody();
        $staff = $this->makeStaffWithPin(['orders.create'], '246813');

        $device = $this->makeDevice('order_entry');
        $terminalUser = User::find($device->user_id);
        $this->actingAs($terminalUser);

        // Operatörü aktif et.
        $this->postJson('/terminal/operator', ['staff_id' => $staff->id, 'pin' => '246813'])->assertOk();

        // Adisyon aç → opened_by = OPERATÖR (gizli terminal kullanıcısı DEĞİL).
        $orderId = $this->postJson('/api/v1/orders', $ctx['body'])->assertCreated()->json('order.id');

        $order = Order::withoutTenancy()->findOrFail($orderId);
        $this->assertSame((int) $staff->id, (int) $order->opened_by_id);
        $this->assertNotSame((int) $device->user_id, (int) $order->opened_by_id);
    }

    /* ---------------- BUG #1 fix: operatör yokken PIN-fallback ---------------- */

    public function test_operator_yokken_pin_ile_siparis_acilir_personele_atfedilir(): void
    {
        // Kasa'daki (payments) desenle AYNI: aktif operatör seçilmemiş olsa
        // bile gövdede PIN gelirse adisyon PIN sahibi personele atfedilerek
        // açılır — "Önce personel seçin" duvarına takılmaz (BUG #1 fix).
        $ctx = $this->orderBody();
        $staff = $this->makeStaffWithPin(['orders.create'], '246813');

        $device = $this->makeDevice('order_entry');
        $this->actingAs(User::find($device->user_id));

        $orderId = $this->postJson('/api/v1/orders', $ctx['body'] + ['pin' => '246813'])
            ->assertCreated()
            ->json('order.id');

        $order = Order::withoutTenancy()->findOrFail($orderId);
        $this->assertSame((int) $staff->id, (int) $order->opened_by_id);
        $this->assertNotSame((int) $device->user_id, (int) $order->opened_by_id);
    }

    public function test_operator_yokken_yetkisiz_pin_ile_siparis_acilamaz(): void
    {
        $ctx = $this->orderBody();
        // PIN'li ama orders.create İZNİ YOK.
        $this->makeStaffWithPin(['orders.view'], '135791');

        $device = $this->makeDevice('order_entry');
        $this->actingAs(User::find($device->user_id));

        $this->postJson('/api/v1/orders', $ctx['body'] + ['pin' => '135791'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('pin');

        $this->assertSame(0, Order::withoutTenancy()->where('branch_id', $this->a['branch']->id)->count());
    }

    /* ---------------- Atıf: ödeme alımı ---------------- */

    public function test_terminalde_alinan_odeme_aktif_operatore_atfedilir_pinsiz(): void
    {
        $this->actingAs($this->a['user']);
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        $staff = $this->makeStaffWithPin(['payments.take'], '246813');

        $device = $this->makeDevice('kasa');
        $this->actingAs(User::find($device->user_id));

        // Operatör aktif; ödeme PIN GÖNDERMEDEN alınır → operatöre atfedilir.
        $this->postJson('/terminal/operator', ['staff_id' => $staff->id, 'pin' => '246813'])->assertOk();

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->assertCreated();

        $payment = Payment::withoutTenancy()->where('order_id', $orderId)->where('kind', 'payment')->first();
        $this->assertNotNull($payment);
        $this->assertSame((int) $staff->id, (int) $payment->cashier_id);
        $this->assertNotSame((int) $device->user_id, (int) $payment->cashier_id);
    }

    public function test_operator_yetkisizse_odeme_reddedilir(): void
    {
        $this->actingAs($this->a['user']);
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        // Operatör aktif ama payments.take YOK.
        $staff = $this->makeStaffWithPin(['orders.view'], '246813');

        $device = $this->makeDevice('kasa');
        $this->actingAs(User::find($device->user_id));

        $this->postJson('/terminal/operator', ['staff_id' => $staff->id, 'pin' => '246813'])->assertOk();

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->assertStatus(422)->assertJsonValidationErrors('operator');

        $this->assertSame(0, Payment::withoutTenancy()->where('order_id', $orderId)->count());
    }

    /* ---------------- NON-terminal davranışı DEĞİŞMEZ ---------------- */

    public function test_normal_oturumda_operator_gerekmez_davranis_degismez(): void
    {
        $this->actingAs($this->a['user']);
        $table = $this->makeTable($this->a);
        $this->makeProduct($this->a, ['price_minor' => 5000]);

        // Yönetici (terminal DEĞİL): operatör kavramı yok — adisyon açılır,
        // opened_by = oturum kullanıcısının kendisi.
        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertCreated()->json('order.id');

        $order = Order::withoutTenancy()->findOrFail($orderId);
        $this->assertSame((int) $this->a['user']->id, (int) $order->opened_by_id);
    }

    /* ---------------- Idle-timeout ---------------- */

    public function test_idle_timeout_sonrasi_operator_duser(): void
    {
        $ctx = $this->orderBody();
        $staff = $this->makeStaffWithPin(['orders.create'], '246813');

        $device = $this->makeDevice('order_entry');
        $this->actingAs(User::find($device->user_id));

        $this->postJson('/terminal/operator', ['staff_id' => $staff->id, 'pin' => '246813'])->assertOk();

        // IDLE_MINUTES (10) üzerinde işlemsiz süre → operatör düşer, 422.
        $this->travel(11)->minutes();

        $this->postJson('/api/v1/orders', $ctx['body'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('operator');

        $this->travelBack();
    }

    /* ---------------- Temizleme ---------------- */

    public function test_operator_clear_atfi_durdurur(): void
    {
        $ctx = $this->orderBody();
        $staff = $this->makeStaffWithPin(['orders.create'], '246813');

        $device = $this->makeDevice('order_entry');
        $this->actingAs(User::find($device->user_id));

        $this->postJson('/terminal/operator', ['staff_id' => $staff->id, 'pin' => '246813'])->assertOk();
        $this->postJson('/terminal/operator/clear')->assertOk()->assertJsonPath('operator', null);

        // Temizlendikten sonra operatör yok → sipariş açılamaz.
        $this->postJson('/api/v1/orders', $ctx['body'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('operator');
    }

    public function test_normal_kullanici_terminal_operator_uclarina_erisemez_403(): void
    {
        // Terminal OLMAYAN oturum bu uçları çağıramaz (kavram terminale özgü).
        $this->actingAs($this->a['user']);

        $this->getJson('/terminal/operators')->assertForbidden();
        $this->postJson('/terminal/operator', ['staff_id' => 1, 'pin' => '246813'])->assertForbidden();
    }
}
