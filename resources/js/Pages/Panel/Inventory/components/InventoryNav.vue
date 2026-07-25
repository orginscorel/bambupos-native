<script setup lang="ts">
import { computed } from 'vue';
import { Link } from '@inertiajs/vue3';
import AppIcon from '@/Components/ui/AppIcon.vue';

/**
 * Stok modülü alt gezinmesi — İKİ KADEMELİ + AÇIKLAMALI.
 * 8 ekran, 6 anlaşılır gruba toplandı (kullanıcı "sekmeler arası boğuluyorum" dedi):
 *   Genel Bakış · Stok · Hareketler · Giriş · Reçeteler · Rapor
 * Alt sayfalar (Uyarılar, Sayım, Tedarikçiler) ait oldukları grubun 2. satırında.
 * Her grubun ne işe yaradığı tek satırda yazılır.
 *
 * `active` = bulunulan ekranın anahtarı: overview | items | alerts | movements |
 * counts | purchasing | suppliers | recipes | reports.
 * ("overview" ve "items" aynı rotadır: /panel/stok — ?gorunum=kartlar ile ayrışır.)
 */
const props = defineProps<{ active: string }>();

interface SubTab { key: string; label: string; href: string }
interface Group {
    key: string;
    label: string;
    icon: string;
    /** Tek ekranlı gruplarda doğrudan hedef. */
    href?: string;
    /** Bu gruba ait ekran anahtarları (tek ekranlılar için). */
    keys?: string[];
    /** Çok ekranlı gruplarda 2. satır sekmeleri. */
    subs?: SubTab[];
    desc: string;
}

const groups: Group[] = [
    {
        key: 'overview',
        label: 'Genel Bakış',
        icon: 'dashboard',
        href: '/panel/stok',
        keys: ['overview'],
        desc: 'Stok durumunu tek ekranda görür, kritik kalemlere ve sık kullanılan işlemlere hızlıca gidersiniz.',
    },
    {
        key: 'stock',
        label: 'Stok',
        icon: 'package',
        desc: 'Stok kartlarını (kalem, birim, eşik, maliyet) yönetir; kritik ve azalan uyarıları görürsünüz.',
        subs: [
            { key: 'items', label: 'Stok Kartları', href: '/panel/stok?gorunum=kartlar' },
            { key: 'alerts', label: 'Uyarılar', href: '/panel/stok/uyarilar' },
        ],
    },
    {
        key: 'movements',
        label: 'Hareketler',
        icon: 'arrow-right',
        desc: 'Değişmez stok hareket defterini izler; fiziki sayım açıp farkları deftere işlersiniz.',
        subs: [
            { key: 'movements', label: 'Hareket Defteri', href: '/panel/stok/hareketler' },
            { key: 'counts', label: 'Sayım', href: '/panel/stok/sayim' },
        ],
    },
    {
        key: 'inbound',
        label: 'Giriş',
        icon: 'inbox',
        desc: 'Satın alma siparişi açar, gelen malı kabul eder (stok otomatik girer) ve tedarikçileri yönetirsiniz.',
        subs: [
            { key: 'purchasing', label: 'Mal Kabul / Satın Alma', href: '/panel/stok/satin-alma' },
            { key: 'suppliers', label: 'Tedarikçiler', href: '/panel/stok/tedarikciler' },
        ],
    },
    {
        key: 'recipes',
        label: 'Reçeteler',
        icon: 'chef-hat',
        href: '/panel/stok/receteler',
        keys: ['recipes'],
        desc: 'Ürün→hammadde reçetelerini tanımlarsınız; satış servis edilince stok bu reçeteye göre düşer.',
    },
    {
        key: 'reports',
        label: 'Rapor',
        icon: 'chart',
        href: '/panel/stok/rapor',
        keys: ['reports'],
        desc: 'Gün / ay / dönem mutabakatı (açılış→giriş→çıkış→kapanış) ile tüketim ve maliyet raporlarını alırsınız.',
    },
];

/** Ekran anahtarı → üst grup. */
const pageToGroup: Record<string, string> = {
    overview: 'overview',
    items: 'stock',
    alerts: 'stock',
    movements: 'movements',
    counts: 'movements',
    purchasing: 'inbound',
    suppliers: 'inbound',
    recipes: 'recipes',
    reports: 'reports',
};

const activeGroupKey = computed(() => pageToGroup[props.active] ?? 'overview');
const activeGroup = computed(() => groups.find((g) => g.key === activeGroupKey.value) ?? groups[0]);

/** Grup sekmesinin gideceği yer: tek ekranlıda kendi href'i, çok ekranlıda ilk alt sekme. */
const groupHref = (g: Group): string => g.href ?? g.subs?.[0]?.href ?? '/panel/stok';
</script>

<template>
    <div class="mb-4 flex flex-col gap-2">
        <!-- 1. kademe: gruplar -->
        <nav aria-label="Stok bölümleri" class="-mx-1 overflow-x-auto overscroll-x-contain">
            <ul class="flex min-w-max items-center gap-1 border-b border-default px-1">
                <li v-for="g in groups" :key="g.key">
                    <Link
                        :href="groupHref(g)"
                        class="inline-flex items-center gap-1.5 whitespace-nowrap border-b-2 px-3 py-2 text-sm font-medium transition-colors"
                        :class="g.key === activeGroupKey
                            ? 'border-primary text-primary'
                            : 'border-transparent text-muted hover:text-body'"
                        :aria-current="g.key === activeGroupKey ? 'page' : undefined"
                    >
                        <AppIcon :name="g.icon" :size="15" />
                        {{ g.label }}
                    </Link>
                </li>
            </ul>
        </nav>

        <!-- Aktif grubun açıklaması -->
        <p class="px-1 text-xs text-subtle">{{ activeGroup.desc }}</p>

        <!-- 2. kademe: alt ekranlar (yalnız çok ekranlı grupta) -->
        <nav
            v-if="activeGroup.subs"
            aria-label="Alt ekranlar"
            class="-mx-1 overflow-x-auto overscroll-x-contain"
        >
            <ul class="flex min-w-max items-center gap-1.5 px-1">
                <li v-for="s in activeGroup.subs" :key="s.key">
                    <Link
                        :href="s.href"
                        class="inline-flex items-center whitespace-nowrap rounded-full border px-3 py-1 text-xs font-medium transition-colors"
                        :class="s.key === props.active
                            ? 'border-primary bg-primary-soft text-primary'
                            : 'border-default text-muted hover:text-body hover:bg-inset'"
                        :aria-current="s.key === props.active ? 'page' : undefined"
                    >
                        {{ s.label }}
                    </Link>
                </li>
            </ul>
        </nav>
    </div>
</template>
