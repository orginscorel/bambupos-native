/**
 * §13 (Faz D) — Terminal OTOMATİK KİLİTLEME (boşta-kalma / idle-lock).
 *
 * SORUN (denetim §3a): kasa/sipariş-girişi/KDS terminallerinde AKTİF OPERATÖR
 * varken cihaz fiziksel olarak terk edilirse ekran açık ve veriler (adisyon,
 * tutar) görünür kalırdı — hiçbir zaman-bazlı ekran kilidi yoktu. Bu
 * composable belirli bir süre ETKİLEŞİMSİZ (fare/dokunma/klavye yok) kalınca
 * `locked` bayrağını AÇAR; ekranı tümüyle örten LockOverlay bileşeni bu
 * bayrağı okuyup tek-PIN ile devam ettirir.
 *
 * BİLİNÇLİ AYRIM (audit önerisi #4): sunucudaki `TerminalOperator`
 * IDLE_MINUTES=10 AKTİF OPERATÖRÜ tamamen düşürür (yeniden personel SEÇİMİ +
 * PIN gerekir — TerminalOperatorGate). Bu composable ONDAN AYRI, daha erken
 * devreye giren, YALNIZ İSTEMCİ tarafı bir "ekran kilidi"dir — operatör
 * kimliği KORUNUR; unlock tek PIN'le olur, personel yeniden SEÇİLMEZ (#183:
 * aktif operatör varken gereksiz sürtünme yaratılmaz).
 *
 * Süre: çağıran `minutes` verebilir; vermezse `auth.terminal_idle_lock_minutes`
 * paylaşılan Inertia prop'undan (ileride bir "terminal ayarı" eklenirse) okunur;
 * o da yoksa DEFAULT_IDLE_LOCK_MINUTES kullanılır.
 *
 * DÜZELTME 2026-08-06 (URL girince oto-kilit): `locked` DAİMA `false` ile
 * başlıyordu → terminal URL'ine (yeni sekme/yenileme/uzun aradan sonra geri
 * dönüş) girildiğinde, aktif operatör olsa BİLE ekran açık geliyordu; yalnız
 * "boşta kalınca" tetikleniyordu. Artık İLK durum hesaplanır (bkz.
 * `initialLocked`): terminal + aktif operatör varken varsayılan KİLİTLİ başlar.
 * AŞIRI SÜRTÜNME olmasın diye: her başarılı unlock() bir `sessionStorage`
 * damgası (yalnız opak zaman damgası — PII yok) bırakır; bu composable AYNI
 * SEKMEDE (JS modül durumu bir tam yenilemede sıfırlanır, Inertia SPA
 * gezinmesinde SIFIRLANMAZ — bu ayrım `jsSessionLive` ile yapılır) kısa süre
 * (SOFT_NAV_GRACE_MS) içinde YENİDEN monte olursa (ör. Kitchen→Board gibi
 * terminal ekranları arası iç nav) kilit YENİDEN sorulmaz. Ama YENİ
 * sekme/pencere, tam sayfa yenileme (F5) veya uzun aradan sonra dönüş
 * `jsSessionLive` sıfır bulunacağından HER ZAMAN kilitli başlar — damga
 * içeride olsa bile. #183 (aktif operatör varken gereksiz PIN yok) KORUNUR:
 * bu yalnız İLK bağlanma anını etkiler; `enabled` sonradan false→true olursa
 * (ör. TerminalOperatorGate'te az önce PIN girildi) aşağıdaki `watch` hâlâ
 * kilitlemez.
 */
import { onBeforeUnmount, onMounted, ref, watch, type Ref } from 'vue';
import { usePage } from '@inertiajs/vue3';

export const DEFAULT_IDLE_LOCK_MINUTES = 3;

/** Boşta-kalma kontrolü bu sıklıkla yapılır (gerçek zamanlı setTimeout yerine
 *  poll — arka plan sekmesinde tarayıcı zamanlayıcı kısıtlamalarına dayanıklı). */
const CHECK_INTERVAL_MS = 5000;

const ACTIVITY_EVENTS = ['pointerdown', 'mousemove', 'keydown', 'touchstart', 'wheel'] as const;

/** "Az önce PIN girdim" damgası — yalnız zaman damgası (opak sayı), PII yok. */
const UNLOCK_STAMP_KEY = 'bhx_terminal_unlocked_at';

/** Bu pencerede son unlock'tan sonra bu süre içindeki İÇ (Inertia SPA)
 *  gezinme yeniden PIN sormaz — 15-30 sn aralığının ortası. */
export const SOFT_NAV_GRACE_MS = 20000;

