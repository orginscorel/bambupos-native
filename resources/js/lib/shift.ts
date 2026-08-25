/**
 * Mesai/vardiya saatini DÖNEME göre renklendirme — okurken hızlı ayırt etmek
 * için (sabah / gündüz / akşam / gece). Başlangıç saatine göre. Renkler açık
 * ve koyu temada okunur: /15-20 opak zemin + orta-ton metin (her iki temada
 * yeterli kontrast). Tailwind bu literal sınıfları kaynak taramasında görür.
 */
export function shiftTone(iso: string): string {
    const h = new Date(iso).getHours();
    if (h >= 5 && h < 11) return 'bg-amber-400/15 text-amber-600'; // sabah
    if (h >= 11 && h < 17) return 'bg-sky-400/15 text-sky-600'; // gündüz
    if (h >= 17 && h < 22) return 'bg-orange-400/15 text-orange-600'; // akşam
    return 'bg-indigo-400/20 text-indigo-500'; // gece
}

export function shiftPeriodLabel(iso: string): string {
    const h = new Date(iso).getHours();
    if (h >= 5 && h < 11) return 'Sabah';
    if (h >= 11 && h < 17) return 'Gündüz';
    if (h >= 17 && h < 22) return 'Akşam';
    return 'Gece';
}
