/**
 * KDS (mutfak/bar/komi) ortak tipleri + yardımcıları.
 *
 * ULAŞIM KATMANI SOYUT (ADR-006): ekranlar veriyi `KdsFeed` arayüzünden
 * alır; bugün cursor'lı HTTP polling (3-5 sn, değişiklik yoksa 204), yarın
 * WebSocket gelirse yalnız `createPollingFeed` yerine yeni bir fabrika
 * yazılır — ekran kodu DEĞİŞMEZ.
 */
import { ref, type Ref } from 'vue';
import { api } from '@/lib/http';

/* =========================================================
 |  Tipler
 * ========================================================= */

export interface VariantMeta {
    value: string;
    label: string;
    icon: string;
    variant: 'neutral' | 'primary' | 'success' | 'warning' | 'danger' | 'info';
}

export interface StationRow {
    id: number | null;
    key: string;
    name: string;
    is_builtin: boolean;
    is_active: boolean;
    sort_order: number;
}

export interface KdsConfig {
    poll_interval_seconds: number;
    default_prep_minutes: number;
    late_ratio: number;
    unassigned_key: string;
}

export interface AllergenChip {
    name: string;
    icon: string | null;
    color: string | null;
}

export interface KdsItem {
    id: number;
    order_id: number;
    qty: number;
    name: string;
    variant_name: string | null;
    /** Ürün kartı görseli (WebP, tenant-izolasyonlu); yoksa null → zarif yer tutucu gösterilir. */
    image_url: string | null;
    note: string | null;
    status: string;
    status_label: string;
    status_icon: string;
    status_variant: VariantMeta['variant'];
    station: string | null;
    station_label: string;
    target_minutes: number;
    created_at: string | null;
    updated_at: string | null;
    allergens: AllergenChip[];
    diets: string[];
    /** Reçete / hazırlama notu (ürün açıklaması). */
    recipe: string | null;
    options: string[];
    picked_up_at: string | null;
    picked_up_by: string | null;
}

export interface KdsOrderCard {
    id: number;
    version: number;
    table_name: string | null;
    table_number: number | null;
    area_name: string | null;
    channel: string;
    channel_label: string;
    channel_icon: string;
    channel_variant: VariantMeta['variant'];
    /** Servis tipi (Masada/Gel-al/Paket) — backend'de zaten var, fişte gösterilir (PARA DEĞİL). */
    service_type_label?: string | null;
    status: string;
    status_label: string;
    status_icon: string;
    status_variant: VariantMeta['variant'];
    note: string | null;
    guest_count: number | null;
    waiter: string | null;
    customer_name: string | null;
    placed_at: string | null;
    items: KdsItem[];
}

export interface StationSummaryRow {
    station: string | null;
    station_label: string;
    pending: number;
}

export interface KitchenPayload {
    orders: KdsOrderCard[];
    summary: StationSummaryRow[];
    cursor: number;
    server_time: string;
}

export interface RunnerItem extends KdsItem {
    order_version: number;
    table_name: string | null;
    table_number: number | null;
    area_name: string | null;
    channel: string;
    channel_label: string;
    channel_icon: string;
    channel_variant: VariantMeta['variant'];
    order_note: string | null;
    waiter: string | null;
}

export interface RunnerPayload {
    items: RunnerItem[];
    cursor: number;
    server_time: string;
}

/* =========================================================
 |  Ulaşım katmanı (ADR-006 soyutlaması)
 * ========================================================= */

export interface KdsFeed {
    /** İlk tam yükleme. */
    load(): Promise<void>;
    /** Periyodik takibi başlat/durdur. */
    start(): void;
    stop(): void;
    /** Eylem sonrası zorunlu tazeleme (cursor sıfırlanır). */
    refresh(): Promise<void>;
}

interface FeedOptions<T extends { cursor: number }> {
    /** Tam kuyruk isteği (ör. /api/v1/kds/queue?...). */
    fetchFull: () => Promise<T>;
    /** Delta isteği; 204 (değişiklik yok) → null döner. */
    fetchDelta: (cursor: number) => Promise<T | null>;
    onData: (payload: T) => void;
    onError?: (e: unknown) => void;
    intervalMs: number;
}

/**
 * Cursor'lı polling ulaşımı: 3-5 sn'de bir `updates` ucuna sorar; sunucu
 * değişiklik yoksa 204 döndürür (tek indeksli MAX sorgusu — ADR-006).
 * Sekme gizliyken yoklama yavaşlar (×4) — mutfak tableti ekranı açık tutar.
 */
