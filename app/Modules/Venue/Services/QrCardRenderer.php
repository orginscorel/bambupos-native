<?php

namespace App\Modules\Venue\Services;

use chillerlan\QRCode\Common\EccLevel;
use chillerlan\QRCode\QRCode;
use chillerlan\QRCode\QROptions;
use RuntimeException;

/**
 * QR kart üretimi — TAMAMEN SUNUCUDA (dış servise hiçbir veri gitmez).
 *
 * Kütüphane gerekçesi (rapor için de geçerli):
 * - chillerlan/php-qrcode: saf PHP QR kodlayıcı; sunucudaki GD ile PNG,
 *   eklentisiz SVG üretir (Imagick yok, bu yüzden bacon-qr-code'un raster
 *   çıktısı kullanılamazdı). Matris API'si açık olduğundan kartı (renk,
 *   çerçeve, logo, metin) kendimiz çiziyoruz.
 * - Logo bindirme için hata düzeltme seviyesi H (%30) kullanılır.
 *
 * Kart düzeni (640×820 birim): çerçeve + başlık (işletme adı) + QR +
 * masa no/adı + açıklama.
 */
class QrCardRenderer
{
    public const CARD_W = 640;

    public const CARD_H = 820;

    private const QR_SIZE = 480;

    private const QR_X = 80;

    private const QR_Y = 150;

    private const FONT_REGULAR = '/usr/share/fonts/dejavu/DejaVuSans.ttf';

    private const FONT_BOLD = '/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf';

    /**
     * @param  array{color: string, bg_color: string, frame: string, logo_path: ?string}  $design
     */
    public function png(string $url, string $header, string $tableLabel, string $description, array $design): string
    {
        $matrix = $this->matrix($url, $design['logo_path'] !== null);
        $size = count($matrix);

        $img = imagecreatetruecolor(self::CARD_W, self::CARD_H);

        [$fr, $fg, $fb] = $this->rgb($design['color']);
        [$br, $bg2, $bb] = $this->rgb($design['bg_color']);

        $fgCol = imagecolorallocate($img, $fr, $fg, $fb);
        $bgCol = imagecolorallocate($img, $br, $bg2, $bb);

        imagefilledrectangle($img, 0, 0, self::CARD_W, self::CARD_H, $bgCol);

        // Çerçeve
        if ($design['frame'] !== 'none') {
            imagesetthickness($img, 4);
            imagerectangle($img, 8, 8, self::CARD_W - 9, self::CARD_H - 9, $fgCol);

            if ($design['frame'] === 'rounded') {
                // Köşe yumuşatma imâsı: iç ikinci ince çizgi
                imagesetthickness($img, 1);
                imagerectangle($img, 14, 14, self::CARD_W - 15, self::CARD_H - 15, $fgCol);
            }

            imagesetthickness($img, 1);
        }

        // Başlık (işletme adı / şablon başlığı)
        $this->gdTextCentered($img, $header, 30, 88, $fgCol, self::FONT_BOLD);

        // QR modülleri
        $module = self::QR_SIZE / $size;

        for ($y = 0; $y < $size; $y++) {
            for ($x = 0; $x < $size; $x++) {
                if ($matrix[$y][$x]) {
                    imagefilledrectangle(
                        $img,
                        (int) floor(self::QR_X + $x * $module),
                        (int) floor(self::QR_Y + $y * $module),
                        (int) ceil(self::QR_X + ($x + 1) * $module) - 1,
                        (int) ceil(self::QR_Y + ($y + 1) * $module) - 1,
                        $fgCol,
                    );
                }
            }
        }

        // Logo (merkez, beyaz yastıklı)
        if ($design['logo_path'] !== null && is_file($design['logo_path'])) {
            $this->gdOverlayLogo($img, $design['logo_path'], $bgCol);
        }

        // Masa no / adı
        if ($tableLabel !== '') {
            $this->gdTextCentered($img, $tableLabel, 34, self::QR_Y + self::QR_SIZE + 78, $fgCol, self::FONT_BOLD);
        }

        // Açıklama
        if ($description !== '') {
            $this->gdTextCentered($img, $description, 17, self::QR_Y + self::QR_SIZE + ($tableLabel !== '' ? 128 : 90), $fgCol, self::FONT_REGULAR);
        }

        ob_start();
        imagepng($img);
        imagedestroy($img);

        return (string) ob_get_clean();
    }

