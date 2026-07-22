<?php

namespace App\Modules\Settings\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Settings\Models\MailSetting;
use App\Modules\Settings\Services\MailSettingsService;
use App\Modules\Settings\Support\SmtpErrorTranslator;
use App\Modules\Settings\Support\SmtpHostGuard;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Throwable;

/**
 * Panelden e-posta (SMTP) ayarı yönetimi.
 *
 * Yetki: settings.manage. Kiracı izolasyonu: uçlar KENDİ kiracısının
 * satırından başkasına asla dokunmaz (id parametresi yok, route binding yok).
 * Platform varsayılanını yalnız platform işletmecisi kiracı düzenler.
 *
 * GÜVENLİK: parola yanıtlarda asla yer almaz (modelde $hidden); denetim
 * kaydına yalnız "değişti" bilgisi yazılır, değerin kendisi yazılmaz.
 */
class MailSettingsController extends Controller
{
    public function __construct(
        private readonly MailSettingsService $service,
        private readonly AuditLogger $audit,
    ) {
    }

    public function show(Request $request): JsonResponse
    {
        $user = $this->authorizeManage($request);

        $tenantId = (int) $user->tenant_id;
        $platform = $this->service->platform();
        ['source' => $source] = $this->service->effective($tenantId);

        return response()->json([
            'can_manage_platform' => $this->isPlatformManager($user),
            'effective_source' => $source,
            'tenant' => $this->service->forTenant($tenantId),
            'platform' => $this->isPlatformManager($user) ? $platform : null,
            // Platform-dışı işletmeye sır içermeyen özet: varsayılanın var
            // olup olmadığını ve hangi adresten gönderileceğini görebilsin.
            'platform_summary' => [
                'exists' => $platform !== null,
                'mailer' => $platform?->mailer,
                'from_address' => $platform?->from_address,
            ],
            'env' => [
                'mailer' => config('mail.default'),
                'from_address' => config('mail.from.address'),
            ],
            'tenant_smtp_ports' => config('settings.tenant_smtp_ports'),
        ]);
    }

    /** @param  'tenant'|'platform'  $scope */
    public function update(Request $request, string $scope): JsonResponse
    {
        $user = $this->authorizeManage($request);

        if ($scope === 'platform') {
            abort_unless($this->isPlatformManager($user), 403, 'Platform varsayılanını yalnız platform işletmecisi düzenleyebilir.');
            $targetTenantId = null;
        } else {
            // Kiracı izolasyonu: hedef DAİMA oturum kullanıcısının kiracısı.
            $targetTenantId = (int) $user->tenant_id;
        }

        $data = $this->validated($request, $scope, $user);

        $existing = $targetTenantId === null
            ? $this->service->platform()
            : $this->service->forTenant($targetTenantId);

        $old = $this->auditable($existing);

        $setting = $this->service->save($targetTenantId, $data);

        $this->audit->log(
            $scope === 'platform' ? 'settings.mail.platform_updated' : 'settings.mail.updated',
            $setting,
            $old,
            $this->auditable($setting->fresh()),
        );

        ['source' => $source] = $this->service->effective((int) $user->tenant_id);

        return response()->json([
            'setting' => $setting->fresh(),
            'effective_source' => $source,
        ]);
    }

    /** İşletme override'ını kaldırır (platform/env varsayılanına dönülür). */
    public function destroy(Request $request): JsonResponse
    {
        $user = $this->authorizeManage($request);

        $setting = $this->service->forTenant((int) $user->tenant_id);

        if ($setting !== null) {
            $this->audit->log('settings.mail.override_removed', $setting, $this->auditable($setting), null);
            $setting->delete();
        }

        ['source' => $source] = $this->service->effective((int) $user->tenant_id);

        return response()->json(['ok' => true, 'effective_source' => $source]);
    }

