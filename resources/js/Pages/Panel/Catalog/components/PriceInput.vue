<script setup lang="ts">
import { ref, watch } from 'vue';
import { useFieldContext } from '@/Components/ui/formField';

/**
 * Kuruş-integer fiyat girişi (ADR-007): kullanıcı "125,50" yazar,
 * model daima kuruş (12550) tutar. Boş bırakılabilir (null).
 */
const props = withDefaults(
    defineProps<{
        modelValue: number | null;
        placeholder?: string;
        disabled?: boolean;
    }>(),
    { placeholder: '0,00', disabled: false },
);

const emit = defineEmits<{ 'update:modelValue': [value: number | null] }>();

const field = useFieldContext();

const toText = (minor: number | null): string =>
    minor === null || Number.isNaN(minor) ? '' : (minor / 100).toFixed(2).replace('.', ',');

const text = ref(toText(props.modelValue));

watch(
    () => props.modelValue,
    (v) => {
        if (parse(text.value) !== v) text.value = toText(v);
    },
);

function parse(raw: string): number | null {
    const trimmed = raw.trim();
    if (trimmed === '') return null;
    // TR biçimi: binlik "." + ondalık ","
    const normalized = trimmed.includes(',')
        ? trimmed.replace(/\./g, '').replace(',', '.')
        : trimmed;
    const num = Number(normalized);
    if (Number.isNaN(num) || num < 0) return null;
    return Math.round(num * 100);
}

function onInput(e: Event): void {
    text.value = (e.target as HTMLInputElement).value;
    emit('update:modelValue', parse(text.value));
}

function onBlur(): void {
    text.value = toText(parse(text.value));
}
</script>

<template>
    <div class="relative">
        <input
            :id="field?.id"
            type="text"
            inputmode="decimal"
            :value="text"
            :placeholder="placeholder"
            :disabled="disabled"
            :aria-describedby="field?.describedBy.value"
            :aria-invalid="field?.invalid.value || undefined"
            class="h-10 w-full rounded-md border bg-raised pr-8 pl-3 text-sm text-body placeholder:text-subtle
                   transition-colors duration-(--dur-fast)
                   focus:ring-ring-brand focus:border-strong focus:ring-2 focus:outline-none
                   disabled:cursor-not-allowed disabled:bg-inset disabled:opacity-55"
            :class="field?.invalid.value ? 'border-danger' : 'border-strong'"
            @input="onInput"
            @blur="onBlur"
        />
        <span class="pointer-events-none absolute inset-y-0 right-3 flex items-center text-sm text-subtle">₺</span>
    </div>
</template>
