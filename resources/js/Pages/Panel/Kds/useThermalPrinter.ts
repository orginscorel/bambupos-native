/**
 * TERMAL YAZICI (ESC/POS) — tarayıcı-native sessiz fiş (§13 FAZ C-2).
 *
 * AMAÇ: sipariş girilince ilgili birimin (Mutfak/Barista/Komi/Kasa) termal
 * yazıcısına DİYALOGSUZ, OTOMATİK fiş basmak. Yazıcı bir kez kullanıcı jestiyle
 * bağlanır (WebUSB veya WebSerial), izin tarayıcıda KALICI hatırlanır; sonraki
 * her fiş sessizce ESC/POS byte akışı olarak gönderilir.
 *
 * NEDEN CİHAZ-YEREL: fiziksel USB/seri port seçimi tarayıcı-izniyle CİHAZA
 * bağlıdır, sunucuya taşınamaz. Bu yüzden bağlama tercihi localStorage'da
 * cihaz-yerel tutulur (mevcut bhx-kds-* deseniyle uyumlu); yeniden açılışta
 * getDevices()/getPorts() ile sessizce yeniden bağlanır.
 *
 * FALLBACK: yazıcı bağlı değilse veya gönderim başarısızsa, çağıran taraf
 * mevcut iframe + window.print() yoluna düşer (tüm-cihaz uyumu korunur).
 *
 * NOT: ESC/POS akışı ASCII'dir; Türkçe karakterler güvenli okunurluk için
 * ASCII'ye çevrilir (ç→c, ş→s, ğ→g, ı→i, ö→o, ü→u …) — kod sayfası farkı olan
 * ucuz termallerde bozuk karakter riskini ortadan kaldırır.
 */

import { ref, computed } from 'vue';
import type { ReceiptData } from './useReceiptPrint';

/* =========================================================
 |  Minimal WebUSB / WebSerial tipleri (DOM lib garantisi yok)
 * ========================================================= */
interface UsbEndpoint { direction: 'in' | 'out'; endpointNumber: number; type: string }
interface UsbAltInterface { endpoints: UsbEndpoint[] }
interface UsbInterface { interfaceNumber: number; alternate: UsbAltInterface }
interface UsbConfiguration { interfaces: UsbInterface[] }
interface UsbDevice {
    productName?: string;
    manufacturerName?: string;
    opened: boolean;
    configuration: UsbConfiguration | null;
    open(): Promise<void>;
    selectConfiguration(n: number): Promise<void>;
    claimInterface(n: number): Promise<void>;
    transferOut(endpoint: number, data: Uint8Array): Promise<unknown>;
}
interface UsbApi {
    getDevices(): Promise<UsbDevice[]>;
    requestDevice(opts: { filters: unknown[] }): Promise<UsbDevice>;
}
interface SerialPortInfoLike { usbVendorId?: number }
interface SerialPort {
    getInfo(): SerialPortInfoLike;
    readonly writable: WritableStream<Uint8Array> | null;
    open(opts: { baudRate: number }): Promise<void>;
}
interface SerialApi {
    getPorts(): Promise<SerialPort[]>;
    requestPort(): Promise<SerialPort>;
}

type Transport = 'usb' | 'serial';

const LS_KIND = 'bhx-thermal-kind'; // 'usb' | 'serial'
const LS_WIDTH = 'bhx-thermal-width'; // '58' | '80'
const LS_KIOSK = 'bhx-thermal-kiosk'; // 'on' → tarayıcı sessiz yazdırma (Chrome --kiosk-printing)

function usbApi(): UsbApi | null {
    const u = (navigator as unknown as { usb?: UsbApi }).usb;
    return u ?? null;
}
function serialApi(): SerialApi | null {
    const s = (navigator as unknown as { serial?: SerialApi }).serial;
    return s ?? null;
}

/* =========================================================
 |  Türkçe → ASCII (termal kod sayfası güvenliği)
 * ========================================================= */
const TR_MAP: Record<string, string> = {
    ç: 'c', Ç: 'C', ğ: 'g', Ğ: 'G', ı: 'i', İ: 'I', ö: 'o', Ö: 'O',
    ş: 's', Ş: 'S', ü: 'u', Ü: 'U', â: 'a', î: 'i', û: 'u',
};
function translit(s: string): string {
    return String(s ?? '').replace(/[çÇğĞıİöÖşŞüÜâîû]/g, (c) => TR_MAP[c] ?? c);
}

/* =========================================================
 |  ESC/POS byte kurucu
 * ========================================================= */
const ESC = 0x1b;
const GS = 0x1d;

class EscPosBuilder {
    private bytes: number[] = [];

