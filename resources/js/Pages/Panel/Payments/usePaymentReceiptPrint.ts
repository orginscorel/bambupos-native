/**
 * KASA / MÜŞTERİ FİŞİ — üretim + yazdırma (§13 FAZ C-2).
 *
 * KDS istasyon fişinin (§13 FAZ C-1, `Kds/useReceiptPrint.ts`) PARALI
 * karşılığı. Aynı YALITILMIŞ iframe + `window.print()` deseni kullanılır
 * (en uyumlu, tüm cihaz/yazıcı) ama bu fiş PARA GÖSTERİR: fiyat, KDV,
 * ödeme yöntemi, para üstü. KDS'e DOKUNULMADI — bu ayrı bir composable'dır
 * (ortak makineyi Kds dosyasından çıkarmak Kds'i etkileyeceğinden, iframe
 * yazdırma sırası burada bağımsız olarak yeniden yazıldı).
 *
 * TÜM-CİHAZ UYUMU — NEDEN TARAYICI YAZDIRMASI:
 *   Yazıcıya doğrudan sürücü YOK. Fiş, sayfadan YALITILMIŞ gizli bir
 *   <iframe> içine kendi bağımsız belgesi olarak yazılır ve
 *   `iframe.contentWindow.print()` çağrılır → cihazın VARSAYILAN yazıcısı
 *   (termal 58/80mm, A4, veya "PDF'e kaydet") tarayıcının yazdırma diyaloğu
 *   üzerinden basar (otomatik algıla). Böylece:
 *     • kasa panelinin düzeni yazdırmayı BOZAMAZ (yalıtım),
 *     • app.css'e global `@media print` kuralı EKLEMEK GEREKMEZ,
 *     • fiş her zaman siyah-beyaz termal görünür (kasa teması ne olursa olsun).
 *
 * TEK KAYNAK: fiş gövdesi `renderPaymentTicketBody()` ile üretilir;
 * ÖNİZLEME (PaymentReceipt.vue, v-html) ve YAZDIRMA (aşağıdaki iframe belgesi)
 * AYNI markup'ı kullanır → görsel asla ikisi arasında kaymaz.
 *
 * İKİ TÜR:
 *   • 'bill'    → Hesap Fişi (ön-hesap): müşteriye ödemeden ÖNCE verilir.
 *                 Kalemler + ara toplam + indirim + servis + KDV (dahil) +
 *                 TOPLAM (ödenecek).
 *   • 'payment' → Ödeme/Adisyon Fişi (kapanış): aynı + ödeme yöntemi
 *                 (Nakit/Kart) + ödenen + para üstü + "Teşekkürler".
 */

/* =========================================================
 |  Para biçimi (kuruş → "1.234,56") — payments.ts ile birebir
 * ========================================================= */

