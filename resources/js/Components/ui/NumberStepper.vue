<script setup lang="ts">
import { computed } from 'vue';
import { useId } from '@/composables/useId';
import AppIcon from './AppIcon.vue';

/**
 * Sayı adımlayıcı: POS'ta adet seçimi için − [n] + kontrolü. Büyük dokunma
 * hedefleri (44px), tabular hizalama, sınırlarda pasifleşen butonlar.
 * Değer elle de yazılabilir; girişte min/max'e kırpılır.
 */
const props = withDefaults(
    defineProps<{
        modelValue: number;
        min?: number;
        max?: number;
        step?: number;
        disabled?: boolean;
        /** Ekran okuyucu etiketi (görünen etiket ayrıca sağlanmıyorsa). */
        ariaLabel?: string;
        /** Kompakt/normal dokunma boyu. */
        size?: 'md' | 'lg';
    }>(),
    { min: 0, max: Number.MAX_SAFE_INTEGER, step: 1, disabled: false, size: 'lg' },
);

const emit = defineEmits<{ 'update:modelValue': [value: number] }>();

const id = useId('stepper');

const canDecrement = computed(() => !props.disabled && props.modelValue > props.min);
const canIncrement = computed(() => !props.disabled && props.modelValue < props.max);

/** Değeri sınırlar içine kırp ve step'e göre değiştir. */
function clamp(v: number): number {
    if (Number.isNaN(v)) return props.min;
    return Math.min(props.max, Math.max(props.min, v));
}

function decrement(): void {
    if (!canDecrement.value) return;
    emit('update:modelValue', clamp(props.modelValue - props.step));
}

function increment(): void {
    if (!canIncrement.value) return;
    emit('update:modelValue', clamp(props.modelValue + props.step));
}

function onInput(e: Event): void {
    const raw = (e.target as HTMLInputElement).value;
    emit('update:modelValue', clamp(Number(raw)));
}

const btnSize = computed(() => (props.size === 'lg' ? 'size-11' : 'size-10'));
const fieldWidth = computed(() => (props.size === 'lg' ? 'w-14 text-base' : 'w-12 text-sm'));
</script>

<template>
    <div
        class="inline-flex items-center overflow-hidden rounded-md border border-strong bg-raised"
        :class="disabled ? 'opacity-55' : ''"
    >
        <button
            type="button"
            :disabled="!canDecrement"
            :aria-label="`Azalt${ariaLabel ? ` — ${ariaLabel}` : ''}`"
            :aria-controls="id"
            class="flex shrink-0 items-center justify-center text-body transition-colors duration-(--dur-fast) hover:bg-inset disabled:cursor-not-allowed disabled:text-subtle disabled:opacity-60 hover:disabled:bg-transparent"
            :class="btnSize"
            @click="decrement"
        >
            <AppIcon name="minus" :size="18" />
        </button>

        <input
            :id="id"
            type="text"
            inputmode="numeric"
            :value="modelValue"
            :disabled="disabled"
            :aria-label="ariaLabel || undefined"
            class="h-11 border-x border-default bg-transparent text-center font-medium text-body tabular-nums outline-none disabled:cursor-not-allowed"
            :class="fieldWidth"
            @input="onInput"
        />

        <button
            type="button"
            :disabled="!canIncrement"
            :aria-label="`Artır${ariaLabel ? ` — ${ariaLabel}` : ''}`"
            :aria-controls="id"
            class="flex shrink-0 items-center justify-center text-body transition-colors duration-(--dur-fast) hover:bg-inset disabled:cursor-not-allowed disabled:text-subtle disabled:opacity-60 hover:disabled:bg-transparent"
            :class="btnSize"
            @click="increment"
        >
            <AppIcon name="plus" :size="18" />
        </button>
    </div>
</template>
