<script setup lang="ts">
import { formatCurrencyMinor, formatNumber } from '@/lib/format';
import EmptyState from '@/Components/ui/EmptyState.vue';

/**
 * Rapor tablosu: kolon tanımı + satırlar. Sayısal kolonlar sağa yaslı,
 * tabular rakamlarla dizilir; '*_minor' alanları ₺ biçimlenir.
 * Veri yoksa DÜRÜST boş durum gösterilir — asla sahte satır yok.
 */
export interface TableColumn {
    key: string;
    label: string;
    align?: 'left' | 'right';
    /** minor: kuruş → ₺ · number: sayı · percent: %x,y · minutes: dk · raw */
    format?: 'minor' | 'number' | 'percent' | 'minutes' | 'raw';
}

withDefaults(
    defineProps<{
        columns: TableColumn[];
        /** Satırlar: herhangi bir düz nesne listesi (rapor tipleri dahil). */
        rows: object[];
        emptyText?: string;
    }>(),
    { emptyText: 'Bu aralıkta veri yok.' },
);

function cell(row: object, col: TableColumn): string {
    const v = (row as Record<string, unknown>)[col.key];
    if (v === null || v === undefined || v === '') return '—';

    switch (col.format) {
        case 'minor':
            return formatCurrencyMinor(Number(v));
        case 'number':
            return formatNumber(Number(v));
        case 'percent':
            return `%${Number(v).toFixed(1).replace('.', ',')}`;
        case 'minutes':
            return `${Number(v).toFixed(1).replace('.', ',')} dk`;
        default:
            return String(v);
    }
}
</script>

<template>
    <EmptyState v-if="rows.length === 0" icon="chart" title="Veri yok" :description="emptyText" />

    <div v-else class="overflow-x-auto">
        <table class="w-full text-sm">
            <thead>
                <tr class="border-b border-default bg-surface-alt">
                    <th
                        v-for="col in columns"
                        :key="col.key"
                        class="px-3 py-2 text-xs font-semibold whitespace-nowrap text-muted"
                        :class="col.align === 'right' ? 'text-right' : 'text-left'"
                        scope="col"
                    >
                        {{ col.label }}
                    </th>
                </tr>
            </thead>
            <tbody>
                <tr v-for="(row, i) in rows" :key="i" class="border-b border-default last:border-0">
                    <td
                        v-for="col in columns"
                        :key="col.key"
                        class="px-3 py-2 whitespace-nowrap"
                        :class="[
                            col.align === 'right' ? 'text-right tabular-nums' : 'text-left',
                            col.format === 'minor' ? 'font-medium text-body' : 'text-muted',
                        ]"
                    >
                        <slot :name="`cell-${col.key}`" :row="row" :value="(row as Record<string, unknown>)[col.key]">
                            {{ cell(row, col) }}
                        </slot>
                    </td>
                </tr>
            </tbody>
        </table>
    </div>
</template>