/**
 * Modül-seviyesi (bileşen değil) bayrak: bu SEKME/pencerenin JS yürütme
 * bağlamında daha önce bir terminal idle-lock örneği zaten monte olmuş mu?
 * Tam sayfa yenileme / yeni sekme / yeni pencere JS modül grafiğini SIFIRLAR
 * (bu değişken de `false`'a döner) — ama Inertia SPA gezinmesi (Link tıklama)
 * sayfayı yeniden YÜKLEMEZ, aynı modül durumu KORUNUR. Bu yüzden bu bayrak,
 * "gerçekten yeni bir URL girişi mi yoksa uygulama-içi geçiş mi" ayrımını
 * sessionStorage'ın TEK BAŞINA yapamadığı yerde tamamlar (sessionStorage hem
 * yenilemede hem SPA gezinmesinde aynen kalır).
 */
let jsSessionLive = false;

function readUnlockStamp(): number | null {
    try {
        const v = sessionStorage.getItem(UNLOCK_STAMP_KEY);
        if (!v) return null;
        const n = Number(v);
        return Number.isFinite(n) ? n : null;
    } catch {
        return null; // gizli mod vb. — güvenli taraf: damga yok say (kilitli başlar)
    }
}

function writeUnlockStamp(): void {
    try {
        sessionStorage.setItem(UNLOCK_STAMP_KEY, String(Date.now()));
    } catch {
        /* sessionStorage engelliyse yalnız yumuşak-geçiş ayrıcalığı çalışmaz */
    }
}

export interface UseTerminalIdleLockOptions {
    /** Kilit yalnız bu true iken izlenir (ör. terminal + aktif operatör var).
     *  Verilmezse her zaman izlenir. */
    enabled?: Ref<boolean>;
    /** Dakika cinsinden boşta-kalma süresi; verilmezse terminal ayarından/varsayılandan okunur. */
    minutes?: number;
}

export interface UseTerminalIdleLockReturn {
    /** true olunca çağıran LockOverlay'i göstermeli. */
    locked: Ref<boolean>;
    /** Başarılı PIN sonrası: kilidi kaldır + boşta-kalma sayacını sıfırla. */
    unlock: () => void;
    /** Elle/anında kilitle (ör. "Ekranı kilitle" düğmesi ileride eklenirse). */
    lockNow: () => void;
}

export function useTerminalIdleLock(options: UseTerminalIdleLockOptions = {}): UseTerminalIdleLockReturn {
    const page = usePage();

    function resolveMinutes(): number {
        if (typeof options.minutes === 'number' && options.minutes > 0) return options.minutes;
        const fromSettings = (page.props.auth as { terminal_idle_lock_minutes?: number } | null)
            ?.terminal_idle_lock_minutes;
        return typeof fromSettings === 'number' && fromSettings > 0 ? fromSettings : DEFAULT_IDLE_LOCK_MINUTES;
    }

    function isEnabled(): boolean {
        return options.enabled ? options.enabled.value : true;
    }

    /* Bu mount'tan ÖNCE aynı sekmede zaten bir örnek çalışmış mıydı? (Inertia
     * SPA gezinmesiyle bir terminal ekranından diğerine geçiş — DOM/JS modülü
     * sıfırlanmadı.) Tam yenileme/yeni sekmede bu HER ZAMAN false'tur. */
    const wasJsSessionLive = jsSessionLive;
    jsSessionLive = true;

    /** İLK `locked` durumu (mount anı) — bkz. dosya başı DÜZELTME notu. */
    function initialLocked(): boolean {
        if (!isEnabled()) return false;
        if (!wasJsSessionLive) return true; // gerçek yeni URL girişi/yenileme/yeni sekme
        const ts = readUnlockStamp();
        if (ts !== null && Date.now() - ts <= SOFT_NAV_GRACE_MS) return false; // yumuşak iç gezinme
        return true;
    }

    const locked = ref(initialLocked());
    let lastActivity = Date.now();
    let checkTimer: ReturnType<typeof setInterval> | null = null;

    function markActivity(): void {
        lastActivity = Date.now();
    }

    function checkIdle(): void {
        if (locked.value || !isEnabled()) return;
        if (Date.now() - lastActivity >= resolveMinutes() * 60000) {
            locked.value = true;
        }
    }

    function unlock(): void {
        locked.value = false;
        markActivity();
        writeUnlockStamp(); // yumuşak iç gezinme penceresini başlat/tazele
    }

    function lockNow(): void {
        locked.value = true;
    }

    // enabled false → true geçişinde (ör. az önce operatör seçildi) sayaç
    // sıfırlanır — devre dışıyken biriken "boşta" süresi kilidi tetiklemesin.
    if (options.enabled) {
        watch(options.enabled, (en) => {
            if (en) markActivity();
        });
    }

    onMounted(() => {
        markActivity();
        for (const ev of ACTIVITY_EVENTS) {
            document.addEventListener(ev, markActivity, { passive: true });
        }
        checkTimer = setInterval(checkIdle, CHECK_INTERVAL_MS);
    });

    onBeforeUnmount(() => {
        for (const ev of ACTIVITY_EVENTS) {
            document.removeEventListener(ev, markActivity);
        }
        if (checkTimer) clearInterval(checkTimer);
    });

    return { locked, unlock, lockNow };
}
