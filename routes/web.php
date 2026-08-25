<?php

use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| Giriş noktası: BamBumPOS kurumsal tanıtım (landing) ana sayfası.
| Oturum varsa doğrudan uygulamaya (panel/istasyon) yönlenir.
|--------------------------------------------------------------------------
*/
Route::get('/', [\App\Modules\Marketing\Http\Controllers\MarketingController::class, 'home'])->name('home');
Route::post('/demo-talep', [\App\Modules\Marketing\Http\Controllers\MarketingController::class, 'storeDemo'])->name('marketing.demo');

// Fiyatlandırma (sabit sayfa — slug catch-all'lardan önce tanımlanır).
Route::get('/fiyatlandirma', [\App\Modules\Marketing\Http\Controllers\PageController::class, 'pricing'])
    ->name('marketing.pricing');

// Tek /{slug} dispatcher: kurumsal + sektör + çözüm sayfaları.
// DİKKAT: Aynı URI+method'lu birden fazla Route::get('/{slug}') Laravel'de
// birbirini EZER (yalnız sonuncusu kalır) → hepsi tek route + tek handler'da
// toplanır. where-constraint yalnız bilinen slug'ları yakalar; /giris, /panel
// gibi diğer rotaları gölgelemez.
Route::get('/{slug}', [\App\Modules\Marketing\Http\Controllers\PageController::class, 'dispatch'])
    ->where('slug', implode('|', array_map('preg_quote', array_merge(
        array_keys((array) config('corporate', [])),
        array_keys((array) config('sectors', [])),
        array_keys((array) config('solutions', [])),
    ))))
    ->name('marketing.page');

/*
|--------------------------------------------------------------------------
| SaaS SÜPER-ADMIN (kiracı-üstü) — /yonetim. `tenant` middleware YOK.
|--------------------------------------------------------------------------
*/
Route::middleware(['auth:web', 'superadmin'])->prefix('yonetim')->name('superadmin.')->group(function (): void {
    $c = \App\Modules\Marketing\Http\Controllers\SuperAdminController::class;
    Route::get('/', [$c, 'dashboard'])->name('dashboard');
    Route::get('/isletmeler', [$c, 'tenants'])->name('tenants');
    Route::post('/isletmeler', [$c, 'tenantStore'])->name('tenants.store');
    Route::put('/isletmeler/{id}', [$c, 'tenantUpdate'])->whereNumber('id')->name('tenants.update');
    Route::post('/isletmeler/{id}/durum', [$c, 'tenantSetStatus'])->whereNumber('id')->name('tenants.status');
    Route::get('/demo-talepleri', [$c, 'demoRequests'])->name('demos');
    Route::put('/demo-talepleri/{id}', [$c, 'demoUpdate'])->whereNumber('id')->name('demos.update');
});

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
// Askıdaki işletmenin kullanıcısı buraya yönlenir (kiracı middleware'i YOK; oturum korunur).
Route::middleware('auth:web')->get('/hesap-askida', function () {
    $tenant = request()->user()?->tenant;

    // "Şimdi Öde" butonu için: işletmenin en güncel ödenmemiş faturası +
    // aktif ödeme sağlayıcısı manuel mi (öyleyse buton gösterilmez — bkz.
    // routes/saas_payment.php, App\Modules\Billing\Payments\SaasPaymentRegistry).
    $unpaidInvoice = $tenant
        ? \App\Modules\Billing\Models\SaasInvoice::query()
            ->where('tenant_id', $tenant->id)
            ->where('status', \App\Modules\Billing\Models\SaasInvoice::STATUS_UNPAID)
            ->orderByDesc('id')
            ->first()
        : null;

    return view('tenant.suspended', [
        'tenantName' => $tenant?->name,
        'unpaidInvoice' => $unpaidInvoice,
        'paymentProviderManual' => app(\App\Modules\Billing\Payments\SaasPaymentRegistry::class)->current()->key() === 'manual',
    ]);
})->name('tenant.suspended');

Route::middleware(['auth:web', 'tenant'])->prefix('panel')->group(function (): void {
    Route::get('/', function () {
        $user = request()->user();

        // Açık tercihi olmayan (Otomatik) dar-yetkili personel doğrudan
        // dashboard'a gelirse kendi ekranına yönlenir; açık tercih EZİLMEZ,
        // dashboard'a çözülenlerde döngü olmaması için hedef == '/panel' ise
        // olduğu gibi gösterilir.
        if (\App\Modules\Identity\Support\HomeScreen::isAutomatic($user)) {
            $target = \App\Modules\Identity\Support\HomeScreen::resolve($user);

            if ($target !== '/panel') {
                return redirect($target);
            }
        }

        return Inertia::render('Panel/Dashboard');
    })->name('panel.dashboard');
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
