<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { Head } from '@inertiajs/vue3';
import { api, ApiError } from '@/lib/http';
import { useToast } from '@/composables/useToast';
import PanelShell from '@/Components/panel/PanelShell.vue';
import BaseBadge from '@/Components/ui/BaseBadge.vue';
import BaseButton from '@/Components/ui/BaseButton.vue';
import BaseCard from '@/Components/ui/BaseCard.vue';
import BaseInput from '@/Components/ui/BaseInput.vue';
import EmptyState from '@/Components/ui/EmptyState.vue';
import InventoryNav from './components/InventoryNav.vue';
import { money } from './inventory';

/**
 * STOK RAPORU (§17.7): dönem mutabakatı (açılış→giriş→çıkış→kapanış) +
 * gün sonu azalma ("bugün stoktan şu kadar X azaldı") + giriş/tüketim
 * maliyeti (ciro-maliyet bağı). Tüm hesap sunucuda; defter tek kaynak.
 */
interface PeriodRow {
    item_id: number; name: string; unit: string;
    opening: string; in: string; out: string; consumed: string;
    consumed_cost_minor: number; closing: string; closing_milli: number;
}
interface PeriodData {
    from: string; to: string; rows: PeriodRow[];
    totals: { moved_items: number; in_cost_minor: number; consumed_cost_minor: number };
}
interface DayEndItem { item_id: number; name: string; unit: string; used: string; cost_minor: number; lines: number }

const { danger } = useToast();

const today = new Date().toISOString().slice(0, 10);
const preset = ref<'day' | 'month' | 'range'>('day');
const anchor = ref(today);
const from = ref(today);
const to = ref(today);

const period = ref<PeriodData | null>(null);
const dayEnd = ref<{ date: string; items: DayEndItem[] } | null>(null);
const loading = ref(true);

function periodQuery(): string {
    if (preset.value === 'range') return `from=${from.value}&to=${to.value}`;
    return `preset=${preset.value}&date=${anchor.value}`;
}

async function load(): Promise<void> {
    loading.value = true;
    try {
        [period.value, dayEnd.value] = await Promise.all([
            api<PeriodData>(`/api/v1/inventory/reports/period?${periodQuery()}`),
            api<{ date: string; items: DayEndItem[] }>(`/api/v1/inventory/reports/day-end?date=${preset.value === 'range' ? to.value : anchor.value}`),
        ]);
    } catch (e) {
        danger('Yüklenemedi', e instanceof ApiError ? e.displayMessage : 'Beklenmeyen hata.');
    } finally {
        loading.value = false;
    }
}

onMounted(load);

function setPreset(p: 'day' | 'month' | 'range'): void {
    preset.value = p;
    load();
}

const dayEndTotalCost = computed(() => (dayEnd.value?.items ?? []).reduce((s, i) => s + i.cost_minor, 0));
</script>

