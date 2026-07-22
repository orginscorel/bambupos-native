<script setup lang="ts">
import { useId } from '@/composables/useId';

const props = withDefaults(
    defineProps<{
        modelValue?: boolean;
        label: string;
        description?: string;
        disabled?: boolean;
    }>(),
    { modelValue: false, description: '', disabled: false },
);

const emit = defineEmits<{ 'update:modelValue': [value: boolean] }>();
const id = useId('chk');
const descId = `${id}-desc`;
</script>

<template>
    <label
        :for="id"
        class="flex min-h-11 cursor-pointer items-start gap-3 py-2 select-none"
        :class="disabled ? 'cursor-not-allowed opacity-55' : ''"
    >
        <input
            :id="id"
            type="checkbox"
            :checked="modelValue"
            :disabled="disabled"
            :aria-describedby="description ? descId : undefined"
            class="mt-0.5 size-5 shrink-0 cursor-pointer appearance-none rounded-xs border border-strong bg-raised
                   transition-colors duration-(--dur-fast)
                   checked:border-primary checked:bg-primary
                   checked:bg-[url('data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20viewBox%3D%220%200%2024%2024%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-width%3D%223%22%20stroke-linecap%3D%22round%22%20stroke-linejoin%3D%22round%22%3E%3Cpath%20d%3D%22M20%206%209%2017l-5-5%22%2F%3E%3C%2Fsvg%3E')]
                   checked:bg-center checked:bg-no-repeat checked:bg-[length:14px]
                   disabled:cursor-not-allowed"
            @change="emit('update:modelValue', ($event.target as HTMLInputElement).checked)"
        />
        <span class="flex flex-col gap-0.5">
            <span class="text-sm font-medium text-body">{{ label }}</span>
            <span v-if="description" :id="descId" class="text-xs text-muted">{{ description }}</span>
        </span>
    </label>
</template>
