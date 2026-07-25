<script setup lang="ts">
import { computed } from 'vue';
import { Link } from '@inertiajs/vue3';
import AppIcon from '@/Components/ui/AppIcon.vue';

/**
 * Rezervasyon modülü alt gezinmesi — GRUPLU + AÇIKLAMALI (Stok deseni).
 * 4 ekran net gruplara toplanır ve her grubun ne işe yaradığı tek satırda yazılır:
 *   Genel Bakış · Takvim ve Liste · Bekleme Listesi · No-Show Raporu
 *
 * `active` = bulunulan ekranın anahtarı: overview | calendar | waitlist | noshow.
 * ("overview" ve "calendar" aynı rotadır: /panel/rezervasyonlar — ?gorunum=takvim ile ayrışır.)
 */
const props = defineProps<{ active: string }>();

interface SubTab { key: string; label: string; href: string }
interface Group {
    key: string;
    label: string;
    icon: string;
    /** Tek ekranlı gruplarda doğrudan hedef. */
    href?: string;
    /** Bu gruba ait ekran anahtarları. */
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
        href: '/panel/rezervasyonlar',
        keys: ['overview'],
        desc: 'Bu ekranda bugünün ve yaklaşan rezervasyonların özetini görür, sık kullanılan işlemlere tek tıkla gidersiniz.',
    },
    {
        key: 'calendar',
        label: 'Takvim ve Liste',
        icon: 'calendar',
        href: '/panel/rezervasyonlar?gorunum=takvim',
        keys: ['calendar'],
        desc: 'Bu ekranda gün/hafta takviminde rezervasyonları görüntüler; oluşturur, düzenler ve durumlarını (onay, geldi, masaya al) yönetirsiniz.',
    },
    {
        key: 'waitlist',
        label: 'Bekleme Listesi',
        icon: 'inbox',
        href: '/panel/rezervasyonlar/bekleme-listesi',
        keys: ['waitlist'],
        desc: 'Bu ekranda doluluk anında müşterileri sıraya alır, tahmini bekleme süresiyle çağırıp masaya alırsınız.',
    },
    {
        key: 'noshow',
        label: 'No-Show Raporu',
        icon: 'chart',
        href: '/panel/rezervasyonlar/no-show',
        keys: ['noshow'],
        desc: 'Bu ekranda seçtiğiniz dönemde gelmeyen (no-show) müşterileri, oranları ve yanan kaporaları raporlarsınız.',
    },
];

/** Ekran anahtarı → üst grup. */
const pageToGroup: Record<string, string> = {
    overview: 'overview',
    calendar: 'calendar',
    waitlist: 'waitlist',
    noshow: 'noshow',
};

const activeGroupKey = computed(() => pageToGroup[props.active] ?? 'overview');
const activeGroup = computed(() => groups.find((g) => g.key === activeGroupKey.value) ?? groups[0]);

/** Grup sekmesinin gideceği yer: tek ekranlıda kendi href'i, çok ekranlıda ilk alt sekme. */
const groupHref = (g: Group): string => g.href ?? g.subs?.[0]?.href ?? '/panel/rezervasyonlar';
</script>

<template>
    <div class="mb-4 flex flex-col gap-2">
        <!-- 1. kademe: gruplar -->
        <nav aria-label="Rezervasyon bölümleri" class="-mx-1 overflow-x-auto overscroll-x-contain">
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
