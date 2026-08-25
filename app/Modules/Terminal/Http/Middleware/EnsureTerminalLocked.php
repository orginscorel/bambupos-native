<?php

namespace App\Modules\Terminal\Http\Middleware;

use App\Modules\Identity\Models\User;
use App\Modules\Terminal\Support\TerminalStation;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * TERMINAL ERİŞİM MODELİ — rota koruması (§13).
 *
 * ESKİ MODEL: is_terminal kullanıcı YALNIZ kendi istasyon ekranını açabilirdi
 * (allow-list; başka her panel sayfası kendi ekranına redirect). Bu, mutfak
 * terminalinin Menü'yü, kasa terminalinin Siparişler'i görmesini de engelliyordu.
 *
 * YENİ MODEL (block-list): terminal artık tek ekrana KİLİTLİ değil; SAHİP OLDUĞU
 * izinlere karşılık gelen YÖNETİM-DIŞI operasyon ekranlarına serbestçe gidebilir
 * (siparişler/masalar/kasa/mutfak/barista/komi/menü/stok/teslimat…). Yalnız
 * YÖNETİM / HASSAS öbekler kapalı kalır:
 *   Ayarlar, Personel, Roller, Raporlar, BOSS, Entegrasyonlar, Prim, Şubeler,
 *   Vardiya (yönetim), Kiosk yönetimi, Terminal yönetimi — VE karşılık gelen
 *   API uçları.
 *
 * Gerçek erişim kararını yine de rota/denetleyicinin izin kontrolü (authorize)
 * verir: terminalin izni + istasyon-kapsamı zaten süzer (izin yoksa 403). Bu
 * katman, yönetim yüzeyini SUNUCU tarafında da (derin-link / elle URL denemesi)
 * kesin olarak kapatır ve savunma derinliği sağlar.
 *
 * KORUNAN GÜVENLİK: gizli terminal kullanıcısı başka token/cihaz/kiracıya
 * geçemez (TerminalTokenResolver + tenant scope), normal giriş/impersonation
 * yapamaz (Identity), hassas eylemler is_terminal iken PIN ister
 * (TerminalPinGate). Kök/oto-giriş → cihaz yine kendi istasyon ekranıyla açılır.
 */
class EnsureTerminalLocked
{
    /**
     * YÖNETİM / HASSAS öbekler — terminal ERİŞEMEZ (block-list). Panel yönetim
     * SAYFALARI + karşılık gelen API uçları. API uçlarını burada da kesmek
     * savunma derinliğidir; izin sistemi zaten süzer (terminal bu izinlere
     * sahip değildir), ancak elle istek / gelecekteki izin genişlemesine karşı
     * sunucuda kesin sınır çizeriz.
     *
     * DİKKAT: `api/v1/venue` prefix'i Şubeler (yönetim) İLE Masalar/Alanlar/
     * Katlar (operasyon) arasında PAYLAŞILIR → tüm venue'yu değil, YALNIZ
     * `api/v1/venue/branches*` (şube yönetimi) uçlarını kes; masalar operasyona
     * açık kalsın.
     *
     * @var array<int, string>
     */
    private const MANAGEMENT_PATTERNS = [
        // ---- Panel yönetim/hassas SAYFA öbekleri ----
        'panel/ayarlar', 'panel/ayarlar/*',
        'panel/personel', 'panel/personel/*',
        'panel/roller', 'panel/roller/*',
        'panel/raporlar', 'panel/raporlar/*',
        'panel/boss', 'panel/boss/*',
        'panel/entegrasyonlar', 'panel/entegrasyonlar/*',
        'panel/prim', 'panel/prim/*',
        'panel/subeler', 'panel/subeler/*',
        'panel/vardiya', 'panel/vardiya/*',
        'panel/kiosklar', 'panel/kiosklar/*',
        'panel/terminaller', 'panel/terminaller/*',
        // Menü düzenleme / rezervasyon / stok yönetimi de terminal-DIŞI (denetim
        // sızıntısı kapatıldı). Borçlar (receivables) BİLİNÇLİ dışarıda: kasa
        // terminali cari tahsilat yapabilir.
        'panel/menu', 'panel/menu/*',
        'panel/rezervasyonlar', 'panel/rezervasyonlar/*',
        'panel/stok', 'panel/stok/*',

        // ---- Karşılık gelen API uçları (savunma derinliği) ----
        'api/v1/settings', 'api/v1/settings/*',
        'api/v1/staff', 'api/v1/staff/*',
        'api/v1/staff-access', 'api/v1/staff-access/*',
        'api/v1/roles', 'api/v1/roles/*',
        'api/v1/reports', 'api/v1/reports/*',
        'api/v1/boss', 'api/v1/boss/*',
        'api/v1/commission', 'api/v1/commission/*',
        'api/v1/shifts', 'api/v1/shifts/*',
        'api/v1/venue/branches', 'api/v1/venue/branches/*', // YALNIZ şube yönetimi
        'api/v1/kiosk', 'api/v1/kiosk/*',
        'api/v1/terminals', 'api/v1/terminals/*',
        'api/v1/integrations', 'api/v1/integrations/*',
        // Katalog YÖNETİM API'si (sipariş girişi `api/v1/orders/catalog` kullanır,
        // bu değil), rezervasyon ve stok yönetimi API'leri de terminal-DIŞI.
        'api/v1/catalog', 'api/v1/catalog/*',
        'api/v1/reservations', 'api/v1/reservations/*',
        'api/v1/inventory', 'api/v1/inventory/*',
    ];

    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (! $user instanceof User || ! $user->is_terminal) {
            return $next($request);
        }

