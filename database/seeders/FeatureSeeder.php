<?php

namespace Database\Seeders;

use App\Modules\Settings\Models\TenantFeature;
use App\Modules\Settings\Support\FeatureCatalog;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Database\Seeder;

/**
 * §9 Eklentiler/feature-flag demo verisi.
 *
 * Demo kiracı için tüm OPSİYONEL özellikleri AÇIK olarak yazar (makul
 * varsayılan = her şey açık; yönetici Eklentiler ekranından kapatabilir).
 * Idempotent (updateOrCreate). DemoTenantSeeder'dan SONRA çalışır.
 *
 * Not: satır olmasa da FeatureService varsayılanı zaten "açık" döndürür;
 * bu seeder yalnız durumu AÇIKÇA görünür kılar (denetim/örnek).
 */
class FeatureSeeder extends Seeder
{
    public function run(): void
    {
        app(TenantContext::class)->runWithoutTenancy(function (): void {
            $tenant = Tenant::query()->where('slug', 'demo')->first();

            if ($tenant === null) {
                return;
            }

            foreach (FeatureCatalog::keys() as $key) {
                TenantFeature::query()->updateOrCreate(
                    ['tenant_id' => $tenant->id, 'feature' => $key],
                    ['enabled' => true],
                );
            }
        });
    }
}
