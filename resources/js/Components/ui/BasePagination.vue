<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from './AppIcon.vue';

const props = withDefaults(
    defineProps<{
        page: number;
        lastPage: number;
        /** Toplam kayıt bilgisi (isteğe bağlı, "X kayıt" olarak gösterilir) */
        total?: number;
    }>(),
    { total: 0 },
);

const emit = defineEmits<{ 'update:page': [page: number] }>();

/** 1 … (p-1) p (p+1) … son penceresi */
const windowPages = computed<(number | '…')[]>(() => {
    const { page, lastPage } = props;
    if (lastPage <= 7) return Array.from({ length: lastPage }, (_, i) => i + 1);
    const pages: (number | '…')[] = [1];
    if (page > 3) pages.push('…');
    for (let p = Math.max(2, page - 1); p <= Math.min(lastPage - 1, page + 1); p++) pages.push(p);
    if (page < lastPage - 2) pages.push('…');
    pages.push(lastPage);
    return pages;
});

function go(p: number): void {
    if (p >= 1 && p <= props.lastPage && p !== props.page) emit('update:page', p);
}
</script>

<template>
    <nav class="flex flex-wrap items-center justify-between gap-3" aria-label="Sayfalama">
        <p v-if="total" class="text-xs text-muted">Toplam {{ total }} kayıt</p>
        <div class="flex items-center gap-1">
            <button
                type="button"
                class="flex size-9 items-center justify-center rounded-md border border-default bg-raised text-muted transition-colors duration-(--dur-fast) hover:bg-inset disabled:cursor-not-allowed disabled:opacity-45"
                :disabled="page <= 1"
                aria-label="Önceki sayfa"
                @click="go(page - 1)"
            >
                <AppIcon name="chevron-left" :size="16" />
            </button>
            <template v-for="(p, i) in windowPages" :key="i">
                <span v-if="p === '…'" class="px-1.5 text-sm text-subtle" aria-hidden="true">…</span>
                <button
                    v-else
                    type="button"
                    class="flex size-9 items-center justify-center rounded-md border text-sm font-medium transition-colors duration-(--dur-fast)"
                    :class="
                        p === page
                            ? 'border-primary bg-primary text-on-primary'
                            : 'border-default bg-raised text-body hover:bg-inset'
                    "
                    :aria-current="p === page ? 'page' : undefined"
                    :aria-label="`Sayfa ${p}`"
                    @click="go(p)"
                >
                    {{ p }}
                </button>
            </template>
            <button
                type="button"
                class="flex size-9 items-center justify-center rounded-md border border-default bg-raised text-muted transition-colors duration-(--dur-fast) hover:bg-inset disabled:cursor-not-allowed disabled:opacity-45"
                :disabled="page >= lastPage"
                aria-label="Sonraki sayfa"
                @click="go(page + 1)"
            >
                <AppIcon name="chevron-right" :size="16" />
            </button>
        </div>
    </nav>
</template>
