/**
 * Genel bildirim ses uyarısı — WebAudio bip (dış ses dosyası / kütüphane YOK).
 *
 * kds.ts'teki `createKdsSound` deseninin yeniden kullanılabilir, uygulama
 * genelinde TEK ÖRNEKLİ (singleton) hâli: tüm kabuklar ve composable'lar aynı
 * AudioContext'i, unlock durumunu ve "bu cihazda ses" tercihini paylaşır.
 *
 * Tarayıcılar kullanıcı jesti olmadan ses başlatmaz: ilk pointerdown/keydown'da
 * AudioContext resume edilir (`unlock`). Tercih localStorage'da saklanır ve
 * reaktif `enabled` ref'i ile okunur/yazılır.
 */
import { ref } from 'vue';

const STORAGE_KEY = 'notif_sound';

function readEnabled(): boolean {
    try {
        return localStorage.getItem(STORAGE_KEY) !== 'off';
    } catch {
        return true;
    }
}

/* Modül-kapsamlı tekil durum (import edildiği her yerde aynı örnek). */
const enabled = ref<boolean>(readEnabled());
let ctx: AudioContext | null = null;
let unlocked = false;
let gestureBound = false;

type AudioContextCtor = new () => AudioContext;

function resolveAudioContext(): AudioContextCtor | null {
    if (typeof window === 'undefined') return null;
    const w = window as unknown as { AudioContext?: AudioContextCtor; webkitAudioContext?: AudioContextCtor };
    return w.AudioContext ?? w.webkitAudioContext ?? null;
}

/** İlk kullanıcı jestinde AudioContext'i resume et (otomatik-oynatma kısıtı). */
function unlock(): void {
    if (unlocked) return;
    try {
        const Ctor = resolveAudioContext();
        if (!Ctor) return;
        ctx = ctx ?? new Ctor();
        if (ctx.state === 'suspended') void ctx.resume();
        unlocked = true;
    } catch {
        /* ses desteklenmiyor — sessiz geç */
    }
}

/** Belge geneline BİR kez ilk-jest dinleyicisi bağla (unlock için). */
function bindFirstGesture(): void {
    if (gestureBound || typeof document === 'undefined') return;
    gestureBound = true;
    const handler = (): void => {
        unlock();
        document.removeEventListener('pointerdown', handler);
        document.removeEventListener('keydown', handler);
    };
    document.addEventListener('pointerdown', handler);
    document.addEventListener('keydown', handler);
}

/** `times` kez kısa bip. Ses kapalı / henüz unlock edilmemişse sessizce döner. */
function beep(times = 2): void {
    if (!enabled.value || !unlocked || !ctx) return;
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

function setEnabled(on: boolean): void {
    enabled.value = on;
    try {
        localStorage.setItem(STORAGE_KEY, on ? 'on' : 'off');
    } catch {
        /* gizli mod vb. — bu oturumda hatırlanmaz, işlevi bozmaz */
    }
    // Açılırken kullanıcı zaten bir jest yapmış olur → hemen unlock dene.
    if (on) unlock();
}

function toggle(): void {
    setEnabled(!enabled.value);
}

export function useNotificationSound() {
    bindFirstGesture();
    return { enabled, beep, unlock, setEnabled, toggle };
}
