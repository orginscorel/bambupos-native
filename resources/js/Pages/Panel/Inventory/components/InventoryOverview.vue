<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Link } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import AppIcon from '@/Components/ui/AppIcon.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import { money } from '../inventory';

/**
 * GENEL BAKIŞ (landing) — stok modülünün açılış ekranı.
 * Amaç: kullanıcı sekmelerde kaybolmadan durumu tek bakışta görsün ve
 * doğru ekrana tek tıkla gitsin. Tüm veriler mevcut salt-okunur uçlardan gelir
 * (yeni backend YOK): /alerts, /counts, /reports/day-end.
 */
interface AlertsShape {
    critical: { item_id: number; name: string; severity: string; on_hand: string; unit: string; min: string; critical: string }[];
    negative: { item_id: number; name: string }[];
    depletion: { item_id: number; name: string; days_left: number; unit: string; daily_use: string }[];
    missing_recipes: { product_id: number; name: string }[];
}
interface CountRow { id: number; status: string }
interface DayEndItem { item_id: number; name: string; used: string; unit: string; cost_minor: number }

const { danger } = useToast();
const loading = ref(true);
const alerts = ref<AlertsShape | null>(null);
const counts = ref<CountRow[]>([]);
const dayEnd = ref<{ date: string; items: DayEndItem[] } | null>(null);

const today = new Date().toISOString().slice(0, 10);

