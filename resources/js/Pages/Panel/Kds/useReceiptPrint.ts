/**
 * KDS İSTASYON FİŞİ — üretim + yazdırma (§13 FAZ C-1).
 *
 * AMAÇ: sipariş girilince ilgili birime (Mutfak / Barista / Komi) OTOMATİK
 * fiş; giden fişin ÖNİZLEMESİ görülebilir; TÜM cihazlarda çalışır.
 *
 * TÜM-CİHAZ UYUMU — NEDEN TARAYICI YAZDIRMASI:
 *   Yazıcıya doğrudan sürücü YOK. Her cihaz kendi VARSAYILAN yazıcısına
 *   (termal 58/80mm, A4, veya "PDF'e kaydet") tarayıcının yazdırma diyaloğu
 *   üzerinden basar → evrensel uyum + "otomatik algıla". Fiş, sayfadan
 *   YALITILMIŞ gizli bir <iframe> içine kendi bağımsız belgesi olarak
 *   yazılır ve `iframe.contentWindow.print()` çağrılır. Böylece:
 *     • panelin `fixed inset-0` / `overflow-hidden` KDS düzeni yazdırmayı
 *       BOZAMAZ (yalıtım),
 *     • app.css'e global `@media print` kuralı EKLEMEK GEREKMEZ (mevcut
 *       stilleri bozma riski yok),
 *     • fiş her zaman siyah-beyaz termal görünür (KDS teması ne olursa olsun).
 *
 * TEK KAYNAK: fiş gövdesi `renderTicketBody()` ile üretilir; ÖNİZLEME
 * (KdsTicket.vue, v-html) ve YAZDIRMA (aşağıdaki iframe belgesi) AYNI
 * markup'ı kullanır → görsel asla ikisi arasında kaymaz.
 *
 * PARA GÖRMEZ: fişte fiyat/tutar/ödeme YOKTUR — yalnız hazırlanacak kalemler
 * (adet × ürün, varyant/seçenek, kalem/sipariş notu), istasyon, masa/servis
 * tipi, sipariş no ve saat. (Alerjen de fişe konmaz — bkz. brief.)
 */

/* =========================================================
 |  Veri şekli
 * ========================================================= */

export interface ReceiptLine {
    qty: number;
    name: string;
    variant?: string | null;
    options?: string[];
    note?: string | null;
}

export interface ReceiptData {
    /** İşletme adı (tenant). */
    business: string;
    /** Şube adı. */
    branch: string;
    /** Büyük yönlendirme etiketi: MUTFAK / BARISTA / (istasyon adı) / TESLİM. */
    station: string;
    /** Sipariş numarası (order id). */
    orderNo: number;
    /** Hedef: masa adı / müşteri / #id. */
    destination: string;
    /** Servis tipi / kanal etiketi (Masada · Gel-al · Paket). */
    serviceType?: string | null;
    /** Alan · garson satırı. */
    areaWaiter?: string | null;
    /** Biçimlenmiş saat (+ kısa tarih). */
    time: string;
    /** Sipariş notu (varsa). */
    note?: string | null;
    /** Fiş kalemleri (fiyatsız). */
    lines: ReceiptLine[];
    /** İstasyon fişi mi, komi teslim fişi mi (alt etiket metni). */
    kind: 'station' | 'delivery';
}

/* =========================================================
 |  Markup üretimi (TEK KAYNAK: önizleme + yazdırma paylaşır)
 * ========================================================= */

