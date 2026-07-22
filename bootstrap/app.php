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

            // Ayarlar modülü: panelden yönetilen e-posta (SMTP) yapılandırması.
            \Illuminate\Support\Facades\Route::middleware('web')
                ->group(__DIR__.'/../routes/settings.php');
        },
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->web(append: [
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
