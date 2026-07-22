<?php

namespace Tests\Feature\Settings;

use App\Modules\Settings\Models\MailSetting;
use App\Modules\Settings\Services\MailConfigurator;
use App\Modules\Settings\Services\MailSettingsService;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Panelden yönetilen e-posta (SMTP) ayarları: şifreli saklama, parola
 * sızıntısı yasağı, kiracı izolasyonu, yetki, çalışma anı override'ı,
 * dürüst bağlantı testi ve SSRF önlemleri.
 */
class MailSettingsTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    /** @return array<string, mixed> */
    private function smtpPayload(array $overrides = []): array
    {
        return array_merge([
            'mailer' => 'smtp',
            'host' => 'smtp.example.com',
            'port' => 587,
            'encryption' => 'tls',
            'username' => 'postaci@example.com',
            'password' => 'cok-gizli-parola-123',
            'from_name' => 'Test İşletme',
            'from_address' => 'bilgi@example.com',
            'reply_to' => 'destek@example.com',
            'timeout' => 30,
        ], $overrides);
    }

    /* ================= Yetki ================= */

    public function test_settings_manage_izni_olmayan_kullanici_erisemez(): void
    {
        $setup = $this->makeTenantWithUser(['orders.view']);
        $this->actingAs($setup['user']);

        $this->getJson('/api/v1/settings/mail')->assertForbidden();
        $this->putJson('/api/v1/settings/mail/tenant', $this->smtpPayload())->assertForbidden();
        $this->postJson('/api/v1/settings/mail/test', ['to' => 'a@b.com'])->assertForbidden();
        $this->deleteJson('/api/v1/settings/mail/tenant')->assertForbidden();
        $this->get('/panel/ayarlar/e-posta')->assertForbidden();
    }

    public function test_izinli_kullanici_ekrana_ve_apiye_erisir(): void
    {
        $setup = $this->makeTenantWithUser(['settings.view', 'settings.manage']);
        $this->actingAs($setup['user']);

        $this->get('/panel/ayarlar/e-posta')->assertOk();
        $this->getJson('/api/v1/settings/mail')
            ->assertOk()
            ->assertJsonPath('effective_source', 'env')
            ->assertJsonPath('can_manage_platform', false);
    }

    /* ================= Şifreli saklama & parola sızıntısı ================= */

    public function test_parola_veritabaninda_sifreli_saklanir_duz_metin_yoktur(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $this->actingAs($setup['user']);

        $this->putJson('/api/v1/settings/mail/tenant', $this->smtpPayload())->assertOk();

        $raw = DB::table('mail_settings')->where('tenant_id', $setup['tenant']->id)->value('password');

        $this->assertNotNull($raw);
        $this->assertNotSame('cok-gizli-parola-123', $raw);
        $this->assertStringNotContainsString('cok-gizli-parola-123', $raw);
        // Crypt ile çözülebilmeli (gerçekten Laravel Crypt formatı)
        $this->assertSame('cok-gizli-parola-123', Crypt::decryptString($raw));
    }

    public function test_parola_hicbir_yanitta_donmez(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $this->actingAs($setup['user']);

        $update = $this->putJson('/api/v1/settings/mail/tenant', $this->smtpPayload())->assertOk();
        $this->assertStringNotContainsString('cok-gizli-parola-123', $update->getContent());
        $this->assertArrayNotHasKey('password', $update->json('setting'));
        $this->assertTrue($update->json('setting.has_password'));

        $show = $this->getJson('/api/v1/settings/mail')->assertOk();
        $this->assertStringNotContainsString('cok-gizli-parola-123', $show->getContent());
        $this->assertArrayNotHasKey('password', $show->json('tenant'));
    }

    public function test_denetim_kaydina_parola_yazilmaz(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $this->actingAs($setup['user']);

        $this->putJson('/api/v1/settings/mail/tenant', $this->smtpPayload())->assertOk();

        $log = DB::table('audit_logs')->where('action', 'settings.mail.updated')->first();
        $this->assertNotNull($log);
        $this->assertStringNotContainsString('cok-gizli-parola-123', (string) $log->new_values);
    }

    public function test_bos_parola_mevcut_parolayi_korur(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $this->actingAs($setup['user']);

        $this->putJson('/api/v1/settings/mail/tenant', $this->smtpPayload())->assertOk();

        // Parolasız güncelleme: diğer alan değişir, parola aynen kalır
        $payload = $this->smtpPayload(['host' => 'smtp2.example.com']);
        unset($payload['password']);
        $this->putJson('/api/v1/settings/mail/tenant', $payload)
            ->assertOk()
            ->assertJsonPath('setting.host', 'smtp2.example.com')
            ->assertJsonPath('setting.has_password', true);

        $setting = MailSetting::query()->where('tenant_id', $setup['tenant']->id)->first();
        $this->assertSame('cok-gizli-parola-123', $setting->password);
    }

    /* ================= Kiracı izolasyonu ================= */

    public function test_kiraci_baskasinin_ayarini_goremez_ve_ezemez(): void
    {
        $setupA = $this->makeTenantWithUser(['settings.manage']);
        $setupB = $this->makeTenantWithUser(['settings.manage']);

        $this->actingAs($setupA['user']);
        $this->putJson('/api/v1/settings/mail/tenant', $this->smtpPayload(['host' => 'smtp.tenant-a.com']))->assertOk();

        // B kendi ekranında A'nın ayarını GÖREMEZ
        $this->actingAs($setupB['user']);
        $show = $this->getJson('/api/v1/settings/mail')->assertOk();
        $this->assertNull($show->json('tenant'));
        $this->assertStringNotContainsString('tenant-a.com', $show->getContent());

        // B'nin kaydı A'nınkini EZMEZ, kendi satırını oluşturur
        $this->putJson('/api/v1/settings/mail/tenant', $this->smtpPayload(['host' => 'smtp.tenant-b.com']))->assertOk();
        $this->assertSame('smtp.tenant-a.com', MailSetting::query()->where('tenant_id', $setupA['tenant']->id)->value('host'));
        $this->assertSame('smtp.tenant-b.com', MailSetting::query()->where('tenant_id', $setupB['tenant']->id)->value('host'));

        // B'nin silmesi yalnız KENDİ satırını siler
        $this->deleteJson('/api/v1/settings/mail/tenant')->assertOk();
        $this->assertNull(MailSetting::query()->where('tenant_id', $setupB['tenant']->id)->first());
        $this->assertNotNull(MailSetting::query()->where('tenant_id', $setupA['tenant']->id)->first());
    }

    public function test_platform_disi_kiraci_platform_varsayilanini_degistiremez(): void
    {
        $platform = $this->makeTenantWithUser(['settings.manage']);
        $other = $this->makeTenantWithUser(['settings.manage']);

        config(['settings.platform_tenant_id' => $platform['tenant']->id]);

        $this->actingAs($other['user']);
        $this->putJson('/api/v1/settings/mail/platform', $this->smtpPayload())->assertForbidden();

        // Platform işletmecisi ise düzenleyebilir
        $this->actingAs($platform['user']);
        $this->putJson('/api/v1/settings/mail/platform', $this->smtpPayload())->assertOk();
        $this->assertNotNull(MailSetting::query()->whereNull('tenant_id')->first());
    }

    /* ================= Geçerli ayar çözümlemesi ================= */

    public function test_gecerli_kaynak_dogru_raporlanir(): void
    {
        $platform = $this->makeTenantWithUser(['settings.manage']);
        config(['settings.platform_tenant_id' => $platform['tenant']->id]);
        $this->actingAs($platform['user']);

        // Hiç ayar yok → env
        $this->getJson('/api/v1/settings/mail')->assertJsonPath('effective_source', 'env');

        // Platform varsayılanı → platform
        $this->putJson('/api/v1/settings/mail/platform', $this->smtpPayload())->assertOk();
        $this->getJson('/api/v1/settings/mail')->assertJsonPath('effective_source', 'platform');

        // İşletme override'ı → tenant
        $this->putJson('/api/v1/settings/mail/tenant', $this->smtpPayload(['host' => 'smtp.own.com']))->assertOk();
        $this->getJson('/api/v1/settings/mail')->assertJsonPath('effective_source', 'tenant');

        // Override kaldırılınca tekrar platform
        $this->deleteJson('/api/v1/settings/mail/tenant')->assertOk()
            ->assertJsonPath('effective_source', 'platform');
    }

    /* ================= Çalışma anı (runtime) uygulama ================= */

    public function test_db_ayari_mail_yapilandirmasini_calisma_aninda_ezer(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);

        app(MailSettingsService::class)->save(null, [
            'mailer' => 'smtp',
            'host' => 'mail.platform.test',
            'port' => 587,
            'encryption' => 'tls',
            'username' => 'u',
            'password' => 'p',
            'from_address' => 'noreply@platform.test',
            'from_name' => 'Platform',
            'timeout' => 30,
        ]);

        $this->assertSame('array', config('mail.default')); // henüz dokunulmadı

        app(TenantContext::class)->setTenant($setup['tenant']);
        app('mail.manager')->mailer(); // gönderim anını simüle eder

        $this->assertSame('smtp', config('mail.default'));
        $this->assertSame('mail.platform.test', config('mail.mailers.smtp.host'));
        $this->assertSame('noreply@platform.test', config('mail.from.address'));
    }

    public function test_ayar_yoksa_env_yapilandirmasina_duser(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);

        app(TenantContext::class)->setTenant($setup['tenant']);
        app('mail.manager')->mailer();

        // Hiç DB kaydı yok → phpunit env'i (array) aynen geçerli
        $this->assertSame('array', config('mail.default'));
    }

    public function test_isletme_overridei_platformdan_oncelikli_uygulanir(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $service = app(MailSettingsService::class);

        $service->save(null, ['mailer' => 'smtp', 'host' => 'mail.platform.test', 'port' => 587, 'encryption' => 'tls', 'from_address' => 'a@platform.test', 'timeout' => 30]);
        $service->save($setup['tenant']->id, ['mailer' => 'smtp', 'host' => 'mail.tenant.test', 'port' => 465, 'encryption' => 'ssl', 'from_address' => 'a@tenant.test', 'timeout' => 30]);

        app(TenantContext::class)->setTenant($setup['tenant']);
        app('mail.manager')->mailer();

        $this->assertSame('mail.tenant.test', config('mail.mailers.smtp.host'));
        $this->assertSame(465, config('mail.mailers.smtp.port'));
        $this->assertSame('smtps', config('mail.mailers.smtp.scheme'));

        // Configurator, bildirim ipucuyla da (misafir akışı) aynı sonucu verir
        app(TenantContext::class)->forget();
        app(MailConfigurator::class)->hintTenant($setup['tenant']->id);
        app('mail.manager')->mailer();
        $this->assertSame('mail.tenant.test', config('mail.mailers.smtp.host'));
    }

    /* ================= Bağlantı testi (dürüstlük) ================= */

    public function test_baglanti_testi_hatayi_durustce_bildirir_ve_parola_sizdirmaz(): void
    {
        $platform = $this->makeTenantWithUser(['settings.manage']);
        config(['settings.platform_tenant_id' => $platform['tenant']->id]);
        $this->actingAs($platform['user']);

        // 127.0.0.1:1 → bağlantı reddi (gerçek soket denemesi, anında döner)
        $this->putJson('/api/v1/settings/mail/platform', $this->smtpPayload([
            'host' => '127.0.0.1',
            'port' => 1,
            'encryption' => 'none',
            'timeout' => 5,
        ]))->assertOk();

        $res = $this->postJson('/api/v1/settings/mail/test', ['to' => 'alici@example.com'])->assertOk();

        $this->assertFalse($res->json('ok'));
        $this->assertNotSame('', (string) $res->json('error'));
        $this->assertStringNotContainsString('cok-gizli-parola-123', $res->getContent());
    }

    public function test_baglanti_testi_log_surucusunde_gercek_gonderim_olmadigini_soyler(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $this->actingAs($setup['user']);

        $this->putJson('/api/v1/settings/mail/tenant', [
            'mailer' => 'log',
            'from_address' => 'bilgi@example.com',
        ])->assertOk();

        $res = $this->postJson('/api/v1/settings/mail/test', ['to' => 'alici@example.com'])->assertOk();

        $this->assertTrue($res->json('ok'));
        $this->assertNotNull($res->json('note')); // "gerçekte gönderilmedi" uyarısı
        $this->assertStringContainsString('GERÇEKTE', (string) $res->json('note'));
    }

    public function test_baglanti_testi_hiz_sinirlidir(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $this->actingAs($setup['user']);

        $this->putJson('/api/v1/settings/mail/tenant', [
            'mailer' => 'log',
            'from_address' => 'bilgi@example.com',
        ])->assertOk();

        for ($i = 0; $i < 3; $i++) {
            $this->postJson('/api/v1/settings/mail/test', ['to' => 'alici@example.com'])->assertOk();
        }

        $this->postJson('/api/v1/settings/mail/test', ['to' => 'alici@example.com'])->assertStatus(429);
    }

    /* ================= SSRF önlemleri ================= */

    public function test_platform_disi_isletme_ic_ag_adresi_kaydedemez(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $this->actingAs($setup['user']);

        foreach (['127.0.0.1', '10.0.0.5', '192.168.1.10', 'localhost', '169.254.169.254'] as $host) {
            $this->putJson('/api/v1/settings/mail/tenant', $this->smtpPayload(['host' => $host]))
                ->assertStatus(422)
                ->assertJsonValidationErrors(['host']);
        }
    }

    public function test_platform_disi_isletme_yalnizca_izinli_smtp_portlarini_kullanir(): void
    {
        $setup = $this->makeTenantWithUser(['settings.manage']);
        $this->actingAs($setup['user']);

        $this->putJson('/api/v1/settings/mail/tenant', $this->smtpPayload(['port' => 8080]))
            ->assertStatus(422)
            ->assertJsonValidationErrors(['port']);

        $this->putJson('/api/v1/settings/mail/tenant', $this->smtpPayload(['port' => 587]))->assertOk();
    }
}
