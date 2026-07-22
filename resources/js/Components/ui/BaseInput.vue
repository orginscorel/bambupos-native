<script setup lang="ts">
import { computed } from 'vue';
import { useFieldContext } from './formField';

const props = withDefaults(
    defineProps<{
        modelValue?: string | number;
        type?: string;
        size?: 'sm' | 'md';
        invalid?: boolean;
        disabled?: boolean;
        placeholder?: string;
        autocomplete?: string;
        inputmode?: 'text' | 'numeric' | 'decimal' | 'tel' | 'email' | 'url' | 'search';
    }>(),
    { modelValue: '', type: 'text', size: 'md', invalid: false, disabled: false },
);

const emit = defineEmits<{ 'update:modelValue': [value: string] }>();

const field = useFieldContext();
const isInvalid = computed(() => props.invalid || Boolean(field?.invalid.value));

const classes = computed(() => [
    'w-full rounded-md border bg-raised text-body placeholder:text-subtle',
    'transition-colors duration-(--dur-fast)',
    'focus:outline-none focus:ring-2 focus:ring-ring-brand focus:border-strong',
    'disabled:opacity-55 disabled:cursor-not-allowed disabled:bg-inset',
    props.size === 'sm' ? 'h-8 px-2.5 text-sm' : 'h-10 px-3 text-sm',
    isInvalid.value ? 'border-danger' : 'border-strong',
]);
</script>

<template>
    <input
        :id="field?.id"
        :type="type"
        :value="modelValue"
        :disabled="disabled"
        :placeholder="placeholder"
        :autocomplete="autocomplete"
        :inputmode="inputmode"
        :required="field?.required || undefined"
        :aria-invalid="isInvalid || undefined"
        :aria-describedby="field?.describedBy.value"
        :class="classes"
        @input="emit('update:modelValue', ($event.target as HTMLInputElement).value)"
    />
</template>