    /**
     * @param  array{color: string, bg_color: string, frame: string, logo_path: ?string}  $design
     */
    public function svg(string $url, string $header, string $tableLabel, string $description, array $design): string
    {
        $matrix = $this->matrix($url, $design['logo_path'] !== null);
        $size = count($matrix);
        $scale = self::QR_SIZE / $size;

        $fg = htmlspecialchars($design['color'], ENT_QUOTES);
        $bg = htmlspecialchars($design['bg_color'], ENT_QUOTES);
        $w = self::CARD_W;
        $h = self::CARD_H;

        $path = '';

        for ($y = 0; $y < $size; $y++) {
            $x = 0;
            while ($x < $size) {
                if (! $matrix[$y][$x]) {
                    $x++;

                    continue;
                }
                // Yatay ardışık modülleri tek dikdörtgende birleştir (küçük dosya)
                $run = 0;
                while ($x + $run < $size && $matrix[$y][$x + $run]) {
                    $run++;
                }
                $path .= sprintf('M%d %dh%dv1h-%dz', $x, $y, $run, $run);
                $x += $run;
            }
        }

        $frameSvg = '';

        if ($design['frame'] !== 'none') {
            $radius = $design['frame'] === 'rounded' ? 24 : 0;
            $frameSvg = sprintf(
                '<rect x="10" y="10" width="%d" height="%d" rx="%d" fill="none" stroke="%s" stroke-width="4"/>',
                $w - 20, $h - 20, $radius, $fg,
            );
        }

        $logoSvg = '';

        if ($design['logo_path'] !== null && is_file($design['logo_path'])) {
            $mime = mime_content_type($design['logo_path']) ?: 'image/png';
            $data = base64_encode((string) file_get_contents($design['logo_path']));
            $pad = 12;
            $logoSize = 104;
            $lx = self::QR_X + (self::QR_SIZE - $logoSize) / 2;
            $ly = self::QR_Y + (self::QR_SIZE - $logoSize) / 2;
            $logoSvg = sprintf(
                '<rect x="%d" y="%d" width="%d" height="%d" rx="14" fill="%s"/>'
                .'<image x="%d" y="%d" width="%d" height="%d" href="data:%s;base64,%s" preserveAspectRatio="xMidYMid meet"/>',
                $lx - $pad, $ly - $pad, $logoSize + 2 * $pad, $logoSize + 2 * $pad, $bg,
                $lx, $ly, $logoSize, $logoSize, $mime, $data,
            );
        }

        $texts = sprintf(
            '<text x="%d" y="96" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="34" font-weight="bold" fill="%s">%s</text>',
            $w / 2, $fg, htmlspecialchars($header, ENT_QUOTES),
        );

        if ($tableLabel !== '') {
            $texts .= sprintf(
                '<text x="%d" y="%d" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="40" font-weight="bold" fill="%s">%s</text>',
                $w / 2, self::QR_Y + self::QR_SIZE + 86, $fg, htmlspecialchars($tableLabel, ENT_QUOTES),
            );
        }

        if ($description !== '') {
            $texts .= sprintf(
                '<text x="%d" y="%d" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="20" fill="%s">%s</text>',
                $w / 2, self::QR_Y + self::QR_SIZE + ($tableLabel !== '' ? 134 : 96), $fg, htmlspecialchars($description, ENT_QUOTES),
            );
        }

        return sprintf(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">'
            .'<rect width="%d" height="%d" fill="%s"/>%s'
            .'<path transform="translate(%d %d) scale(%.4F)" d="%s" fill="%s"/>%s%s</svg>',
            $w, $h, $w, $h,
            $w, $h, $bg, $frameSvg,
            self::QR_X, self::QR_Y, $scale, $path, $fg,
            $logoSvg, $texts,
        );
    }