    raw(...b: number[]): this { this.bytes.push(...b); return this; }
    init(): this { return this.raw(ESC, 0x40); }
    alignLeft(): this { return this.raw(ESC, 0x61, 0); }
    alignCenter(): this { return this.raw(ESC, 0x61, 1); }
    bold(on: boolean): this { return this.raw(ESC, 0x45, on ? 1 : 0); }
    /** size: 0 normal, 1 double-height, 2 double-width+height */
    size(mode: 0 | 1 | 2): this {
        const n = mode === 2 ? 0x11 : mode === 1 ? 0x01 : 0x00;
        return this.raw(GS, 0x21, n);
    }
    text(s: string): this {
        const a = translit(s);
        for (let i = 0; i < a.length; i++) {
            const code = a.charCodeAt(i);
            this.bytes.push(code < 0x80 ? code : 0x3f); // ASCII dışı → '?'
        }
        return this;
    }
    line(s = ''): this { return this.text(s).raw(0x0a); }
    feed(n = 1): this { for (let i = 0; i < n; i++) this.bytes.push(0x0a); return this; }
    cut(): this { return this.raw(GS, 0x56, 0x00); } // tam kesim (kesici yoksa yok sayılır)
    build(): Uint8Array { return new Uint8Array(this.bytes); }
}

/** Fiş genişliğine göre karakter sayısı (58mm≈32, 80mm≈48). */
function cols(width: string): number {
    return width === '80' ? 48 : 32;
}
function ruleLine(width: string, ch = '-'): string {
    return ch.repeat(cols(width));
}

/** ReceiptData → ESC/POS. useReceiptPrint.renderTicketBody ile AYNI bilgi. */
function encodeReceipt(data: ReceiptData, width: string): Uint8Array {
    const b = new EscPosBuilder().init();

    // Başlık: işletme + şube (ortalı)
    b.alignCenter().bold(true).size(1).line(data.business).size(0);
    if (data.branch) b.line(data.branch);
    b.bold(false).line(ruleLine(width, '='));

    // İstasyon (en baskın)
    b.bold(true).size(2).line(data.station).size(0).bold(false);

    // Sipariş no + saat
    b.alignLeft().bold(true).line(`Siparis #${data.orderNo}   ${data.time}`).bold(false);
    b.line(ruleLine(width));

    // Hedef + servis tipi
    b.bold(true).size(1).line(data.destination).size(0).bold(false);
    const svc = [data.serviceType, data.areaWaiter].filter(Boolean).join(' · ');
    if (svc) b.line(svc);
    b.line(ruleLine(width));

    // Kalemler (fiyatsız)
    if (data.lines.length === 0) {
        b.line('(kalem yok)');
    } else {
        for (const l of data.lines) {
            b.bold(true).size(1).line(`${l.qty}x ${l.name}`).size(0).bold(false);
            const opts: string[] = [];
            if (l.variant) opts.push(l.variant);
            if (l.options && l.options.length) opts.push(l.options.join(' · '));
            if (opts.length) b.line(`   ${opts.join(' · ')}`);
            if (l.note) b.bold(true).line(`   » ${l.note}`).bold(false);
        }
    }

    if (data.note) {
        b.line(ruleLine(width)).bold(true).line(`Not: ${data.note}`).bold(false);
    }

    b.line(ruleLine(width, '='));
    const foot = data.kind === 'delivery' ? 'Teslim Fisi' : 'Istasyon Fisi';
    b.alignCenter().line(`${foot} · #${data.orderNo}`);
    b.feed(3).cut();

    return b.build();
}

/* =========================================================
 |  Bağlı cihaz durumu (modül-tekil — tüm ekranlar paylaşır)
 * ========================================================= */
const boundKind = ref<Transport | null>(null);
const boundName = ref<string>('');
let usbDevice: UsbDevice | null = null;
let usbEndpoint = 0;
let usbIface = 0;
let serialPort: SerialPort | null = null;

const paperWidth = ref<string>(
    (typeof localStorage !== 'undefined' && localStorage.getItem(LS_WIDTH)) || '58',
);

/** Tarayıcı sessiz yazdırma modu: Chrome `--kiosk-printing` ile başlatıldığında
 * window.print() diyalogsuz basar → OS'ta kurulu (WebUSB açamayan) yazıcılar
 * için sessiz oto-fiş yolu. */
const kioskPrint = ref<boolean>(
    typeof localStorage !== 'undefined' && localStorage.getItem(LS_KIOSK) === 'on',
);
export function isKioskPrint(): boolean {
    return kioskPrint.value;
}
export function setKioskPrint(on: boolean): void {
    kioskPrint.value = on;
    if (typeof localStorage !== 'undefined') localStorage.setItem(LS_KIOSK, on ? 'on' : 'off');
}

export function isThermalSupported(): boolean {
    return !!usbApi() || !!serialApi();
}

