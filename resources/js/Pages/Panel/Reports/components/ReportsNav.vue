<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from '@/Components/ui/AppIcon.vue';

/**
 * Raporlar modülü alt gezinmesi — İKİ KADEMELİ + AÇIKLAMALI.
 * (Stok modülündeki InventoryNav deseninin birebir uyarlaması.)
 *
 * Raporlar tek Inertia sayfası; sekmeler rota değil, sayfa-içi durumdur.
 * Bu yüzden InventoryNav'daki <Link href> yerine `select` olayı yayılır.
 *
 * 9 rapor ekranı 5 anlaşılır üst gruba toplanır; her grubun ne işe
 * yaradığı tek satırda yazılır, çok ekranlı gruplar 2. satırda açılır.
 *
 * `active` = bulunulan sekmenin anahtarı:
 *   overview | sales | profit | finance | eod | reconciliation | ops | staff | exports
 */
const props = defineProps<{ active: string }>();
const emit = defineEmits<{ select: [key: string] }>();

interface SubTab { key: string; label: string }
interface Group {
    key: string;
    label: string;
    icon: string;
    /** Tek ekranlı gruplarda doğrudan hedef sekme. */
    tab?: string;
    /** Çok ekranlı gruplarda 2. satır sekmeleri. */
    subs?: SubTab[];
    desc: string;
}

const groups: Group[] = [
    {
        key: 'overview',
        label: 'Genel Bakış',
        icon: 'dashboard',
        tab: 'overview',
        desc: 'Bugünün ana göstergeleri — ciro, nakit/POS tahsilat, açık masa ve en çok satan — ve sık raporlara tek tıkla geçiş.',
    },
    {
        key: 'sales',
        label: 'Satış & Kârlılık',
        icon: 'chart',
        desc: 'Ciro trendi, yoğun saatler, kanal/kategori/ürün/masa satışları ve ürün bazında kâr-maliyet.',
        subs: [
            { key: 'sales', label: 'Satış' },
            { key: 'profit', label: 'Kârlılık' },
        ],
    },
    {
        key: 'finance',
        label: 'Finans & Kasa',
        icon: 'cart',
        desc: 'Tahsilat, ödeme yöntemleri, KDV, gün sonu (Z) özeti ve nakit/POS mutabakatı.',
        subs: [
            { key: 'finance', label: 'Finans' },
            { key: 'eod', label: 'Gün Sonu' },
            { key: 'reconciliation', label: 'Mutabakat' },
        ],
    },
    {
        key: 'ops',
        label: 'Operasyon & Personel',
        icon: 'users',
        desc: 'Hazırlama/servis süreleri, iptal-ikram nedenleri, QR kullanımı ve personel performansı.',
        subs: [
            { key: 'ops', label: 'Operasyon' },
            { key: 'staff', label: 'Personel' },
        ],
    },
    {
        key: 'exports',
        label: 'Dışa Aktarım',
        icon: 'inbox',
        tab: 'exports',
        desc: 'Raporları CSV/Excel olarak dışa aktarır; isteklerin durumunu ve indirmelerini görürsünüz.',
    },
];

/** Sekme anahtarı → üst grup. */
const tabToGroup: Record<string, string> = {
    overview: 'overview',
    sales: 'sales',
    profit: 'sales',
    finance: 'finance',
    eod: 'finance',
    reconciliation: 'finance',
    ops: 'ops',
    staff: 'ops',
    exports: 'exports',
};

const activeGroupKey = computed(() => tabToGroup[props.active] ?? 'overview');
const activeGroup = computed(() => groups.find((g) => g.key === activeGroupKey.value) ?? groups[0]);

/** Grup sekmesine tıklayınca: tek ekranlıda kendi sekmesi, çok ekranlıda ilk alt sekme. */
const groupTab = (g: Group): string => g.tab ?? g.subs?.[0]?.key ?? 'overview';
</script>

<template>
    <div class="mb-4 flex flex-col gap-2">
        <!-- 1. kademe: gruplar -->
        <nav aria-label="Rapor bölümleri" class="-mx-1 overflow-x-auto overscroll-x-contain">
            <ul class="flex min-w-max items-center gap-1 border-b border-default px-1">
                <li v-for="g in groups" :key="g.key">
                    <button
                        type="button"
                        class="inline-flex items-center gap-1.5 whitespace-nowrap border-b-2 px-3 py-2 text-sm font-medium transition-colors"
                        :class="g.key === activeGroupKey
                            ? 'border-primary text-primary'
                            : 'border-transparent text-muted hover:text-body'"
                        :aria-current="g.key === activeGroupKey ? 'page' : undefined"
                        @click="emit('select', groupTab(g))"
                    >
                        <AppIcon :name="g.icon" :size="15" />
                        {{ g.label }}
                    </button>
                </li>
            </ul>
        </nav>

        <!-- Aktif grubun açıklaması -->
        <p class="px-1 text-xs text-subtle">{{ activeGroup.desc }}</p>

        <!-- 2. kademe: alt ekranlar (yalnız çok ekranlı grupta) -->
        <nav
            v-if="activeGroup.subs"
            aria-label="Alt raporlar"
            class="-mx-1 overflow-x-auto overscroll-x-contain"
        >
            <ul class="flex min-w-max items-center gap-1.5 px-1">
                <li v-for="s in activeGroup.subs" :key="s.key">
                    <button
                        type="button"
                        class="inline-flex items-center whitespace-nowrap rounded-full border px-3 py-1 text-xs font-medium transition-colors"
                        :class="s.key === props.active
                            ? 'border-primary bg-primary-soft text-primary'
                            : 'border-default text-muted hover:text-body hover:bg-inset'"
                        :aria-current="s.key === props.active ? 'page' : undefined"
                        @click="emit('select', s.key)"
                    >
                        {{ s.label }}
                    </button>
                </li>
            </ul>
        </nav>
    </div>
</template>
