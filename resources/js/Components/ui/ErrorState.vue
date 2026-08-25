<script setup lang="ts">
import AppIcon from './AppIcon.vue';
import BaseButton from './BaseButton.vue';

/**
 * Hata durumu (EmptyState kardeşi): sunucu hatası, bağlantı yok, yetkisiz vb.
 * İkon + başlık + açıklama + "Tekrar dene" aksiyonu. `retryLabel` boşsa buton
 * gizlenir. `variant` ikon/renk tonunu belirler.
 */
const props = withDefaults(
    defineProps<{
        title?: string;
        description?: string;
        /** offline | server | forbidden | generic → uygun ikon/ton. */
        variant?: 'offline' | 'server' | 'forbidden' | 'generic';
        retryLabel?: string;
    }>(),
    { title: '', description: '', variant: 'generic', retryLabel: 'Tekrar dene' },
);

const emit = defineEmits<{ retry: [] }>();

const presets: Record<string, { icon: string; title: string; desc: string }> = {
    offline: {
        icon: 'plug',
        title: 'Bağlantı yok',
        desc: 'İnternet bağlantınızı kontrol edip yeniden deneyin.',
    },
    server: {
        icon: 'alert-triangle',
        title: 'Bir şeyler ters gitti',
        desc: 'Sunucuya ulaşılamadı. Lütfen birazdan tekrar deneyin.',
    },
    forbidden: {
        icon: 'x-circle',
        title: 'Yetkiniz yok',
        desc: 'Bu bölümü görüntüleme izniniz bulunmuyor.',
    },
    generic: {
        icon: 'alert-circle',
        title: 'Bir hata oluştu',
        desc: 'İşlem tamamlanamadı. Lütfen tekrar deneyin.',
    },
};
</script>

<template>
    <div class="flex flex-col items-center justify-center gap-2 px-6 py-12 text-center">
        <span class="mb-1 flex size-12 items-center justify-center rounded-full bg-danger-soft text-danger">
            <AppIcon :name="presets[variant].icon" :size="24" />
        </span>
        <h3 class="text-sm font-semibold text-body">{{ title || presets[variant].title }}</h3>
        <p class="max-w-sm text-sm text-muted">{{ description || presets[variant].desc }}</p>
        <div v-if="retryLabel || $slots.action" class="mt-3 flex items-center gap-2">
            <BaseButton v-if="retryLabel" variant="secondary" size="sm" @click="emit('retry')">
                {{ retryLabel }}
            </BaseButton>
            <slot name="action" />
        </div>
    </div>
</template>
