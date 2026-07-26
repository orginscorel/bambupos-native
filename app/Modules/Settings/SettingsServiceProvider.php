<?php

namespace App\Modules\Settings;

use App\Modules\Settings\Mail\RuntimeMailManager;
use App\Modules\Settings\Services\MailConfigurator;
use App\Modules\Settings\Support\PublicMenuBranding;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Notifications\Events\NotificationFailed;
use Illuminate\Notifications\Events\NotificationSending;
use Illuminate\Notifications\Events\NotificationSent;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\View;
use Illuminate\Support\ServiceProvider;

/**
 * Ayar modülü: veritabanından yönetilen e-posta yapılandırmasını
 * çalışma anında devreye alır.
 */
class SettingsServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(MailConfigurator::class);

        // Feature-flag servisi (§9): istek-başına memo → `scoped`. Nav süzgeci,
        // rota gate'leri ve auth paylaşımı tek sorguyla çözülür; testler arası
        // bayat durum riski yok (Redis yok).
        $this->app->scoped(\App\Modules\Settings\Services\FeatureService::class);

        // Mail yöneticisini, gönderim anında DB ayarını uygulayan
        // türevle değiştir. Ayar satırı yoksa davranış .env ile birebirdir.
        $this->app->extend(
            'mail.manager',
            fn ($manager, $app) => new RuntimeMailManager($app),
        );
    }

    public function boot(): void
    {
        // Bildirimler (ör. parola sıfırlama) misafir istekte gönderilir;
        // kiracı, alıcının tenant_id'sinden ipucu olarak verilir ki
        // işletme override'ı varsa onun ayarıyla gönderilsin.
        Event::listen(NotificationSending::class, function (NotificationSending $event): void {
            $tenantId = $event->notifiable instanceof Model
                ? $event->notifiable->getAttribute('tenant_id')
                : null;

            if ($tenantId !== null) {
                $this->app->make(MailConfigurator::class)->hintTenant((int) $tenantId);
            }
        });

        $clear = fn () => $this->app->make(MailConfigurator::class)->hintTenant(null);
        Event::listen(NotificationSent::class, $clear);
        Event::listen(NotificationFailed::class, $clear);

        // Public menü (venue.menu) başlığına marka verisi: logo + kategori
        // renk/ikon meta'sı. Marka alanı bu modülün malı; Venue modülüne
        // dokunmadan composer ile bağlanır (çerezsiz → tam-sayfa cache korunur).
        View::composer('venue.menu', PublicMenuBranding::class);
    }
}
