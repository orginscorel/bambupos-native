<script setup lang="ts">
import { computed } from 'vue';

/**
 * Masa kartlarının üst görsel alanı için tamamen inline (dış asset/CDN YOK,
 * CSP-güvenli) izometrik 3D vektörel masa illüstrasyonu.
 *
 * Renk stratejisi: gövde monokromdur ve `currentColor` üzerinden kurulur; kart
 * `text-primary` (dolu) veya `text-subtle` (boş) sınıfını verir, böylece açık/
 * koyu tema ve turuncu marka paletiyle otomatik uyumludur. Doluluk vurgusu için
 * yalnız yemek ipuçları (tabak/bardak) sabit tok'larla boyanır.
 *
 * Şekle (yuvarlak/kare/dikdörtgen/oval/loca/bar taburesi) ve kapasiteye
 * (sandalye sayısı) göre uyarlanır.
 */
const props = withDefaults(
    defineProps<{
        shape?: string;
        capacity?: number;
        busy?: boolean;
    }>(),
    { shape: 'square', capacity: 4, busy: false },
);

const CX = 70;
const CY = 52;
const KX = 0.86;
const KY = 0.5;
const TH = 8; // masa kalınlığı (izometrik yükseklik)

type Kind = 'round' | 'rect' | 'stool';

const kind = computed<Kind>(() => {
    if (props.shape === 'bar_stool') return 'stool';
    if (props.shape === 'round' || props.shape === 'oval') return 'round';
    return 'rect';
});

/** Zeminde yarı-genişlik (u) ve yarı-derinlik (v) — px cinsi. */
const extent = computed<{ u: number; v: number }>(() => {
    switch (props.shape) {
        case 'rectangle':
            return { u: 34, v: 19 };
        case 'booth':
            return { u: 32, v: 20 };
        case 'oval':
            return { u: 30, v: 20 };
        case 'round':
            return { u: 25, v: 25 };
        case 'bar_stool':
            return { u: 12, v: 12 };
        default: // square
            return { u: 23, v: 23 };
    }
});

function iso(u: number, v: number): { x: number; y: number } {
    return { x: CX + (u - v) * KX, y: CY + (u + v) * KY };
}

/* ---- Yuvarlak/oval masa: izometrik elips ---- */
const ell = computed(() => {
    const { u, v } = extent.value;
    // zemindeki daireyi/elipsi izometriğe yansıt: eksen-hizalı elips
    return { rx: u * KX * 1.414, ry: v * KY * 1.414 };
});

const ellSidePath = computed(() => {
    const { rx, ry } = ell.value;
    const l = CX - rx;
    const r = CX + rx;
    return `M ${l} ${CY} L ${l} ${CY + TH} A ${rx} ${ry} 0 0 0 ${r} ${CY + TH} L ${r} ${CY} A ${rx} ${ry} 0 0 1 ${l} ${CY} Z`;
});

/* ---- Kare/dikdörtgen/loca masa: izometrik dörtgen ---- */
const quad = computed(() => {
    const { u, v } = extent.value;
    const p = {
        top: iso(-u, -v), // arka
        right: iso(u, -v),
        bottom: iso(u, v), // ön
        left: iso(-u, v),
    };
    return p;
});

const quadTopPoints = computed(() => {
    const q = quad.value;
    return `${q.top.x},${q.top.y} ${q.right.x},${q.right.y} ${q.bottom.x},${q.bottom.y} ${q.left.x},${q.left.y}`;
});

// ön iki yüzeyin (sağ-alt ve sol-alt kenar) aşağı ekstrüzyonu
const quadSideRight = computed(() => {
    const q = quad.value;
    return `${q.right.x},${q.right.y} ${q.bottom.x},${q.bottom.y} ${q.bottom.x},${q.bottom.y + TH} ${q.right.x},${q.right.y + TH}`;
});
const quadSideLeft = computed(() => {
    const q = quad.value;
    return `${q.left.x},${q.left.y} ${q.bottom.x},${q.bottom.y} ${q.bottom.x},${q.bottom.y + TH} ${q.left.x},${q.left.y + TH}`;
});

/* ---- Sandalyeler ---- */
interface Chair {
    x: number;
    y: number;
    behind: boolean;
}
const chairs = computed<Chair[]>(() => {
    const n =
        kind.value === 'stool'
            ? Math.min(Math.max(props.capacity, 1), 2)
            : Math.min(Math.max(props.capacity, 2), 8);
    const { u, v } = extent.value;
    const gap = kind.value === 'stool' ? 8 : 15;
    const rU = u + gap;
    const rV = v + gap;
    const out: Chair[] = [];
    for (let i = 0; i < n; i++) {
        const t = -Math.PI / 2 + (i * 2 * Math.PI) / n;
        const p = iso(rU * Math.cos(t), rV * Math.sin(t));
        out.push({ x: p.x, y: p.y, behind: Math.sin(t) < -0.15 });
    }
    return out;
});
const chairsBehind = computed(() => chairs.value.filter((c) => c.behind));
const chairsFront = computed(() => chairs.value.filter((c) => !c.behind));

