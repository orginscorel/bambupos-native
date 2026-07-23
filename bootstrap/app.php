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
        },
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->web(append: [
            // Pasife alınan personelin AÇIK oturumu da düşer (Personel-Yetki).
            \App\Modules\Identity\Http\Middleware\EnsureUserIsActive::class,
            \App\Http\Middleware\HandleInertiaRequests::class,
        ]);

        $middleware->alias([
            'tenant' => \App\Modules\Tenancy\Http\Middleware\EnsureTenantContext::class,
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

        // Oturumu olan kullanıcı misafir sayfalarına (giriş vb.) gelirse panele.
        $middleware->redirectUsersTo('/panel');
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );
    })->create();
