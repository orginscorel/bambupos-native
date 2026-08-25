<script setup lang="ts">
import { computed } from 'vue';
import { Link } from '@inertiajs/vue3';
import AppIcon from './AppIcon.vue';

/**
 * Native-mobil liste satırı (iOS/Android hissi). Anatomi:
 *   [ikon]  Başlık                         [değer] [rozet] [chevron]
 *           Alt açıklama
 * Satırın TAMAMI tıklanabilir; basıldığında hafif zemin geri bildirimi.
 * `MobileListGroup` içinde kullanılır (grup hairline ayraçları verir).
 */
const props = withDefaults(
    defineProps<{
        title?: string;
        subtitle?: string;
        /** Sol sabit ikon (22-24px). */
        icon?: string;
        /** İkon tonu: nötr | marka | başarı | uyarı | tehlike | bilgi. */
        tone?: 'neutral' | 'primary' | 'success' | 'warning' | 'danger' | 'info';
        /** Sağda düz değer metni (₺, sayı, saat vb.). */
        value?: string | number;
        /** Sağda chevron göster (varsayılan: href varsa true). */
        chevron?: boolean;
        /** Inertia Link hedefi → satır <Link> olur. */
        href?: string;
        /** Etkileşimli mi (buton gibi). href yoksa @click ile kullanılır. */
        interactive?: boolean;
        /** Değeri vurgulu (koyu, tabular) göster. */
        strongValue?: boolean;
    }>(),
    { tone: 'neutral', interactive: false, strongValue: false },
);

const toneClasses: Record<string, string> = {
    neutral: 'bg-inset text-muted',
    primary: 'bg-primary-soft text-primary',
    success: 'bg-success-soft text-success',
    warning: 'bg-warning-soft text-warning',
    danger: 'bg-danger-soft text-danger',
    info: 'bg-info-soft text-info',
};

const showChevron = computed(() => props.chevron ?? Boolean(props.href));
const clickable = computed(() => Boolean(props.href) || props.interactive);

const rowClass = computed(() => [
    'flex w-full items-center gap-3 px-4 text-left',
    clickable.value
        ? 'press-row active:bg-inset hover:bg-inset/60 cursor-pointer'
        : '',
]);
</script>

<template>
    <component
        :is="href ? Link : interactive ? 'button' : 'div'"
        :href="href || undefined"
        :type="interactive && !href ? 'button' : undefined"
        :class="rowClass"
        :style="{ minHeight: subtitle ? 'var(--h-list-row-lg)' : 'var(--h-list-row)' }"
    >
        <!-- Sol ikon (opsiyonel) -->
        <span
            v-if="icon || $slots.leading"
            class="flex size-9 shrink-0 items-center justify-center rounded-[10px]"
            :class="toneClasses[tone]"
        >
            <slot name="leading"><AppIcon v-if="icon" :name="icon" :size="19" /></slot>
        </span>

        <!-- Orta: başlık + alt açıklama -->
        <span class="flex min-w-0 grow flex-col py-2.5">
            <slot name="title">
                <span class="truncate text-[15px] font-semibold text-body">{{ title }}</span>
            </slot>
            <slot name="subtitle">
                <span v-if="subtitle" class="truncate text-[13px] text-muted">{{ subtitle }}</span>
            </slot>
        </span>

        <!-- Sağ: değer / rozet / switch / chevron -->
        <span class="flex shrink-0 items-center gap-2">
            <slot name="trailing" />
            <span
                v-if="value !== undefined && value !== ''"
                class="text-[14px]"
                :class="strongValue ? 'font-semibold text-body tabular-nums' : 'text-muted'"
            >
                {{ value }}
            </span>
            <AppIcon v-if="showChevron" name="chevron-right" :size="18" class="text-subtle" />
        </span>
    </component>
</template>
