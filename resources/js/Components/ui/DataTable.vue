<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from './AppIcon.vue';
import BaseSkeleton from './BaseSkeleton.vue';
import EmptyState from './EmptyState.vue';

/**
 * Kurumsal veri tablosu.
 *
 * TAŞMA ÇÖZÜMÜ (Faz 2):
 *  - Geniş ekran: tablo, KENDİ `overflow-x-auto` sarmalayıcısında kayar; sayfa
 *    asla yatay taşmaz. Aksiyon kolonu sağa YAPIŞIK (sticky) kalır → dar tabloda
 *    bile kırpılmaz.
 *  - `stackAt` kırılımının altında (varsayılan `md` = <768px) tablo otomatik
 *    KART-LİSTE moduna geçer: her satır bir kart, birincil alan başlık, ikincil
 *    alanlar etiketli satır, aksiyonlar kartın altında. Yatay kaydırma yok.
 *  - `hideBelow` ile ikincil kolonlar tablo modunda dar ekranda gizlenir (bilgi
 *    kaybı yok — kart modunda yine görünür).
 *
 * GERİYE UYUMLU: mevcut çağrılar (`columns`/`rows`/`loading`/`caption`/
 * `empty-*`/`row-key` + `#cell-<key>` / `#empty` slotları) aynen çalışır.
 * Yeni alanların hepsi opsiyoneldir.
 */
export interface TableColumn {
    key: string;
    label: string;
    align?: 'left' | 'right' | 'center';
    /** Tailwind genişlik sınıfı (ör. "w-32") */
    widthClass?: string;
    /** Para/sayı: sağa yaslı + tabular-nums (align verilmezse right varsayılır) */
    numeric?: boolean;
    /** Başlık tıklanabilir olur; tıklanınca `sort` olayı yayınlanır */
    sortable?: boolean;
    /** Tablo modunda bu kırılımın ALTINDA kolon gizlenir (karta iner) */
    hideBelow?: 'sm' | 'md' | 'lg';
    /** Kart modunda rol: 'primary' başlık olur, 'secondary' etiketli satır */
    priority?: 'primary' | 'secondary';
    /** İşlem kolonu: tabloda sağa yapışık, kartta alt aksiyon satırı
     *  (key === 'actions' otomatik işaretlenir) */
    action?: boolean;
    /** Kart modunda bu kolonu gizle */
    hideOnCard?: boolean;
    /** Kart modu etiketi (varsayılan: label) */
    cardLabel?: string;
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
        /** Altında kart-liste moduna geçilecek kırılım (varsayılan md=<768px) */
        stackAt?: 'never' | 'sm' | 'md' | 'lg';
        /** Aksiyon kolonunu sağa yapıştır (kırpılmayı önler) */
        stickyActions?: boolean;
        /** Sıralı olduğu kolon anahtarı (sortable başlık göstergesi için) */
        sortKey?: string;
        /** Sıralama yönü */
        sortDir?: 'asc' | 'desc';
        /** Daha sık satır yüksekliği */
        dense?: boolean;
    }>(),
    {
        rowKey: 'id',
        loading: false,
        emptyTitle: 'Kayıt bulunamadı',
        emptyDescription: '',
        caption: '',
        stackAt: 'md',
        stickyActions: true,
        sortKey: '',
        sortDir: 'asc',
        dense: false,
    },
);

const emit = defineEmits<{ sort: [key: string] }>();

/* ---- kırılım → statik sınıf eşlemeleri (Tailwind JIT için literal olmalı) ---- */
const STACK: Record<string, { table: string; cards: string }> = {
    never: { table: '', cards: 'hidden' },
    sm: { table: 'hidden sm:block', cards: 'sm:hidden' },
    md: { table: 'hidden md:block', cards: 'md:hidden' },
    lg: { table: 'hidden lg:block', cards: 'lg:hidden' },
};
const HIDE: Record<string, string> = {
    sm: 'hidden sm:table-cell',
    md: 'hidden md:table-cell',
    lg: 'hidden lg:table-cell',
};

const stackClass = computed(() => STACK[props.stackAt] ?? STACK.md);
const cellPad = computed(() => (props.dense ? 'px-2.5 py-1.5' : 'px-3.5 py-2'));

const actionCol = computed<TableColumn | null>(
    () => props.columns.find((c) => c.action || c.key === 'actions') ?? null,
);
const primaryCol = computed<TableColumn | null>(() => {
    const forced = props.columns.find((c) => c.priority === 'primary');
    if (forced) return forced;
    return props.columns.find((c) => c !== actionCol.value && c.priority !== 'secondary') ?? null;
});
const cardCols = computed(() =>
    props.columns.filter((c) => c !== actionCol.value && c !== primaryCol.value && !c.hideOnCard),
);

const isAction = (c: TableColumn) => c === actionCol.value;
const isSticky = (c: TableColumn) => props.stickyActions && isAction(c);

const alignClass = (c: TableColumn): string => {
    const a = c.align ?? (c.numeric ? 'right' : 'left');
    return a === 'right' ? 'text-right' : a === 'center' ? 'text-center' : 'text-left';
};
const numClass = (c: TableColumn): string => (c.numeric || c.align === 'right' ? 'tabular-nums' : '');
const hideClass = (c: TableColumn): string => (c.hideBelow ? HIDE[c.hideBelow] : '');

const ariaSort = (c: TableColumn): 'ascending' | 'descending' | 'none' | undefined => {
    if (!c.sortable) return undefined;
    if (props.sortKey !== c.key) return 'none';
    return props.sortDir === 'desc' ? 'descending' : 'ascending';
};
const sortIcon = (c: TableColumn): string => {
    if (props.sortKey === c.key) return props.sortDir === 'desc' ? 'chevron-down' : 'chevron-up';
    return 'chevron-down';
};