/** Daha önce izin verilmiş cihazı sessizce yeniden bağla (sayfa açılışında). */
async function reconnect(): Promise<void> {
    const kind = typeof localStorage !== 'undefined' ? localStorage.getItem(LS_KIND) : null;
    try {
        if (kind === 'usb' && usbApi()) {
            const devices = await usbApi()!.getDevices();
            if (devices.length > 0) {
                await openUsb(devices[0]);
            }
        } else if (kind === 'serial' && serialApi()) {
            const ports = await serialApi()!.getPorts();
            if (ports.length > 0) {
                serialPort = ports[0];
                boundKind.value = 'serial';
                boundName.value = 'Seri yazıcı';
            }
        }
    } catch {
        /* sessiz — kullanıcı yeniden bağlayabilir */
    }
}

async function openUsb(device: UsbDevice): Promise<void> {
    if (!device.opened) await device.open();
    await device.selectConfiguration(1);
    const cfg = device.configuration;
    if (!cfg) throw new Error('USB yapılandırması yok');
    // Bulk OUT endpoint'i olan ilk arayüzü seç.
    for (const iface of cfg.interfaces) {
        const out = iface.alternate.endpoints.find((e) => e.direction === 'out');
        if (out) {
            await device.claimInterface(iface.interfaceNumber);
            usbIface = iface.interfaceNumber;
            usbEndpoint = out.endpointNumber;
            usbDevice = device;
            boundKind.value = 'usb';
            boundName.value = device.productName || device.manufacturerName || 'USB yazıcı';
            return;
        }
    }
    throw new Error('Yazıcı OUT endpoint bulunamadı');
}

/** Kullanıcı jestiyle USB yazıcı bağla. */
export async function bindUsbPrinter(): Promise<void> {
    const api = usbApi();
    if (!api) throw new Error('Bu tarayıcı WebUSB desteklemiyor');
    const device = await api.requestDevice({ filters: [] });
    await openUsb(device);
    if (typeof localStorage !== 'undefined') localStorage.setItem(LS_KIND, 'usb');
}

/** Kullanıcı jestiyle Seri (USB-seri) yazıcı bağla. */
export async function bindSerialPrinter(): Promise<void> {
    const api = serialApi();
    if (!api) throw new Error('Bu tarayıcı WebSerial desteklemiyor');
    const port = await api.requestPort();
    await port.open({ baudRate: 9600 });
    serialPort = port;
    boundKind.value = 'serial';
    boundName.value = 'Seri yazıcı';
    if (typeof localStorage !== 'undefined') localStorage.setItem(LS_KIND, 'serial');
}

export function unbindThermal(): void {
    usbDevice = null;
    serialPort = null;
    boundKind.value = null;
    boundName.value = '';
    if (typeof localStorage !== 'undefined') localStorage.removeItem(LS_KIND);
}

export function setPaperWidth(w: '58' | '80'): void {
    paperWidth.value = w;
    if (typeof localStorage !== 'undefined') localStorage.setItem(LS_WIDTH, w);
}

async function sendBytes(bytes: Uint8Array): Promise<void> {
    if (usbDevice && boundKind.value === 'usb') {
        // transferOut kopyalanabilir bir ArrayBuffer ister.
        await usbDevice.transferOut(usbEndpoint, bytes);
        return;
    }
    if (serialPort && boundKind.value === 'serial') {
        const w = serialPort.writable;
        if (!w) throw new Error('Seri port yazılamıyor');
        const writer = w.getWriter();
        try {
            await writer.write(bytes);
        } finally {
            writer.releaseLock();
        }
        return;
    }
    throw new Error('Bağlı termal yazıcı yok');
}

/**
 * Termal yazıcı composable'ı.
 * - `bound`: bir yazıcı bağlı mı (reaktif).
 * - `printReceipt(data)`: bağlı yazıcıya sessiz ESC/POS basar; başarısızsa hata
 *   fırlatır (çağıran fallback + bildirim yapar).
 */
export function useThermalPrinter() {
    // İlk kullananda sessiz yeniden bağlanmayı dene.
    if (boundKind.value === null && typeof navigator !== 'undefined') {
        void reconnect();
    }

    async function printReceipt(data: ReceiptData): Promise<void> {
        if (!boundKind.value) throw new Error('Termal yazıcı bağlı değil');
        const bytes = encodeReceipt(data, paperWidth.value);
        await sendBytes(bytes);
    }

    /** Test fişi (bağlama sonrası doğrulama). */
    async function printTest(): Promise<void> {
        await printReceipt({
            business: 'Test',
            branch: '',
            station: 'TEST',
            orderNo: 0,
            destination: 'Deneme fisi',
            serviceType: null,
            areaWaiter: null,
            time: new Date().toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' }),
            note: null,
            lines: [{ qty: 1, name: 'Termal baglanti tamam', options: [], note: null }],
            kind: 'station',
        });
    }

    return {
        bound: computed(() => boundKind.value !== null),
        boundKind: computed(() => boundKind.value),
        boundName: computed(() => boundName.value),
        paperWidth: computed(() => paperWidth.value),
        kioskPrint: computed(() => kioskPrint.value),
        supported: isThermalSupported(),
        printReceipt,
        printTest,
        reconnect,
    };
}
