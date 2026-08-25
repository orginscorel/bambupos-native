<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { formatDate, formatDateTime } from '@/lib/format';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import InventoryNav from './components/InventoryNav.vue';

/**
 * UYARI PANOSU (§17.5): kritik/eksi stok, yaklaşan SKT, bitiş tahmini,
 * anormal tüketim, reçetesiz satış, sayım farkları — hepsi anlık sorgu.
 */
interface Alerts {
    critical: { item_id: number; name: string; severity: string; on_hand: string; min: string; critical: string; unit: string }[];
    negative: { item_id: number; name: string; warehouse: string; on_hand: string; unit: string }[];
    expiry: { item_id: number; name: string; lot_no: string | null; expires_at: string | null; expired: boolean; qty: string; unit: string }[];
    depletion: { item_id: number; name: string; on_hand: string; unit: string; daily_use: string; days_left: number }[];
    abnormal: { item_id: number; name: string; recent: string; previous: string; unit: string; ratio: number }[];
    missing_recipes: { product_id: number; name: string }[];
    count_diffs: { count_id: number; warehouse: string; item: string; diff: string; unit: string; approved_at: string | null }[];
}

const { danger } = useToast();
const data = ref<Alerts | null>(null);
const loading = ref(true);

async function load(): Promise<void> {
    loading.value = true;
    try {
        data.value = (await api<{ alerts: Alerts }>('/api/v1/inventory/alerts')).alerts;
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

const totalCount = computed(() => {
    const d = data.value;
    if (!d) return 0;
    return d.critical.length + d.negative.length + d.expiry.length + d.depletion.length + d.abnormal.length + d.missing_recipes.length + d.count_diffs.length;
});
</script>

<template>
    <Head title="Stok Uyarıları" />
    <PanelShell title="Stok" flush canvas>
        <div class="shrink-0 border-b border-default bg-raised px-4 py-2.5 sm:px-6">
            <InventoryNav active="alerts" />
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">
        <div v-if="loading" class="p-6 text-center text-sm text-muted">Yükleniyor…</div>

        <EmptyState
            v-else-if="totalCount === 0"
            title="Uyarı yok"
            description="Kritik seviye, eksi stok, yaklaşan SKT ve anormal tüketim burada belirir. Şu an her şey yolunda."
        />

        <div v-else-if="data" class="grid gap-4 md:grid-cols-2">
            <!-- Kritik / düşük -->
            <BaseCard v-if="data.critical.length" title="Kritik / azalan stok">
                <ul class="divide-y divide-default text-sm">
                    <li v-for="a in data.critical" :key="'c' + a.item_id" class="flex items-center gap-2 py-2">
                        <BaseBadge :variant="a.severity === 'critical' ? 'danger' : 'warning'" no-icon>
                            {{ a.severity === 'critical' ? 'Kritik' : 'Azalıyor' }}
                        </BaseBadge>
                        <span class="font-medium">{{ a.name }}</span>
                        <span class="ms-auto tabular-nums text-muted">{{ a.on_hand }} {{ a.unit }} · eşik {{ a.critical !== '0' ? a.critical : a.min }}</span>
                    </li>
                </ul>
            </BaseCard>

            <!-- Eksi stok -->
            <BaseCard v-if="data.negative.length" title="Eksi stok (tüketim düştü, giriş yok)">
                <ul class="divide-y divide-default text-sm">
                    <li v-for="a in data.negative" :key="'n' + a.item_id + a.warehouse" class="flex items-center gap-2 py-2">
                        <span class="font-medium">{{ a.name }}</span>
                        <span class="text-muted">· {{ a.warehouse }}</span>
                        <span class="ms-auto tabular-nums text-danger">{{ a.on_hand }} {{ a.unit }}</span>
                    </li>
                </ul>
            </BaseCard>

            <!-- SKT -->
            <BaseCard v-if="data.expiry.length" title="Son kullanma tarihi yaklaşan">
                <ul class="divide-y divide-default text-sm">
                    <li v-for="(a, i) in data.expiry" :key="'e' + a.item_id + i" class="flex items-center gap-2 py-2">
                        <BaseBadge :variant="a.expired ? 'danger' : 'warning'" no-icon>{{ a.expired ? 'Geçti' : 'Yaklaşıyor' }}</BaseBadge>
                        <span class="font-medium">{{ a.name }}</span>
                        <span v-if="a.lot_no" class="text-xs text-subtle">[{{ a.lot_no }}]</span>
                        <span class="ms-auto text-muted">{{ a.expires_at ? formatDate(a.expires_at) : '—' }}</span>
                    </li>
                </ul>
            </BaseCard>

            <!-- Bitiş tahmini -->
            <BaseCard v-if="data.depletion.length" title="Yakında tükenecek (tüketim hızına göre)">
                <ul class="divide-y divide-default text-sm">
                    <li v-for="a in data.depletion" :key="'d' + a.item_id" class="flex items-center gap-2 py-2">
                        <span class="font-medium">{{ a.name }}</span>
                        <span class="text-muted">· günlük ~{{ a.daily_use }} {{ a.unit }}</span>
                        <span class="ms-auto tabular-nums text-warning">~{{ a.days_left }} gün</span>
                    </li>
                </ul>
            </BaseCard>

            <!-- Anormal tüketim -->
            <BaseCard v-if="data.abnormal.length" title="Anormal tüketim (önceki haftanın 2 katından fazla)">
                <ul class="divide-y divide-default text-sm">
                    <li v-for="a in data.abnormal" :key="'ab' + a.item_id" class="flex items-center gap-2 py-2">
                        <span class="font-medium">{{ a.name }}</span>
                        <span class="ms-auto tabular-nums text-muted">{{ a.previous }} → {{ a.recent }} {{ a.unit }} (×{{ a.ratio }})</span>
                    </li>
                </ul>
            </BaseCard>

            <!-- Reçetesiz satış -->
            <BaseCard v-if="data.missing_recipes.length" title="Reçetesiz ürün (satış olur, stok düşmez)">
                <p class="mb-2 text-xs text-subtle">Bu ürünler satıldığında stok tüketimi işlenmez. Reçete tanımlayın.</p>
                <ul class="flex flex-wrap gap-1.5">
                    <li v-for="p in data.missing_recipes" :key="'m' + p.product_id">
                        <BaseBadge variant="warning" no-icon>{{ p.name }}</BaseBadge>
                    </li>
                </ul>
            </BaseCard>

            <!-- Sayım farkları -->
            <BaseCard v-if="data.count_diffs.length" title="Son sayım farkları (onaylı)">
                <ul class="divide-y divide-default text-sm">
                    <li v-for="(a, i) in data.count_diffs" :key="'cd' + a.count_id + i" class="flex items-center gap-2 py-2">
                        <span class="font-medium">{{ a.item }}</span>
                        <span class="text-muted">· {{ a.warehouse }}</span>
                        <span class="ms-auto tabular-nums" :class="a.diff.startsWith('-') ? 'text-danger' : 'text-success'">{{ a.diff }} {{ a.unit }}</span>
                        <span class="text-xs text-subtle">{{ a.approved_at ? formatDateTime(a.approved_at) : '' }}</span>
                    </li>
                </ul>
            </BaseCard>
        </div>
        </div>
        </div>
    </PanelShell>
</template>
