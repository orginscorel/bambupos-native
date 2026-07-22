<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from 'vue';
import AppIcon from './AppIcon.vue';

const props = withDefaults(
    defineProps<{
        modelValue?: string;
        placeholder?: string;
        /** ms; 0 = anında */
        debounce?: number;
        label?: string;
    }>(),
    { modelValue: '', placeholder: 'Ara…', debounce: 300, label: 'Ara' },
);

const emit = defineEmits<{ 'update:modelValue': [value: string] }>();

const local = ref(props.modelValue);
let timer: number | undefined;

watch(
    () => props.modelValue,
    (v) => {
        if (v !== local.value) local.value = v;
    },
);

function onInput(e: Event): void {
    local.value = (e.target as HTMLInputElement).value;
    window.clearTimeout(timer);
    timer = window.setTimeout(() => emit('update:modelValue', local.value), props.debounce);
}

function clear(): void {
    window.clearTimeout(timer);
    local.value = '';
    emit('update:modelValue', '');
}

onBeforeUnmount(() => window.clearTimeout(timer));
</script>

<template>
    <div class="relative">
        <span class="pointer-events-none absolute inset-y-0 left-3 flex items-center text-subtle">
            <AppIcon name="search" :size="16" />
        </span>
        <input
            type="search"
            role="searchbox"
            :value="local"
            :placeholder="placeholder"
            :aria-label="label"
            class="h-10 w-full rounded-md border border-strong bg-raised pr-9 pl-9 text-sm text-body placeholder:text-subtle
                   transition-colors duration-(--dur-fast)
                   focus:ring-ring-brand focus:ring-2 focus:outline-none
                   [&::-webkit-search-cancel-button]:hidden"
            @input="onInput"
        />
        <button
            v-if="local"
            type="button"
            class="absolute inset-y-0 right-1.5 my-auto flex size-7 items-center justify-center rounded-md text-subtle transition-colors duration-(--dur-fast) hover:bg-inset hover:text-body"
            aria-label="Aramayı temizle"
            @click="clear"
        >
            <AppIcon name="x" :size="14" />
        </button>
    </div>
</template>