        // Giriş/çıkış yüzeyi (token'la oto-giriş/çıkış) + health her zaman serbest
        // — kimlik yalnız token; bu uçlar ekranın çalışması için gereklidir.
        if ($request->is('terminal', 'terminal/*', 'up')) {
            return $next($request);
        }

        $screen = TerminalStation::screenFor($user->terminal_station);

        // YÖNETİM / HASSAS öbekler → terminal ERİŞEMEZ. Sayfa gezinmesi kendi
        // ekranına yönlenir (temiz UX); API/JSON/mutasyon 403 alır (kesin sınır).
        if ($request->is(...self::MANAGEMENT_PATTERNS)) {
            if ($this->isPageNavigation($request)) {
                return redirect()->to($screen);
            }

            abort(403);
        }

        // Yönetim-DIŞI API/JSON/mutasyon uçlarına DOKUNMA: operasyon ekranlarının
        // çalışması için gerekli (KDS polling, adisyon/ödeme yazma + PIN kapısı,
        // masa/katalog okuma…); izin + istasyon-kapsamı + PIN kapısı zaten süzer.
        if (! $this->isPageNavigation($request)) {
            return $next($request);
        }

        // Kök / oto-giriş / panel kökü → cihaz kendi istasyon ekranıyla açılır
        // (varsayılan ekran); genel panel/dashboard'a düşmez.
        if ($request->is('/', 'panel')) {
            return redirect()->to($screen);
        }

        // Kalan YÖNETİM-DIŞI /panel operasyon ekranları serbest. Erişim kararını
        // rota/denetleyici izin kontrolü verir (izin yoksa 403). Böylece model
        // "tek ekrana kilit"ten "yönetim-dışı, izinli operasyon ekranlarına
        // serbest"e döner; frontend terminal nav'ı da bu kümeyi gösterir.
        return $next($request);
    }

    /**
     * Bir tarayıcı SAYFA gezinmesi mi? (GET + JSON beklemiyor + API ucu değil)
     * Yalnız bunlar yönetimde redirect edilir / kök yönlendirmesine tabidir;
     * geri kalan (POST/PUT/DELETE, JSON, /api/*) API/mutasyon kabul edilir.
     */
    private function isPageNavigation(Request $request): bool
    {
        return $request->isMethod('GET')
            && ! $request->expectsJson()
            && ! $request->is('api/*');
    }
}