export function createPollingFeed<T extends { cursor: number }>(opts: FeedOptions<T>): KdsFeed {
    let cursor = 0;
    let timer: ReturnType<typeof setTimeout> | null = null;
    let running = false;
    let busy = false;

    async function tick(): Promise<void> {
        if (!running) return;
        if (!busy) {
            busy = true;
            try {
                const payload = await opts.fetchDelta(cursor);
                if (payload) {
                    cursor = payload.cursor;
                    opts.onData(payload);
                }
            } catch (e) {
                opts.onError?.(e);
            } finally {
                busy = false;
            }
        }
        schedule();
    }

    function schedule(): void {
        if (!running) return;
        // Ekran arka plandayken hafif yavaşlar (×2), tamamen durmaz — adanmış
        // mutfak/terminal ekranı öne gelmeden de yeni siparişi yakında yakalar.
        const hidden = typeof document !== 'undefined' && document.hidden;
        timer = setTimeout(() => void tick(), hidden ? opts.intervalMs * 2 : opts.intervalMs);
    }

    async function load(): Promise<void> {
        const payload = await opts.fetchFull();
        cursor = payload.cursor;
        opts.onData(payload);
    }

    return {
        load,
        start(): void {
            if (running) return;
            running = true;
            schedule();
        },
        stop(): void {
            running = false;
            if (timer) clearTimeout(timer);
            timer = null;
        },
        async refresh(): Promise<void> {
            await load();
        },
    };
}

/** GET; 204 → null (değişiklik yok). */
export async function getOrNull<T>(path: string): Promise<T | null> {
    const res = (await api<T | undefined>(path)) as T | undefined;
    return res ?? null;
}

/* =========================================================
 |  Tema: KDS ekranının KENDİ açık/koyu tercihi — panelin genel tema
 |  ayarından BAĞIMSIZ. Varsayılan AÇIK; ekran/cihaz kendi seçimini
 |  localStorage'da ('kds_theme') tutar (duvar ekranı sabit kalır).
 |  Panelin 'theme' anahtarına DOKUNULMAZ — --ui-* token'ları aynen
 |  kullanılır, yalnız bu ekranda hangi kademenin (light/dark) aktif
 |  olduğu bağımsız seçilir.
 * ========================================================= */

export type KdsTheme = 'light' | 'dark';

const KDS_THEME_STORAGE_KEY = 'kds_theme';

function readStoredKdsTheme(): KdsTheme {
    try {
        return localStorage.getItem(KDS_THEME_STORAGE_KEY) === 'dark' ? 'dark' : 'light';
    } catch {
        return 'light';
    }
}

let kdsActiveCount = 0;
let savedTheme: string | undefined;

/**
 * KDS ekranı süresince <html data-theme> bu ekranın kendi tercihine göre
 * ayarlanır (varsayılan: light). Dönen `release()` panelin önceki temasını
 * geri yükler; sayaç, Inertia sayfa geçişinde mount/unmount sırası ne
 * olursa olsun (Mutfak → Komi) temanın yanlışlıkla geri dönmesini engeller.
 */
export function useKdsTheme(): { theme: Ref<KdsTheme>; toggle: () => void; release: () => void } {
    const theme = ref<KdsTheme>(readStoredKdsTheme());

    if (typeof document === 'undefined') {
        return { theme, toggle: () => {}, release: () => {} };
    }

    const el = document.documentElement;
    if (kdsActiveCount === 0) savedTheme = el.dataset.theme;
    kdsActiveCount++;
    el.dataset.theme = theme.value;

    function toggle(): void {
        theme.value = theme.value === 'dark' ? 'light' : 'dark';
        el.dataset.theme = theme.value;
        try {
            localStorage.setItem(KDS_THEME_STORAGE_KEY, theme.value);
        } catch {
            /* gizli mod vb. — bu oturumda hatırlanmaz, işlevi bozmaz */
        }
    }

    let released = false;
    function release(): void {
        if (released) return;
        released = true;
        kdsActiveCount--;
        if (kdsActiveCount === 0) el.dataset.theme = savedTheme ?? 'light';
    }

    return { theme, toggle, release };
}

/* =========================================================
 |  SLA (bekleme süresi) — renk + ikon + metin BİRLİKTE
 * ========================================================= */

export type SlaLevel = 'ok' | 'warn' | 'late';

export function minutesSince(iso: string | null, skewMs = 0): number {
    if (!iso) return 0;
    return Math.max(0, Math.floor((Date.now() - skewMs - new Date(iso).getTime()) / 60000));
}

