<?php

namespace Tests\Feature\Terminal;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Kds\Models\UserStation;
use App\Modules\Orders\Models\OrderItem;
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
 * §13 İstasyon Cihaz Modu — FAZ B: Kasa + Sipariş-giriş terminalleri + hassas
 * işlemlerde PIN kapısı. Faz A (KDS terminalleri) BOZULMADAN üstüne kurulur.
 */
class TerminalPhaseBTest extends TestCase
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

    /** Aynı kiracıda PIN'li + istenen izinlere sahip GERÇEK personel. */
    private function makeStaffWithPin(array $perms, string $pin, ?string $code = null): User
    {
        $role = Role::factory()->create(['tenant_id' => $this->a['tenant']->id]);
        $role->permissions()->sync(Permission::query()->whereIn('key', $perms)->pluck('id')->all());

        $user = User::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'staff_code' => $code,
        ]);
        $user->roles()->sync([$role->id]);
        $user->forceFill(['pin_hash' => Hash::make($pin)])->save();

        return $user;
    }

    /* ---------------- Yeni istasyon tipleri + izinler ---------------- */

    public function test_kasa_terminali_para_izinleri_alir_kds_istasyonu_atanmaz(): void
    {
        $device = $this->makeDevice('kasa');
        $user = User::find($device->user_id);

        $this->assertTrue((bool) $user->is_terminal);
        $this->assertSame('kasa', $user->terminal_station);

        $keys = $user->permissionKeys();
        $this->assertContains('payments.take', $keys);
        $this->assertContains('orders.view', $keys);
        $this->assertContains('orders.comp', $keys);
        $this->assertContains('orders.cancel', $keys);
        $this->assertContains('payments.refund', $keys);
        // Kasa KDS istasyon-kapsamı DIŞI (para ekranı, mutfak değil).
        $this->assertNotContains('kds.view', $keys);
        $this->assertSame(0, UserStation::query()->where('user_id', $user->id)->count());
    }

    public function test_order_entry_terminali_siparis_izinleri_alir_para_almaz(): void
    {
        $device = $this->makeDevice('order_entry');
        $user = User::find($device->user_id);

        $keys = $user->permissionKeys();
        $this->assertContains('orders.view', $keys);
        $this->assertContains('orders.create', $keys);
        $this->assertContains('orders.update', $keys);
        // Sipariş-giriş rutin izinler; para eylemleri PIN'e bağlıdır.
        $this->assertNotContains('payments.take', $keys);
        $this->assertNotContains('orders.cancel', $keys);
        $this->assertSame(0, UserStation::query()->where('user_id', $user->id)->count());
    }

    /* ---------------- Giriş yönlendirme + kilitli rota ---------------- */

    public function test_kasa_token_kasa_ekranina_yonlendirir(): void
    {
        $device = $this->makeDevice('kasa');

        $this->get('/terminal/'.$device->token)->assertRedirect('/panel/kasa');
        $this->assertAuthenticatedAs(User::find($device->user_id));
    }

    public function test_order_entry_token_siparisler_ekranina_yonlendirir(): void
    {
        $device = $this->makeDevice('order_entry');

        $this->get('/terminal/'.$device->token)->assertRedirect('/panel/siparisler');
    }

    public function test_kasa_terminali_yonetime_erisemez_operasyona_erisir(): void
    {
        // Güncellenmiş erişim modeli (§13): terminal tek ekrana KİLİTLİ değil;
        // yönetim-DIŞI, izinli operasyon ekranlarına gidebilir, yönetim kapalıdır.
        $device = $this->makeDevice('kasa');
        $this->actingAs(User::find($device->user_id));

        // Kendi istasyon ekranı açık.
        $this->get('/panel/kasa')->assertOk();

        // İzinli başka OPERASYON ekranı: kasa'nın orders.view izni var →
        // Siparişler artık erişilebilir (eskiden kendi ekranına redirect'ti).
        $this->get('/panel/siparisler')->assertOk();

        // YÖNETİM/hassas sayfalar → kendi ekranına redirect (block-list).
        $this->get('/panel/personel')->assertRedirect('/panel/kasa');
        $this->get('/panel/ayarlar/e-posta')->assertRedirect('/panel/kasa');
        $this->get('/panel/raporlar')->assertRedirect('/panel/kasa');
        // (/panel/boss KALDIRILDI — Patron Paneli artık yalnız patron.* subdomain'inde.)

        // Kök / panel kökü → cihaz kendi istasyon ekranıyla açılır.
        $this->get('/panel')->assertRedirect('/panel/kasa');
    }

    public function test_order_entry_terminali_adisyon_detayina_gidebilir(): void
    {
        $this->actingAs($this->a['user']);
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $device = $this->makeDevice('order_entry');
        $this->actingAs(User::find($device->user_id));

        $this->get('/panel/siparisler')->assertOk();
        // Alt yol (adisyon detay) SERBEST — sipariş-giriş terminali için.
        $this->get("/panel/siparisler/{$orderId}")->assertOk();
        // YÖNETİM sayfası → kendi ekranına redirect (block-list).
        $this->get('/panel/personel')->assertRedirect('/panel/siparisler');
        // Operasyon ekranı ama İZNİ YOK (kasa = payments.take): 403 —
        // yönlendirme değil; erişim kararını rota izin kontrolü verir.
        $this->get('/panel/kasa')->assertForbidden();
    }

    /* ---------------- PIN kapısı (hassas işlemler) ---------------- */

    public function test_terminal_odeme_pinsiz_reddedilir(): void
    {
        $this->actingAs($this->a['user']);
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $device = $this->makeDevice('kasa');
        $this->actingAs(User::find($device->user_id));

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->assertStatus(422);

        $this->assertSame(0, Payment::withoutTenancy()->where('order_id', $orderId)->count());
    }

    public function test_terminal_odeme_gecerli_pinle_personele_atfedilir(): void
    {
        $this->actingAs($this->a['user']);
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        $staff = $this->makeStaffWithPin(['payments.take'], '246813');

        $device = $this->makeDevice('kasa');
        $this->actingAs(User::find($device->user_id));

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000, 'pin' => '246813',
        ])->assertCreated();

        // Ödeme, terminal (gizli) kullanıcıya DEĞİL, PIN sahibi personele atfedilir.
        $payment = Payment::withoutTenancy()->where('order_id', $orderId)->where('kind', 'payment')->first();
        $this->assertNotNull($payment);
        $this->assertSame((int) $staff->id, (int) $payment->cashier_id);
        $this->assertNotSame((int) $device->user_id, (int) $payment->cashier_id);
    }

    public function test_terminal_odeme_yetkisiz_pin_reddedilir_eylem_yok(): void
    {
        $this->actingAs($this->a['user']);
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        // Personel PIN'li ama payments.take YOK.
        $this->makeStaffWithPin(['orders.view'], '135791');

        $device = $this->makeDevice('kasa');
        $this->actingAs(User::find($device->user_id));

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000, 'pin' => '135791',
        ])->assertStatus(422);

        $this->assertSame(0, Payment::withoutTenancy()->where('order_id', $orderId)->count());
    }

    public function test_terminal_ikram_pin_ile_personele_atfedilir(): void
    {
        $this->actingAs($this->a['user']);
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        $item = OrderItem::withoutTenancy()->where('order_id', $orderId)->firstOrFail();
        $staff = $this->makeStaffWithPin(['orders.comp'], '246813');

        $device = $this->makeDevice('kasa');
        $this->actingAs(User::find($device->user_id));

        $this->postJson("/api/v1/orders/{$orderId}/items/{$item->id}/comp", [
            'reason' => 'müşteri memnuniyeti', 'pin' => '246813',
        ])->assertOk();

        $fresh = OrderItem::withoutTenancy()->findOrFail($item->id);
        $this->assertTrue((bool) $fresh->is_comp);
        $this->assertSame((int) $staff->id, (int) $fresh->comp_by_id);
    }

    public function test_normal_oturum_pin_istemez(): void
    {
        // Yönetici (terminal DEĞİL): mevcut davranış — PIN olmadan ödeme alır.
        $this->actingAs($this->a['user']);
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->assertCreated();

        $payment = Payment::withoutTenancy()->where('order_id', $orderId)->where('kind', 'payment')->first();
        $this->assertSame((int) $this->a['user']->id, (int) $payment->cashier_id);
    }

    /* ---------------- Panel yönetimi (yeni istasyon seçenekleri) ---------------- */

    public function test_panel_kasa_ve_siparis_terminali_olusturur(): void
    {
        $manager = $this->makeTenantWithUser(['terminals.manage', 'terminals.view']);
        $this->actingAs($manager['user']);

        $kasa = $this->postJson('/api/v1/terminals/devices', [
            'name' => 'Kasa 1', 'branch_id' => $manager['branch']->id, 'station' => 'kasa',
        ])->assertCreated();
        $this->assertSame('kasa', $kasa->json('device.station'));
        $this->assertSame('Kasa', $kasa->json('device.station_label'));

        $oe = $this->postJson('/api/v1/terminals/devices', [
            'name' => 'Sipariş 1', 'branch_id' => $manager['branch']->id, 'station' => 'order_entry',
        ])->assertCreated();
        $this->assertSame('order_entry', $oe->json('device.station'));

        // İstasyon seçenekleri listesinde yeni türler yer alır.
        $stations = collect($this->getJson('/api/v1/terminals/devices')->json('stations'))->pluck('value')->all();
        $this->assertContains('kasa', $stations);
        $this->assertContains('order_entry', $stations);
        $this->assertContains('kitchen', $stations); // Faz A korunur
    }
}
