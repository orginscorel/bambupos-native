<?php

namespace Tests\Feature\Terminal;

use App\Modules\Identity\Models\User;
use App\Modules\Terminal\Models\TerminalDevice;
use App\Modules\Terminal\Services\TerminalProvisioner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * §13 Terminal ERİŞİM MODELİ (güncellendi): "tek ekrana kilit" → "yönetim-dışı,
 * izinli operasyon ekranlarına serbest".
 *
 * Doğrulanan davranış:
 *  - Terminal, SAHİP OLDUĞU izne karşılık gelen operasyon ekranına erişebilir
 *    (kendi istasyon ekranı DIŞINDA da).
 *  - Yönetim/hassas ekranlar KAPALI: sayfa → kendi ekranına redirect; API → 403.
 *  - İzni olmayan operasyon ekranı → 403 (kararı rota izin kontrolü verir).
 *  - Başka istasyon-kapsamı dışına ÇIKAMAZ (KDS scope 403).
 *  - Kök / panel kökü → cihaz kendi istasyon ekranıyla açılır.
 *
 * Mevcut güvenlik KORUNUR: gizli kullanıcı token/cihaz/kiracı geçemez, normal
 * giriş yapamaz, hassas eylemler PIN ister (ayrı testlerde).
 */
class TerminalAccessTest extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
    }

    private function makeDevice(string $station, string $name = 'Terminal'): TerminalDevice
    {
        return $this->asTenant($this->a['tenant'], fn (): TerminalDevice => app(TerminalProvisioner::class)
            ->createDevice($name, (int) $this->a['branch']->id, (int) $this->a['tenant']->id, $station));
    }

    /* ---------------- Operasyon ekranlarına erişim (yeni model) ---------------- */

    public function test_terminal_izinli_operasyon_ekranina_erisir_kendi_ekrani_disinda(): void
    {
        // Kasa terminali: orders.view izni var → Siparişler operasyon ekranına
        // artık erişebilir (eski modelde kendi ekranına redirect'lenirdi).
        $device = $this->makeDevice('kasa');
        $this->actingAs(User::find($device->user_id));

        // Kendi istasyon ekranı (kasa) — varsayılan açılış — erişilebilir.
        $this->get('/panel/kasa')->assertOk();

        // İzinli BAŞKA operasyon ekranı — erişilebilir.
        $this->get('/panel/siparisler')->assertOk();
    }

    public function test_terminal_izni_olmayan_operasyon_ekrani_403(): void
    {
        // Sipariş-giriş terminali: payments.take YOK → Kasa ekranı operasyon
        // olsa da izin süzer (redirect değil, 403 — kararı rota izin kontrolü).
        $device = $this->makeDevice('order_entry');
        $this->actingAs(User::find($device->user_id));

        $this->get('/panel/siparisler')->assertOk();      // izinli
        $this->get('/panel/kasa')->assertForbidden();     // izinsiz operasyon
    }

    /* ---------------- Yönetim/hassas ekranlar KAPALI ---------------- */

    public function test_terminal_yonetim_sayfalarina_erisemez_kendi_ekranina_doner(): void
    {
        $device = $this->makeDevice('kasa');
        $this->actingAs(User::find($device->user_id));

        // Block-list'teki her yönetim/hassas öbek → kendi ekranına (kasa) redirect.
        $blocked = [
            '/panel/ayarlar/e-posta',
            '/panel/personel',
            '/panel/roller',
            '/panel/raporlar',
            '/panel/boss',
            '/panel/entegrasyonlar',
            '/panel/prim',
            '/panel/subeler',
            '/panel/vardiya',
            '/panel/kiosklar',
            '/panel/terminaller',
        ];

        foreach ($blocked as $path) {
            // Yönetim ekranı terminale KAPALI: ya kendi ekranına redirect (302)
            // ya da özellik kapalıysa 404 (feature-gate). İkisi de "erişemez".
            $status = $this->get($path)->baseResponse->getStatusCode();
            $this->assertContains($status, [302, 404], "Terminal '{$path}' erişimi engellenmeli (302/404), gelen: {$status}");
        }
    }

    public function test_terminal_yonetim_api_uclari_403(): void
    {
        $device = $this->makeDevice('kasa');
        $this->actingAs(User::find($device->user_id));

        // Yönetim API uçları savunma derinliğiyle 403 (izin de zaten süzerdi).
        $this->getJson('/api/v1/staff')->assertForbidden();
        $this->getJson('/api/v1/venue/branches')->assertForbidden();  // YALNIZ şube yönetimi
        $this->getJson('/api/v1/terminals/devices')->assertForbidden();
    }

    /* ---------------- İstasyon-kapsamı korunur ---------------- */

    public function test_terminal_istasyon_kapsami_disina_cikamaz(): void
    {
        // Mutfak terminali: UserStation = ['kitchen']. Operasyon API'si (KDS
        // kuyruğu) çalışır AMA başka istasyonun kuyruğu açıkça istenirse 403.
        $device = $this->makeDevice('kitchen');
        $this->actingAs(User::find($device->user_id));

        // Kendi kapsamındaki KDS kuyruğu — erişilebilir (operasyon API'si açık).
        $this->getJson('/api/v1/kds/queue')->assertOk();

        // Atanmamış istasyonun kuyruğu → 403 (istasyon-kapsamı zorlanır).
        $this->getJson('/api/v1/kds/queue?station=bar')->assertForbidden();
    }

    /* ---------------- Kök / oto-giriş varsayılan ekran ---------------- */

    public function test_terminal_kok_ve_panel_koku_kendi_ekranina_yonlenir(): void
    {
        $device = $this->makeDevice('kitchen');
        $this->actingAs(User::find($device->user_id));

        // Panel kökü (genel dashboard) → cihaz kendi istasyon ekranıyla açılır.
        $this->get('/panel')->assertRedirect('/panel/mutfak');

        // Kendi istasyon ekranı doğrudan açık.
        $this->get('/panel/mutfak')->assertOk();
    }
}
