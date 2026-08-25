<?php

namespace App\Modules\Venue\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Venue\Models\Area;
use App\Modules\Venue\Models\QrSetting;
use App\Modules\Venue\Services\QrCardRenderer;
use App\Modules\Venue\Services\QrSheetBuilder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * QR yönetimi: şablon ayarları, önizleme/indirme (PNG+SVG), A4 toplu
 * baskı PDF'i ve rotasyon (tekil + toplu). Üretim tamamen sunucuda
 * (dış servise veri gitmez — ADR-008 / KVKK).
 */
class QrController extends Controller
{
    public function __construct(
        private readonly QrCardRenderer $renderer,
        private readonly QrSheetBuilder $sheet,
    ) {
    }

    /* ================= Şablon ayarları ================= */

    public function settings(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Table::class);

        return response()->json(['settings' => $this->presentSettings()]);
    }

    public function updateSettings(Request $request): JsonResponse
    {
        $this->authorize('create', Table::class); // tables.create: QR şablonu masa yönetiminin parçası

        $data = $request->validate([
            'header_text' => ['nullable', 'string', 'max:100'],
            'description' => ['nullable', 'string', 'max:160'],
            'color' => ['sometimes', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'bg_color' => ['sometimes', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'frame' => ['sometimes', 'in:none,simple,rounded'],
            'show_table_no' => ['sometimes', 'boolean'],
        ]);

        // Kontrast uyarısı: QR okunabilirliği için desen/zemin ayrımı şart.
        $color = $data['color'] ?? null;
        $bg = $data['bg_color'] ?? null;

        if ($color !== null && $bg !== null && strcasecmp($color, $bg) === 0) {
            throw ValidationException::withMessages(['color' => ['Desen rengi ile arka plan aynı olamaz; QR okunamaz.']]);
        }

        $settings = QrSetting::query()->first();

        if ($settings === null) {
            $settings = new QrSetting;
        }

        $settings->fill($data);
        $settings->save();

        return response()->json(['settings' => $this->presentSettings()]);
    }

    public function uploadLogo(Request $request): JsonResponse
    {
        $this->authorize('create', Table::class);

        $request->validate([
            'logo' => ['required', 'file', 'image', 'mimes:png,jpg,jpeg,webp', 'max:2048'],
        ]);

        $file = $request->file('logo');

        // İçerik doğrulaması: uzantıya değil gerçek içeriğe bakılır.
        $mime = (string) finfo_file(finfo_open(FILEINFO_MIME_TYPE), $file->getRealPath());

        if (! in_array($mime, ['image/png', 'image/jpeg', 'image/webp'], true)) {
            throw ValidationException::withMessages(['logo' => ['Geçersiz görsel içeriği.']]);
        }

        $tenantId = (int) $request->user()->tenant_id;
        $path = "venue-logos/{$tenantId}.png";

        // GD ile 256px'e küçültüp PNG olarak normalize et (EXIF/payload temizliği).
        $src = match ($mime) {
            'image/png' => imagecreatefrompng($file->getRealPath()),
            'image/jpeg' => imagecreatefromjpeg($file->getRealPath()),
            'image/webp' => imagecreatefromwebp($file->getRealPath()),
        };

        if ($src === false) {
            throw ValidationException::withMessages(['logo' => ['Görsel işlenemedi.']]);
        }

        $size = 256;
        $dst = imagecreatetruecolor($size, $size);
        imagealphablending($dst, false);
        imagesavealpha($dst, true);
        imagefill($dst, 0, 0, (int) imagecolorallocatealpha($dst, 255, 255, 255, 127));
        imagealphablending($dst, true);

        $srcW = imagesx($src);
        $srcH = imagesy($src);
        $scale = min($size / $srcW, $size / $srcH);
        $w = (int) ($srcW * $scale);
        $h = (int) ($srcH * $scale);
        imagecopyresampled($dst, $src, (int) (($size - $w) / 2), (int) (($size - $h) / 2), 0, 0, $w, $h, $srcW, $srcH);

        ob_start();
        imagepng($dst);
        $png = (string) ob_get_clean();
        imagedestroy($src);
        imagedestroy($dst);

        Storage::disk('local')->put($path, $png);

        $settings = QrSetting::query()->first() ?? new QrSetting;
        $settings->logo_path = $path;
        $settings->save();

        return response()->json(['settings' => $this->presentSettings()]);
    }

    public function deleteLogo(Request $request): JsonResponse
    {
        $this->authorize('create', Table::class);

        $settings = QrSetting::query()->first();

        if ($settings?->logo_path !== null) {
            Storage::disk('local')->delete($settings->logo_path);
            $settings->logo_path = null;
            $settings->save();
        }

        return response()->json(['settings' => $this->presentSettings()]);
    }

    /* ================= Görsel çıktılar ================= */

    /** Tek masa QR kartı — PNG veya SVG (?format=svg), ?download=1 ile indirme. */
    public function tableImage(Request $request, Table $table): Response
    {
        $this->authorize('view', $table);

        [$header, $description, $design] = $this->designFor($request);
        $label = $this->tableLabel($table);

        return $this->imageResponse(
            $request,
            $table->menuUrl(),
            $header,
            $label,
            $description,
            $design,
            'qr-masa-'.($table->number ?? $table->id),
        );
    }

    /** Şube genel menü QR kartı (masasız: paket servis, ayakta menü). */
    public function branchImage(Request $request, Branch $branch): Response
    {
        $this->authorize('view', $branch);

        $token = $this->ensureBranchToken($branch);
        [$header, $description, $design] = $this->designFor($request);

        return $this->imageResponse(
            $request,
            $this->menuUrlFor($token),
            $header,
            'Genel Menü',
            $description,
            $design,
            'qr-genel-menu-'.$branch->id,
        );
    }

    /**
     * A4 toplu baskı PDF'i (kesim payıyla): masa seçimi table_ids ile,
     * ya da branch_id (+area_id) kapsamındaki tüm aktif masalar.
     * include_general=1 → şube genel menü kartı da eklenir.
     */
    public function sheet(Request $request): Response
    {
        $this->authorize('viewAny', Table::class);

        $data = $request->validate([
            'branch_id' => ['nullable', 'integer'],
            'area_id' => ['nullable', 'integer'],
            'table_ids' => ['nullable', 'array', 'max:200'],
            'table_ids.*' => ['integer'],
            'include_general' => ['sometimes', 'boolean'],
        ]);

        $query = Table::query()->where('is_active', true)->orderBy('number')->orderBy('name');

        if (! empty($data['table_ids'])) {
            $query->whereIn('id', $data['table_ids']);
        } else {
            if (empty($data['branch_id'])) {
                throw ValidationException::withMessages(['branch_id' => ['Şube veya masa seçimi gereklidir.']]);
            }

            $query->where('branch_id', (int) $data['branch_id']);

            if (! empty($data['area_id'])) {
                $query->where('area_id', (int) $data['area_id']);
            }
        }

        $tables = $query->limit(200)->get();

        if ($tables->isEmpty() && ! $request->boolean('include_general')) {
            throw ValidationException::withMessages(['table_ids' => ['Seçime uyan masa bulunamadı.']]);
        }

        [$header, $description, $design] = $this->designFor($request);

        $cards = [];

        if ($request->boolean('include_general') && ! empty($data['branch_id'])) {
            $branch = Branch::query()->find((int) $data['branch_id']);

            if ($branch !== null) {
                $cards[] = [
                    'png' => $this->renderer->png($this->menuUrlFor($this->ensureBranchToken($branch)), $header, 'Genel Menü', $description, $design),
                    'label' => 'Genel Menü',
                ];
            }
        }

        foreach ($tables as $table) {
            $cards[] = [
                'png' => $this->renderer->png($table->menuUrl(), $header, $this->tableLabel($table), $description, $design),
                'label' => $this->tableLabel($table),
            ];
        }

        $pdf = $this->sheet->build($cards, $header.' — QR kartları');

        return response($pdf, 200, [
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'attachment; filename="qr-kartlari-a4.pdf"',
        ]);
    }

    /* ================= Rotasyon (ADR-008) ================= */

    public function rotateTable(Request $request, Table $table): JsonResponse
    {
        $this->authorize('update', $table);

        $table->rotateQrToken();

        return response()->json([
            'ok' => true,
            'menu_url' => $table->fresh()->menuUrl(),
        ]);
    }

    public function rotateBranch(Request $request, Branch $branch): JsonResponse
    {
        $this->authorize('update', $branch);

        $branch->previous_qr_token = $branch->qr_token;
        $branch->qr_token = Table::generateQrToken();
        $branch->save();

        return response()->json(['ok' => true, 'menu_url' => $this->menuUrlFor((string) $branch->qr_token)]);
    }

    /** Toplu rotasyon: seçili masalar ya da şube (+alan) kapsamı. */
    public function rotateBulk(Request $request): JsonResponse
    {
        $data = $request->validate([
            'table_ids' => ['nullable', 'array', 'max:500'],
            'table_ids.*' => ['integer'],
            'branch_id' => ['nullable', 'integer'],
            'area_id' => ['nullable', 'integer'],
        ]);

        $query = Table::query();

        if (! empty($data['table_ids'])) {
            $query->whereIn('id', $data['table_ids']);
        } elseif (! empty($data['branch_id'])) {
            $query->where('branch_id', (int) $data['branch_id']);

            if (! empty($data['area_id'])) {
                $query->where('area_id', (int) $data['area_id']);
            }
        } else {
            throw ValidationException::withMessages(['table_ids' => ['Masa seçimi veya şube kapsamı gereklidir.']]);
        }

        $tables = $query->get();

        foreach ($tables as $table) {
            $this->authorize('update', $table);
        }

        foreach ($tables as $table) {
            $table->rotateQrToken();
        }

        return response()->json(['rotated' => $tables->count()]);
    }

    /* ================= Yardımcılar ================= */

    /** @return array{settings: array<string, mixed>} */
    private function presentSettings(): array
    {
        $settings = QrSetting::forCurrentTenant();

        return [
            'header_text' => $settings->header_text,
            'description' => $settings->description,
            'color' => $settings->color ?? '#111111',
            'bg_color' => $settings->bg_color ?? '#FFFFFF',
            'frame' => $settings->frame ?? 'simple',
            'show_table_no' => $settings->show_table_no ?? true,
            'has_logo' => $settings->logo_path !== null,
        ];
    }

    /** @return array{0: string, 1: string, 2: array{color: string, bg_color: string, frame: string, logo_path: ?string}} */
    private function designFor(Request $request): array
    {
        $settings = QrSetting::forCurrentTenant();
        $tenant = $request->user()->tenant;

        $logoAbsolute = null;

        if ($settings->logo_path !== null && Storage::disk('local')->exists($settings->logo_path)) {
            $logoAbsolute = Storage::disk('local')->path($settings->logo_path);
        }

        // CANLI ÖNİZLEME: ?preview=1 iken kaydedilmemiş şablon değerleri query'den
        // gelir → tasarımcı kaydetmeden anında görür. YALNIZ görüntü; kayıt değişmez.
        // İndirme/baskı yolunda (preview yok) DAİMA kayıtlı ayar kullanılır.
        $preview = $request->boolean('preview');
        $hex = static fn (?string $v): ?string => is_string($v) && preg_match('/^#[0-9A-Fa-f]{6}$/', $v) ? $v : null;

        $color = ($preview ? $hex($request->query('color')) : null) ?? $settings->color ?? '#111111';
        $bg = ($preview ? $hex($request->query('bg_color')) : null) ?? $settings->bg_color ?? '#FFFFFF';
        $frame = $preview && in_array($request->query('frame'), ['none', 'simple', 'rounded'], true)
            ? (string) $request->query('frame')
            : ($settings->frame ?? 'simple');
        $header = $preview && $request->filled('header')
            ? mb_substr((string) $request->query('header'), 0, 60)
            : ($settings->header_text ?: (string) ($tenant?->name ?? 'Menü'));
        $description = $preview && $request->has('description')
            ? mb_substr((string) $request->query('description'), 0, 120)
            : ($settings->description ?? 'Menü için QR kodu okutun');

        return [
            $header,
            $description,
            [
                'color' => $color,
                'bg_color' => $bg,
                'frame' => $frame,
                'logo_path' => $logoAbsolute,
            ],
        ];
    }

    private function tableLabel(Table $table): string
    {
        $settings = QrSetting::forCurrentTenant();
        $showNo = $settings->show_table_no ?? true;

        if ($showNo && $table->number !== null) {
            return $table->name.' · No '.$table->number;
        }

        return $table->name;
    }

    /**
     * @param  array{color: string, bg_color: string, frame: string, logo_path: ?string}  $design
     */
    private function imageResponse(Request $request, string $url, string $header, string $label, string $description, array $design, string $filename): Response
    {
        $format = $request->query('format', 'png') === 'svg' ? 'svg' : 'png';

        $body = $format === 'svg'
            ? $this->renderer->svg($url, $header, $label, $description, $design)
            : $this->renderer->png($url, $header, $label, $description, $design);

        $headers = [
            'Content-Type' => $format === 'svg' ? 'image/svg+xml' : 'image/png',
            'Cache-Control' => 'no-store', // token içerir; ara önbelleklere yazılmasın
        ];

        if ($request->boolean('download')) {
            $headers['Content-Disposition'] = sprintf('attachment; filename="%s.%s"', $filename, $format);
        }

        return response($body, 200, $headers);
    }

    /** Şube genel menü token'ı yoksa üret (ADR-008 kurallarıyla). */
    private function ensureBranchToken(Branch $branch): string
    {
        if ($branch->qr_token === null) {
            $branch->qr_token = Table::generateQrToken();
            $branch->save();
        }

        return (string) $branch->qr_token;
    }

    private function menuUrlFor(string $token): string
    {
        return rtrim((string) config('app.url'), '/').'/m/'.$token;
    }
}
