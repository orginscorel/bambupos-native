<?php

namespace App\Modules\Catalog\Services;

use App\Modules\Catalog\Models\Product;
use App\Modules\Catalog\Models\ProductImage;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Güvenli ürün görseli yükleme (prompt §26.3):
 *  - uzantı + bildirilen MIME + GERÇEK içerik (finfo + getimagesize) doğrulaması
 *  - dosya adı istemciden ASLA alınmaz → rastgele ad, uzantı MIME'den türetilir
 *  - kiracı-izolasyonlu yol: tenants/{tenant}/products/{product}/
 *  - yükleme dizininde script çalıştırma kapalı (.htaccess, bir kez yazılır)
 *  - boyut sınırı ve ürün başına adet sınırı
 */
class ProductImageService
{
    public const MAX_BYTES = 4 * 1024 * 1024; // 4 MB

    public const MAX_PER_PRODUCT = 8;

    /** İzinli gerçek MIME → saklama uzantısı. Başka her şey reddedilir. */
    private const MIME_EXTENSIONS = [
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
    ];

    public function store(Product $product, UploadedFile $file): ProductImage
    {
        $this->assertValidImage($file);

        if ($product->images()->count() >= self::MAX_PER_PRODUCT) {
            throw ValidationException::withMessages([
                'image' => ['Bir ürüne en fazla '.self::MAX_PER_PRODUCT.' görsel eklenebilir.'],
            ]);
        }

        $realMime = $this->realMime($file);
        $extension = self::MIME_EXTENSIONS[$realMime];

        $directory = sprintf('tenants/%d/products/%d', (int) $product->tenant_id, (int) $product->id);
        $filename = Str::lower(Str::random(40)).'.'.$extension; // rastgele ad; istemci adı yalnız etiket

        $this->ensureNoScriptExecution();

        $path = $file->storeAs($directory, $filename, ['disk' => 'public']);

        if ($path === false) {
            throw ValidationException::withMessages(['image' => ['Görsel kaydedilemedi.']]);
        }

        $isFirst = $product->images()->count() === 0;

        return $product->images()->create([
            'path' => $path,
            'original_name' => Str::limit($file->getClientOriginalName(), 140, ''),
            'mime' => $realMime,
            'size' => (int) $file->getSize(),
            'is_primary' => $isFirst,
            'sort_order' => ($product->images()->max('sort_order') ?? 0) + 10,
        ]);
    }

    public function delete(ProductImage $image): void
    {
        Storage::disk('public')->delete($image->path);

        $wasPrimary = $image->is_primary;
        $productId = $image->product_id;
        $image->delete();

        if ($wasPrimary) {
            // Kapak silindiyse sıradaki görseli kapak yap
            ProductImage::query()
                ->where('product_id', $productId)
                ->orderBy('sort_order')
                ->first()?->update(['is_primary' => true]);
        }
    }

    public function makePrimary(ProductImage $image): void
    {
        ProductImage::query()
            ->where('product_id', $image->product_id)
            ->where('id', '!=', $image->id)
            ->update(['is_primary' => false]);

        $image->update(['is_primary' => true]);
    }

    /** Katmanlı doğrulama; herhangi biri düşerse 422. */
    private function assertValidImage(UploadedFile $file): void
    {
        $fail = function (string $message): never {
            throw ValidationException::withMessages(['image' => [$message]]);
        };

        if (! $file->isValid()) {
            $fail('Dosya yüklenemedi, lütfen tekrar deneyin.');
        }

        if ($file->getSize() > self::MAX_BYTES) {
            $fail('Görsel en fazla 4 MB olabilir.');
        }

        // 1) Uzantı beyaz listesi (istemci adından)
        $clientExt = Str::lower($file->getClientOriginalExtension());
        if (! in_array($clientExt, ['jpg', 'jpeg', 'png', 'webp'], true)) {
            $fail('Yalnız JPG, PNG veya WebP görsel yüklenebilir.');
        }

        // 2) Gerçek içerik MIME'i (finfo — istemci beyanına güvenilmez)
        $realMime = $this->realMime($file);
        if (! array_key_exists($realMime, self::MIME_EXTENSIONS)) {
            $fail('Dosya içeriği geçerli bir görsel değil.');
        }

        // 3) Görsel olarak açılabiliyor mu (içine gömülü script'li sahte dosyaları eler)
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

    /**
     * `storage/app/public/tenants/.htaccess`: bu ağaçta PHP/CGI çalıştırma kapalı.
     * (Dosya adları zaten rastgele + uzantı beyaz listeli; bu derinlemesine savunma.)
     */
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
