<script setup lang="ts">
/**
 * Dikey zaman çizelgesi (son hareketler/operasyon geçmişi). Solda ince çizgi +
 * her kayıtta renkli durum noktası; sağda saat + açıklama. Veri odaklı: `items`.
 * Nokta tonu `tone` ile semantik renk alır. Beyaz yüzey üstünde okunur.
 */
export interface TimelineEntry {
    id?: string | number;
    /** Saat/zaman etiketi (ör. "14:32"). */
    time?: string;
    /** Ana açıklama. */
    title: string;
    /** İkincil açıklama (personel, tür vb.). */
    meta?: string;
    tone?: 'neutral' | 'primary' | 'success' | 'warning' | 'danger' | 'info';
}

withDefaults(defineProps<{ items: TimelineEntry[] }>(), {});

const dotClasses: Record<string, string> = {
    neutral: 'bg-subtle',
    primary: 'bg-primary',
    success: 'bg-success',
    warning: 'bg-warning',
    danger: 'bg-danger',
    info: 'bg-info',
};
</script>

<template>
    <ol class="relative flex flex-col">
        <li
            v-for="(entry, i) in items"
            :key="entry.id ?? i"
            class="relative flex gap-3 pb-4 last:pb-0"
        >
            <!-- Dikey çizgi (son öğede kesilir) -->
            <span
                v-if="i < items.length - 1"
                class="absolute top-4 left-[5px] h-full w-px bg-default"
                aria-hidden="true"
            />
            <!-- Durum noktası -->
            <span
                class="relative z-10 mt-1 size-2.5 shrink-0 rounded-full ring-4 ring-surface"
                :class="dotClasses[entry.tone ?? 'neutral']"
                aria-hidden="true"
            />
            <div class="flex min-w-0 grow flex-col -mt-0.5">
                <div class="flex items-baseline justify-between gap-2">
                    <span class="text-[14px] font-medium text-body">{{ entry.title }}</span>
                    <span v-if="entry.time" class="shrink-0 text-[12px] text-subtle tabular-nums">
                        {{ entry.time }}
                    </span>
                </div>
                <span v-if="entry.meta" class="text-[13px] text-muted">{{ entry.meta }}</span>
                <slot name="extra" :entry="entry" />
            </div>
        </li>
    </ol>
</template>
