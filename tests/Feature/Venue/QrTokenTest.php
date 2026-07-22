<?php

namespace Tests\Feature\Venue;

use App\Modules\Tables\Models\Table;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * ADR-008 kanıtları: opak token çözümleme, rotasyonun eski token'ı anında
 * geçersiz kılması, yabancı kiracı token/id'siyle panel erişiminin olmaması,
 * rate limit ve şüpheli kullanım denetim kaydı.
 */
class QrTokenTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    private array $a;

    private array $b;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->b = $this->makeTenantWithUser();
    }

    private function makeTable(array $overrides = []): Table
    {
        return Table::factory()->create(array_merge([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'name' => 'Teras 4',
            'number' => 4,
        ], $overrides));
    }

    /* ---------------- Public çözümleme ---------------- */

    public function test_gecerli_token_menuyu_acar_ve_masayi_gosterir(): void
    {
        $table = $this->makeTable();

        $response = $this->get('/m/'.$table->qr_token);

        $response->assertOk()
            ->assertSee($this->a['tenant']->name)
            ->assertSee('Teras 4');

        $this->assertDatabaseHas('qr_scans', [
            'token' => $table->qr_token,
            'table_id' => $table->id,
            'result' => 'ok',
        ]);
    }

    public function test_gecersiz_token_404_doner_ve_gunluge_yazilir(): void
    {
        $bogus = 'AAAAAAAAAAAAAAAAAAAAAAAAAA';

        $this->get('/m/'.$bogus)->assertNotFound();

        $this->assertDatabaseHas('qr_scans', ['token' => $bogus, 'result' => 'invalid']);
    }

    public function test_yenilenen_token_eskisini_aninda_gecersiz_kilar(): void
    {
        $table = $this->makeTable();
        $oldToken = $table->qr_token;

        $this->get('/m/'.$oldToken)->assertOk();

        $table->rotateQrToken();
        $newToken = $table->fresh()->qr_token;

        $this->assertNotSame($oldToken, $newToken);

        // Eski token: 410 + açıklama; yeni token: çalışır
        $this->get('/m/'.$oldToken)->assertStatus(410)->assertSee('yeniledi');
        $this->get('/m/'.$newToken)->assertOk();

        $this->assertDatabaseHas('qr_scans', ['token' => $oldToken, 'result' => 'revoked']);
    }

    public function test_pasif_masa_veya_sube_410_doner(): void
    {
        $table = $this->makeTable(['is_active' => false]);

        $this->get('/m/'.$table->qr_token)->assertStatus(410);

        $active = $this->makeTable(['name' => 'Bahçe 1', 'number' => 11]);
        $this->a['branch']->update(['is_active' => false]);

        $this->get('/m/'.$active->qr_token)->assertStatus(410);
    }

    public function test_token_kiracisini_kendisi_tasir_url_parametresiyle_degistirilemez(): void
    {
        $aTable = $this->makeTable();
        $bTable = Table::factory()->create([
            'tenant_id' => $this->b['tenant']->id,
            'branch_id' => $this->b['branch']->id,
            'name' => 'B Salon 1',
        ]);

        // A'nın token'ı yalnız A'nın işletmesini açar; sorgu parametreleri yok sayılır.
        $this->get('/m/'.$aTable->qr_token.'?tenant_id='.$this->b['tenant']->id.'&table_id='.$bTable->id)
            ->assertOk()
            ->assertSee($this->a['tenant']->name)
            ->assertDontSee($this->b['tenant']->name)
            ->assertDontSee('B Salon 1');
    }

    /* ---------------- Panel izolasyonu ---------------- */

    public function test_a_kullanicisi_b_nin_masasinin_qr_gorselini_alamaz_rotasyon_yapamaz(): void
    {
        $bTable = Table::factory()->create([
            'tenant_id' => $this->b['tenant']->id,
            'branch_id' => $this->b['branch']->id,
        ]);
        $oldToken = $bTable->qr_token;

        $this->actingAs($this->a['user']);

        $this->get("/api/v1/venue/tables/{$bTable->id}/qr-image")->assertNotFound();
        $this->postJson("/api/v1/venue/tables/{$bTable->id}/qr-rotate")->assertNotFound();

        // Toplu rotasyona B'nin id'si karıştırılırsa etkisizdir
        $res = $this->postJson('/api/v1/venue/qr/rotate-bulk', ['table_ids' => [$bTable->id]])->assertOk();
        $this->assertSame(0, $res->json('rotated'));

        $this->assertSame($oldToken, Table::withoutTenancy()->find($bTable->id)->qr_token);
    }

    public function test_b_nin_subesinin_genel_menu_qr_i_a_tarafindan_alinamaz(): void
    {
        $this->actingAs($this->a['user']);

        $this->get("/api/v1/venue/branches/{$this->b['branch']->id}/qr-image")->assertNotFound();
        $this->postJson("/api/v1/venue/branches/{$this->b['branch']->id}/qr-rotate")->assertNotFound();
    }

    /* ---------------- Görsel çıktılar ---------------- */

    public function test_qr_png_svg_ve_a4_pdf_uretilir(): void
    {
        $table = $this->makeTable();

        $this->actingAs($this->a['user']);

        $png = $this->get("/api/v1/venue/tables/{$table->id}/qr-image?download=1");
        $png->assertOk()->assertHeader('Content-Type', 'image/png');
        $this->assertStringStartsWith("\x89PNG", (string) $png->getContent());

        $svg = $this->get("/api/v1/venue/tables/{$table->id}/qr-image?format=svg");
        $svg->assertOk()->assertHeader('Content-Type', 'image/svg+xml');
        $this->assertStringContainsString('<svg', (string) $svg->getContent());
        $this->assertStringContainsString('Teras 4', (string) $svg->getContent());

        $pdf = $this->get('/api/v1/venue/qr/sheet?branch_id='.$this->a['branch']->id);
        $pdf->assertOk()->assertHeader('Content-Type', 'application/pdf');
        $this->assertStringStartsWith('%PDF', (string) $pdf->getContent());
    }

    public function test_gorsel_icindeki_qr_dogru_menu_adresini_kodlar(): void
    {
        $table = $this->makeTable();

        $this->actingAs($this->a['user']);

        $png = $this->get("/api/v1/venue/tables/{$table->id}/qr-image");
        $tmp = tempnam(sys_get_temp_dir(), 'qr').'.png';
        file_put_contents($tmp, (string) $png->getContent());

        $decoded = (new \chillerlan\QRCode\QRCode)->readFromFile($tmp);
        unlink($tmp);

        $this->assertSame($table->menuUrl(), (string) $decoded->data);
        $this->assertStringContainsString('/m/'.$table->qr_token, (string) $decoded->data);
    }

    public function test_genel_menu_qr_i_sube_tokeni_uretir_ve_calisir(): void
    {
        $this->actingAs($this->a['user']);

        $this->get("/api/v1/venue/branches/{$this->a['branch']->id}/qr-image")->assertOk();

        $branch = $this->a['branch']->fresh();
        $this->assertNotNull($branch->qr_token);

        // Şube token'ı public menüyü masasız açar
        $this->app['auth']->guard('web')->logout();
        $this->get('/m/'.$branch->qr_token)->assertOk()->assertSee($this->a['tenant']->name);
    }

    /* ---------------- Rate limit + şüpheli kullanım ---------------- */

    public function test_rate_limit_asiminda_429_doner(): void
    {
        $table = $this->makeTable();

        for ($i = 0; $i < 120; $i++) {
            RateLimiter::hit('qr-scan:'.sha1('127.0.0.1'), 60);
        }

        $this->get('/m/'.$table->qr_token)->assertStatus(429)->assertHeader('Retry-After');
    }

    public function test_cok_sayida_gecersiz_deneme_denetim_kaydina_dusuluyor(): void
    {
        for ($i = 0; $i < 11; $i++) {
            // Geçerli biçimli ama var olmayan token'lar (tarama girişimi simülasyonu)
            $this->get('/m/'.Table::generateQrToken());
        }

        $this->assertDatabaseHas('audit_logs', ['action' => 'qr.suspicious_scan']);
    }
}
