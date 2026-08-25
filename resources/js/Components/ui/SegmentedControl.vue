<script setup lang="ts">
import { ref } from 'vue';
import { useId } from '@/composables/useId';
import AppIcon from './AppIcon.vue';

/**
 * Segmentli kontrol: az sayıda seçenek arasında tek seçim (dönem, görünüm,
 * mod). Aktif seçenek marka mavisi "pill" ile vurgulanır. Radio grup
 * semantiği + roving tabindex: ok tuşları seçenekler arasında gezer ve seçer.
 * Dokunma hedefi ≥ 44px.
 */
type OptionValue = string | number;

interface SegOption {
    value: OptionValue;
    label: string;
    /** Opsiyonel AppIcon adı. */
    icon?: string;
}

const props = defineProps<{
    modelValue: OptionValue;
    options: SegOption[];
    /** Ekran okuyucu için grup etiketi. */
    ariaLabel?: string;
}>();

const emit = defineEmits<{ 'update:modelValue': [value: OptionValue] }>();

const idBase = useId('seg');
const listRef = ref<HTMLElement | null>(null);

function select(value: OptionValue): void {
    emit('update:modelValue', value);
}

/** Ok tuşları: seçimi taşır + odağı yeni seçeneğe götürür (roving tabindex). */
function onKeydown(e: KeyboardEvent): void {
    const idx = props.options.findIndex((o) => o.value === props.modelValue);
    let next = -1;
    if (e.key === 'ArrowRight' || e.key === 'ArrowDown') next = (idx + 1) % props.options.length;
    else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') next = (idx - 1 + props.options.length) % props.options.length;
    else if (e.key === 'Home') next = 0;
    else if (e.key === 'End') next = props.options.length - 1;
    if (next === -1) return;
    e.preventDefault();
    const value = props.options[next].value;
    select(value);
    listRef.value?.querySelector<HTMLElement>(`#${idBase}-opt-${next}`)?.focus();
}
</script>

<template>
    <div
        ref="listRef"
        role="radiogroup"
        :aria-label="ariaLabel || undefined"
        class="inline-flex gap-1 rounded-lg border border-default bg-inset p-1"
        @keydown="onKeydown"
    >
        <button
            v-for="(opt, i) in options"
            :id="`${idBase}-opt-${i}`"
            :key="opt.value"
            type="button"
            role="radio"
            :aria-checked="modelValue === opt.value"
            :tabindex="modelValue === opt.value ? 0 : -1"
            class="inline-flex min-h-11 items-center justify-center gap-1.5 rounded-md px-3 text-sm font-medium whitespace-nowrap transition-colors duration-(--dur-fast)"
            :class="
                modelValue === opt.value
                    ? 'bg-primary text-on-primary shadow-card'
                    : 'text-muted hover:bg-raised hover:text-body'
            "
            @click="select(opt.value)"
        >
            <AppIcon v-if="opt.icon" :name="opt.icon" :size="16" />
            {{ opt.label }}
        </button>
    </div>
</template>
