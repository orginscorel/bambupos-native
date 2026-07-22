<?php

namespace App\Providers;

use App\Modules\Catalog\Models\Allergen;
use App\Modules\Catalog\Models\Category;
use App\Modules\Catalog\Models\Menu;
use App\Modules\Catalog\Models\OptionGroup;
use App\Modules\Catalog\Models\Product;
use App\Modules\Catalog\Policies\AllergenPolicy;
use App\Modules\Catalog\Policies\CategoryPolicy;
use App\Modules\Catalog\Policies\MenuPolicy;
use App\Modules\Catalog\Policies\OptionGroupPolicy;
use App\Modules\Catalog\Policies\ProductPolicy;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Policies\RolePolicy;
use App\Modules\Identity\Policies\StaffPolicy;
use App\Modules\Ordering\Models\Customer;
use App\Modules\Ordering\Models\Order;
use App\Modules\Ordering\Policies\CustomerPolicy;
use App\Modules\Ordering\Policies\OrderPolicy;
use App\Modules\Tables\Models\Table;
use App\Modules\Tables\Policies\TablePolicy;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;
use Illuminate\Validation\Rules\Password;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // Kiracı bağlamı: istek başına tek örnek (ADR-004).
        $this->app->singleton(TenantContext::class);
    }

    public function boot(): void
    {
        // Katman 2: policy kayıtları
        Gate::policy(Product::class, ProductPolicy::class);
        Gate::policy(Category::class, CategoryPolicy::class);
        Gate::policy(OptionGroup::class, OptionGroupPolicy::class);
        Gate::policy(Allergen::class, AllergenPolicy::class);
        Gate::policy(Menu::class, MenuPolicy::class);
        Gate::policy(Order::class, OrderPolicy::class);
        Gate::policy(Customer::class, CustomerPolicy::class);
        Gate::policy(Table::class, TablePolicy::class);
        Gate::policy(User::class, StaffPolicy::class);
        Gate::policy(Role::class, RolePolicy::class);

        Password::defaults(fn () => Password::min(10));

        // Sıfırlama e-postasındaki bağlantı (SPA sayfasını Arayüz fazı kurar).
        \Illuminate\Auth\Notifications\ResetPassword::createUrlUsing(
            fn ($notifiable, string $token) => config('app.url')
                .'/reset-password?token='.$token
                .'&email='.urlencode($notifiable->getEmailForPasswordReset()),
        );
    }
}
