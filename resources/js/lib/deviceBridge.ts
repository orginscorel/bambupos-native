/**
 * CİHAZ KÖPRÜSÜ (masaüstü uygulaması) — panel tarafı.
 *
 * Tarayıcı yerel ağı tarayamaz, ham TCP açamaz ve işletim sistemine kurulu
 * yazıcıları listeleyemez. Bu işleri masaüstü uygulaması (Tauri) yapar ve
 * komut olarak sunar. Panel aynı kod tabanıyla iki ortamda çalışır:
 *
 *   • Masaüstü uygulamasında  → köprü VAR: ağ taraması, ÖKC, OS yazıcıları
 *   • Saf tarayıcıda          → köprü YOK: yalnız WebUSB/Web Serial + kiosk
 *
 * Köprü yokken fonksiyonlar sessizce boş döner; arayüz de "masaüstü
 * uygulamasında kullanılabilir" uyarısını gösterir — sahte cihaz üretilmez.
 */

export interface BridgeDevice {
    /** 'os_printer' | 'network' | 'serial' */
    kind: 'os_printer' | 'network' | 'serial';
    name: string;
    /** Yazıcı adı, "ip:port" ya da seri port yolu */
    address: string;
    detail: string | null;
}

export interface BridgeInfo {
    bridge: string;
    version: string;
    os: string;
    arch: string;
    local_ip?: string;
}

type InvokeFn = <T>(cmd: string, args?: Record<string, unknown>) => Promise<T>;

function invoker(): InvokeFn | null {
    const w = window as unknown as {
        __TAURI__?: { core?: { invoke?: InvokeFn }; invoke?: InvokeFn };
    };
    // Tauri 2: __TAURI__.core.invoke · Tauri 1: __TAURI__.invoke
    return w.__TAURI__?.core?.invoke ?? w.__TAURI__?.invoke ?? null;
}

/** Masaüstü uygulamasının içinde miyiz? */
export function hasBridge(): boolean {
    return invoker() !== null;
}

async function call<T>(cmd: string, args?: Record<string, unknown>, fallback?: T): Promise<T> {
    const invoke = invoker();
    if (!invoke) {
        if (fallback !== undefined) return fallback;
        throw new Error('Bu işlem yalnız BamBumPOS masaüstü uygulamasında kullanılabilir.');
    }
    return invoke<T>(cmd, args);
}

/** Köprü sürümü/işletim sistemi — "native mod" rozetinde gösterilir. */
export const bridgeInfo = (): Promise<BridgeInfo | null> =>
    hasBridge() ? call<BridgeInfo>('bridge_info') : Promise.resolve(null);

/** İşletim sistemine kurulu yazıcılar (Windows: Get-Printer, diğeri: CUPS). */
export const listOsPrinters = (): Promise<BridgeDevice[]> =>
    call<BridgeDevice[]>('list_os_printers', undefined, []);

/** Seri portlar — ÖKC ve seri termal yazıcılar buradan bağlanır. */
export const listSerialPorts = (): Promise<BridgeDevice[]> =>
    call<BridgeDevice[]>('list_serial_ports', undefined, []);

/**
 * Aynı ağı tara. Varsayılan portlar 9100 (RAW/ESC-POS), 631 (IPP), 515 (LPD).
 * ÖKC'ler çoğunlukla 9100 ya da üreticiye özel bir port dinler.
 */
export const scanNetwork = (ports?: number[], timeoutMs?: number): Promise<BridgeDevice[]> =>
    call<BridgeDevice[]>('scan_network', { ports, timeoutMs }, []);

/** Adres/port ulaşılabilir mi (test bağlantısı). */
export const probeDevice = (host: string, port: number, timeoutMs?: number): Promise<boolean> =>
    call<boolean>('probe_device', { host, port, timeoutMs }, false);

/** Ağ yazıcısına ham bayt gönder (ESC/POS fiş, ÖKC komutu). */
export const rawPrintNetwork = (host: string, port: number, bytes: number[]): Promise<string> =>
    call<string>('raw_print_network', { host, port, bytes });

/** İşletim sistemi yazıcısına ham bayt gönder. */
export const rawPrintOs = (printer: string, bytes: number[]): Promise<string> =>
    call<string>('raw_print_os', { printer, bytes });

/**
 * Kayıtlı cihazlar (terminal başına, bu cihazda saklanır).
 * Rol ataması sunucuda değil CİHAZDA tutulur: aynı işletmenin iki kasası
 * farklı yazıcılara bağlıdır; sunucuda tutulsa biri diğerinin yazıcısına
 * basardı.
 */
export interface SavedDevice extends BridgeDevice {
    /** 'receipt' = kasa fişi · 'kitchen' = mutfak · 'okc' = ÖKC */
    role: 'receipt' | 'kitchen' | 'okc';
}

const LS_KEY = 'bhx-devices';

export function savedDevices(): SavedDevice[] {
    try {
        const raw = localStorage.getItem(LS_KEY);
        return raw ? (JSON.parse(raw) as SavedDevice[]) : [];
    } catch {
        return [];
    }
}

export function saveDevices(list: SavedDevice[]): void {
    try {
        localStorage.setItem(LS_KEY, JSON.stringify(list));
    } catch {
        /* depolama kapalıysa yalnız bu oturum için geçerli olur */
    }
}

/** Role atanmış cihazı bul (yoksa null). */
export function deviceForRole(role: SavedDevice['role']): SavedDevice | null {
    return savedDevices().find((d) => d.role === role) ?? null;
}

/** Role atanmış cihaza ham bayt gönder; atanmamışsa hata döndürür. */
export async function printToRole(role: SavedDevice['role'], bytes: number[]): Promise<string> {
    const dev = deviceForRole(role);
    if (!dev) throw new Error('Bu iş için cihaz atanmamış (Ayarlar → Cihazlar).');

    if (dev.kind === 'network') {
        const [host, port] = dev.address.split(':');
        return rawPrintNetwork(host, Number(port || 9100), bytes);
    }
    if (dev.kind === 'os_printer') {
        return rawPrintOs(dev.address, bytes);
    }
    throw new Error('Seri cihazlar şu an doğrudan yazdırmayı desteklemiyor.');
}
