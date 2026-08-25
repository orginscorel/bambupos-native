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

import { useToast } from '@/composables/useToast';
import { useThermalPrinter, isKioskPrint } from './useThermalPrinter';

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
    const solidRule = '<div style="border-top:2px solid #000;margin:7px 0;"></div>';
    const totalQty = data.lines.reduce((n, l) => n + (Number(l.qty) || 0), 0);

    const lines = data.lines
        .map((l, i) => {
            const opts: string[] = [];
            if (l.variant) opts.push(esc(l.variant));
            if (l.options && l.options.length) opts.push(esc(l.options.join(' · ')));
            const optHtml = opts.length
                ? `<div style="font-size:12px;margin:2px 0 0 40px;line-height:1.25;">${opts.join(' · ')}</div>`
                : '';
            // Kalem notu: mutfağın kaçırmaması için ÇERÇEVELİ vurgu kutusu.
            const noteHtml = l.note
                ? `<div style="font-size:12px;font-weight:800;margin:3px 0 0 40px;border:1.5px solid #000;padding:2px 5px;">» ${esc(l.note)}</div>`
                : '';
            const sep = i > 0 ? 'border-top:1px dotted #999;padding-top:6px;' : '';
            return (
                `<div style="margin:6px 0;${sep}">` +
                '<div style="display:flex;gap:8px;align-items:flex-start;line-height:1.2;">' +
                // Adet: kalın çerçeveli kutu — bir bakışta "kaç adet".
                `<span style="flex:none;min-width:30px;text-align:center;font-size:16px;font-weight:800;border:2px solid #000;padding:1px 4px;">${esc(l.qty)}×</span>` +
                `<span style="flex:1;font-size:16px;font-weight:800;">${esc(l.name)}</span>` +
                '</div>' +
                optHtml +
                noteHtml +
                '</div>'
            );
        })
        .join('');

    const serviceLine =
        data.serviceType || data.areaWaiter
            ? `<div style="text-align:center;font-size:12px;margin-top:3px;">${esc(
                  [data.serviceType, data.areaWaiter].filter(Boolean).join(' · '),
              )}</div>`
            : '';

    const orderNote = data.note
        ? `<div style="font-size:13px;font-weight:800;border:1.5px solid #000;padding:3px 6px;margin-top:6px;">SİPARİŞ NOTU: ${esc(data.note)}</div>`
        : '';

    const footLabel = data.kind === 'delivery' ? 'TESLİM FİŞİ' : 'İSTASYON FİŞİ';

    return (
        '<div style="font-family:\'Courier New\',ui-monospace,monospace;color:#000;background:#fff;' +
        'width:100%;box-sizing:border-box;padding:2px 4px;">' +
        // Başlık: işletme + şube
        `<div style="text-align:center;font-size:17px;font-weight:800;letter-spacing:.4px;text-transform:uppercase;">${esc(data.business)}</div>` +
        (data.branch
            ? `<div style="text-align:center;font-size:11px;margin-top:1px;">${esc(data.branch)}</div>`
            : '') +
        // İSTASYON BANDI — ters renk (siyah zemin/beyaz yazı): nereye gideceği bir bakışta.
        '<div style="background:#000;color:#fff;text-align:center;font-size:24px;font-weight:800;' +
        'letter-spacing:2px;text-transform:uppercase;padding:6px 4px;margin:7px 0;-webkit-print-color-adjust:exact;print-color-adjust:exact;">' +
        `${esc(data.station)}</div>` +
        // Sipariş no + saat + kalem sayısı
        '<div style="display:flex;justify-content:space-between;font-size:13px;font-weight:700;">' +
        `<span>ADİSYON #${esc(data.orderNo)}</span><span>${esc(data.time)}</span>` +
        '</div>' +
        rule +
        // Hedef (masa) — büyük, ortalı
        `<div style="text-align:center;font-size:19px;font-weight:800;line-height:1.2;">${esc(data.destination)}</div>` +
        serviceLine +
        solidRule +
        // Kalemler
        (lines || '<div style="font-size:13px;text-align:center;">(kalem yok)</div>') +
        solidRule +
        // Kalem sayısı özeti (mutfak "kaç ürün hazırlayacağım" bilsin)
        `<div style="display:flex;justify-content:space-between;font-size:13px;font-weight:800;">` +
        `<span>TOPLAM</span><span>${esc(data.lines.length)} çeşit · ${esc(totalQty)} adet</span></div>` +
        orderNote +
        rule +
        `<div style="text-align:center;font-size:11px;letter-spacing:.5px;">${footLabel} · #${esc(data.orderNo)} · ${esc(data.time)}</div>` +
        `<div style="text-align:center;font-size:16px;margin-top:2px;">✂ - - - - - - - - - - - -</div>` +
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
interface QueueItem {
    data: ReceiptData;
    /** true → yalnız bağlı termal yazıcıya sessiz bas; yazıcı yoksa tarayıcı
     * diyaloğunu AÇMA (oto-fiş için). false → yazıcı yoksa iframe diyaloğuna düş
     * (manuel "Fiş" butonu için). */
    silentOnly: boolean;
}
let printQueue: QueueItem[] = [];
let printing = false;
let bindHintShown = false;

function printOneIframe(data: ReceiptData): void {
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
        void drainNext();
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

/**
 * Sıradaki fişi bas: termal yazıcı BAĞLIYSA sessiz ESC/POS ile; yoksa (veya
 * gönderim başarısızsa) mevcut iframe + window.print() yoluna düşer. Böylece
 * bağlı terminalde sipariş girince otomatik-sessiz fiş çıkar, bağlı değilse
 * eski davranış korunur.
 */
async function drainNext(): Promise<void> {
    if (printing) return;
    const next = printQueue.shift();
    if (!next) return;
    printing = true;

    const thermal = useThermalPrinter();
    if (thermal.bound.value) {
        try {
            await thermal.printReceipt(next.data);
            printing = false;
            void drainNext();
            return;
        } catch {
            useToast().danger(
                'Termal yazıcıya basılamadı',
                'Yazıcı bağlantısını kontrol edin.',
            );
            if (next.silentOnly) {
                // Oto-fiş: bağlı yazıcıya basılamadıysa diyalog AÇMA.
                printing = false;
                void drainNext();
                return;
            }
            // Manuel: iframe fallback'e düş.
        }
    } else if (next.silentOnly && !isKioskPrint()) {
        // Oto-fiş + yazıcı yok + kiosk sessiz kapalı → diyalog spam'i YOK; bir kez uyar.
        if (!bindHintShown) {
            bindHintShown = true;
            useToast().warning(
                'Otomatik fiş için yazıcı ayarı gerekli',
                'Mutfak ekranında fiş-bağlama (🔌) ikonundan ya termal yazıcıyı bağlayın ya da "Sessiz yazdırma (kiosk)" seçeneğini açın.',
            );
        }
        printing = false;
        void drainNext();
        return;
    }

    // Termal yoksa: kiosk sessiz açıksa oto-fiş de dahil window.print() (Chrome
    // --kiosk-printing ile diyalogsuz basar); manuelde diyalog açılır.
    printOneIframe(next.data); // cleanup içinde printing=false + drainNext
}

/**
 * KDS fiş yazdırma composable'ı — `print(data)` fişi yalıtılmış bir iframe'e
 * basar. Aynı anda gelen birden çok fiş sıraya alınır.
 */
export function useReceiptPrint(): {
    print: (data: ReceiptData, opts?: { silentOnly?: boolean }) => void;
} {
    function print(data: ReceiptData, opts?: { silentOnly?: boolean }): void {
        if (typeof document === 'undefined') return;
        printQueue.push({ data, silentOnly: opts?.silentOnly ?? false });
        void drainNext();
    }
    return { print };
}
