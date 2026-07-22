<script setup lang="ts">
import { useId } from '@/composables/useId';

export interface RadioOption {
    value: string | number;
    label: string;
    description?: string;
    disabled?: boolean;
}

const props = withDefaults(
    defineProps<{
        modelValue?: string | number;
        label: string;
        options: RadioOption[];
        disabled?: boolean;
    }>(),
    { modelValue: '', disabled: false },
);

const emit = defineEmits<{ 'update:modelValue': [value: string | number] }>();
const name = useId('radio');
</script>

<template>
    <fieldset :disabled="disabled" class="flex flex-col gap-1">
        <legend class="mb-1 text-sm font-medium text-body">{{ label }}</legend>
        <label
            v-for="opt in options"
            :key="opt.value"
            class="flex min-h-11 cursor-pointer items-start gap-3 py-2 select-none"
            :class="opt.disabled || disabled ? 'cursor-not-allowed opacity-55' : ''"
        >
            <input
                type="radio"
                :name="name"
                :value="opt.value"
                :checked="modelValue === opt.value"
                :disabled="opt.disabled"
                class="mt-0.5 size-5 shrink-0 cursor-pointer appearance-none rounded-full border border-strong bg-raised
                       transition-colors duration-(--dur-fast)
                       checked:border-[6px] checked:border-primary
                       disabled:cursor-not-allowed"
                @change="emit('update:modelValue', opt.value)"
            />
            <span class="flex flex-col gap-0.5">
                <span class="text-sm font-medium text-body">{{ opt.label }}</span>
                <span v-if="opt.description" class="text-xs text-muted">{{ opt.description }}</span>
            </span>
        </label>
    </fieldset>
</template>
