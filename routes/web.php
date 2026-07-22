<?php

use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| Giriş noktası: karşılama sayfası yok.
| Oturum varsa panel, yoksa giriş ekranı.
|--------------------------------------------------------------------------
*/
Route::get('/', function () {
    $user = Auth::guard('web')->user();

    return $user instanceof \App\Modules\Identity\Models\User
        // Role özel açılış ekranı (Personel-Yetki): tercih > otomatik profil.
        ? redirect(\App\Modules\Identity\Support\HomeScreen::resolve($user))
        : redirect()->route('login');
})->name('home');

/*
|--------------------------------------------------------------------------
| Kimlik ekranları (yalnız misafir; oturum varsa /panel'e yönlenir)
|--------------------------------------------------------------------------
*/
Route::middleware('guest')->group(function (): void {
    Route::get('/giris', fn () => Inertia::render('Auth/Login'))->name('login');

    Route::get('/giris/pin', fn () => Inertia::render('Auth/PinLogin'))->name('login.pin');

    Route::get('/parola-sifirla', fn () => Inertia::render('Auth/ForgotPassword'))->name('password.request');

    // ResetPassword::createUrlUsing bu adresi üretir (AppServiceProvider).
    Route::get('/reset-password', function () {
        return Inertia::render('Auth/ResetPassword', [
            'token' => (string) request()->query('token', ''),
            'email' => (string) request()->query('email', ''),
        ]);
    })->name('password.reset');
});

/*
|--------------------------------------------------------------------------
| Panel ekranları (oturum + kiracı bağlamı zorunlu)
|--------------------------------------------------------------------------
*/
Route::middleware(['auth:web', 'tenant'])->prefix('panel')->group(function (): void {
    Route::get('/', fn () => Inertia::render('Panel/Dashboard'))->name('panel.dashboard');
    Route::get('/profil', fn () => Inertia::render('Panel/Profile'))->name('panel.profile');
});

/*
|--------------------------------------------------------------------------
| Tasarım sistemi (Arayüz-Temeli ajanı) — geliştirme referans sayfaları
|--------------------------------------------------------------------------
| DESIGN_PAGE_ENABLED=false yapıldığında 404 döner (canlıya çıkarken kapatın).
| İş mantığı içermez; token/bileşen vitrinidir.
*/
Route::get('/tasarim', function () {
    abort_unless(config('design.page_enabled'), 404);

    return Inertia::render('DesignSystem');
})->name('design.system');

Route::get('/tasarim/menu', function () {
    abort_unless(config('design.page_enabled'), 404);

    $fmt = fn (int $minor): string => '₺ '.number_format($minor / 100, 2, ',', '.');
    $p = fn (int $id, string $name, string $desc, int $minor, bool $unavailable = false) => [
        'id' => $id, 'name' => $name, 'description' => $desc,
        'price_minor' => $minor, 'price_formatted' => $fmt($minor), 'unavailable' => $unavailable,
    ];

    return view('public.menu-demo', [
        'venue' => ['name' => 'Örnek İşletme', 'table' => 'Masa: Bahçe 4'],
        'categories' => [
            ['id' => 1, 'name' => 'Çorbalar', 'products' => [
                $p(1, 'Mercimek Çorbası', 'Tereyağı ve limon ile servis edilir', 9500),
                $p(2, 'Ezogelin Çorbası', 'Nane ve pul biberli', 9500),
            ]],
            ['id' => 2, 'name' => 'Ana Yemekler', 'products' => [
                $p(3, 'Izgara Köfte', 'Pilav, közlenmiş biber ve domates ile', 32500),
                $p(4, 'Tavuk Şiş', 'Yoğurtlu marine, salata eşliğinde', 28000),
                $p(5, 'Karışık Izgara', 'İki kişilik; köfte, şiş, kanat, pirzola', 79000, true),
            ]],
            ['id' => 3, 'name' => 'Salatalar', 'products' => [
                $p(6, 'Çoban Salata', 'Domates, salatalık, biber, soğan', 12000),
                $p(7, 'Sezar Salata', 'Izgara tavuk, kruton, parmesan', 18500),
            ]],
            ['id' => 4, 'name' => 'İçecekler', 'products' => [
                $p(8, 'Ayran', '300 ml', 4000),
                $p(9, 'Taze Sıkılmış Portakal Suyu', '330 ml', 9000),
                $p(10, 'Çay', 'İnce belli bardakta', 2500),
            ]],
            ['id' => 5, 'name' => 'Tatlılar', 'products' => [
                $p(11, 'Künefe', 'Antep fıstıklı, sıcak servis', 19500),
                $p(12, 'Sütlaç', 'Fırında, tarçınlı', 12500),
            ]],
        ],
    ]);
})->name('design.menu');
