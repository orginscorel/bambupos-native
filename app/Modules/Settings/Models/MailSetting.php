<?php

namespace App\Modules\Settings\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * E-posta (SMTP) ayarı.
 *
 *  - tenant_id NULL → platform varsayılanı (tek satır)
 *  - tenant_id dolu → işletme override'ı
 *
 * GÜVENLİK:
 *  - `password` Crypt ile şifreli saklanır (`encrypted` cast) ve `$hidden`
 *    olduğundan hiçbir JSON yanıtına çıkmaz; arayüz yalnız `has_password`
 *    bayrağını görür.
 *  - Bu model BelongsToTenant scope'u KULLANMAZ (platform satırı tenant_id
 *    NULL olduğundan scope onu asla döndüremezdi). Kiracı süzgeci
 *    MailSettingsService içinde açıkça uygulanır; route model binding yoktur.
 */
class MailSetting extends Model
{
    protected $fillable = [
        'mailer',
        'host',
        'port',
        'encryption',
        'username',
        'password',
        'from_name',
        'from_address',
        'reply_to',
        'timeout',
    ];

    protected $hidden = ['password'];

    protected $appends = ['has_password'];

    protected function casts(): array
    {
        return [
            'password' => 'encrypted',
            'port' => 'integer',
            'timeout' => 'integer',
        ];
    }

    public function getHasPasswordAttribute(): bool
    {
        $raw = $this->getRawOriginal('password');

        return $raw !== null && $raw !== '';
    }

    public function isPlatform(): bool
    {
        return $this->tenant_id === null;
    }

    /**
     * Bu ayarın karşılığı olan Laravel mailer yapılandırması.
     *
     * @return array<string, mixed>
     */
    public function toMailerConfig(): array
    {
        return match ($this->mailer) {
            'smtp' => [
                'transport' => 'smtp',
                // 'smtps' = bağlantı baştan TLS (SSL/465). Düz 'smtp'
                // şemasında sunucu STARTTLS sunarsa otomatik kullanılır.
                'scheme' => $this->encryption === 'ssl' ? 'smtps' : 'smtp',
                'url' => null,
                'host' => (string) $this->host,
                'port' => (int) $this->port,
                'username' => $this->username !== '' ? $this->username : null,
                'password' => $this->password !== '' ? $this->password : null,
                'timeout' => max(1, (int) ($this->timeout ?: 30)),
                'local_domain' => parse_url((string) config('app.url'), PHP_URL_HOST),
            ],
            'sendmail' => [
                'transport' => 'sendmail',
                'path' => config('mail.mailers.sendmail.path', '/usr/sbin/sendmail -bs -i'),
            ],
            default => ['transport' => 'log', 'channel' => config('mail.mailers.log.channel')],
        };
    }
}
