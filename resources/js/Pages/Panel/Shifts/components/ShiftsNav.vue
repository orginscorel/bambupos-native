<script setup lang="ts">
import { computed } from 'vue';
import { Link, usePage } from '@inertiajs/vue3';
import AppIcon from '@/Components/ui/AppIcon.vue';

/**
 * Vardiya & Mesai bölümü alt gezinmesi — İKİ KADEMELİ + AÇIKLAMALI (Stok deseni).
 * 8 ekran 5 anlaşılır gruba toplandı; her grubun ne işe yaradığı tek satırda yazar:
 *   Genel Bakış · Plan · Mesai & Devam · İzinler · Cihazlar & Ayar
 * Çok ekranlı gruplar (Mesai & Devam, İzinler) alt ekranlarını 2. satır pill'lerde açar.
 * Sekmeler izne göre süzülür (Devam Takibi=staff.view; Onaylar & Ayarlar=staff.manage).
 *
 * `active` = bulunulan ekranın anahtarı:
 *   overview | schedule | entries | clock | performance | leaves | approvals | settings.
 * ("overview" ve "schedule" aynı rotadır: /panel/vardiya — ?gorunum=takvim ile ayrışır.)
 */
const props = defineProps<{ active: string }>();

const page = usePage();
const permissions = computed<string[]>(() => {
    const auth = (page.props as Record<string, unknown>).auth as { permissions?: string[] } | undefined;
    return auth?.permissions ?? [];
});
const canManage = computed(() => permissions.value.includes('staff.manage'));
const canView = computed(() => canManage.value || permissions.value.includes('staff.view'));

interface SubTab { key: string; label: string; href: string }
interface Group {
    key: string;
    label: string;
    icon: string;
    /** Tek ekranlı gruplarda doğrudan hedef. */
    href?: string;
    /** Çok ekranlı gruplarda 2. satır sekmeleri. */
    subs?: SubTab[];
    desc: string;
}

const groups = computed<Group[]>(() => {
    const attendanceSubs: SubTab[] = [
        { key: 'entries', label: 'Mesai Kayıtları', href: '/panel/mesai' },
        { key: 'clock', label: 'Giriş / Çıkış', href: '/panel/mesai/giris-cikis' },
    ];
    if (canView.value) attendanceSubs.push({ key: 'performance', label: 'Devam Takibi', href: '/panel/mesai/performans' });

    const leaveSubs: SubTab[] = [{ key: 'leaves', label: 'İzin & Devamsızlık', href: '/panel/mesai/izinler' }];
    if (canManage.value) leaveSubs.push({ key: 'approvals', label: 'Onay Bekleyenler', href: '/panel/mesai/talepler' });

    const list: Group[] = [
        {
            key: 'overview',
            label: 'Genel Bakış',
            icon: 'dashboard',
            href: '/panel/vardiya',
            desc: 'Bugünün vardiya ve mesai durumunu tek ekranda görür, sık kullanılan işlemlere hızla geçersiniz.',
        },
        {
            key: 'plan',
            label: 'Plan',
            icon: 'calendar',
            href: '/panel/vardiya?gorunum=takvim',
            desc: 'Haftalık ve aylık vardiya takvimini kurar, sürükle-bırak ile personele atar; çakışma ve minimum personel uyarılarını görürsünüz.',
        },
        {
            key: 'attendance',
            label: 'Mesai & Devam',
            icon: 'coffee',
            desc: 'Giriş/çıkış kayıtlarını izler, ortak cihazdan PIN ile mesai alır ve kişi bazlı devam/fazla mesai raporunu görürsünüz.',
            subs: attendanceSubs,
        },
        {
            key: 'leaves',
            label: 'İzinler',
            icon: 'inbox',
            desc: 'İzin, rapor ve devamsızlık kayıtlarını yönetir; bekleyen izin ve vardiya değişim taleplerini onaylarsınız.',
            subs: leaveSubs,
        },
    ];

    if (canManage.value) {
        list.push({
            key: 'payroll',
            label: 'Maaşlar',
            icon: 'wallet',
            href: '/panel/mesai/maaslar',
            desc: 'Personele aylık sabit veya saatlik maaş tanımlar; saatlikte mesaiye göre günlük/aylık hak edişi otomatik hesaplanır.',
        });
        list.push({
            key: 'settings',
            label: 'Cihazlar & Ayar',
            icon: 'settings',
            href: '/panel/mesai/ayarlar',
            desc: 'Süre/tolerans kurallarını, KVKK konum politikasını, kiosk cihazlarını ve minimum personel kurallarını ayarlarsınız.',
        });
    }

    return list;
});

/** Ekran anahtarı → üst grup. */
const pageToGroup: Record<string, string> = {
    overview: 'overview',
    schedule: 'plan',
    entries: 'attendance',
    clock: 'attendance',
    performance: 'attendance',
    leaves: 'leaves',
    approvals: 'leaves',
    payroll: 'payroll',
    settings: 'settings',
};

const activeGroupKey = computed(() => pageToGroup[props.active] ?? 'overview');
const activeGroup = computed(() => groups.value.find((g) => g.key === activeGroupKey.value) ?? groups.value[0]);

/** Grup sekmesinin gideceği yer: tek ekranlıda kendi href'i, çok ekranlıda ilk alt sekme. */
const groupHref = (g: Group): string => g.href ?? g.subs?.[0]?.href ?? '/panel/vardiya';
</script>

<template>
    <div class="mb-4 flex flex-col gap-2">
        <!-- 1. kademe: gruplar -->
        <nav aria-label="Vardiya bölümleri" class="-mx-1 overflow-x-auto overscroll-x-contain">
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
