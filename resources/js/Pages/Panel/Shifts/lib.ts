/** Shifts modülü tarih/süre yardımcıları (dış kütüphane yok). */

/** Dakikayı "7s 30dk" biçimine çevirir. */
export function fmtMin(min: number | null | undefined): string {
    if (min === null || min === undefined) return '—';
    const h = Math.floor(min / 60);
    const m = min % 60;
    if (h === 0) return `${m}dk`;
    if (m === 0) return `${h}s`;
    return `${h}s ${m}dk`;
}

/** ISO tarihten "09:00" saati. */
export function fmtTime(iso: string | null | undefined): string {
    if (!iso) return '—';
    const d = new Date(iso);
    return d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
}

/** ISO tarihten "23 Tem" gibi kısa tarih. */
export function fmtDate(iso: string | null | undefined): string {
    if (!iso) return '—';
    const d = new Date(iso);
    return d.toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' });
}

export function fmtDateTime(iso: string | null | undefined): string {
    if (!iso) return '—';
    const d = new Date(iso);
    return d.toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' }) + ' ' + fmtTime(iso);
}

/** Kuruş → "1.234,56 ₺". */
export function fmtMoney(minor: number): string {
    return (minor / 100).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' ₺';
}

/** Yerel saat diliminde YYYY-MM-DD. */
export function ymd(d: Date): string {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}

/** Haftanın pazartesisi (yerel). */
export function startOfWeek(d: Date): Date {
    const copy = new Date(d);
    const day = (copy.getDay() + 6) % 7; // 0=Pzt
    copy.setDate(copy.getDate() - day);
    copy.setHours(0, 0, 0, 0);
    return copy;
}

export function addDays(d: Date, n: number): Date {
    const copy = new Date(d);
    copy.setDate(copy.getDate() + n);
    return copy;
}

/** ISO string'in yerel gün anahtarı (YYYY-MM-DD). */
export function dayKey(iso: string): string {
    return ymd(new Date(iso));
}

/** "YYYY-MM-DD" + "HH:MM" → "YYYY-MM-DD HH:MM:00" (sunucuya yerel saat). */
export function joinDateTime(date: string, time: string): string {
    return `${date} ${time}:00`;
}

/** ISO'dan "HH:MM". */
export function timeOf(iso: string): string {
    const d = new Date(iso);
    return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
}

/** Hafta başlıkları (startOfWeek Pazartesi tabanlıdır). */
export const WEEKDAY_LABELS = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
