<script setup lang="ts">
import BaseSkeleton from './BaseSkeleton.vue';
import EmptyState from './EmptyState.vue';

export interface TableColumn {
    key: string;
    label: string;
    align?: 'left' | 'right' | 'center';
    /** Tailwind genişlik sınıfı (ör. "w-32") */
    widthClass?: string;
}

type Row = Record<string, unknown>;

const props = withDefaults(
    defineProps<{
        columns: TableColumn[];
        rows: Row[];
        rowKey?: string;
        loading?: boolean;
        emptyTitle?: string;
        emptyDescription?: string;
        caption?: string;
    }>(),
    {
        rowKey: 'id',
        loading: false,
        emptyTitle: 'Kayıt bulunamadı',
        emptyDescription: '',
        caption: '',
    },
);

const alignClass = (a?: string) => (a === 'right' ? 'text-right' : a === 'center' ? 'text-center' : 'text-left');
</script>

<template>
    <!-- Yatay taşma tablonun KENDİ kapsayıcısında kayar; sayfa kaymaz -->
    <div class="w-full overflow-x-auto overscroll-x-contain" tabindex="0" role="group" :aria-label="caption || 'Tablo'">
        <table class="w-full min-w-max border-collapse text-sm">
            <caption v-if="caption" class="sr-only">{{ caption }}</caption>
            <thead>
                <tr class="border-b border-default bg-surface-alt">
                    <th
                        v-for="col in columns"
                        :key="col.key"
                        scope="col"
                        class="px-4 py-2.5 text-xs font-semibold tracking-wide text-muted uppercase"
                        :class="[alignClass(col.align), col.widthClass]"
                    >
                        {{ col.label }}
                    </th>
                </tr>
            </thead>
            <tbody v-if="loading">
                <tr v-for="i in 5" :key="i" class="border-b border-default">
                    <td v-for="col in columns" :key="col.key" class="px-4 py-3">
                        <BaseSkeleton size-class="h-3.5 w-3/4" />
                    </td>
                </tr>
            </tbody>
            <tbody v-else-if="rows.length">
                <tr
                    v-for="row in rows"
                    :key="String(row[rowKey])"
                    class="border-b border-default transition-colors duration-(--dur-fast) last:border-b-0 hover:bg-surface-alt"
                >
                    <td v-for="col in columns" :key="col.key" class="px-4 py-3 text-body" :class="alignClass(col.align)">
                        <slot :name="`cell-${col.key}`" :row="row" :value="row[col.key]">
                            {{ row[col.key] }}
                        </slot>
                    </td>
                </tr>
            </tbody>
            <tbody v-else>
                <tr>
                    <td :colspan="columns.length">
                        <slot name="empty">
                            <EmptyState :title="emptyTitle" :description="emptyDescription" />
                        </slot>
                    </td>
                </tr>
            </tbody>
        </table>
    </div>
</template>
