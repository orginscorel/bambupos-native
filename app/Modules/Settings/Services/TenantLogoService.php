<?php

namespace App\Modules\Settings\Services;

use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Güvenli işletme (kiracı) logosu yükleme — ProductImageService ile
 * birebir aynı güvenlik katmanları (§26.3):
 *  - uzantı + bildirilen MIME + GERÇEK içerik (finfo + getimagesize)
 *  - dosya adı istemciden ASLA alınmaz → rastgele ad, uzantı MIME'den
 *  - kiracı-izolasyonlu yol: tenants/{tenant}/branding/
 *  - yükleme ağacında script çalıştırma kapalı (tenants/.htaccess)
 *  - boyut sınırı; eski logo dosyası değişimde silinir (çöp birikmez)
 *
 * Rastgele dosya adı aynı zamanda doğal cache-buster'dır: her yeni logo
 * yeni bir URL alır, tarayıcı/Cloudflare eski dosyayı sunamaz.
 */
class TenantLogoService
{
    public const MAX_BYTES = 2 * 1024 * 1024; // 2 MB — logo için fazlasıyla yeterli

    /** İzinli gerçek MIME → saklama uzantısı. Başka her şey reddedilir (SVG bilinçli yok: script taşıyabilir). */
    private const MIME_EXTENSIONS = [
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
    ];

    public function store(Tenant $tenant, UploadedFile $file): string
    {
        $this->assertValidImage($file);

        $realMime = $this->realMime($file);
        $extension = self::MIME_EXTENSIONS[$realMime];

        $directory = sprintf('tenants/%d/branding', (int) $tenant->getKey());
        $filename = Str::lower(Str::random(40)).'.'.$extension;

        $this->ensureNoScriptExecution();

        $path = $file->storeAs($directory, $filename, ['disk' => 'public']);

        if ($path === false) {
            throw ValidationException::withMessages(['logo' => ['Logo kaydedilemedi.']]);
        }

        $this->deleteFile($tenant->logo_path);
        $tenant->forceFill(['logo_path' => $path])->save();

        return $path;
    }

    public function delete(Tenant $tenant): void
    {
        $this->deleteFile($tenant->logo_path);
        $tenant->forceFill(['logo_path' => null])->save();
    }

    private function deleteFile(?string $path): void
    {
        if ($path !== null && $path !== '') {
            Storage::disk('public')->delete($path);
        }
    }

    /** Katmanlı doğrulama; herhangi biri düşerse 422. */
    private function assertValidImage(UploadedFile $file): void
    {
        $fail = function (string $message): never {
            throw ValidationException::withMessages(['logo' => [$message]]);
        };

        if (! $file->isValid()) {
            $fail('Dosya yüklenemedi, lütfen tekrar deneyin.');
        }

        if ($file->getSize() > self::MAX_BYTES) {
            $fail('Logo en fazla 2 MB olabilir.');
        }

        // 1) Uzantı beyaz listesi (istemci adından)
        $clientExt = Str::lower($file->getClientOriginalExtension());
        if (! in_array($clientExt, ['jpg', 'jpeg', 'png', 'webp'], true)) {
            $fail('Yalnız JPG, PNG veya WebP logo yüklenebilir.');
        }

        // 2) Gerçek içerik MIME'i (finfo — istemci beyanına güvenilmez)
        $realMime = $this->realMime($file);
        if (! array_key_exists($realMime, self::MIME_EXTENSIONS)) {
            $fail('Dosya içeriği geçerli bir görsel değil.');
        }

        // 3) Görsel olarak açılabiliyor mu (gömülü script'li sahte dosyaları eler)
        if (@getimagesize($file->getRealPath()) === false) {
            $fail('Dosya içeriği geçerli bir görsel değil.');
        }
    }

    private function realMime(UploadedFile $file): string
    {
        $finfo = finfo_open(FILEINFO_MIME_TYPE);

        try {
            return (string) finfo_file($finfo, $file->getRealPath());
        } finally {
            finfo_close($finfo);
        }
    }

    /** Katalog medya ağacıyla aynı derinlemesine savunma (bir kez yazılır). */
    private function ensureNoScriptExecution(): void
    {
        $disk = Storage::disk('public');

        if ($disk->exists('tenants/.htaccess')) {
            return;
        }

        $disk->put('tenants/.htaccess', implode("\n", [
            '# Katalog medya ağacı: script çalıştırma kapalı (derinlemesine savunma)',
            '<FilesMatch "\.(?i:php|phtml|php[0-9]|pht|phar|cgi|pl|py|sh|shtml)$">',
            '    Require all denied',
            '</FilesMatch>',
            'RemoveHandler .php .phtml .phar .pht .cgi .pl .py',
            'RemoveType .php .phtml .phar',
            'Options -ExecCGI -Indexes',
            '',
        ]));
    }
}
