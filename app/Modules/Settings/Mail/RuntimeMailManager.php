<?php

namespace App\Modules\Settings\Mail;

use App\Modules\Settings\Services\MailConfigurator;
use Illuminate\Mail\MailManager;

/**
 * Mailer çözümlenmeden hemen önce veritabanındaki e-posta ayarını
 * yapılandırmaya uygulayan yönetici. `Mail::send`, bildirimler, parola
 * sıfırlama vb. tüm akışlar buradan geçer; ayar yoksa .env aynen geçerlidir.
 *
 * SettingsServiceProvider `mail.manager` bağlamasını bu sınıfla değiştirir.
 */
class RuntimeMailManager extends MailManager
{
    public function mailer($name = null)
    {
        // DB ayarını uygula (tembel + imza kontrollü; değişmediyse ucuz).
        $this->app->make(MailConfigurator::class)->apply();

        return parent::mailer($name);
    }
}