function esc(v: unknown): string {
    return String(v ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

/** Sipariş saati/tarihini fişe uygun kısa biçime getirir. */
export function formatReceiptTime(iso: string | null | undefined): string {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    try {
        const t = d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
        const day = d.toLocaleDateString('tr-TR', { day: '2-digit', month: '2-digit' });
        return `${day} · ${t}`;
    } catch {
        return d.toISOString().slice(11, 16);
    }
}

/**
 * Fişin GÖVDE markup'ı (inline stiller — hiçbir dış CSS'e/temaya bağlı
 * değil; hem v-html önizlemesinde hem iframe yazdırmasında birebir aynı
 * görünür). Termal-dar, tek renk (siyah/beyaz), monospace — okunaklı.
 */
export function renderTicketBody(data: ReceiptData): string {
    const rule = '<div style="border-top:1px dashed #000;margin:6px 0;"></div>';
    const solidRule = '<div style="border-top:2px solid #000;margin:6px 0;"></div>';

    const lines = data.lines
        .map((l) => {
            const opts: string[] = [];
            if (l.variant) opts.push(esc(l.variant));
            if (l.options && l.options.length) opts.push(esc(l.options.join(' · ')));
            const optHtml = opts.length
                ? `<div style="font-size:12px;margin:1px 0 0 26px;">${opts.join(' · ')}</div>`
                : '';
            const noteHtml = l.note
                ? `<div style="font-size:12px;font-weight:700;margin:1px 0 0 26px;">» ${esc(l.note)}</div>`
                : '';
            return (
                '<div style="margin:5px 0;">' +
                '<div style="display:flex;gap:6px;align-items:baseline;font-size:15px;font-weight:700;line-height:1.25;">' +
                `<span style="min-width:22px;">${esc(l.qty)}×</span>` +
                `<span style="flex:1;">${esc(l.name)}</span>` +
                '</div>' +
                optHtml +
                noteHtml +
                '</div>'
            );
        })
        .join('');

    const serviceLine =
        data.serviceType || data.areaWaiter
            ? `<div style="font-size:12px;margin-top:2px;">${esc(
                  [data.serviceType, data.areaWaiter].filter(Boolean).join(' · '),
              )}</div>`
            : '';

    const orderNote = data.note
        ? `${rule}<div style="font-size:13px;font-weight:700;">Not: ${esc(data.note)}</div>`
        : '';

    const footLabel = data.kind === 'delivery' ? 'Teslim Fişi' : 'İstasyon Fişi';

    return (
        '<div style="font-family:\'Courier New\',ui-monospace,monospace;color:#000;background:#fff;' +
        'width:100%;box-sizing:border-box;padding:2px 4px;">' +
        // Başlık: işletme + şube
        `<div style="text-align:center;font-size:16px;font-weight:800;letter-spacing:.3px;">${esc(data.business)}</div>` +
        (data.branch
            ? `<div style="text-align:center;font-size:12px;margin-top:1px;">${esc(data.branch)}</div>`
            : '') +
        solidRule +
        // İstasyon (büyük, en baskın — nereye gideceği)
        `<div style="text-align:center;font-size:22px;font-weight:800;letter-spacing:1px;text-transform:uppercase;">${esc(
            data.station,
        )}</div>` +
        // Sipariş no + saat
        '<div style="display:flex;justify-content:space-between;font-size:13px;font-weight:700;margin-top:4px;">' +
        `<span>Sipariş #${esc(data.orderNo)}</span><span>${esc(data.time)}</span>` +
        '</div>' +
        rule +
        // Hedef (masa / servis tipi)
        `<div style="font-size:18px;font-weight:800;line-height:1.2;">${esc(data.destination)}</div>` +
        serviceLine +
        rule +
        // Kalemler
        (lines || '<div style="font-size:13px;">(kalem yok)</div>') +
        orderNote +
        solidRule +
        `<div style="text-align:center;font-size:12px;">${footLabel} · #${esc(data.orderNo)}</div>` +
        '</div>'
    );
}

/**
 * Yazdırma için TAM belge — gövdeyi @page + termal print CSS ile sarar.
 * `@page { margin }` küçük tutulur; genişlik %100 → yazıcı 58/80mm de olsa
 * A4 de olsa içerik kâğıda otururu (otomatik uyum).
 */
function renderTicketDocument(data: ReceiptData): string {
    return (
        '<!doctype html><html lang="tr"><head><meta charset="utf-8">' +
        `<title>Fiş #${esc(data.orderNo)}</title>` +
        '<style>' +
        '@page{margin:4mm;}' +
        'html,body{margin:0;padding:0;background:#fff;color:#000;}' +
        '*{-webkit-print-color-adjust:exact;print-color-adjust:exact;}' +
        '</style></head><body>' +
        renderTicketBody(data) +
        '</body></html>'
    );
}

/* =========================================================
 |  Yazdırma (yalıtılmış iframe + sıra)
 * ========================================================= */

// Aynı anda birden çok yeni sipariş gelirse yazdırma diyalogları
// çakışmasın diye basit bir sıra: biri bitince (afterprint / zaman aşımı)
// sonraki basılır.
let printQueue: ReceiptData[] = [];
let printing = false;

function printOne(data: ReceiptData): void {
    const iframe = document.createElement('iframe');
    iframe.setAttribute('aria-hidden', 'true');
    iframe.style.cssText =
        'position:fixed;right:0;bottom:0;width:0;height:0;border:0;visibility:hidden;';
    document.body.appendChild(iframe);

    let done = false;
    const cleanup = (): void => {
        if (done) return;
        done = true;
        setTimeout(() => iframe.remove(), 500);
        printing = false;
        drain();
    };

    iframe.onload = (): void => {
        const win = iframe.contentWindow;
        if (!win) {
            cleanup();
            return;
        }
        // afterprint hem "yazdır" hem "iptal"de tetiklenir → sırayı ilerletir.
        win.addEventListener('afterprint', cleanup, { once: true });
        // Emniyet: bazı mobil tarayıcılar afterprint vermez.
        setTimeout(cleanup, 8000);
        try {
            win.focus();
            win.print();
        } catch {
            cleanup();
        }
    };

    const doc = iframe.contentWindow?.document;
    if (!doc) {
        cleanup();
        return;
    }
    doc.open();
    doc.write(renderTicketDocument(data));
    doc.close();
}

function drain(): void {
    if (printing) return;
    const next = printQueue.shift();
    if (!next) return;
    printing = true;
    printOne(next);
}

/**
 * KDS fiş yazdırma composable'ı — `print(data)` fişi yalıtılmış bir iframe'e
 * basar. Aynı anda gelen birden çok fiş sıraya alınır.
 */
export function useReceiptPrint(): { print: (data: ReceiptData) => void } {
    function print(data: ReceiptData): void {
        if (typeof document === 'undefined') return;
        printQueue.push(data);
        drain();
    }
    return { print };
}
