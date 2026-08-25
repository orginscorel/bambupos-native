<?php

namespace Tests\Feature\Payments;

use App\Modules\Payments\Enums\PaymentMethod;
use App\Modules\Payments\Models\Payment;
use App\Modules\Payments\Providers\GenericRestPosProvider;
use App\Modules\Payments\Providers\GenericXmlPosProvider;
use App\Modules\Payments\Providers\ProviderRegistry;
use App\Modules\Payments\Providers\ProviderResult;
use App\Modules\Payments\Services\PosConfigResolver;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * POS ENTEGRATÖR çekirdeği: her işletme kendi cihazını config'le seçer; jenerik
 * REST adaptörü herhangi bir sağlayıcıya config ile bağlanır ve ASLA sahte onay
 * üretmez (yapılandırılmamış = güvenli hata).
 */
class PosIntegratorTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        app(TenantContext::class)->setTenant($this->a['tenant']->id);
    }

    /** @param array<string, mixed> $config */
    private function configurePos(array $config): void
    {
        DB::table('tenant_integrations')->updateOrInsert(
            ['tenant_id' => $this->a['tenant']->id, 'key' => 'pos_terminal'],
            ['is_enabled' => true, 'config' => json_encode($config), 'created_at' => now(), 'updated_at' => now()],
        );
        app(PosConfigResolver::class)->flush();
    }

    private function payment(int $amountMinor, ?string $txn = null): Payment
    {
        $p = new Payment();
        $p->reference = 'REF'.$amountMinor;
        $p->amount_minor = $amountMinor;
        $p->provider_txn_id = $txn;

        return $p;
    }

    public function test_isletme_kendi_saglayicisini_secince_registry_onu_dondurur(): void
    {
        // Entegrasyon yokken terminal yöntemi global varsayılana (mock) düşer.
        $this->assertSame('mock', app(ProviderRegistry::class)->keyForMethod(PaymentMethod::CreditCard));

        $this->configurePos(['provider' => 'generic_rest', 'base_url' => 'https://pos.example/api']);

        // İşletme kendi entegratörünü seçince registry onu döndürür.
        $this->assertSame('generic_rest', app(ProviderRegistry::class)->keyForMethod(PaymentMethod::CreditCard));

        // Nakit her zaman 'cash' (terminal değil) — entegrasyon etkilemez.
        $this->assertSame('cash', app(ProviderRegistry::class)->keyForMethod(PaymentMethod::Cash));
    }

    public function test_yapilandirilmamis_jenerik_saglayici_asla_onaylamaz(): void
    {
        $this->configurePos(['provider' => 'generic_rest']); // base_url YOK

        $res = app(GenericRestPosProvider::class)->sendAmountToTerminal($this->payment(10000));

        $this->assertFalse($res->approved());
        $this->assertSame(ProviderResult::ERROR, $res->status);
    }

    public function test_jenerik_saglayici_onayli_yaniti_normalize_eder(): void
    {
        $this->configurePos([
            'provider' => 'generic_rest',
            'base_url' => 'https://pos.example/api',
            'endpoints' => ['charge' => '/sale'],
            'map' => ['status_field' => 'result', 'txn_id_field' => 'txnId', 'approved' => ['OK'], 'declined' => ['NO']],
        ]);

        Http::fake(['pos.example/*' => Http::response(['result' => 'OK', 'txnId' => 'T-99', 'auth_code' => 'A1'], 200)]);

        $res = app(GenericRestPosProvider::class)->sendAmountToTerminal($this->payment(5000));

        $this->assertTrue($res->approved());
        $this->assertSame('T-99', $res->providerTxnId);
    }

    public function test_bilinmeyen_durum_pending_dondurur(): void
    {
        $this->configurePos([
            'provider' => 'generic_rest',
            'base_url' => 'https://pos.example/api',
            'endpoints' => ['charge' => '/sale'],
            'map' => ['status_field' => 'result'],
        ]);

        Http::fake(['pos.example/*' => Http::response(['result' => 'garip-bilinmeyen'], 200)]);

        // Kesin olmayan sonuç ASLA approved değildir → pending (queryPayment netleştirir).
        $this->assertSame(ProviderResult::PENDING, app(GenericRestPosProvider::class)->sendAmountToTerminal($this->payment(5000))->status);
    }

    public function test_uc_config_kaydeder_sirri_maskeler_ve_registry_secer(): void
    {
        $this->actingAs($this->a['user']);

        $this->putJson('/api/v1/payments/pos-integration', [
            'enabled' => true,
            'provider' => 'generic_rest',
            'config' => ['preset' => 'token_gmp3', 'base_url' => 'https://tsm.x/api', 'merchant_id' => 'M1', 'auth' => ['secret' => 'realsecret']],
        ])->assertOk()->assertJsonPath('config.auth.secret', '••••');

        // Kaydedildi → registry bu işletme için generic_rest döndürür.
        app(PosConfigResolver::class)->flush();
        $this->assertSame('generic_rest', app(ProviderRegistry::class)->keyForMethod(PaymentMethod::CreditCard));

        // show: base_url açık, sır maskeli.
        $this->getJson('/api/v1/payments/pos-integration')->assertOk()
            ->assertJsonPath('config.base_url', 'https://tsm.x/api')
            ->assertJsonPath('config.auth.secret', '••••')
            ->assertJsonPath('enabled', true);

        // Maskeli (••••) tekrar kaydedilince gerçek sır KORUNUR.
        $this->putJson('/api/v1/payments/pos-integration', [
            'enabled' => true,
            'provider' => 'generic_rest',
            'config' => ['preset' => 'token_gmp3', 'base_url' => 'https://tsm.x/api', 'merchant_id' => 'M1', 'auth' => ['secret' => '••••']],
        ])->assertOk();

        $row = DB::table('tenant_integrations')->where('tenant_id', $this->a['tenant']->id)->where('key', 'pos_terminal')->first();
        $this->assertSame('realsecret', json_decode((string) $row->config, true)['auth']['secret']);
    }

    public function test_xml_banka_saglayici_onayli_yaniti_cozer(): void
    {
        $this->configurePos([
            'provider' => 'generic_soap',
            'base_url' => 'https://vpos.bank/api',
            'merchant_id' => 'M1',
            'auth' => ['type' => 'none', 'username' => 'u', 'password' => 'p'],
            'endpoints' => ['charge' => '/fim/api'],
            'xml' => ['root' => 'CC5Request', 'requests' => ['charge' => ['Type' => 'Auth', 'Total' => '{amount}', 'OrderId' => '{reference}']]],
            'map' => ['status_field' => 'Response', 'txn_id_field' => 'TransId', 'approved' => ['Approved']],
        ]);

        Http::fake(['vpos.bank/*' => Http::response(
            '<?xml version="1.0"?><CC5Response><Response>Approved</Response><TransId>T-77</TransId><AuthCode>A9</AuthCode></CC5Response>', 200)]);

        $res = app(GenericXmlPosProvider::class)->sendAmountToTerminal($this->payment(5000));

        $this->assertTrue($res->approved());
        $this->assertSame('T-77', $res->providerTxnId);
    }

    public function test_xml_yapilandirilmamis_asla_onaylamaz(): void
    {
        $this->configurePos(['provider' => 'generic_soap']); // base_url YOK
        $res = app(GenericXmlPosProvider::class)->sendAmountToTerminal($this->payment(5000));
        $this->assertFalse($res->approved());
        $this->assertSame(ProviderResult::ERROR, $res->status);
    }

    public function test_registry_banka_preset_ile_generic_soap_secer(): void
    {
        $this->configurePos(['provider' => 'generic_soap', 'base_url' => 'https://vpos.bank']);
        $this->assertSame('generic_soap', app(ProviderRegistry::class)->keyForMethod(PaymentMethod::CreditCard));
    }

    public function test_callback_hmac_dogrulanir_bozuk_reddedilir(): void
    {
        $secret = 'topsecret-integrator';
        $this->configurePos(['provider' => 'generic_rest', 'base_url' => 'https://x/api', 'callback' => ['secret' => $secret]]);
        $provider = app(GenericRestPosProvider::class);

        $body = json_encode(['reference' => 'R4', 'status' => 'approved', 'amount_minor' => 5000]);
        $ts = (string) time();
        $sig = hash_hmac('sha256', $ts.'.'.$body, $secret);

        $ok = Request::create('/cb', 'POST', [], [], [], [
            'HTTP_X-Pos-Signature' => $sig, 'HTTP_X-Pos-Timestamp' => $ts, 'CONTENT_TYPE' => 'application/json',
        ], $body);
        $result = $provider->verifyCallback($ok);
        $this->assertTrue($result->valid);
        $this->assertSame('approved', $result->status);

        $bad = Request::create('/cb', 'POST', [], [], [], [
            'HTTP_X-Pos-Signature' => str_repeat('0', 64), 'HTTP_X-Pos-Timestamp' => $ts, 'CONTENT_TYPE' => 'application/json',
        ], $body);
        $this->assertFalse($provider->verifyCallback($bad)->valid);
    }
}
