<script setup lang="ts">
import { computed } from 'vue';
import { useFieldContext } from './formField';
import AppIcon from './AppIcon.vue';

export interface SelectOption {
    value: string | number;
    label: string;
    disabled?: boolean;
}

const props = withDefaults(
    defineProps<{
        modelValue?: string | number;
        options: SelectOption[];
        placeholder?: string;
        size?: 'sm' | 'md';
        invalid?: boolean;
        disabled?: boolean;
    }>(),
    { modelValue: '', placeholder: '', size: 'md', invalid: false, disabled: false },
);

const emit = defineEmits<{ 'update:modelValue': [value: string] }>();

const field = useFieldContext();
const isInvalid = computed(() => props.invalid || Boolean(field?.invalid.value));

const classes = computed(() => [
    'w-full appearance-none rounded-md border bg-raised text-body pr-9',
    'transition-colors duration-(--dur-fast)',
    'focus:outline-none focus:ring-2 focus:ring-ring-brand',
    'disabled:opacity-55 disabled:cursor-not-allowed disabled:bg-inset',
    props.size === 'sm' ? 'h-8 pl-2.5 text-sm' : 'h-10 pl-3 text-sm',
    isInvalid.value ? 'border-danger' : 'border-strong',
]);
</script>

<template>
    <div class="relative">
        <select
            :id="field?.id"
            :value="modelValue"
            :disabled="disabled"
            :required="field?.required || undefined"
            :aria-invalid="isInvalid || undefined"
            :aria-describedby="field?.describedBy.value"
            :class="classes"
            @change="emit('update:modelValue', ($event.target as HTMLSelectElement).value)"
        >
            <option v-if="placeholder" value="" disabled>{{ placeholder }}</option>
            <option v-for="opt in options" :key="opt.value" :value="opt.value" :disabled="opt.disabled">
                {{ opt.label }}
            </option>
        </select>
        <span class="pointer-events-none absolute inset-y-0 right-2.5 flex items-center text-muted">
            <AppIcon name="chevron-down" :size="16" />
        </span>
    </div>
</template>
