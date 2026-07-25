<?php

namespace App\Modules\Reports\Support;

use App\Modules\Catalog\Support\Money;

/**
 * Rapor verisini tabloya normalize eder ve CSV / XLSX / PDF yazar.
 *
 * - CSV: UTF-8 BOM + noktalı virgül (TR Excel varsayılanı sorunsuz açar).
 * - XLSX: dış paket YOK — ZipArchive ile asgari geçerli SpreadsheetML
 *   (inline string + number hücreleri). Amaç bağımlılık şişirmeden
 *   "Excel'de açılır" dosya üretmek.
 * - PDF: dompdf (pakette zaten var) basit tablo görünümü; satır tavanı
 *   config('reports.pdf_row_limit') — aşarsa dosyada açıkça belirtilir.
 */
final class ExportBuilder
{
    /**
     * Rapor çıktısını [headers, rows] tablosuna çevirir.
     * '*_minor' kolonları TL ondalık dizesine dönüştürülür.
     *
     * @return array{0: array<int, string>, 1: array<int, array<int, string|int|float|null>>}
     */
    public static function tabulate(string $reportKey, array $data): array
    {
        $def = ReportRegistry::get($reportKey);

        // Özet raporları (rows tanımsız): anahtar/değer tablosu.
        if ($def['rows'] === '') {
            $flat = self::flatten($data);
            $rows = [];
            foreach ($flat as $k => $v) {
                $rows[] = [$k, self::formatValue($k, $v)];
            }

            return [['Alan', 'Değer'], $rows];
        }

        $headers = array_values($def['columns']);
        $fields = array_keys($def['columns']);
        $list = (array) ($data[$def['rows']] ?? []);

        $limit = (int) config('reports.export_row_limit', 100000);
        $rows = [];

        foreach ($list as $item) {
            $row = [];
            foreach ($fields as $field) {
                $row[] = self::formatValue($field, $item[$field] ?? null);
            }
            $rows[] = $row;
            if (count($rows) >= $limit) {
                break;
            }
        }

        return [$headers, $rows];
    }

    private static function formatValue(string $field, mixed $value): string|int|float|null
    {
        if ($value === null) {
            return null;
        }

        if (str_ends_with($field, '_minor') && is_numeric($value)) {
            return Money::toDecimalString((int) $value);
        }

        if (is_bool($value)) {
            return $value ? 'Evet' : 'Hayır';
        }

        // Ondalıklar dışa aktarmada TR biçimiyle, tek haneli ve temiz yazılır
        // (float serileştirme gürültüsü "21.199999…" dosyaya sızmasın).
        if (is_float($value)) {
            return str_replace('.', ',', (string) round($value, 1));
        }

        if (is_array($value)) {
            return json_encode($value, JSON_UNESCAPED_UNICODE);
        }

        return $value;
    }

    /** İç içe özet dizisini "a.b" anahtarlarına düzler. */
    private static function flatten(array $data, string $prefix = ''): array
    {
        $out = [];
        foreach ($data as $key => $value) {
            $path = $prefix === '' ? (string) $key : "{$prefix}.{$key}";
            if (is_array($value) && $value !== [] && ! array_is_list($value)) {
                $out += self::flatten($value, $path);
            } elseif (! is_array($value)) {
                $out[$path] = $value;
            }
        }

        return $out;
    }

    /* ---------------------------- Yazıcılar ---------------------------- */

    public static function writeCsv(string $absolutePath, array $headers, array $rows): void
    {
        $fh = fopen($absolutePath, 'wb');
        if ($fh === false) {
            throw new \RuntimeException('CSV dosyası açılamadı.');
        }

        try {
            fwrite($fh, "\xEF\xBB\xBF"); // BOM: Excel'in UTF-8 tanıması için
            fputcsv($fh, $headers, ';', '"', '\\');
            foreach ($rows as $row) {
                fputcsv($fh, array_map(fn ($v) => $v ?? '', $row), ';', '"', '\\');
            }
        } finally {
            fclose($fh);
        }
    }