<template>
    <Head title="Stok Raporu" />
    <PanelShell title="Stok" flush canvas>
        <div class="shrink-0 border-b border-default bg-raised px-4 py-2.5 sm:px-6">
            <InventoryNav active="reports" />
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto p-3 pb-24 sm:p-4 lg:pb-4">
        <div class="mx-auto flex w-full max-w-[1440px] flex-col gap-3">
        <!-- Dönem seçimi -->
        <div class="mb-4 flex flex-wrap items-end gap-2">
            <div class="inline-flex overflow-hidden rounded-md border border-default">
                <button
                    v-for="p in (['day','month','range'] as const)" :key="p"
                    class="px-3 py-1.5 text-sm transition-colors"
                    :class="preset === p ? 'bg-primary text-on-primary' : 'text-muted hover:bg-inset'"
                    @click="setPreset(p)"
                >
                    {{ p === 'day' ? 'Gün' : p === 'month' ? 'Ay' : 'Aralık' }}
                </button>
            </div>
            <div v-if="preset !== 'range'" class="w-40">
                <BaseInput v-model="anchor" type="date" size="sm" @update:model-value="load()" />
            </div>
            <template v-else>
                <div class="w-36"><BaseInput v-model="from" type="date" size="sm" @update:model-value="load()" /></div>
                <div class="w-36"><BaseInput v-model="to" type="date" size="sm" @update:model-value="load()" /></div>
            </template>
            <BaseButton size="sm" variant="secondary" @click="load">Yenile</BaseButton>
        </div>

        <div v-if="loading" class="p-6 text-center text-sm text-muted">Yükleniyor…</div>

        <div v-else class="flex flex-col gap-4">
            <!-- Özet kutuları -->
            <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
                <BaseCard>
                    <p class="text-xs text-muted uppercase">Giriş maliyeti (alış/üretim)</p>
                    <p class="mt-1 text-lg font-semibold tabular-nums">{{ money(period?.totals.in_cost_minor ?? 0) }}</p>
                </BaseCard>
                <BaseCard>
                    <p class="text-xs text-muted uppercase">Tüketim maliyeti (satış)</p>
                    <p class="mt-1 text-lg font-semibold tabular-nums text-danger">{{ money(period?.totals.consumed_cost_minor ?? 0) }}</p>
                </BaseCard>
                <BaseCard>
                    <p class="text-xs text-muted uppercase">Hareket gören kalem</p>
                    <p class="mt-1 text-lg font-semibold tabular-nums">{{ period?.totals.moved_items ?? 0 }}</p>
                </BaseCard>
            </div>

            <!-- Gün sonu azalma -->
            <BaseCard :title="`Gün sonu — ${dayEnd?.date ?? ''} stoktan azalan`">
                <p class="mb-2 text-xs text-subtle">
                    Seçilen günde reçete/ikram/satış tüketimiyle stoktan düşen kalemler.
                    Toplam maliyet: <span class="font-semibold text-body">{{ money(dayEndTotalCost) }}</span>
                </p>
                <ul v-if="dayEnd?.items.length" class="divide-y divide-default text-sm">
                    <li v-for="d in dayEnd.items" :key="d.item_id" class="flex items-center gap-2 py-2">
                        <span class="font-medium">{{ d.name }}</span>
                        <span class="text-xs text-subtle">· {{ d.lines }} hareket</span>
                        <span class="ms-auto tabular-nums text-danger">−{{ d.used }} {{ d.unit }}</span>
                        <span class="w-24 text-right tabular-nums text-muted">{{ money(d.cost_minor) }}</span>
                    </li>
                </ul>
                <EmptyState v-else title="Bu gün tüketim yok" description="Seçilen günde stoktan düşen kalem bulunmuyor." />
            </BaseCard>

            <!-- Mutabakat tablosu -->
            <BaseCard flush :title="`Dönem mutabakatı (${period?.from ?? ''} → ${period?.to ?? ''})`">
                <div class="w-full overflow-x-auto overscroll-x-contain">
                    <table class="w-full min-w-max border-collapse text-sm" aria-label="Dönem mutabakatı">
                        <thead>
                            <tr class="border-b border-default bg-surface-alt text-xs font-semibold tracking-wide text-muted uppercase">
                                <th class="px-4 py-2.5 text-left">Kalem</th>
                                <th class="px-4 py-2.5 text-right">Açılış</th>
                                <th class="px-4 py-2.5 text-right">Giriş</th>
                                <th class="px-4 py-2.5 text-right">Çıkış</th>
                                <th class="px-4 py-2.5 text-right">Kapanış</th>
                                <th class="px-4 py-2.5 text-right">Tüketim maliyeti</th>
                            </tr>
                        </thead>
                        <tbody v-if="period && period.rows.length">
                            <tr v-for="r in period.rows" :key="r.item_id" class="border-b border-default">
                                <td class="px-4 py-2 font-medium">{{ r.name }} <span class="text-subtle">/ {{ r.unit }}</span></td>
                                <td class="px-4 py-2 text-right tabular-nums text-muted">{{ r.opening }}</td>
                                <td class="px-4 py-2 text-right tabular-nums text-success">+{{ r.in }}</td>
                                <td class="px-4 py-2 text-right tabular-nums text-danger">−{{ r.out }}</td>
                                <td class="px-4 py-2 text-right tabular-nums font-medium" :class="r.closing_milli < 0 ? 'text-danger' : ''">{{ r.closing }}</td>
                                <td class="px-4 py-2 text-right tabular-nums text-muted">{{ money(r.consumed_cost_minor) }}</td>
                            </tr>
                        </tbody>
                    </table>
                    <EmptyState v-if="!period || !period.rows.length" title="Hareket yok" description="Seçilen dönemde stok hareketi bulunmuyor." />
                </div>
                <p class="border-t border-default px-4 py-2 text-xs text-subtle">
                    Mutabakat: her kalem için Açılış + Giriş − Çıkış = Kapanış. Defter değişmezdir; rakamlar hareket defterinden anlık hesaplanır.
                </p>
            </BaseCard>
        </div>
        </div>
        </div>
    </PanelShell>
</template>