    /**
     * Bağlantı testi: geçerli (effective) ayarla verilen adrese GERÇEK bir
     * deneme e-postası gönderir ve sonucu dürüstçe bildirir. Başarısızsa
     * ham hata anlaşılır Türkçeyle (parola temizlenmiş olarak) döner.
     */
    public function test(Request $request): JsonResponse
    {
        $user = $this->authorizeManage($request);

        $data = $request->validate(
            ['to' => ['required', 'email']],
            [],
            ['to' => 'alıcı adresi'],
        );

        // Hız sınırı: kötüye kullanım / iç ağ taraması caydırılır.
        $key = 'settings-mail-test:'.$user->getKey();
        $max = (int) config('settings.mail_test.max_attempts', 3);

        if (RateLimiter::tooManyAttempts($key, $max)) {
            return response()->json([
                'ok' => false,
                'error' => 'Çok fazla deneme yapıldı. '.RateLimiter::availableIn($key).' saniye sonra tekrar deneyin.',
            ], 429);
        }

        RateLimiter::hit($key, (int) config('settings.mail_test.decay_seconds', 60));

        ['setting' => $setting, 'source' => $source] = $this->service->effective((int) $user->tenant_id);

        // Savunma katmanı: işletme kaynaklı SMTP ayarı iç ağa işaret
        // ediyorsa (kayıt sonrası DNS değişmiş olabilir) bağlanma.
        if (
            $setting !== null && $source === 'tenant' && $setting->mailer === 'smtp'
            && ! $this->isPlatformManager($user) && SmtpHostGuard::isForbidden((string) $setting->host)
        ) {
            return response()->json([
                'ok' => false,
                'error' => 'SMTP sunucu adresi iç ağ/yerel bir adrese işaret ediyor; güvenlik gereği bağlanılmadı.',
            ], 200);
        }

        $driver = $setting?->mailer ?? (string) config('mail.default');
        $fromAddress = $setting?->from_address ?: (string) config('mail.from.address');
        $fromName = $setting?->from_name ?: (string) config('mail.from.name');

        $mailerConfig = $setting?->toMailerConfig()
            ?? (array) config('mail.mailers.'.$driver, ['transport' => 'log']);

        // Test isteği sunucuyu dakikalarca bekletmesin.
        if (($mailerConfig['transport'] ?? null) === 'smtp') {
            $cap = (int) config('settings.mail_test.timeout_cap', 15);
            $mailerConfig['timeout'] = min((int) ($mailerConfig['timeout'] ?? $cap), $cap);
        }

        try {
            Mail::build($mailerConfig)->raw(
                "Bu bir deneme e-postasıdır.\n\n"
                ."QR Menü Platformu e-posta ayarlarınız bu iletiyi gönderebildiyse doğru çalışıyor demektir.\n"
                .'Gönderim kaynağı: '.match ($source) {
                    'tenant' => 'işletme ayarı',
                    'platform' => 'platform varsayılanı',
                    default => 'sunucu (.env) varsayılanı',
                }." · Sürücü: {$driver}",
                function ($message) use ($data, $fromAddress, $fromName): void {
                    $message->to($data['to'])
                        ->from($fromAddress, $fromName ?: null)
                        ->subject('QR Menü — E-posta bağlantı testi');
                },
            );
        } catch (Throwable $e) {
            return response()->json([
                'ok' => false,
                'error' => SmtpErrorTranslator::friendly($e, $setting?->password),
            ], 200);
        }

        return response()->json([
            'ok' => true,
            'source' => $source,
            'driver' => $driver,
            // DÜRÜSTLÜK: log/array sürücüsü gerçek gönderim yapmaz; kullanıcı
            // "başarılı" görüp aldanmasın.
            'note' => in_array($driver, ['log', 'array'], true)
                ? 'Dikkat: seçili sürücü "'.$driver.'" — e-posta GERÇEKTE gönderilmedi, yalnızca kayda yazıldı. Gerçek gönderim için SMTP yapılandırın.'
                : null,
        ]);
    }

    /* ---------------- Yardımcılar ---------------- */

    private function authorizeManage(Request $request): User
    {
        /** @var User $user */
        $user = $request->user();

        abort_unless($user->hasPermission('settings.manage'), 403);
        abort_if($user->tenant_id === null, 403);

        return $user;
    }

    private function isPlatformManager(User $user): bool
    {
        $platformTenantId = config('settings.platform_tenant_id');

        return $platformTenantId !== null
            && (int) $platformTenantId === (int) $user->tenant_id;
    }

    /**
     * @return array<string, mixed>
     */
    private function validated(Request $request, string $scope, User $user): array
    {
        $isSmtp = $request->input('mailer') === 'smtp';
        $tenantRestricted = $scope === 'tenant' && ! $this->isPlatformManager($user);

        $data = $request->validate([
            'mailer' => ['required', Rule::in(['smtp', 'sendmail', 'log'])],
            'host' => [Rule::requiredIf($isSmtp), 'nullable', 'string', 'max:255'],
            'port' => array_filter([
                Rule::requiredIf($isSmtp), 'nullable', 'integer',
                $tenantRestricted
                    ? Rule::in(config('settings.tenant_smtp_ports', [25, 465, 587, 2525]))
                    : 'between:1,65535',
            ]),
            'encryption' => [Rule::requiredIf($isSmtp), 'nullable', Rule::in(['tls', 'ssl', 'none'])],
            'username' => ['nullable', 'string', 'max:255'],
            // Boş bırakılırsa mevcut parola korunur (serviste uygulanır).
            'password' => ['nullable', 'string', 'max:255'],
            'from_name' => ['nullable', 'string', 'max:120'],
            'from_address' => ['required', 'email', 'max:255'],
            'reply_to' => ['nullable', 'email', 'max:255'],
            'timeout' => ['nullable', 'integer', 'between:5,120'],
        ], [], [
            'mailer' => 'sürücü',
            'host' => 'sunucu adresi',
            'port' => 'port',
            'encryption' => 'şifreleme',
            'username' => 'kullanıcı adı',
            'password' => 'parola',
            'from_name' => 'gönderen adı',
            'from_address' => 'gönderen adresi',
            'reply_to' => 'yanıt adresi',
            'timeout' => 'zaman aşımı',
        ]);

        // SSRF önlemi: platform-dışı işletme iç ağ adresi kaydedemez.
        if ($isSmtp && $tenantRestricted && SmtpHostGuard::isForbidden((string) $data['host'])) {
            throw ValidationException::withMessages([
                'host' => 'Bu sunucu adresi kullanılamaz: yerel/iç ağ adreslerine izin verilmez.',
            ]);
        }

        $data['timeout'] = $data['timeout'] ?? 30;

        return $data;
    }

    /**
     * Denetim kaydına yazılacak GÜVENLİ alanlar; parolanın kendisi asla
     * yazılmaz, yalnız tanımlı olup olmadığı yazılır.
     *
     * @return array<string, mixed>|null
     */
    private function auditable(?MailSetting $setting): ?array
    {
        if ($setting === null) {
            return null;
        }

        return [
            'mailer' => $setting->mailer,
            'host' => $setting->host,
            'port' => $setting->port,
            'encryption' => $setting->encryption,
            'username' => $setting->username,
            'from_name' => $setting->from_name,
            'from_address' => $setting->from_address,
            'reply_to' => $setting->reply_to,
            'timeout' => $setting->timeout,
            'password_set' => $setting->has_password,
        ];
    }
}