export function slaLevel(waitMinutes: number, targetMinutes: number, lateRatio: number): SlaLevel {
    if (waitMinutes >= Math.ceil(targetMinutes * lateRatio)) return 'late';
    if (waitMinutes >= targetMinutes) return 'warn';
    return 'ok';
}

export function slaText(mins: number): string {
    if (mins < 60) return `${mins} dk`;
    return `${Math.floor(mins / 60)} sa ${String(mins % 60).padStart(2, '0')} dk`;
}

/**
 * Bekleme çipi sınıfları — panel rozet dilinin büyütülmüş hali. Tek sinyal
 * ilkesi: aciliyet YALNIZ bu çipte renklenir; "late" durumunda metne
 * "gecikti" sözcüğü eklenir (renk körlüğü desteği ekranda).
 *
 * "late" DOLU (solid) kırmızı kullanır: soft-danger ikilisi (bg-danger-soft
 * + text-danger) açık temada ölçülen 4.41:1 ile AA metin eşiğinin (4.5:1)
 * az altında kalıyor. Dolu bg-danger + text-on-status açık temada 4.83:1,
 * koyu temada 6.32:1 — her iki temada da AA geçer; en acil durumu ayrıca
 * daha da güçlü vurgular.
 */
export function waitChipClass(level: SlaLevel): string {
    if (level === 'late') return 'border-danger bg-danger text-on-status';
    if (level === 'warn') return 'border-warning-border bg-warning-soft text-warning';
    return 'border-default bg-inset text-muted';
}

/* =========================================================
 |  Ses uyarısı (tarayyıcı otomatik-oynatma kısıtına saygılı)
 * ========================================================= */

/**
 * WebAudio bip sesi — dış ses dosyası yok. Tarayıcılar kullanıcı etkileşimi
 * olmadan ses başlatmaz: ilk dokunuşta `unlock()` çağrılır; kullanıcı
 * tercihi localStorage'da saklanır.
 */
export function createKdsSound(storageKey = 'kds_sound') {
    let ctx: AudioContext | null = null;
    let unlocked = false;

    function enabled(): boolean {
        return localStorage.getItem(storageKey) !== 'off';
    }

    function setEnabled(on: boolean): void {
        localStorage.setItem(storageKey, on ? 'on' : 'off');
    }

    function unlock(): void {
        if (unlocked) return;
        try {
            ctx = ctx ?? new AudioContext();
            if (ctx.state === 'suspended') void ctx.resume();
            unlocked = true;
        } catch {
            /* ses desteklenmiyor */
        }
    }

    function beep(times = 2): void {
        if (!enabled() || !unlocked || !ctx) return;
        try {
            const now = ctx.currentTime;
            for (let i = 0; i < times; i++) {
                const osc = ctx.createOscillator();
                const gain = ctx.createGain();
                osc.type = 'sine';
                osc.frequency.value = 880;
                gain.gain.setValueAtTime(0.0001, now + i * 0.35);
                gain.gain.exponentialRampToValueAtTime(0.4, now + i * 0.35 + 0.02);
                gain.gain.exponentialRampToValueAtTime(0.0001, now + i * 0.35 + 0.3);
                osc.connect(gain).connect(ctx.destination);
                osc.start(now + i * 0.35);
                osc.stop(now + i * 0.35 + 0.32);
            }
        } catch {
            /* sessiz geç */
        }
    }

    return { enabled, setEnabled, unlock, beep };
}

/* =========================================================
 |  Ortak küçük yardımcılar
 * ========================================================= */

export function metaFromKdsProps(props: Record<string, unknown>): {
    stations: StationRow[];
    allowedStations: string[] | null;
    itemStatuses: VariantMeta[];
    channels: VariantMeta[];
    config: KdsConfig;
    canManageStations: boolean;
    canDeliver: boolean;
} {
    return {
        stations: (props.stations as StationRow[]) ?? [],
        allowedStations: (props.allowedStations as string[] | null) ?? null,
        itemStatuses: (props.itemStatuses as VariantMeta[]) ?? [],
        channels: (props.channels as VariantMeta[]) ?? [],
        config: (props.kdsConfig as KdsConfig) ?? {
            poll_interval_seconds: 4,
            default_prep_minutes: 15,
            late_ratio: 1.5,
            unassigned_key: '_none',
        },
        canManageStations: Boolean(props.canManageStations),
        canDeliver: Boolean(props.canDeliver),
    };
}