    /**
     * @return array<int, array<int, bool>> kenar boşluklu boolean matris
     */
    private function matrix(string $url, bool $withLogo): array
    {
        $options = new QROptions([
            'eccLevel' => $withLogo ? EccLevel::H : EccLevel::Q,
            'addQuietzone' => false, // kart düzeni kendi boşluğunu bırakır
        ]);

        $qr = (new QRCode($options))->addByteSegment($url);

        /** @var array<int, array<int, bool>> $matrix */
        $matrix = $qr->getQRMatrix()->getMatrix(true);

        if ($matrix === []) {
            throw new RuntimeException('QR matrisi üretilemedi.');
        }

        return $matrix;
    }

    /** @return array{0: int, 1: int, 2: int} */
    private function rgb(string $hex): array
    {
        $hex = ltrim($hex, '#');

        if (strlen($hex) !== 6 || preg_match('/^[0-9a-fA-F]{6}$/', $hex) !== 1) {
            $hex = '111111';
        }

        return [
            (int) hexdec(substr($hex, 0, 2)),
            (int) hexdec(substr($hex, 2, 2)),
            (int) hexdec(substr($hex, 4, 2)),
        ];
    }

    /** @param resource|\GdImage $img */
    private function gdTextCentered($img, string $text, int $fontSize, int $baselineY, int $color, string $font): void
    {
        if ($text === '') {
            return;
        }

        if (! is_file($font)) {
            // TTF yoksa (beklenmiyor) ASCII yaklaşık merkezleme ile devam
            $ascii = (string) iconv('UTF-8', 'ASCII//TRANSLIT', $text) ?: $text;
            imagestring($img, 5, (int) ((self::CARD_W - strlen($ascii) * 9) / 2), $baselineY - 14, $ascii, $color);

            return;
        }

        // Sığmayan başlıkları kısalt
        while ($text !== '') {
            $box = imagettfbbox($fontSize, 0, $font, $text);
            $width = abs($box[2] - $box[0]);

            if ($width <= self::CARD_W - 80) {
                break;
            }

            $text = mb_substr($text, 0, mb_strlen($text) - 2).'…';
        }

        $box = imagettfbbox($fontSize, 0, $font, $text);
        $width = abs($box[2] - $box[0]);

        imagettftext($img, $fontSize, 0, (int) ((self::CARD_W - $width) / 2), $baselineY, $color, $font, $text);
    }

    /** @param resource|\GdImage $img */
    private function gdOverlayLogo($img, string $logoPath, int $padColor): void
    {
        $info = getimagesize($logoPath);

        if ($info === false) {
            return;
        }

        $logo = match ($info['mime']) {
            'image/png' => imagecreatefrompng($logoPath),
            'image/jpeg' => imagecreatefromjpeg($logoPath),
            'image/webp' => imagecreatefromwebp($logoPath),
            'image/gif' => imagecreatefromgif($logoPath),
            default => false,
        };

        if ($logo === false) {
            return;
        }

        $logoSize = 104;
        $pad = 12;
        $lx = (int) (self::QR_X + (self::QR_SIZE - $logoSize) / 2);
        $ly = (int) (self::QR_Y + (self::QR_SIZE - $logoSize) / 2);

        imagefilledrectangle($img, $lx - $pad, $ly - $pad, $lx + $logoSize + $pad, $ly + $logoSize + $pad, $padColor);
        imagecopyresampled($img, $logo, $lx, $ly, 0, 0, $logoSize, $logoSize, imagesx($logo), imagesy($logo));
        imagedestroy($logo);
    }
}