const skeletonRows = 5;
</script>

<template>
    <!-- ===================== TABLO MODU (geniş ekran) ===================== -->
    <div
        :class="stackClass.table"
        class="w-full overflow-x-auto overscroll-x-contain"
        tabindex="0"
        role="group"
        :aria-label="caption || 'Tablo'"
    >
        <table class="w-full border-collapse text-sm">
            <caption v-if="caption" class="sr-only">{{ caption }}</caption>
            <thead>
                <tr class="border-b border-strong bg-inset/50">
                    <th
                        v-for="col in columns"
                        :key="col.key"
                        scope="col"
                        :aria-sort="ariaSort(col)"
                        class="px-4 py-2.5 text-xs font-semibold tracking-wide text-subtle uppercase"
                        :class="[
                            alignClass(col),
                            col.widthClass,
                            hideClass(col),
                            isSticky(col) ? 'sticky right-0 z-10 border-l border-default bg-surface-alt' : '',
                        ]"
                    >
                        <button
                            v-if="col.sortable"
                            type="button"
                            class="inline-flex items-center gap-1 uppercase transition-colors duration-(--dur-fast) hover:text-body"
                            :class="col.align === 'right' || col.numeric ? 'flex-row-reverse' : ''"
                            @click="emit('sort', col.key)"
                        >
                            <span>{{ col.label }}</span>
                            <AppIcon
                                :name="sortIcon(col)"
                                :size="13"
                                :class="sortKey === col.key ? 'text-primary' : 'text-subtle opacity-40'"
                            />
                        </button>
                        <template v-else>{{ col.label }}</template>
                    </th>
                </tr>
            </thead>

            <tbody v-if="loading">
                <tr v-for="i in skeletonRows" :key="i" class="border-b border-default">
                    <td
                        v-for="col in columns"
                        :key="col.key"
                        :class="[cellPad, hideClass(col), isSticky(col) ? 'sticky right-0 border-l border-default bg-raised' : '']"
                    >
                        <BaseSkeleton :size-class="isAction(col) ? 'h-4 w-16 ml-auto' : 'h-3.5 w-3/4'" />
                    </td>
                </tr>
            </tbody>

            <tbody v-else-if="rows.length">
                <tr
                    v-for="row in rows"
                    :key="String(row[rowKey])"
                    class="group border-b border-default transition-colors duration-(--dur-fast) last:border-b-0 odd:bg-inset/30 hover:bg-inset"
                >
                    <td
                        v-for="col in columns"
                        :key="col.key"
                        class="text-body"
                        :class="[
                            cellPad,
                            alignClass(col),
                            numClass(col),
                            hideClass(col),
                            isSticky(col)
                                ? 'sticky right-0 z-10 border-l border-default bg-raised group-hover:bg-surface-alt'
                                : '',
                        ]"
                    >
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

    <!-- ===================== KART MODU (dar ekran) =====================
         Native GRUPLU LİSTE: tek yüzey + hairline ayraç (her satır AYRI kart
         DEĞİL). Birincil alan başlık, ikincil alanlar kompakt etiket/değer,
         aksiyonlar satır altında. -->
    <div :class="stackClass.cards">
        <!-- Flush: ebeveyn çerçevesinin (rounded/border) içine oturur; satırlar
             hairline ayraçla ayrılır → tek yüzey (her satır ayrı kart değil). -->
        <div
            v-if="loading"
            class="[&>*:not(:last-child)]:border-b [&>*:not(:last-child)]:border-default/70"
        >
            <div v-for="i in skeletonRows" :key="i" class="px-4 py-3.5">
                <BaseSkeleton size-class="h-3.5 w-2/5" />
                <BaseSkeleton class="mt-2.5" size-class="h-3 w-3/5" />
            </div>
        </div>

        <div
            v-else-if="rows.length"
            class="stagger-in [&>*:not(:last-child)]:border-b [&>*:not(:last-child)]:border-default/70"
        >
            <article
                v-for="row in rows"
                :key="String(row[rowKey])"
                class="flex flex-col gap-2 px-4 py-3.5"
            >
                <!-- Birincil alan = başlık -->
                <div v-if="primaryCol" class="min-w-0 text-[15px] font-semibold text-body">
                    <slot :name="`cell-${primaryCol.key}`" :row="row" :value="row[primaryCol.key]">
                        {{ row[primaryCol.key] }}
                    </slot>
                </div>

                <!-- İkincil alanlar = etiketli satırlar -->
                <dl v-if="cardCols.length" class="flex flex-col gap-1.5">
                    <div v-for="col in cardCols" :key="col.key" class="flex items-start justify-between gap-3">
                        <dt class="shrink-0 pt-0.5 text-[13px] text-subtle">{{ col.cardLabel ?? col.label }}</dt>
                        <dd class="min-w-0 text-right text-[14px] text-body" :class="numClass(col)">
                            <slot :name="`cell-${col.key}`" :row="row" :value="row[col.key]">
                                {{ row[col.key] }}
                            </slot>
                        </dd>
                    </div>
                </dl>

                <!-- Aksiyonlar = alt satır -->
                <div v-if="actionCol" class="flex items-center justify-end gap-1 border-t border-default/70 pt-2">
                    <slot :name="`cell-${actionCol.key}`" :row="row" :value="row[actionCol.key]" />
                </div>
            </article>
        </div>

        <slot v-else name="empty">
            <EmptyState :title="emptyTitle" :description="emptyDescription" />
        </slot>
    </div>
</template>