async function load(): Promise<void> {
    loading.value = true;
    try {
        const [a, c, d] = await Promise.all([
            api<{ alerts: AlertsShape }>('/api/v1/inventory/alerts'),
            api<{ counts: CountRow[] }>('/api/v1/inventory/counts'),
            api<{ date: string; items: DayEndItem[] }>(`/api/v1/inventory/reports/day-end?date=${today}`),
        ]);
        alerts.value = a.alerts;
        counts.value = c.counts;
        dayEnd.value = d;
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

const criticalCount = computed(() => (alerts.value?.critical.length ?? 0) + (alerts.value?.negative.length ?? 0));
const pendingCounts = computed(() => counts.value.filter((c) => c.status === 'draft' || c.status === 'submitted').length);
const missingRecipes = computed(() => alerts.value?.missing_recipes.length ?? 0);
const dayEndItems = computed(() => dayEnd.value?.items ?? []);
const dayEndCost = computed(() => dayEndItems.value.reduce((s, i) => s + i.cost_minor, 0));

/** Üst özet kartları — her biri ilgili ekrana götürür. */
const stats = computed(() => [
    {
        key: 'critical',
        label: 'Kritik / eksi kalem',
        value: String(criticalCount.value),
        hint: criticalCount.value ? 'Acil ilgi gerekiyor' : 'Her şey yolunda',
        icon: 'alert-triangle',
        tone: criticalCount.value ? 'danger' : 'ok',
        href: '/panel/stok/uyarilar',
    },
    {
        key: 'today',
        label: 'Bugün stoktan azalan',
        value: String(dayEndItems.value.length),
        hint: dayEndItems.value.length ? `Tüketim maliyeti ${money(dayEndCost.value)}` : 'Bugün tüketim yok',
        icon: 'chart',
        tone: 'info',
        href: '/panel/stok/rapor',
    },
    {
        key: 'counts',
        label: 'Bekleyen sayım',
        value: String(pendingCounts.value),
        hint: pendingCounts.value ? 'Onay/giriş bekliyor' : 'Açık sayım yok',
        icon: 'check-circle',
        tone: pendingCounts.value ? 'warning' : 'ok',
        href: '/panel/stok/sayim',
    },
    {
        key: 'recipes',
        label: 'Reçetesiz ürün',
        value: String(missingRecipes.value),
        hint: missingRecipes.value ? 'Satışta stok düşmez' : 'Tümü reçeteli',
        icon: 'chef-hat',
        tone: missingRecipes.value ? 'warning' : 'ok',
        href: '/panel/stok/receteler',
    },
]);

const toneClass = (tone: string): string =>
    tone === 'danger' ? 'text-danger' : tone === 'warning' ? 'text-warning' : tone === 'info' ? 'text-primary' : 'text-success';

/** Hızlı aksiyon butonları. */
const actions = [
    { label: 'Stok Kartları', desc: 'Kalem ekle / düzenle', icon: 'package', href: '/panel/stok?gorunum=kartlar' },
    { label: 'Mal Kabul', desc: 'Gelen malı stoğa gir', icon: 'inbox', href: '/panel/stok/satin-alma' },
    { label: 'Sayım Başlat', desc: 'Fiziki sayım aç', icon: 'check-circle', href: '/panel/stok/sayim' },
    { label: 'Uyarılar', desc: 'Kritik / SKT / anormal', icon: 'alert-triangle', href: '/panel/stok/uyarilar' },
    { label: 'Rapor', desc: 'Dönem mutabakatı', icon: 'chart', href: '/panel/stok/rapor' },
];
</script>

<template>
    <div class="flex flex-col gap-4">
        <div v-if="loading" class="p-6 text-center text-sm text-muted">Yükleniyor…</div>

        <template v-else>
            <!-- Özet kartları (tıklanınca ilgili ekrana gider) -->
            <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
                <Link
                    v-for="s in stats"
                    :key="s.key"
                    :href="s.href"
                    class="group rounded-lg border border-default bg-raised p-4 shadow-card transition-colors hover:border-primary"
                >
                    <div class="flex items-center justify-between">
                        <p class="text-xs font-medium text-muted uppercase">{{ s.label }}</p>
                        <AppIcon :name="s.icon" :size="16" :class="toneClass(s.tone)" />
                    </div>
                    <p class="mt-2 text-2xl font-semibold tabular-nums" :class="toneClass(s.tone)">{{ s.value }}</p>
                    <p class="mt-0.5 text-xs text-subtle">{{ s.hint }}</p>
                </Link>
            </div>

            <!-- Hızlı işlemler -->
            <BaseCard title="Hızlı işlemler">
                <div class="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
                    <Link
                        v-for="a in actions"
                        :key="a.href"
                        :href="a.href"
                        class="flex flex-col gap-1 rounded-md border border-default p-3 transition-colors hover:border-primary hover:bg-inset"
                    >
                        <AppIcon :name="a.icon" :size="18" class="text-primary" />
                        <span class="text-sm font-medium text-body">{{ a.label }}</span>
                        <span class="text-xs text-subtle">{{ a.desc }}</span>
                    </Link>
                </div>
            </BaseCard>

            <div class="grid gap-4 lg:grid-cols-2">
                <!-- Kritik kalemler -->
                <BaseCard>
                    <template #header>
                        <h2 class="text-sm font-semibold text-body">Kritik / azalan kalemler</h2>
                    </template>
                    <template #actions>
                        <Link href="/panel/stok/uyarilar" class="text-xs font-medium text-primary hover:underline">Tümü</Link>
                    </template>
                    <ul v-if="alerts && alerts.critical.length" class="divide-y divide-default text-sm">
                        <li v-for="a in alerts.critical.slice(0, 6)" :key="a.item_id" class="flex items-center gap-2 py-2">
                            <BaseBadge :variant="a.severity === 'critical' ? 'danger' : 'warning'" no-icon>
                                {{ a.severity === 'critical' ? 'Kritik' : 'Azalıyor' }}
                            </BaseBadge>
                            <span class="font-medium">{{ a.name }}</span>
                            <span class="ms-auto tabular-nums text-muted">{{ a.on_hand }} {{ a.unit }}</span>
                        </li>
                    </ul>
                    <EmptyState v-else icon="check-circle" title="Kritik kalem yok" description="Tüm kalemler eşiğin üzerinde." />
                </BaseCard>

                <!-- Bugün stoktan azalan -->
                <BaseCard>
                    <template #header>
                        <h2 class="text-sm font-semibold text-body">Bugün stoktan azalan</h2>
                    </template>
                    <template #actions>
                        <Link href="/panel/stok/rapor" class="text-xs font-medium text-primary hover:underline">Rapor</Link>
                    </template>
                    <ul v-if="dayEndItems.length" class="divide-y divide-default text-sm">
                        <li v-for="d in dayEndItems.slice(0, 6)" :key="d.item_id" class="flex items-center gap-2 py-2">
                            <span class="font-medium">{{ d.name }}</span>
                            <span class="ms-auto tabular-nums text-danger">−{{ d.used }} {{ d.unit }}</span>
                            <span class="w-20 text-right tabular-nums text-muted">{{ money(d.cost_minor) }}</span>
                        </li>
                    </ul>
                    <EmptyState v-else title="Bugün tüketim yok" description="Bugün stoktan düşen kalem bulunmuyor." />
                </BaseCard>
            </div>
        </template>
    </div>
</template>
