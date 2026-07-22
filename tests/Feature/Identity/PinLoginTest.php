<?php

namespace Tests\Feature\Identity;

use App\Modules\Identity\Services\PinService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

class PinLoginTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    public function test_dort_haneli_pin_reddedilir(): void
    {
        $setup = $this->makeTenantWithUser();

        $this->actingAs($setup['user'])->postJson('/api/v1/auth/pin', [
            'password' => 'password',
            'pin' => '1234', // eski sistemin açığı — kesinlikle yasak
        ])->assertUnprocessable();

        $this->assertNull($setup['user']->fresh()->pin_hash);
    }

    public function test_zayif_pinler_reddedilir(): void
    {
        $setup = $this->makeTenantWithUser();

        foreach (['111111', '123456', '654321', '12345', 'abcdef'] as $weak) {
            $this->actingAs($setup['user'])->postJson('/api/v1/auth/pin', [
                'password' => 'password',
                'pin' => $weak,
            ])->assertUnprocessable();
        }
    }

    public function test_gecerli_alti_haneli_pin_kaydedilir_ve_bcrypt_saklanir(): void
    {
        $setup = $this->makeTenantWithUser();

        $this->actingAs($setup['user'])->postJson('/api/v1/auth/pin', [
            'password' => 'password',
            'pin' => '839274',
        ])->assertOk();

        $hash = $setup['user']->fresh()->pin_hash;

        $this->assertNotNull($hash);
        $this->assertStringNotContainsString('839274', $hash);
        $this->assertTrue(password_verify('839274', $hash));
    }

    public function test_pin_ile_giris_yapilir(): void
    {
        $setup = $this->makeTenantWithUser();
        $setup['user']->forceFill(['staff_code' => 'P100'])->save();

        app(PinService::class)->setPin($setup['user'], '839274');
        auth()->logout();

        $this->postJson('/api/v1/auth/pin-login', [
            'tenant' => $setup['tenant']->slug,
            'staff_code' => 'P100',
            'pin' => '839274',
        ])->assertOk();

        $this->assertAuthenticatedAs($setup['user']);
        $this->assertDatabaseHas('audit_logs', ['action' => 'auth.pin_login', 'user_id' => $setup['user']->id]);
    }

    public function test_baska_kiracinin_slugu_ile_pin_girisi_yapilamaz(): void
    {
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        $a['user']->forceFill(['staff_code' => 'P100'])->save();
        app(PinService::class)->setPin($a['user'], '839274');

        // B kiracısının slug'ı + A'nın personel kodu/PIN'i → giriş yok
        $this->postJson('/api/v1/auth/pin-login', [
            'tenant' => $b['tenant']->slug,
            'staff_code' => 'P100',
            'pin' => '839274',
        ])->assertUnprocessable();

        $this->assertGuest();
    }

    public function test_bes_hatali_pin_denemesi_kullaniciyi_kilitler(): void
    {
        $setup = $this->makeTenantWithUser();
        $setup['user']->forceFill(['staff_code' => 'P200'])->save();

        $pins = app(PinService::class);
        $pins->setPin($setup['user'], '839274');

        for ($i = 0; $i < 5; $i++) {
            $this->assertFalse($pins->verify($setup['user']->fresh(), '000001'));
        }

        $locked = $setup['user']->fresh();
        $this->assertTrue($locked->pinIsLocked());

        // Kilitliyken DOĞRU PIN bile reddedilir
        $this->expectException(ValidationException::class);
        $pins->verify($locked, '839274');
    }
}