function fmtMoney(minor: number): string {
    return (minor / 100).toLocaleString('tr-TR', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
}

/* =========================================================
 |  Veri şekli
 * ========================================================= */

export interface PaymentReceiptLine {
    qty: number;
    name: string;
    variant?: string | null;
    options?: string[];
    note?: string | null;
    /** İkram (ücretsiz) mı — fişte "İKRAM ₺0" gösterilir. */
    isComp: boolean;
    /** KDV DAHİL satır toplamı (kuruş). İkramda 0 basılır. */
    lineTotalMinor: number;
    /** Birim (adet başı) fiyat, KDV dahil (kuruş). */
    unitPriceMinor: number;
}

export interface PaymentReceiptPayment {
    methodLabel: string;
    amountMinor: number;
    changeMinor: number;
}

export interface PaymentReceiptData {
    /** İşletme adı (tenant). */
    business: string;
    /** Şube adı. */
    branch: string;
    /** Fiş türü: ön-hesap mı, kapanış (ödeme) fişi mi. */
    kind: 'bill' | 'payment';
    /** Adisyon numarası (order id). */
    orderNo: number;
    /** Hedef: masa adı / müşteri / #id. */
    destination: string;
    /** Servis tipi / kanal etiketi (Masada · Gel-al · Paket). */
    serviceType?: string | null;
    /** Misafir sayısı (varsa). */
    guestCount?: number | null;
    /** Biçimlenmiş tarih · saat. */
    time: string;

    /** Fiş kalemleri (fiyatlı). Boşsa yalnız tutar özeti basılır. */
    lines: PaymentReceiptLine[];

    /* ---- Tutar özeti (kuruş) ---- */
    itemsTotalMinor: number;
    compTotalMinor: number;
    discountMinor: number;
    serviceChargeMinor: number;
    roundingMinor: number;
    totalMinor: number;
    /** KDV DAHİL toplam KDV payı (kuruş) — toplama zaten dahil (bilgi). */
    vatTotalMinor: number;
    /** Oran-bazlı KDV kırılımı (güvenilirse). */
    vatByRate?: Array<{ rate: number; base_minor: number; vat_minor: number }>;

    /* ---- Ödeme bölümü (yalnız kind='payment') ---- */
    paidMinor?: number;
    remainingMinor?: number;
    changeTotalMinor?: number;
    payments?: PaymentReceiptPayment[];
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

function ratePct(rate: number): string {
    return `%${Number.isInteger(rate) ? rate : rate.toFixed(1)}`;
}

/** Adisyon saati/tarihini fişe uygun kısa biçime getirir. */
export function formatReceiptTime(iso: string | null | undefined): string {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    try {
        const t = d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
        const day = d.toLocaleDateString('tr-TR', { day: '2-digit', month: '2-digit', year: 'numeric' });
        return `${day} · ${t}`;
    } catch {
        return d.toISOString().slice(0, 16).replace('T', ' ');
    }
}

/** Tutar özeti satırı (etiket + değer). */
function summaryRow(label: string, value: string, opts: { bold?: boolean; big?: boolean; muted?: boolean; sign?: string } = {}): string {
    const weight = opts.bold ? '700' : '400';
    const size = opts.big ? '16px' : '13px';
    const color = opts.muted ? '#333' : '#000';
    const border = opts.big ? 'border-top:2px solid #000;margin-top:4px;padding-top:4px;' : '';
    return (
        `<div style="display:flex;justify-content:space-between;gap:8px;font-size:${size};font-weight:${weight};color:${color};line-height:1.5;${border}">` +
        `<span>${esc(label)}</span><span style="white-space:nowrap;">${opts.sign ?? ''}${esc(value)} ₺</span>` +
        '</div>'
    );
}

/**
 * Fişin GÖVDE markup'ı (inline stiller — hiçbir dış CSS'e/temaya bağlı
 * değil; hem v-html önizlemesinde hem iframe yazdırmasında birebir aynı
 * görünür). Termal-dar, tek renk (siyah/beyaz), monospace — okunaklı.
 */
export function renderPaymentTicketBody(data: PaymentReceiptData): string {
    const rule = '<div style="border-top:1px dashed #000;margin:6px 0;"></div>';
    const solidRule = '<div style="border-top:2px solid #000;margin:6px 0;"></div>';

    /* ---- Kalemler (fiyatlı) ---- */
    const lines = data.lines
        .map((l) => {
            const opts: string[] = [];
            if (l.variant) opts.push(l.variant);
            if (l.options && l.options.length) opts.push(l.options.join(' · '));
            const optHtml = opts.length
                ? `<div style="font-size:11px;margin:1px 0 0 26px;color:#333;">${esc(opts.join(' · '))}</div>`
                : '';
            const noteHtml = l.note
                ? `<div style="font-size:11px;margin:1px 0 0 26px;color:#333;">» ${esc(l.note)}</div>`
                : '';
            const priceLabel = l.isComp ? 'İKRAM ₺0' : `${fmtMoney(l.lineTotalMinor)} ₺`;
            const unitHtml =
                !l.isComp && l.qty > 1
                    ? `<div style="font-size:11px;margin:1px 0 0 26px;color:#333;">${esc(l.qty)} × ${fmtMoney(l.unitPriceMinor)} ₺</div>`
                    : '';
            return (
                '<div style="margin:5px 0;">' +
                '<div style="display:flex;gap:6px;align-items:baseline;font-size:13px;font-weight:700;line-height:1.3;">' +
                `<span style="min-width:22px;">${esc(l.qty)}×</span>` +
                `<span style="flex:1;">${esc(l.name)}</span>` +
                `<span style="white-space:nowrap;${l.isComp ? 'font-style:italic;' : ''}">${priceLabel}</span>` +
                '</div>' +
                unitHtml +
                optHtml +
                noteHtml +
                '</div>'
            );
        })
        .join('');

    /* ---- Tutar özeti (TOPLAM'dan ÖNCEKİ satırlar) ---- */
    const preRows: string[] = [];
    preRows.push(summaryRow('Ara toplam', fmtMoney(data.itemsTotalMinor)));
    if (data.compTotalMinor > 0) preRows.push(summaryRow('İkram', fmtMoney(data.compTotalMinor), { sign: '−', muted: true }));
    if (data.discountMinor > 0) preRows.push(summaryRow('İndirim', fmtMoney(data.discountMinor), { sign: '−', muted: true }));
    if (data.serviceChargeMinor > 0) preRows.push(summaryRow('Servis bedeli', fmtMoney(data.serviceChargeMinor)));
    if (data.roundingMinor !== 0)
        preRows.push(summaryRow('Yuvarlama', fmtMoney(Math.abs(data.roundingMinor)), { sign: data.roundingMinor > 0 ? '+' : '−', muted: true }));

    // TOPLAM — ters renk (siyah zemin/beyaz), fişin en baskın satırı.
    const totalBlock =
        '<div style="display:flex;justify-content:space-between;gap:8px;background:#000;color:#fff;' +
        'font-size:18px;font-weight:800;padding:5px 6px;margin:6px 0;-webkit-print-color-adjust:exact;print-color-adjust:exact;">' +
        `<span>TOPLAM</span><span style="white-space:nowrap;">${fmtMoney(data.totalMinor)} ₺</span></div>`;

    // KDV bilgisi (dahil) + oran kırılımı.
    const vatRows: string[] = [];
    if (data.vatTotalMinor > 0) {
        vatRows.push(summaryRow('Toplam KDV (dahil)', fmtMoney(data.vatTotalMinor), { muted: true }));
        if (data.vatByRate && data.vatByRate.length) {
            for (const r of data.vatByRate) {
                vatRows.push(
                    `<div style="display:flex;justify-content:space-between;gap:8px;font-size:11px;color:#333;line-height:1.4;">` +
                        `<span style="padding-left:10px;">KDV ${ratePct(r.rate)} (matrah ${fmtMoney(r.base_minor)} ₺)</span>` +
                        `<span style="white-space:nowrap;">${fmtMoney(r.vat_minor)} ₺</span></div>`,
                );
            }
        }
    }
    const itemCount = data.lines.reduce((n, l) => n + (Number(l.qty) || 0), 0);

    /* ---- Ödeme bölümü (yalnız kapanış fişi) ---- */
    let paymentBlock = '';
    if (data.kind === 'payment') {
        const rows: string[] = [];
        if (data.payments && data.payments.length) {
            for (const p of data.payments) {
                rows.push(summaryRow(p.methodLabel, fmtMoney(p.amountMinor)));
            }
        }
        if (typeof data.paidMinor === 'number' && data.paidMinor > 0) rows.push(summaryRow('Ödenen', fmtMoney(data.paidMinor), { bold: true }));
        if (data.changeTotalMinor && data.changeTotalMinor > 0) rows.push(summaryRow('Para üstü', fmtMoney(data.changeTotalMinor), { bold: true }));
        if (typeof data.remainingMinor === 'number' && data.remainingMinor > 0)
            rows.push(summaryRow('Kalan', fmtMoney(data.remainingMinor), { bold: true }));
        paymentBlock =
            solidRule +
            rows.join('') +
            '<div style="text-align:center;font-size:13px;font-weight:700;margin-top:8px;">Teşekkür ederiz</div>';
    }

    const serviceLine =
        data.serviceType || data.guestCount
            ? `<div style="font-size:11px;margin-top:2px;color:#333;">${esc(
                  [data.serviceType, data.guestCount ? `${data.guestCount} kişi` : null].filter(Boolean).join(' · '),
              )}</div>`
            : '';

    const kindLabel = data.kind === 'bill' ? 'HESAP FİŞİ (ÖN-HESAP)' : 'ADİSYON FİŞİ';

    return (
        '<div style="font-family:\'Courier New\',ui-monospace,monospace;color:#000;background:#fff;' +
        'width:100%;box-sizing:border-box;padding:2px 4px;">' +
        // Başlık: işletme + şube + fiş türü rozeti
        `<div style="text-align:center;font-size:17px;font-weight:800;letter-spacing:.4px;text-transform:uppercase;">${esc(data.business)}</div>` +
        (data.branch ? `<div style="text-align:center;font-size:11px;margin-top:1px;">${esc(data.branch)}</div>` : '') +
        `<div style="text-align:center;font-size:12px;font-weight:800;letter-spacing:1.5px;border:1.5px solid #000;padding:2px 0;margin:6px 0;">${kindLabel}</div>` +
        // Hedef (masa / müşteri) + adisyon no
        `<div style="display:flex;justify-content:space-between;gap:8px;font-size:16px;font-weight:800;line-height:1.2;">` +
        `<span>${esc(data.destination)}</span><span>#${esc(data.orderNo)}</span></div>` +
        serviceLine +
        (data.time ? `<div style="font-size:11px;margin-top:2px;color:#333;">${esc(data.time)}</div>` : '') +
        solidRule +
        // Sütun başlığı (netlik)
        '<div style="display:flex;justify-content:space-between;font-size:10px;letter-spacing:.5px;color:#333;">' +
        '<span>ÜRÜN</span><span>TUTAR</span></div>' +
        rule +
        // Kalemler
        (lines || '<div style="font-size:12px;color:#333;">(kalem dökümü yok)</div>') +
        // Kalem adedi
        `<div style="font-size:11px;color:#333;margin-top:2px;">${esc(data.lines.length)} çeşit · ${esc(itemCount)} adet ürün</div>` +
        rule +
        // Tutar özeti (TOPLAM öncesi) + ters-renk TOPLAM + KDV
        preRows.join('') +
        totalBlock +
        vatRows.join('') +
        // Ödeme (kapanış)
        paymentBlock +
        solidRule +
        // Alt bilgi: teşekkür + mali-değer notu (bu bir mali fiş DEĞİL) + no
        (data.kind === 'payment'
            ? '<div style="text-align:center;font-size:14px;font-weight:800;margin-bottom:2px;">Bizi tercih ettiğiniz için teşekkürler</div>'
            : '<div style="text-align:center;font-size:11px;margin-bottom:2px;">Bu fiş ön-hesaptır — ödeme kasada alınır.</div>') +
        `<div style="text-align:center;font-size:9px;color:#333;line-height:1.4;">Bu belge bilgi amaçlıdır, mali değeri yoktur.<br>${data.kind === 'bill' ? 'Ön-hesap' : 'Adisyon kapanışı'} · #${esc(
            data.orderNo,
        )} · ${esc(data.time)}</div>` +
        `<div style="text-align:center;font-size:16px;margin-top:2px;">✂ - - - - - - - - - - - -</div>` +
        '</div>'
    );
}

/**
 * Yazdırma için TAM belge — gövdeyi @page + termal print CSS ile sarar.
 * Genişlik %100 → yazıcı 58/80mm de olsa A4 de olsa içerik kâğıda oturur.
 */
function renderPaymentTicketDocument(data: PaymentReceiptData): string {
    return (
        '<!doctype html><html lang="tr"><head><meta charset="utf-8">' +
        `<title>${data.kind === 'bill' ? 'Hesap' : 'Fiş'} #${esc(data.orderNo)}</title>` +
        '<style>' +
        '@page{margin:4mm;}' +
        'html,body{margin:0;padding:0;background:#fff;color:#000;}' +
        '*{-webkit-print-color-adjust:exact;print-color-adjust:exact;}' +
        '</style></head><body>' +
        renderPaymentTicketBody(data) +
        '</body></html>'
    );
}

/* =========================================================
 |  Yazdırma (yalıtılmış iframe + sıra)
 * ========================================================= */

let printQueue: PaymentReceiptData[] = [];
let printing = false;

function printOne(data: PaymentReceiptData): void {
    const iframe = document.createElement('iframe');
    iframe.setAttribute('aria-hidden', 'true');
    iframe.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0;visibility:hidden;';
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
    doc.write(renderPaymentTicketDocument(data));
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
 * Kasa fiş yazdırma composable'ı — `print(data)` fişi yalıtılmış bir iframe'e
 * basar. Aynı anda gelen birden çok fiş sıraya alınır.
 */
export function usePaymentReceiptPrint(): { print: (data: PaymentReceiptData) => void } {
    function print(data: PaymentReceiptData): void {
        if (typeof document === 'undefined') return;
        printQueue.push(data);
        drain();
    }
    return { print };
}