/* ---- Dolu masadaki yemek ipuçları (tabak/bardak) ---- */
const plates = computed(() => {
    if (!props.busy) return [];
    if (kind.value === 'stool') return [{ x: CX, y: CY - 1, r: 6 }];
    const { u } = extent.value;
    const spread = Math.min(u * 0.55, 16);
    return [
        { x: CX - spread, y: CY + 3, r: 7 },
        { x: CX + spread, y: CY - 2, r: 7 },
    ];
});
</script>

<template>
    <svg
        class="block h-full w-full"
        viewBox="0 0 140 104"
        role="img"
        :aria-label="busy ? 'Dolu masa önizlemesi' : 'Boş masa önizlemesi'"
        preserveAspectRatio="xMidYMid meet"
    >
        <defs>
            <radialGradient :id="`glow-${busy ? 'on' : 'off'}`" cx="50%" cy="55%" r="60%">
                <stop offset="0%" stop-color="currentColor" :stop-opacity="busy ? 0.28 : 0.08" />
                <stop offset="100%" stop-color="currentColor" stop-opacity="0" />
            </radialGradient>
        </defs>

        <!-- doluluk parıltısı / zemin -->
        <rect x="0" y="0" width="140" height="104" :fill="`url(#glow-${busy ? 'on' : 'off'})`" />
        <!-- zemin gölgesi -->
        <ellipse :cx="CX" :cy="CY + 26" rx="52" ry="12" fill="currentColor" opacity="0.1" />

        <!-- arka sandalyeler -->
        <g v-for="(c, i) in chairsBehind" :key="`b${i}`">
            <ellipse :cx="c.x" :cy="c.y - 4" rx="8" ry="5" fill="currentColor" opacity="0.6" />
            <ellipse :cx="c.x" :cy="c.y" rx="8.5" ry="5" fill="currentColor" opacity="0.42" />
        </g>

        <!-- ==== YUVARLAK / OVAL / BAR ==== -->
        <template v-if="kind !== 'rect'">
            <path :d="ellSidePath" fill="currentColor" opacity="0.34" />
            <ellipse :cx="CX" :cy="CY" :rx="ell.rx" :ry="ell.ry" fill="currentColor" opacity="0.16" />
            <ellipse
                :cx="CX"
                :cy="CY"
                :rx="ell.rx"
                :ry="ell.ry"
                fill="none"
                stroke="currentColor"
                stroke-width="1.4"
                opacity="0.85"
            />
            <!-- merkez bağlantı ışıltısı -->
            <ellipse :cx="CX" :cy="CY - 1.5" :rx="ell.rx * 0.5" :ry="ell.ry * 0.5" fill="currentColor" opacity="0.06" />
        </template>

        <!-- ==== KARE / DİKDÖRTGEN / LOCA ==== -->
        <template v-else>
            <polygon :points="quadSideLeft" fill="currentColor" opacity="0.4" />
            <polygon :points="quadSideRight" fill="currentColor" opacity="0.28" />
            <polygon :points="quadTopPoints" fill="currentColor" opacity="0.16" />
            <polygon
                :points="quadTopPoints"
                fill="none"
                stroke="currentColor"
                stroke-width="1.4"
                stroke-linejoin="round"
                opacity="0.85"
            />
        </template>

        <!-- yemek ipuçları (yalnız dolu): tabaklar + bardak -->
        <template v-if="busy">
            <g v-for="(p, i) in plates" :key="`p${i}`">
                <ellipse :cx="p.x" :cy="p.y" :rx="p.r" :ry="p.r * 0.6" fill="#ffffff" opacity="0.95" />
                <ellipse
                    :cx="p.x"
                    :cy="p.y"
                    :rx="p.r"
                    :ry="p.r * 0.6"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1"
                    opacity="0.7"
                />
                <ellipse :cx="p.x" :cy="p.y" :rx="p.r * 0.45" :ry="p.r * 0.27" fill="currentColor" opacity="0.28" />
            </g>
            <!-- bardak -->
            <g v-if="kind !== 'stool'">
                <ellipse :cx="CX + 2" :cy="CY - 9" rx="3.4" ry="2" fill="#ffffff" opacity="0.9" />
                <path
                    :d="`M ${CX - 1.4} ${CY - 9} L ${CX - 0.4} ${CY - 2} L ${CX + 4.4} ${CY - 2} L ${CX + 5.4} ${CY - 9} Z`"
                    fill="#ffffff"
                    opacity="0.85"
                />
                <path
                    :d="`M ${CX - 1.4} ${CY - 9} L ${CX - 0.4} ${CY - 2} L ${CX + 4.4} ${CY - 2} L ${CX + 5.4} ${CY - 9}`"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="0.9"
                    opacity="0.6"
                />
            </g>
        </template>

        <!-- ön sandalyeler -->
        <g v-for="(c, i) in chairsFront" :key="`f${i}`">
            <ellipse :cx="c.x" :cy="c.y" rx="8.5" ry="5" fill="currentColor" opacity="0.5" />
            <ellipse :cx="c.x" :cy="c.y - 3.5" rx="8" ry="4.5" fill="currentColor" opacity="0.66" />
        </g>
    </svg>
</template>
