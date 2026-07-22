/** TR yerel biçimleri: tarih/saat/para. Tüm ekranlar bunları kullanır. */

const dateFmt = new Intl.DateTimeFormat('tr-TR', { day: 'numeric', month: 'long', year: 'numeric' });
const dateTimeFmt = new Intl.DateTimeFormat('tr-TR', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
});
const longDateFmt = new Intl.DateTimeFormat('tr-TR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
});
const currencyFmt = new Intl.NumberFormat('tr-TR', { style: 'currency', currency: 'TRY' });
const numberFmt = new Intl.NumberFormat('tr-TR');

export const formatDate = (value: string | Date): string => dateFmt.format(new Date(value));
export const formatDateTime = (value: string | Date): string => dateTimeFmt.format(new Date(value));
export const formatLongDate = (value: string | Date): string => longDateFmt.format(new Date(value));
export const formatNumber = (value: number): string => numberFmt.format(value);

/** Kuruş (minor) cinsinden tutarı ₺ olarak biçimler. */
export const formatCurrencyMinor = (minor: number): string => currencyFmt.format(minor / 100);

/** "3 dakika önce" tarzı göreli zaman (oturum listesi için). */
export function formatRelative(value: string | Date): string {
    const rtf = new Intl.RelativeTimeFormat('tr-TR', { numeric: 'auto' });
    const diffSec = Math.round((new Date(value).getTime() - Date.now()) / 1000);
    const abs = Math.abs(diffSec);

    if (abs < 60) return rtf.format(Math.trunc(diffSec / 1), 'second');
    if (abs < 3600) return rtf.format(Math.trunc(diffSec / 60), 'minute');
    if (abs < 86400) return rtf.format(Math.trunc(diffSec / 3600), 'hour');
    return rtf.format(Math.trunc(diffSec / 86400), 'day');
}