    public static function writeXlsx(string $absolutePath, array $headers, array $rows, string $title): void
    {
        $zip = new \ZipArchive;
        if ($zip->open($absolutePath, \ZipArchive::CREATE | \ZipArchive::OVERWRITE) !== true) {
            throw new \RuntimeException('XLSX dosyası açılamadı.');
        }

        $zip->addFromString('[Content_Types].xml',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            .'<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            .'<Default Extension="xml" ContentType="application/xml"/>'
            .'<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            .'<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            .'</Types>');

        $zip->addFromString('_rels/.rels',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            .'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            .'</Relationships>');

        $sheetName = htmlspecialchars(mb_substr($title, 0, 30), ENT_XML1);
        $zip->addFromString('xl/workbook.xml',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            .'<sheets><sheet name="'.$sheetName.'" sheetId="1" r:id="rId1"/></sheets></workbook>');

        $zip->addFromString('xl/_rels/workbook.xml.rels',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            .'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            .'</Relationships>');

        $sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            .'<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>';

        $sheet .= self::xlsxRow(1, $headers);
        $line = 2;
        foreach ($rows as $row) {
            $sheet .= self::xlsxRow($line++, $row);
        }

        $sheet .= '</sheetData></worksheet>';
        $zip->addFromString('xl/worksheets/sheet1.xml', $sheet);
        $zip->close();
    }

    private static function xlsxRow(int $line, array $cells): string
    {
        $xml = '<row r="'.$line.'">';
        foreach ($cells as $cell) {
            if (is_int($cell) || is_float($cell)) {
                $xml .= '<c r="" t="n"><v>'.$cell.'</v></c>';
            } else {
                $xml .= '<c t="inlineStr"><is><t xml:space="preserve">'
                    .htmlspecialchars((string) ($cell ?? ''), ENT_XML1, 'UTF-8')
                    .'</t></is></c>';
            }
        }

        return $xml.'</row>';
    }

    public static function writePdf(string $absolutePath, array $headers, array $rows, string $title, string $subtitle): void
    {
        $limit = (int) config('reports.pdf_row_limit', 2000);
        $truncated = count($rows) > $limit;
        $visible = $truncated ? array_slice($rows, 0, $limit) : $rows;

        $esc = fn ($v) => htmlspecialchars((string) ($v ?? '—'), ENT_QUOTES, 'UTF-8');

        $body = '';
        foreach ($visible as $row) {
            $body .= '<tr>';
            foreach ($row as $cell) {
                $align = is_numeric(str_replace([',', '.'], '', (string) $cell)) ? 'right' : 'left';
                $body .= '<td style="text-align:'.$align.'">'.$esc($cell).'</td>';
            }
            $body .= '</tr>';
        }

        $head = '';
        foreach ($headers as $h) {
            $head .= '<th>'.$esc($h).'</th>';
        }

        $note = $truncated
            ? '<p class="note">Not: PDF görünümü ilk '.$limit.' satırı içerir ('.count($rows).' satırın). Tam veri için CSV/XLSX kullanın.</p>'
            : '';

        $html = '<!DOCTYPE html><html lang="tr"><head><meta charset="utf-8"><style>
            body { font-family: DejaVu Sans, sans-serif; font-size: 9px; color: #1c1917; }
            h1 { font-size: 14px; margin: 0 0 2px; } .sub { color: #57534e; margin: 0 0 10px; }
            table { width: 100%; border-collapse: collapse; }
            th { background: #f5f5f4; text-align: left; }
            th, td { border: 0.5px solid #d6d3d1; padding: 3px 5px; }
            .note { color: #b45309; margin-top: 8px; }
        </style></head><body>'
            .'<h1>'.$esc($title).'</h1><p class="sub">'.$esc($subtitle).'</p>'
            .'<table><thead><tr>'.$head.'</tr></thead><tbody>'.$body.'</tbody></table>'
            .$note.'</body></html>';

        $dompdf = new \Dompdf\Dompdf(['isRemoteEnabled' => false]);
        $dompdf->loadHtml($html, 'UTF-8');
        $dompdf->setPaper('a4', count($headers) > 6 ? 'landscape' : 'portrait');
        $dompdf->render();

        file_put_contents($absolutePath, $dompdf->output());
    }
}
