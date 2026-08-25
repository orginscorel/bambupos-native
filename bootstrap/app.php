<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
        then: function (): void {
            // Kimlik/panel API'si (oturum tabanlı; Inertia paneli bunları kullanır).
            \Illuminate\Support\Facades\Route::middleware('web')
                ->group(__DIR__.'/../routes/identity.php');

            // Katalog domaini (Faz 2): panel ekranları + JSON uçları.
            \Illuminate\Support\Facades\Route::middleware('web')
                ->group(__DIR__.'/../routes/catalog.php');

            // Ayarlar modülü: panelden yönetilen e-posta (SMTP) yapılandırması.
            \Illuminate\Support\Facades\Route::middleware('web')
                ->group(__DIR__.'/../routes/settings.php');

            // Venue domaini (Faz 2): şube/kat/alan/masa + QR (ADR-008).
            // Middleware BİLİNÇLİ olarak dosyanın içinde tanımlı: public
            // /m/{token} ucu oturumsuz kalmalı (ADR-011 tam-sayfa cache,
            // cache'lenen yanıtta Set-Cookie olamaz).
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/venue.php');

            // Orders domaini (Faz 3): sipariş/adisyon çekirdeği + garson
            // ekranları. Middleware dosyanın içinde: public QR sipariş ucu
            // bilinçli oturumsuzdur (ADR-008, kimlik yalnız token).
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/orders.php');

            // KDS domaini (Faz 4): mutfak/bar/komi ekranları + polling uçları.
            // Middleware dosyanın içinde tanımlı (web + auth + tenant).
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/kds.php');

            // Payments domaini (Faz 5, ADR-010): kasa + ödeme + POS adapter.
            // Middleware dosyanın içinde: sağlayıcı callback ucu oturumsuz
            // ve CSRF dışıdır (kimlik = HMAC imza + zaman damgası).
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/payments.php');

            // Personel-Yetki: personel/rol ekranları + kişi bazlı izin
            // istisnaları + PIN/işten çıkarma uçları (middleware dosya içinde).
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/staff.php');

            // Inventory domaini (Faz 6, §17): stok + depo + reçete + sayım +
            // satın alma. Middleware dosyanın içinde (web + auth + tenant);
            // public uç yoktur.
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/inventory.php');

            // Reservations domaini (Faz-9): rezervasyon + bekleme listesi.
            // Middleware dosyanın içinde: public QR talep ucu bilinçli
            // oturumsuz (ADR-008), müşteri onay/iptal sayfası token kimlikli.
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/reservations.php');

            // Kiosk domaini (Faz 8): self-servis sipariş ekranı + cihaz
            // yönetimi. Middleware dosyanın içinde: kiosk uçları bilinçli
            // oturumsuzdur (kimlik = opak cihaz token'ı, ADR-008 deseni).
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/kiosk.php');

            // Shifts domaini (Faz-7): vardiya planlama + mesai takibi.
            // Middleware dosyanın içinde: device-clock ucu bilinçli
            // oturumsuz/CSRF dışıdır (kimlik = X-Device-Token + PIN).
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/shifts.php');

            // Reports domaini (Faz-10): rol bazlı panel açılışı + raporlar +
            // kuyruklu dışa aktarma. identity.php'deki eski /reports/summary
            // ucundan SONRA kaydedilir; {report} joker deseni onu ezmez.
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/reports.php');

            // Sürüm notları (Surum-Changelog): panel sayfası + alt bilgi
            // rozetinin okuduğu hafif JSON. Middleware dosyanın içinde
            // (web + auth + tenant); tenant'a özel veri taşımaz.
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/changelog.php');

            // Borçlar/Cari (Adisyon-Cari): "adisyonu borca taşı" + tahsilat.
            // Middleware dosyanın içinde (web + auth + tenant); public uç yoktur.
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/receivables.php');

            // Terminal domaini (§13, Faz A): istasyon cihaz modu (kilitli
            // Mutfak/Barista/Komi terminalleri) + cihaz yönetimi. Middleware
            // dosyanın içinde: /terminal/{token} token'la oto-giriş (kimlik =
            // opak cihaz token'ı, ADR-008 deseni).
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/terminal.php');

            // Notify domaini (§8): panel-içi bildirim zili + web push (VAPID)
            // abonelik + kişi-bazlı bildirim tercihleri. Middleware dosyanın
            // içinde (web + auth + tenant); public uç yoktur.
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/notify.php');

            // Personel Portalı (Faz 1): host-farkındalıklı mobil self-servis
            // (mesai/mola/profil/rapor). Rotalar dosyanın içinde config('portal.host')
            // alan adına bağlıdır (Route::domain) → yalnız portal host'unda
            // eşleşir; panel + qrmenu.* host DAVRANIŞI DEĞİŞMEZ.
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/portal.php');

            // Teslimat/Paket (feature: delivery) + Prim/Komisyon (feature: commission).
            // Grup middleware'i içlerinde feature-gate uygular ("kapalı = yok").
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/delivery.php');
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/commission.php');

            // BOSS yönetim kokpiti (yetki: boss.view).
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/boss.php');

            // Entegrasyonlar (takılabilir çerçeve): ödeme/teslimat/e-fatura/muhasebe
            // aç-kapa + yapılandırma API'si (yetki: integrations.manage).
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/integrations.php');

            // SaaS abonelik/faturalama genel bakış (süper-admin, /yonetim/faturalama).
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/billing_saas.php');

            // İzinli cihazlar (KDS/kiosk/masaüstü cihaz kilidi) — yönetim API'si.
            \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/devices.php');
        },
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->web(append: [
            // Portal host'unda kök (`/`) isteğini portal ana ekranına (/mesaim)
            // taşır; panel host + diğer yollar için no-op (host-farkındalık).
            \App\Modules\Portal\Http\Middleware\HandlePortalHost::class,
            // Pasife alınan personelin AÇIK oturumu da düşer (Personel-Yetki).
            \App\Modules\Identity\Http\Middleware\EnsureUserIsActive::class,
            // §13 Terminal kilitli mod: is_terminal kullanıcı yalnız kendi
            // istasyon ekranını açar; başka sayfaya gidince kendi ekranına döner.
            \App\Modules\Terminal\Http\Middleware\EnsureTerminalLocked::class,
            \App\Http\Middleware\HandleInertiaRequests::class,
        ]);

        $middleware->alias([
            'tenant' => \App\Modules\Tenancy\Http\Middleware\EnsureTenantContext::class,
            // Rota düzeyi özellik kapısı: `feature:delivery` → kapalıysa 404.
            'feature' => \App\Modules\Settings\Http\Middleware\EnsureFeatureEnabled::class,
            // SaaS süper-admin (kiracı-üstü ürün yöneticisi).
            'superadmin' => \App\Modules\Marketing\Http\Middleware\EnsureSuperAdmin::class,
            // Cihaz kilidi: `device:kds` → link/QR ile bağlanan cihaza kilitler (izinli cihazlar).
            'device' => \App\Modules\Devices\Http\Middleware\EnsureDeviceAuthorized::class,
        ]);

        // Kimliksiz API isteği: YÖNLENDİRME YOK, 401 JSON.
        //
        // 2026-07-22: `/api/v1/*` uçlarına oturumsuz istek 500 döndürüyordu.
        // Sebep: Laravel'in varsayılan davranışı misafiri `login` ADLI rotaya
        // yönlendirmek; bu projede öyle bir rota yok (giriş ucu `auth.login`),
        // dolayısıyla "Route [login] not defined" fırlatılıp 500'e dönüşüyordu.
        // API tüketicisi zaten yönlendirme değil, durum kodu bekler.
        // `null` döndürmek Authenticate middleware'ini 401'e düşürür.
        $middleware->redirectGuestsTo(
            fn (Request $request) => ($request->is('api/*') || $request->expectsJson())
                ? null
                : '/giris',
        );

        // Oturumu olan kullanıcı misafir sayfalarına (giriş vb.) gelirse panele —
        // ANCAK portal host'unda personel portalına (/mesaim). HandlePortalHost
        // zaten panele düşen yolları yakalar; bu, çift-atlamayı önler.
        $middleware->redirectUsersTo(
            fn (Request $request) => \App\Modules\Portal\Support\Portal::isPortalHost($request)
                ? '/panelim'
                : '/panel',
        );
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );
    })->create();
