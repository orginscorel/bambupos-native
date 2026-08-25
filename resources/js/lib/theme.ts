/**
 * KİRACI PANEL TEMASI — marka rengi + font uygulaması.
 *
 * Tasarım sistemi katmanlı (resources/css/app.css): --brand-* HAM marka skalası,
 * --ui-primary/accent/link/focus/soft HEPSİ --brand-*'tan TÜRETİLİR. Bu yüzden
 * yalnız --brand-50..900'ü :root'ta ezmek TÜM vurgu renklerini değiştirir; semantik
 * gri tonlar (bg/text/border) DEĞİŞMEZ → kontrast/erişilebilirlik korunur.
 *
 * Font: --font-sans + body.style.fontFamily (yeni dosya indirilmez; mevcut Poppins
 * veya sistem/serif/mono yığınları). Mod: kullanıcı elle seçmediyse kiracı varsayılanı.
 */

export interface TenantTheme {
    primary?: string | null;
    accent?: string | null;
    font?: string | null;
    mode?: string | null;
}

const FONT_STACKS: Record<string, string> = {
    poppins: "'Poppins', system-ui, -apple-system, sans-serif",
    system: "system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
    serif: "Georgia, Cambria, 'Times New Roman', Times, serif",
    mono: "ui-monospace, 'Courier New', Menlo, Consolas, monospace",
    rounded: "'Poppins', 'Trebuchet MS', 'Segoe UI', system-ui, sans-serif",
};

const BRAND_KEYS = ['50', '100', '200', '300', '400', '500', '600', '700', '800', '900'];

type Rgb = [number, number, number];

function hexToRgb(hex: string): Rgb | null {
    const m = /^#([0-9a-f]{6})$/i.exec(hex.trim());
    if (!m) return null;
    const n = parseInt(m[1], 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function toHex(r: number, g: number, b: number): string {
    const h = (v: number): string => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0');
    return `#${h(r)}${h(g)}${h(b)}`;
}

function mix(a: Rgb, b: Rgb, t: number): string {
    return toHex(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t);
}

/** Tek marka renginden 50–900 skalası üretir (600 = seçilen renk). */
export function brandScaleFrom(primary: string): Record<string, string> | null {
    const p = hexToRgb(primary);
    if (!p) return null;
    const white: Rgb = [255, 255, 255];
    const black: Rgb = [0, 0, 0];
    return {
        '50': mix(p, white, 0.92),
        '100': mix(p, white, 0.84),
        '200': mix(p, white, 0.66),
        '300': mix(p, white, 0.46),
        '400': mix(p, white, 0.24),
        '500': mix(p, white, 0.1),
        '600': primary,
        '700': mix(p, black, 0.16),
        '800': mix(p, black, 0.32),
        '900': mix(p, black, 0.46),
    };
}

export function applyTenantTheme(theme: TenantTheme | null | undefined): void {
    if (typeof document === 'undefined') return;
    const root = document.documentElement;

    // Marka rengi → --brand-* skalası (yoksa tasarım varsayılanına dön).
    const scale = theme?.primary ? brandScaleFrom(theme.primary) : null;
    if (scale) {
        for (const k of BRAND_KEYS) root.style.setProperty(`--brand-${k}`, scale[k]);
    } else {
        for (const k of BRAND_KEYS) root.style.removeProperty(`--brand-${k}`);
    }

    // Font.
    const font = theme?.font && FONT_STACKS[theme.font] ? FONT_STACKS[theme.font] : null;
    if (font) {
        root.style.setProperty('--font-sans', font);
        if (document.body) document.body.style.fontFamily = font;
    } else {
        root.style.removeProperty('--font-sans');
        if (document.body) document.body.style.fontFamily = '';
    }

    // Mod: kullanıcı ELLE seçmediyse (localStorage 'theme' yoksa) kiracı varsayılanı.
    try {
        const userPref = localStorage.getItem('theme');
        if (!userPref && (theme?.mode === 'dark' || theme?.mode === 'light')) {
            root.dataset.theme = theme.mode;
        }
    } catch {
        /* yut */
    }
}
