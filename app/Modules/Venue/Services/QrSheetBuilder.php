<?php

namespace App\Modules\Venue\Services;

use Dompdf\Dompdf;
use Dompdf\Options;

/**
 * A4 toplu QR baskı PDF'i — sunucuda üretilir (dış servis yok).
 *
 * Kütüphane gerekçesi: dompdf/dompdf saf PHP'dir (GD yeterli, Imagick
 * gerekmez), HTML/CSS'ten A4 sayfa düzeni kurar ve data-URI PNG gömer;
 * Türkçe karakterler için DejaVu fontları pakete gömülüdür.
 *
 * Kesim payı: her kart hücresinde 4&nbsp;mm pay + kesikli kesim çizgisi.
 */
class QrSheetBuilder
{
    /**
     * @param  array<int, array{png: string, label: string}>  $cards  png = ham PNG içeriği
     */
    public function build(array $cards, string $title): string
    {
        $cells = '';

        foreach ($cards as $card) {
            $cells .= sprintf(
                '<div class="cell"><div class="cut"><img src="data:image/png;base64,%s" alt="%s"></div></div>',
                base64_encode($card['png']),
                htmlspecialchars($card['label'], ENT_QUOTES),
            );
        }

        $html = <<<HTML
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8">
<style>
    @page { size: A4 portrait; margin: 8mm; }
    body { font-family: DejaVu Sans, sans-serif; margin: 0; }
    .sheet-title { font-size: 9px; color: #666; margin: 0 0 3mm 0; }
    .grid { width: 100%; }
    .cell {
        display: inline-block;
        width: 49%;
        vertical-align: top;
        text-align: center;
        padding: 2mm 0;
    }
    /* Kesim payı: kesikli çizgi kesim hattıdır; içindeki 4mm dolgu paydır */
    .cut {
        display: inline-block;
        border: 0.3mm dashed #9aa0a6;
        padding: 4mm;
    }
    .cut img { width: 78mm; height: auto; display: block; }
</style>
</head>
<body>
<p class="sheet-title">{$this->e($title)} — kesikli çizgiler kesim hattıdır (4 mm pay bırakılmıştır)</p>
<div class="grid">{$cells}</div>
</body>
</html>
HTML;

        $options = new Options;
        $options->set('isRemoteEnabled', false);   // dışarıya istek YASAK
        $options->set('isPhpEnabled', false);
        $options->set('defaultFont', 'DejaVu Sans');

        $dompdf = new Dompdf($options);
        $dompdf->loadHtml($html, 'UTF-8');
        $dompdf->setPaper('A4', 'portrait');
        $dompdf->render();

        return (string) $dompdf->output();
    }

    private function e(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES);
    }
}
